#!/usr/bin/env python3
"""tf-mockups-locate.py — bring every mockup into docs/mockups/ (see tf-mockups-locate.sh).

    bash .tfcore/utils/tf-mockups-locate.sh [--dry-run]

The framework keeps one mockup folder, docs/mockups/. A brownfield repository may hold
mockups elsewhere (a root mockups/ folder, a designs/ folder, an html file beside the
docs). Two folders confused a real project, so this script finds every folder whose
name says mockup (mockup, mockups, wireframes, designs, screens) outside docs/mockups/,
docs/OldDocs/, the framework folders, node_modules, bin and obj, and moves each .html,
.png, .jpg or .svg it holds into docs/mockups/. A name already taken there gets the
source folder name as a suffix. Prints one line per file moved, then the final list of
docs/mockups/ files. Exit 0 always; 2 if docs/ cannot be created.
"""
import os
import shutil
import sys

NAMES = {"mockup", "mockups", "wireframe", "wireframes", "designs", "screens", "ui-mockups", "mock-ups"}
SKIP_DIRS = {".tfcore", ".claude", ".opencode", ".git", "node_modules", "bin", "obj",
             "OldDocs", "tests", "wwwroot"}
EXT = (".html", ".htm", ".png", ".jpg", ".jpeg", ".svg")


def main(argv):
    dry = "--dry-run" in argv
    if "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0
    root = os.getcwd()
    target = os.path.join(root, "docs", "mockups")
    try:
        os.makedirs(target, exist_ok=True)
    except Exception as e:
        print(f"tf-mockups-locate: cannot create docs/mockups ({e})", file=sys.stderr)
        return 2
    moved = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        rel = os.path.relpath(dirpath, root).replace(os.sep, "/")
        if rel in (".", "docs/mockups") or rel.startswith("docs/mockups/"):
            continue
        if os.path.basename(dirpath).lower() not in NAMES:
            continue
        for fn in sorted(filenames):
            if not fn.lower().endswith(EXT):
                continue
            src = os.path.join(dirpath, fn)
            dest = os.path.join(target, fn)
            if os.path.exists(dest):
                stem, ext = os.path.splitext(fn)
                dest = os.path.join(target, f"{stem}-{os.path.basename(dirpath)}{ext}")
            print(f"tf-mockups-locate: {'would move' if dry else 'moved'} {rel}/{fn} -> docs/mockups/{os.path.basename(dest)}")
            if not dry:
                shutil.move(src, dest)
            moved += 1
        if not dry and not os.listdir(dirpath):
            os.rmdir(dirpath)
            print(f"tf-mockups-locate: removed the empty folder {rel}/")
    files = sorted(f for f in os.listdir(target) if f.lower().endswith(EXT))
    print(f"tf-mockups-locate: {moved} file(s) {'to move' if dry else 'moved'}; docs/mockups/ now holds {len(files)}: " + (", ".join(files) if files else "(none)"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
