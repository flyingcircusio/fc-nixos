"""Derive the German source tree src-de/ from src/ + the committed overlay.

Overlay model:

- ``src-de/`` is fully GENERATED and hgignored. Every ``make html-de``
  rebuilds it from scratch: rmtree, copytree ``src/`` -> ``src-de/``, then
  overlay every file from ``translations/de/**`` onto
  ``src-de/<relpath>``.
- German content is edited ONLY in ``translations/de/``, never in
  ``src-de/`` (the next build wipes src-de).
- An overlay file whose English twin ``src/<relpath>`` does not exist is a
  hard error naming the offending path: the overlay must track the English
  tree (tests/test_derive_src_de.py additionally guards structural drift
  between the two).

No polib, no locale knowledge: the overlay is plain Markdown, 1:1 in file
layout with ``src/``.

Usage: ./appenv python scripts/derive_src_de.py
"""

from __future__ import annotations

import shutil
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[1]
SRC = _REPO_ROOT / "src"
SRC_DE = _REPO_ROOT / "src-de"
OVERLAY = _REPO_ROOT / "translations" / "de"


def derive(src: Path, src_de: Path, overlay: Path) -> tuple[int, int]:
    """Rebuild ``src_de`` from scratch and overlay ``overlay`` onto it.

    Returns ``(files_copied, files_overlaid)``. Raises FileNotFoundError
    naming the offending overlay file when its English twin is missing.
    """
    if src_de.exists():
        shutil.rmtree(src_de)
    shutil.copytree(src, src_de)
    files_copied = sum(1 for entry in src_de.rglob("*") if entry.is_file())

    files_overlaid = 0
    if overlay.is_dir():
        for overlay_file in sorted(
            entry for entry in overlay.rglob("*") if entry.is_file()
        ):
            rel = overlay_file.relative_to(overlay)
            twin = src / rel
            if not twin.is_file():
                raise FileNotFoundError(
                    f"overlay file {overlay_file} has no English twin {twin}: "
                    "translations/de must mirror src/ (stale overlay file -- "
                    "was the English page removed or renamed?)"
                )
            target = src_de / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(overlay_file, target)
            files_overlaid += 1

    return files_copied, files_overlaid


def main() -> None:
    files_copied, files_overlaid = derive(SRC, SRC_DE, OVERLAY)
    print(
        f"derived {SRC_DE.name}/: {files_copied} files copied from "
        f"{SRC.name}/, {files_overlaid} overlaid from {OVERLAY.name}/"
    )


if __name__ == "__main__":
    main()
