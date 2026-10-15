"""Write forwarding pages for the old dynamic-des docs under static/dynamic-des/.

dynamic-des was renamed desflow in 0.20.0, and its docs moved from
https://jaehyeon.me/dynamic-des/ to https://jaehyeon.me/desflow/. GitHub Pages has no
server-side redirects, so every old page gets a small HTML page with a meta refresh
and a canonical link to its match under /desflow/latest/, or to the desflow home page
when there is no match. llms.txt and llms-full.txt are plain text, so each becomes a
line giving the URL of its desflow equivalent.

Usage:
    git -C ../desflow ls-tree -r --name-only <old gh-pages commit> > old-files.txt
    python scripts/make-dynamic-des-redirects.py old-files.txt <built desflow site>

The old file list is read from the last gh-pages commit before "Removed everything
with mike". The built desflow site (the output of `mkdocs build`) says which pages
exist under the new name.
"""

import argparse
import html
import shutil
from pathlib import Path

_NEW_ROOT = "https://jaehyeon.me/desflow/"
_NEW_LATEST = _NEW_ROOT + "latest/"
_OUT = Path(__file__).resolve().parent.parent / "static" / "dynamic-des"
_TEXT_FILES = ("llms.txt", "llms-full.txt")


def _page(target: str) -> str:
    """Return a forwarding page for one target URL."""
    url = html.escape(target, quote=True)
    return (
        "<!DOCTYPE html>\n"
        '<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        "<title>Moved to desflow</title>\n"
        f'<link rel="canonical" href="{url}">\n'
        f'<meta http-equiv="refresh" content="0; url={url}">\n'
        '<meta name="robots" content="noindex">\n'
        "</head>\n<body>\n"
        f'<p>dynamic-des is now desflow. This page has moved to <a href="{url}">{url}</a>.</p>\n'
        "</body>\n</html>\n"
    )


def _target(page: str, new_pages: set[str]) -> str:
    """Return the desflow URL for a page path inside a version folder."""
    folder = page.removesuffix("index.html")
    if page in new_pages:
        return _NEW_LATEST + folder
    return _NEW_ROOT


def main() -> None:
    """Read the old file list and the new site, then write the forwarding pages."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("old_files", type=Path, help="file list of the old gh-pages commit")
    parser.add_argument("new_site", type=Path, help="built desflow site")
    parser.add_argument("--out", type=Path, default=_OUT, help="output folder")
    args = parser.parse_args()

    old = [line.strip() for line in args.old_files.read_text().splitlines() if line.strip()]
    new_pages = {str(p.relative_to(args.new_site)) for p in args.new_site.rglob("*.html")}
    versions = sorted({path.split("/", 1)[0] for path in old if "/" in path and path[0].isdigit()})

    # `latest` is a link to the newest version, so it gets that version's pages.
    pages: dict[str, set[str]] = {}
    for path in old:
        if "/" in path and path.endswith(".html") and path[0].isdigit():
            version, page = path.split("/", 1)
            pages.setdefault(version, set()).add(page)
    pages["latest"] = pages[max(versions, key=lambda v: tuple(int(n) for n in v.split(".")))]

    out_root: Path = args.out
    if out_root.exists():
        shutil.rmtree(out_root)
    count = 0
    for version, version_pages in pages.items():
        for page in version_pages:
            out = out_root / version / page
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(_page(_target(page, new_pages)))
            count += 1
    (out_root / "index.html").write_text(_page(_NEW_ROOT))
    for name in _TEXT_FILES:
        (out_root / name).write_text(f"dynamic-des is now desflow. This file is at {_NEW_ROOT}{name}\n")
    print(f"Wrote {count + 1} forwarding pages and {len(_TEXT_FILES)} text files to {out_root}")


if __name__ == "__main__":
    main()
