#!/usr/bin/env python3
"""
noup-workaround.py — unstick PGs after unsetting NOUP flags.

After clearing NOUP, some PGs can get stuck in peering/GetInfo indefinitely.
This script monitors PG states and triggers sequential 'ceph osd down' events
to force a fresh peering round on the affected primaries.

Algorithm:
  1. Poll pg dump every few seconds.
  2. Any PG continuously in a peering state for >= STUCK_SECS is "stuck".
  3. Collect acting-set OSDs from all stuck PGs (primary first, across PGs
     in pgid order).
  4. Trigger 'ceph osd down' on the first OSD in that list not yet tried.
  5. Reset stuck timers and repeat from step 1.
  6. If all candidate OSDs have been tried and PGs are still stuck: exit 1.
  7. If no peering PGs for CLEAN_SECS continuously: exit 0.
"""

import asyncio
import json
import sys
import time

STUCK_SECS = 15.0  # seconds in peering before a PG is considered stuck
CLEAN_SECS = 60.0  # seconds of no peering PGs before declaring success
POLL_SECS = 3.0  # polling interval
POST_DOWN_PAUSE = 5.0  # pause after triggering 'osd down' before next poll

PEERING_STATES = frozenset(
    {
        "peering",
        "getinfo",
        "getlog",
        "getmissing",
        "waitupthru",
    }
)


# ---------------------------------------------------------------------------
# Shell helpers
# ---------------------------------------------------------------------------


async def _run(
    *args: str, timeout: float = 30.0
) -> tuple[int | None, str, str]:
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.communicate()
        return -1, "", f"timeout after {timeout}s"
    return (
        proc.returncode,
        out.decode(errors="replace"),
        err.decode(errors="replace"),
    )


def _parse_json(text: str):
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


# ---------------------------------------------------------------------------
# Ceph queries
# ---------------------------------------------------------------------------


async def fetch_pg_stats() -> list[dict]:
    rc, out, _ = await _run("ceph", "pg", "dump", "--format=json", timeout=30)
    if rc != 0:
        return []
    data = _parse_json(out)
    if not isinstance(data, dict):
        return []
    # Nautilus: top-level pg_stats list
    # Newer: nested under pg_map
    return data.get("pg_map", {}).get("pg_stats") or data.get("pg_stats") or []


async def fetch_osd_hosts() -> dict[int, str]:
    """Return {osd_id: hostname} from osd tree."""
    rc, out, _ = await _run("ceph", "osd", "tree", "--format=json", timeout=15)
    if rc != 0:
        return {}
    data = _parse_json(out)
    if not isinstance(data, dict):
        return {}
    result: dict[int, str] = {}
    for node in data.get("nodes", []):
        if node.get("type") == "host":
            host = node.get("name", "?")
            for child in node.get("children", []):
                result[child] = host
    return result


async def osd_down(osd_id: int) -> bool:
    rc, _, _ = await _run("ceph", "osd", "down", str(osd_id), timeout=15)
    return rc == 0


# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------


def _is_peering(state: str) -> bool:
    return any(
        part.strip() in PEERING_STATES for part in state.lower().split("+")
    )


def _candidate_osds(stuck: dict[str, list[int]]) -> list[int]:
    """
    Ordered, deduplicated OSD list from all stuck PGs.
    PGs sorted by pgid; within each PG, acting-set order (primary first).
    """
    seen: set[int] = set()
    result: list[int] = []
    for pgid in sorted(stuck):
        for osd in stuck[pgid]:
            if osd >= 0 and osd not in seen:
                result.append(osd)
                seen.add(osd)
    return result


def _ts() -> str:
    return time.strftime("%H:%M:%S")


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------


