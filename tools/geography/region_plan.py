#!/usr/bin/env python3
"""World restructure plan (Phase A): city core, outskirts, estate regions and
scenery around the approved compressed New York, with estate plot capacity.

Planning only: renders docs/geography/world_restructure_plan.png and
data/world/estate_plan.json (region polygons, sampled plots, capacity). The
game does not read these yet.

Usage: python3 tools/geography/region_plan.py
"""
import json
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import nyc_blueprint as bp  # noqa: E402

ROOT = bp.ROOT
EXT = (-8500, -14500, 18500, 9500)   # 27 x 24 km frame (playable ~24 x 20 km)
SCALE = 0.12                           # px per metre

PLOT = 140.0          # estate plot: 140 m x 140 m (mansion, grounds, garage, gate)
SPACING = 230.0       # minimum centre-to-centre distance between estates

# --- Extended landforms (beyond the approved city blueprint) -----------------------
LONG_ISLAND = [(7600, -4900), (8800, -5600), (10200, -5300), (11400, -6100), (12900, -5700), (14300, -6400),
               (15800, -6000), (17200, -6500), (18500, -6300), (18500, 9500), (300, 9500), (300, 6400), (560, 5000),
               (2600, 4800), (5200, 5600), (7400, 5300), (9300, 6000), (11200, 5600), (13500, 6200), (15800, 5900),
               (18500, 6100)]
JAMAICA_BAY = [(5200, 5600), (7400, 5300), (9300, 6000), (8600, 7000), (6800, 7300), (5400, 6800)]
WESTCHESTER = [(3466, -8900), (7600, -8900), (9200, -7600), (11000, -8300), (13000, -7800), (14800, -8600),
               (16200, -8200), (18500, -8800), (18500, -14500), (3300, -14500), (3200, -12000), (3350, -10400)]
NEW_JERSEY = [(-8500, -14500), (2600, -14500), (2900, -12000), (2700, -10400), (2638, -8900), (1200, -7400),
              (-200, -5200), (-1100, -3200), (-1700, -1200), (-1700, 1900), (-1500, 2800), (-1900, 3900),
              (-2400, 5000), (-4200, 4700), (-8500, 4600)]
STATEN = [(-6400, 5300), (-3600, 5000), (-1300, 5000), (100, 5600), (300, 7200), (-900, 8600), (-3300, 9500),
          (-6900, 9500), (-7600, 7600)]

REGIONS = [
    # kind: core | outskirts | estate | scenery ; tier for estates
    {"id": "core_manhattan", "kind": "core", "name": "Manhattan"},
    {"id": "core_brooklyn", "kind": "core", "name": "Downtown & North Brooklyn",
     "polygon": [(560, 5000), (760, 4300), (640, 3500), (960, 2350), (1580, 760), (1720, 240), (2160, -1430),
                 (4300, -1520), (4600, 1400), (3600, 3200), (1600, 4600)]},
    {"id": "core_queens", "kind": "core", "name": "Long Island City & Astoria",
     "polygon": [(2160, -1430), (2640, -3150), (3420, -4620), (4800, -4500), (5200, -2400), (4300, -1520)]},
    {"id": "core_bronx", "kind": "core", "name": "South Bronx",
     "polygon": [(3014, -4700), (3350, -4980), (4500, -5400), (5100, -5800), (5000, -7000), (3466, -7300)]},
    {"id": "out_brooklyn", "kind": "outskirts", "name": "Flatbush, Canarsie & Bay Ridge",
     "polygon": [(1600, 4600), (3600, 3200), (4600, 1400), (7600, 1100), (7600, 5300), (5200, 5600), (2600, 4800)]},
    {"id": "out_queens", "kind": "outskirts", "name": "Central Queens",
     "polygon": [(4300, -1520), (5200, -2400), (4800, -4500), (6200, -4980), (7600, -4900), (7600, 1100),
                 (4600, 1400)]},
    {"id": "out_bronx", "kind": "outskirts", "name": "North Bronx",
     "polygon": [(3466, -7300), (5000, -7000), (5100, -5800), (7600, -5900), (8200, -6500), (7600, -8900),
                 (3466, -8900)]},
    {"id": "out_li_west", "kind": "outskirts", "name": "Nassau Suburbs",
     "polygon": [(7600, 1100), (7600, -4900), (10200, -5300), (10400, 5900), (9300, 6000), (7400, 5300)]},
    {"id": "out_nj", "kind": "outskirts", "name": "Hudson County & Fort Lee",
     "polygon": [(-1700, -1200), (-1100, -3200), (-200, -5200), (1200, -7400), (2638, -8900), (-1800, -9400),
                 (-3200, -3800), (-3000, 1200)]},
    # Estate regions (tiers by journey time to the core).
    {"id": "est_staten", "kind": "estate", "tier": "prime", "name": "Staten Island (Todt Hill)",
     "polygon": [(-6200, 5800), (-3600, 5300), (-1500, 5400), (-200, 6200), (-500, 8000), (-3000, 9000),
                 (-6400, 9000), (-7000, 7400)]},
    {"id": "est_riverdale", "kind": "estate", "tier": "prime", "name": "Riverdale & Fieldston",
     "polygon": [(3466, -8900), (5800, -8900), (6000, -10600), (3600, -10800), (3350, -10000)]},
    {"id": "est_palisades", "kind": "estate", "tier": "suburban", "name": "Englewood Cliffs & Palisades",
     "polygon": [(-1800, -9400), (2638, -8900), (2900, -12000), (2600, -14000), (-2200, -14000), (-3600, -11500)]},
    {"id": "est_westchester", "kind": "estate", "tier": "suburban", "name": "Scarsdale & Westchester",
     "polygon": [(6000, -10600), (5800, -8900), (7600, -8900), (9200, -7600), (11000, -8300), (12600, -8000),
                 (12800, -13800), (6200, -14000)]},
    {"id": "est_gold_coast", "kind": "estate", "tier": "suburban", "name": "Gold Coast (Kings Point to Oyster Bay)",
     "polygon": [(10200, -5300), (11400, -6100), (12900, -5700), (14300, -6400), (15800, -6000), (17200, -6500),
                 (18000, -6300), (18000, -1500), (10400, -1200)]},
    {"id": "est_li_south", "kind": "estate", "tier": "outer", "name": "Lawrence & South Shore",
     "polygon": [(10400, -1200), (18000, -1500), (18000, 5800), (15800, 5900), (13500, 6200), (11200, 5600),
                 (10400, 5900)]},
    {"id": "est_nj_west", "kind": "estate", "tier": "outer", "name": "Bergen Hills",
     "polygon": [(-3200, -3800), (-1800, -9400), (-3600, -11500), (-8000, -11000), (-8000, -2500)]},
]

