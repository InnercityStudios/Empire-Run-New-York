#!/usr/bin/env python3
"""Renders the in-game geography world (dumped by tests/tools_geo_dump.gd)
over the blueprint coastlines, so the generated streets, blocks, bridges and
connections can be checked against the approved blueprint.

Usage: python3 tools/geography/render_world.py dump.json out.png [x0 z0 x1 z1 scale]
"""
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import nyc_blueprint as bp  # noqa: E402

STYLE = {k: v["color"] for k, v in bp.STYLES.items()}


def main():
    dump = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    if len(sys.argv) > 3:
        ext = tuple(float(v) for v in sys.argv[3:7])
        scale = float(sys.argv[7])
    else:
        ext, scale = bp.EXTENT, 0.18
    w, h = int((ext[2] - ext[0]) * scale), int((ext[3] - ext[1]) * scale)
    img = Image.new("RGB", (w, h), "#173240")
    d = ImageDraw.Draw(img)
    px = lambda p: ((p[0] - ext[0]) * scale, (p[1] - ext[1]) * scale)
    for c in bp.COASTS:
        d.polygon([px(p) for p in c["polygon"]], fill="#3a3732" if c["kind"] == "playable" else "#2e2c29")
    for p in bp.PARKS:
        d.polygon([px(q) for q in p["polygon"]], fill="#3f6a2e")
        for lake in p.get("lakes", []):
            d.polygon([px(q) for q in lake], fill="#2a5462")
    for b in dump["blocks"]:
        d.polygon([px(q) for q in b["poly"]], fill=STYLE.get(b["style"], "#777777"))
    lw = max(1, int(round(scale * 6)))
    for s in dump["segments"]:
        d.line([px((s[0], s[1])), px((s[2], s[3]))], fill="#e2c27a" if s[4] >= 18 else "#cfc6b2",
               width=max(1, int(s[4] * scale)) if scale > 0.3 else (lw + (1 if s[4] >= 18 else 0)))
    for j in dump["junctions"]:
        d.polygon([px(q) for q in j], fill="#cfc6b2")
    for br in dump["bridges"]:
        d.line([px(p) for p in br["path"]], fill="#c9a24a", width=max(3, int(br["width"] * scale * 1.5)))
    if scale > 0.3:
        for n in dump["nodes"]:
            x, y = px(n)
            d.ellipse([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill="#ff5050")
    for lot in dump["lots"]:
        x, y = px(lot)
        d.point((x, y), fill="#ffd27a")
    for t in dump["towers"]:
        x, y = px(t)
        d.rectangle([x - 4, y - 4, x + 4, y + 4], fill="#ffffff", outline="#000000")
    x0, z0, x1, z1 = bp.LI_RECT
    d.rectangle([px((x0, z0)), px((x1, z1))], outline="#ffd27a", width=3)
    img.save(out)
    print("rendered", out, img.size)


if __name__ == "__main__":
    main()
