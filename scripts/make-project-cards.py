#!/usr/bin/env python3
"""Generate one card image per entry in data/projects.json.

Each card is 1200x420, dark blue-gray to match the site palette, and carries
the project name and the owner/repo path. The card text on the page comes from
`description` in that file, so it is deliberately not repeated in the image.

Adding a project: add the entry to data/projects.json with an `image` field of
"<name>.png", then run this script. Changing the look: edit the constants below
and rerun; every card is rewritten, so they stay consistent.

Needs Pillow only, no browser and no network. Run from the repository root:

    pip install pillow
    python3 scripts/make-project-cards.py

Output goes to assets/projects/, which is committed, so a build never depends
on this script having been run.
"""
import json, pathlib, textwrap
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "projects"
W, H = 1200, 420
BG = (38, 50, 56)          # blue-gray 900, the site's palette
ACCENT = (79, 195, 247)    # light blue for the rule and the tag
TITLE = (255, 255, 255)
BODY = (176, 190, 197)     # blue-gray 200
PAD = 64

SF = "/System/Library/Fonts/SFNS.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"

def font(path, size, weight=None):
    f = ImageFont.truetype(path, size)
    if weight is not None:
        try:
            f.set_variation_by_axes([weight])
        except Exception:
            pass
    return f

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    projects = json.loads((ROOT / "data" / "projects.json").read_text())
    f_title = font(SF, 66, 700)
    f_tag = font(MONO, 26, 500)
    for p in projects:
        img = Image.new("RGB", (W, H), BG)
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, 12, H], fill=ACCENT)
        lines = textwrap.wrap(p["name"], width=24)[:2]
        y = (H - (len(lines) * 80 + 100)) // 2
        for line in lines:
            d.text((PAD, y), line, font=f_title, fill=TITLE)
            y += 80
        y += 20
        d.line([(PAD, y), (PAD + 120, y)], fill=ACCENT, width=4)
        y += 34
        d.text((PAD, y), p["repo"], font=f_tag, fill=BODY)
        out = OUT / f'{p["name"]}.png'
        img.save(out, "PNG", optimize=True)
        print(f'{out.relative_to(ROOT)}  {out.stat().st_size // 1024} KB')

if __name__ == "__main__":
    main()