ROADS = [  # extended highways and bridges (1977-era routes)
    {"name": "Verrazzano-Narrows Br.", "kind": "bridge", "path": [(-600, 6600), (1000, 5600)]},
    {"name": "Staten Island Expwy", "kind": "expressway", "path": [(-7600, 6600), (-4200, 6400), (-600, 6600)]},
    {"name": "Throgs Neck Br.", "kind": "bridge", "path": [(8200, -6500), (9400, -5600)]},
    {"name": "Whitestone Br.", "kind": "bridge", "path": [(6800, -5800), (7000, -4950)]},
    {"name": "George Washington Br.", "kind": "bridge", "path": [(2200, -7200), (1300, -7300)]},
    {"name": "Palisades Pkwy", "kind": "expressway", "path": [(1300, -7300), (600, -9500), (500, -12000), (1200, -14400)]},
    {"name": "Saw Mill / Hutchinson Pkwy", "kind": "expressway",
     "path": [(4300, -8800), (5200, -10500), (6500, -12300), (7400, -14400)]},
    {"name": "Northern State Pkwy", "kind": "expressway",
     "path": [(7600, -2800), (10500, -3300), (13000, -3000), (15500, -3500), (18400, -3200)]},
    {"name": "Long Island Expwy", "kind": "expressway", "path": [(7600, -2800), (10200, -2000), (14000, -1600), (18400, -1200)]},
    {"name": "Southern State Pkwy", "kind": "expressway",
     "path": [(7600, 1500), (10300, 2300), (13000, 2000), (15700, 2600), (18400, 2400)]},
    {"name": "Belt Pkwy", "kind": "expressway", "path": [(1000, 5600), (3000, 4900), (5200, 5500), (7600, 5200), (9800, 5300)]},
    {"name": "Goethals Br.", "kind": "bridge", "path": [(-7600, 6600), (-8400, 6200)]},
]

LANDMARKS = [("Belmont Park", (11200, 2500)), ("Jones Beach", (16000, 7400)), ("Bear Mountain", (1200, -13800)),
             ("Kensico Reservoir", (9000, -13200)), ("Freshkills", (-4800, 7400)), ("Jamaica Bay", (7300, 6400)),
             ("Long Island Sound", (11500, -7600)), ("Raritan Bay", (-4200, 9300))]
LAKES = [[(9000, -13000), (10600, -12600), (10800, -11800), (9400, -11900)],
         [(12400, -10800), (13200, -10600), (13100, -10000), (12300, -10200)],
         [(-5600, -8000), (-4600, -7800), (-4700, -7100), (-5700, -7300)],
         [(14800, -3000), (15500, -3100), (15400, -2600)], [(-3200, 7600), (-2500, 7500), (-2600, 8100)]]


def pip(x, z, poly):
    return bp.point_in_poly(x, z, poly)


def tier_of(r):
    return r.get("tier", "")