async def main() -> int:
    print(f"[{_ts()}] Fetching OSD→host mapping …")
    osd_hosts = await fetch_osd_hosts()

    # pgid → timestamp when it was first seen peering (this window)
    first_seen: dict[str, float] = {}
    # pgid → acting list (kept up to date each poll)
    pg_acting: dict[str, list[int]] = {}

    triggered: list[int] = []  # OSDs we have already downed, in order
    clean_since: float | None = None  # when the last peering PG disappeared

    print(
        f"[{_ts()}] Monitoring  stuck≥{STUCK_SECS}s  clean≥{CLEAN_SECS}s  poll={POLL_SECS}s"
    )

    while True:
        now = time.time()

        stats = await fetch_pg_stats()
        if not stats:
            print(f"[{_ts()}] WARNING: pg dump returned nothing, retrying …")
            await asyncio.sleep(POLL_SECS)
            continue

        # --- update peering set ---
        peering_now: set[str] = set()
        for pg in stats:
            pgid = pg.get("pgid", "")
            state = pg.get("state", "")
            if pgid and _is_peering(state):
                peering_now.add(pgid)
                pg_acting[pgid] = [o for o in pg.get("acting", []) if o >= 0]

        # age new arrivals; drop PGs that are no longer peering
        for pgid in peering_now:
            first_seen.setdefault(pgid, now)
        for pgid in list(first_seen):
            if pgid not in peering_now:
                del first_seen[pgid]
                pg_acting.pop(pgid, None)

        # --- success check ---
        if not peering_now:
            if clean_since is None:
                clean_since = now
                print(
                    f"[{_ts()}] No peering PGs — need {CLEAN_SECS:.0f}s to confirm clean …"
                )
            elif now - clean_since >= CLEAN_SECS:
                print(
                    f"[{_ts()}] SUCCESS: no peering PGs for {CLEAN_SECS:.0f}s."
                )
                return 0
            await asyncio.sleep(POLL_SECS)
            continue

        if clean_since is not None:
            print(f"[{_ts()}] Peering PGs reappeared — resetting clean timer.")
        clean_since = None

        # --- stuck check ---
        stuck_acting: dict[str, list[int]] = {
            pgid: pg_acting[pgid]
            for pgid in peering_now
            if now - first_seen[pgid] >= STUCK_SECS
        }

        if not stuck_acting:
            # PGs are peering but within normal time — just log and wait
            ages = sorted(
                ((pgid, now - first_seen[pgid]) for pgid in peering_now),
                key=lambda x: -x[1],
            )
            snippet = ", ".join(f"{p}({a:.0f}s)" for p, a in ages[:5])
            if len(ages) > 5:
                snippet += f" … +{len(ages) - 5} more"
            print(f"[{_ts()}] Peering ({len(peering_now)}): {snippet}")
            await asyncio.sleep(POLL_SECS)
            continue

        # --- stuck PGs detected ---
        ages = {pgid: now - first_seen[pgid] for pgid in stuck_acting}
        print(f"[{_ts()}] STUCK ({len(stuck_acting)} PGs):")
        for pgid in sorted(stuck_acting):
            osds = stuck_acting[pgid]
            hosts = " ".join(f"osd.{o}({osd_hosts.get(o, '?')})" for o in osds)
            print(f"  {pgid:20s}  age={ages[pgid]:.0f}s  acting: {hosts}")

        candidates = _candidate_osds(stuck_acting)
        next_osd = next((o for o in candidates if o not in triggered), None)

        if next_osd is None:
            # All candidates exhausted — build the error report
            lines = [
                "",
                f"[{_ts()}] ERROR: PGs still stuck after downing all "
                f"{len(triggered)} candidate OSD(s).",
                f"  Triggered OSDs : {triggered}",
                f"  Candidates were: {candidates}",
                "",
                f"  Stuck PGs ({len(stuck_acting)}):",
            ]
            for pgid in sorted(stuck_acting):
                osds = stuck_acting[pgid]
                hosts = ", ".join(
                    f"osd.{o} on {osd_hosts.get(o, 'unknown')}" for o in osds
                )
                lines.append(
                    f"    {pgid:20s}  age={ages[pgid]:.0f}s  acting=[{hosts}]"
                )
            print("\n".join(lines))
            return 1

        host = osd_hosts.get(next_osd, "unknown")
        print(
            f"[{_ts()}] Triggering: ceph osd down {next_osd}  "
            f"(host={host}, previously triggered={triggered})"
        )

        ok = await osd_down(next_osd)
        if not ok:
            print(f"[{_ts()}] WARNING: 'ceph osd down {next_osd}' failed.")
            await asyncio.sleep(POLL_SECS)
            continue

        triggered.append(next_osd)
        print(
            f"[{_ts()}] Done. Resetting stuck timers, pausing {POST_DOWN_PAUSE}s …"
        )

        # Give all currently-peering PGs a fresh stuck window
        for pgid in list(first_seen):
            first_seen[pgid] = time.time()

        await asyncio.sleep(POST_DOWN_PAUSE)


def run() -> int:
    return asyncio.run(main())


if __name__ == "__main__":
    try:
        sys.exit(run())
    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(1)
