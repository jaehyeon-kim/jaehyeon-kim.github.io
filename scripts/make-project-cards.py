#!/usr/bin/env python3
"""Generate one card image per entry in data/projects.json.

Each card is 1200x420, dark blue-gray to match the site palette, and carries
the project name and the owner/repo path. The card text on the page comes from
`description` in that file, so it is deliberately not repeated in the image.

Adding a project: add the entry to data/projects.json with an `image` field of
"<name>.png", then run this script. Changing the look: edit the constants below
and rerun; every card is rewritten, so they stay consistent.

The GitHub mark beside the repo path is scripts/github-mark.png, committed
beside this script, so nothing is fetched at run time.

Needs Pillow only, no browser and no network. Run from the repository root:

    pip install pillow
    python3 scripts/make-project-cards.py

Output goes to assets/projects/, which is committed, so a build never depends
on this script having been run.
"""
import json, pathlib
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "projects"
W, H = 1200, 420
BG = (38, 50, 56)          # blue-gray 900, the site's palette
ACCENT = (79, 195, 247)    # light blue for the rule and the tag
TITLE = (255, 255, 255)
BODY = (176, 190, 197)     # blue-gray 200
PAD = 64

MARK = pathlib.Path(__file__).resolve().parent / "github-mark.png"

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

def fit(draw, text, path, start, max_width, weight):
    """Largest size at or below `start` that draws `text` within `max_width`."""
    size = start
    while size > 20:
        f = font(path, size, weight)
        if draw.textlength(text, font=f) <= max_width:
            return f
        size -= 2
    return font(path, 20, weight)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    projects = json.loads((ROOT / "data" / "projects.json").read_text())
    mark = Image.open(MARK).convert("RGBA")
    f_tag = font(MONO, 26, 500)
    for p in projects:
        img = Image.new("RGB", (W, H), BG)
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, 12, H], fill=ACCENT)
        avail = W - PAD * 2
        f_title = fit(d, p["name"], SF, 66, avail, 700)
        # measure the real glyph box so a descender never touches the rule
        bbox = d.textbbox((0, 0), p["name"], font=f_title)
        title_h = bbox[3] - bbox[1]
        block = title_h + 44 + 34
        y = (H - block) // 2 - bbox[1]
        d.text((PAD, y), p["name"], font=f_title, fill=TITLE)
        y += bbox[3] + 28
        d.line([(PAD, y), (PAD + 120, y)], fill=ACCENT, width=4)
        y += 34
        # GitHub mark, sized to the repo line and vertically centred on it
        m = mark.resize((30, 30), Image.LANCZOS)
        img.paste(m, (PAD, y + 1), m)
        d.text((PAD + 44, y), p["repo"], font=f_tag, fill=BODY)
        out = OUT / f'{p["name"]}.png'
        img.save(out, "PNG", optimize=True)
        print(f'{out.relative_to(ROOT)}  {out.stat().st_size // 1024} KB')

if __name__ == "__main__":
    main()