def sample_plots(region, rng, roads):
    """Poisson-disc estate plots: on land, off lakes, clear of highways, with a
    lane frontage (every plot later connects by a driveway)."""
    poly = region["polygon"]
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    pts = []
    tries = int((max(xs) - min(xs)) * (max(zs) - min(zs)) / (SPACING * SPACING) * 6)
    for _ in range(tries):
        x = rng.uniform(min(xs), max(xs))
        z = rng.uniform(min(zs), max(zs))
        if not pip(x, z, poly):
            continue
        if any(pip(x, z, lake) for lake in LAKES):
            continue
        if any(seg_dist(x, z, r["path"]) < 160 for r in roads):
            continue
        if any((x - px) ** 2 + (z - pz) ** 2 < SPACING ** 2 for px, pz in pts):
            continue
        # Natural clustering: leave woodland gaps (no plots where noise is low).
        if (math.sin(x * 0.0011 + 1.7) + math.cos(z * 0.0013 - 0.4)) < -0.9:
            continue
        pts.append((x, z))
    return pts


def seg_dist(x, z, path):
    best = 1e9
    for (ax, az), (bx, bz) in zip(path[:-1], path[1:]):
        dx, dz = bx - ax, bz - az
        t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz or 1)))
        best = min(best, math.hypot(x - ax - dx * t, z - az - dz * t))
    return best


