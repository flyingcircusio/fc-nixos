/*
 * Pure URL and date logic of the VCS history overlay -- no DOM, no state.
 *
 * Consumed by overlay.js as window.HistoryUrls (loaded dynamically from
 * /v/history-urls.js when the global is missing) and by the e2e logic tier
 * via CommonJS `require()` under node (tests/e2e/test_history_overlay.py)
 * -- hence the dual export (same pattern as
 * src/_static/version-switcher-urls.js).
 *
 * All functions work on the payload shape of /v/manifest.json as written by
 * tools/build_history.py: {"revisions": [{rev, hash, date, branch, subject,
 * status, content, duration, log_excerpt}, ...]} with rev being the hg LOCAL
 * revision number (the directory name under /v/) and date an ISO YYYY-MM-DD
 * string. The history tree is served under the /v/ URL prefix with absolute
 * URLs, so every href built here is absolute with a leading slash and works
 * at any page depth.
 */
(function (root, factory) {
  "use strict";
  if (typeof module === "object" && module.exports) {
    module.exports = factory();
  } else {
    root.HistoryUrls = factory();
  }
})(typeof window !== "undefined" ? window : this, function () {
  "use strict";

  // /v/<rev>/... -- one path segment below /v/ names a revision build.
  // "/v/" itself (the history landing) carries no revision segment.
  var REV_PREFIX = /^\/v\/([^/]+)(\/.*)?$/;

  // Same-page switch into the target revision: the page path below
  // /v/<current-rev>/ is re-based onto /v/<targetRev>/. Paths carrying NO
  // revision prefix -- the live manual, or the /v/ history landing itself --
  // fall back to the target revision's root /v/<targetRev>/.
  function targetHref(path, targetRev) {
    var match = REV_PREFIX.exec(path);
    if (!match) {
      return "/v/" + targetRev + "/";
    }
    return "/v/" + targetRev + (match[2] || "/");
  }

  // Revisions ordered by (date, rev): the manifest arrives ascending by rev,
  // but the order is ESTABLISHED here -- consumers (dropdown, prev/next,
  // revForDate) must not depend on the caller sorting first. Same-day
  // revisions order by their numeric rev (the higher rev is the later
  // state of that day).
  function sortedRevisions(revisions) {
    return revisions.slice().sort(function (a, b) {
      if (a.date !== b.date) return a.date < b.date ? -1 : 1;
      return (+a.rev || 0) - (+b.rev || 0);
    });
  }

  // "Zustand am <date>": the revision of the LAST BUILDABLE (status=ok)
  // entry with date <= dateStr -- the most recent state of that day that
  // is actually navigable. Failed builds are skipped (their /v/<rev>/
  // directory was never placed -- navigating there would 404), exactly
  // like the dropdown's disabled options and prev/next's buildable
  // filter. null when no buildable revision existed on or before dateStr
  // (the overlay shows its notice instead of navigating).
  function revForDate(dateStr, revisions) {
    var best = null;
    var ordered = sortedRevisions(revisions);
    for (var i = 0; i < ordered.length; i += 1) {
      if (ordered[i].date <= dateStr && ordered[i].status === "ok") {
        best = ordered[i];
      }
    }
    return best ? best.rev : null;
  }

  // ISO date arithmetic: dateStr minus 2 days (the "vorgestern" preset of
  // the overlay's 'Zustand am' date field). Uses real calendar arithmetic
  // (Date) so month/year/leap-day boundaries are handled, never day-of-
  // month subtraction.
  function vorgestern(dateStr) {
    var parts = dateStr.split("-");
    var day = new Date(Date.UTC(+parts[0], +parts[1] - 1, +parts[2]));
    day.setUTCDate(day.getUTCDate() - 2);
    return day.toISOString().slice(0, 10);
  }

  return {
    targetHref: targetHref,
    sortedRevisions: sortedRevisions,
    revForDate: revForDate,
    vorgestern: vorgestern,
  };
});