def main():
    w = int((EXT[2] - EXT[0]) * SCALE)
    h = int((EXT[3] - EXT[1]) * SCALE)
    px = lambda p: ((p[0] - EXT[0]) * SCALE, (p[1] - EXT[1]) * SCALE)
    img = Image.new("RGB", (w, h), "#163040")
    d = ImageDraw.Draw(img)
    # Land: extended landforms + approved city coastlines.
    for poly in (NEW_JERSEY, WESTCHESTER, LONG_ISLAND, STATEN):
        d.polygon([px(p) for p in poly], fill="#3c4a33")
    for c in bp.COASTS:
        if c["kind"] == "playable" and c["id"] != "long_island" and c["id"] != "bronx":
            d.polygon([px(p) for p in c["polygon"]], fill="#3c4a33")
    d.polygon([px(p) for p in JAMAICA_BAY], fill="#1c3a4a")
    for lake in LAKES:
        d.polygon([px(p) for p in lake], fill="#2a5a6a")
    colors = {"core": "#6e4a3a", "outskirts": "#7c6a52", "estate": "#4f6e3a"}
    man = next(c for c in bp.COASTS if c["id"] == "manhattan")["polygon"]
    REGIONS[0]["polygon"] = man
    for r in REGIONS:
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        col = colors[r["kind"]]
        ld.polygon([px(p) for p in r["polygon"]], fill=col + "c8", outline="#e8c97f" if r["kind"] == "estate" else None)
        img.paste(layer, (0, 0), layer)
    d = ImageDraw.Draw(img)
    # Woodland texture in estate and outskirts regions.
    rng = random.Random(1977)
    for r in REGIONS:
        if r["kind"] not in ("estate", "outskirts"):
            continue
        poly = r["polygon"]
        xs = [p[0] for p in poly]
        zs = [p[1] for p in poly]
        for _ in range(int((max(xs) - min(xs)) * (max(zs) - min(zs)) / 9000)):
            x, z = rng.uniform(min(xs), max(xs)), rng.uniform(min(zs), max(zs))
            if pip(x, z, poly) and (math.sin(x * 0.0011 + 1.7) + math.cos(z * 0.0013 - 0.4)) < (0.2 if r["kind"] == "estate" else -0.8):
                cx, cy = px((x, z))
                rr = rng.uniform(2.0, 4.5)
                d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=rng.choice(["#2e4a26", "#38592c", "#25401f"]))
    # Existing approved city roads and bridges.
    for road in bp.ROADS:
        d.line([px(p) for p in road["path"]], fill="#e2c27a", width=2)
    for br in bp.BRIDGES:
        d.line([px(p) for p in br["path"]], fill="#c9a24a", width=4)
    for road in ROADS:
        d.line([px(p) for p in road["path"]], fill="#c9a24a" if road["kind"] == "bridge" else "#e2c27a",
               width=5 if road["kind"] == "bridge" else 3)
    # Estate plots.
    plots = []
    prng = random.Random(4242)
    tier_col = {"prime": "#ffd27a", "suburban": "#f0e6c8", "outer": "#b9c7a8"}
    for r in REGIONS:
        if r["kind"] != "estate":
            continue
        pts = sample_plots(r, prng, ROADS)
        r["plots"] = len(pts)
        for i, (x, z) in enumerate(pts):
            plots.append({"id": "estate:%s:%d" % (r["id"], i), "region": r["id"], "tier": r["tier"],
                          "pos": [round(x, 1), round(z, 1)]})
            cx, cy = px((x, z))
            d.rectangle([cx - 2, cy - 2, cx + 2, cy + 2], fill=tier_col[r["tier"]])
    # Example mansions: the Marino estate (prime, Staten Island) and a rival.
    examples = [("MARINO ESTATE", (-3000, 7200)), ("MORETTI ESTATE (rival)", (4700, -9800))]
    f = lambda size, wt=600: _font(bp.FONT_UI, size, wt)
    fd = lambda size: _font(bp.FONT_DISPLAY, size, 700)
    for name, pos in examples:
        cx, cy = px(pos)
        d.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill="#d9473a" if "rival" in name else "#ffd27a", outline="#000")
        bp.label(d, (cx + 14, cy), name, f(18, 700), fill="#ffd27a", anchor="lm", stroke=3)
    # Labels.
    for r in REGIONS:
        xs = [p[0] for p in r["polygon"]]
        zs = [p[1] for p in r["polygon"]]
        c = px((sum(xs) / len(xs), sum(zs) / len(zs)))
        text = r["name"].upper() + (("\n%d ESTATES · %s" % (r["plots"], r["tier"].upper())) if r["kind"] == "estate" else "")
        bp.label(d, c, text, f(17 if r["kind"] != "core" else 16, 700),
                 fill="#ffe7b0" if r["kind"] == "estate" else "#efe6d2", stroke=4)
    for name, pos in LANDMARKS:
        bp.label(d, px(pos), name, f(15, 500), fill="#9fc0c8", stroke=3)
    for road in ROADS:
        mid = road["path"][len(road["path"]) // 2]
        bp.label(d, px(mid), road["name"], f(13, 600), fill="#e8c97f", stroke=3)
    # Title and legend.
    bp.panel(d, (20, 20, 760, 170))
    bp.label(d, (390, 66), "EMPIRE · WORLD RESTRUCTURE", fd(34), fill="#e8c97f", stroke=0)
    bp.label(d, (390, 122), "City core · outskirts · estate regions · scenery  (Phase A plan)", f(18, 600),
             fill="#cfc6b2", stroke=0)
    lx, ly = int(w * 0.36), h - 330  # over the Lower Bay / Atlantic, clear of land labels
    bp.panel(d, (lx, ly, lx + 520, h - 20))
    items = [("#6e4a3a", "City core (dense, businesses, territory)"), ("#7c6a52", "Outskirts (brownstones, suburbs, rail yards)"),
             ("#4f6e3a", "Estate regions (countryside, villages, lakes)"), ("#ffd27a", "Estate plot · prime"),
             ("#f0e6c8", "Estate plot · suburban"), ("#b9c7a8", "Estate plot · outer"), ("#c9a24a", "Bridge / parkway")]
    for k, (col, txt) in enumerate(items):
        y = ly + 34 + k * 40
        d.rectangle([lx + 20, y - 10, lx + 46, y + 10], fill=col, outline="#000")
        d.text((lx + 60, y), txt, font=f(17, 500), fill="#efe6d2", anchor="lm")
    sx, sy = w - 380, h - 60
    km = 1000 * SCALE
    d.rectangle([sx - 14, sy - 40, sx + 5 * km + 40, sy + 24], fill="#0c0b0a")
    d.line([sx, sy, sx + 5 * km, sy], fill="#efe6d2", width=4)
    for t in range(6):
        d.line([sx + t * km, sy - 8, sx + t * km, sy + 8], fill="#efe6d2", width=2)
    d.text((sx + 5 * km * 0.5, sy - 24), "5 km (game metres)", font=f(15, 600), fill="#efe6d2", anchor="mm")
    out = os.path.join(ROOT, "docs", "geography", "world_restructure_plan.png")
    img.save(out)
    caps = {}
    for p in plots:
        caps[p["tier"]] = caps.get(p["tier"], 0) + 1
    summary = {"frame_m": [EXT[2] - EXT[0], EXT[3] - EXT[1]], "plot_m": PLOT, "spacing_m": SPACING,
               "capacity": caps, "total": len(plots),
               "regions": [{k: r[k] for k in ("id", "kind", "name") if k in r} | ({"tier": r["tier"], "plots": r["plots"]}
                           if r["kind"] == "estate" else {}) for r in REGIONS]}
    with open(os.path.join(ROOT, "data", "world", "estate_plan.json"), "w") as fh:
        json.dump(dict(summary, plots=plots), fh, indent=1)
    print(json.dumps(summary, indent=1))


def _font(path, size, weight):
    font = ImageFont.truetype(path, size)
    try:
        font.set_variation_by_axes([weight] if "Cinzel" in path else [14, weight])
    except Exception:
        try:
            font.set_variation_by_axes([weight])
        except Exception:
            pass
    return font


if __name__ == "__main__":
    main()
