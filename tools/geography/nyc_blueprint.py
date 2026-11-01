#!/usr/bin/env python3
"""EMPIRE: RUN NEW YORK - Greater New York geography blueprint (Phase 1).

Authors the world geography as data and renders a labelled top-down preview.
Nothing here touches the running game; Phase 2 will consume the JSON.

Outputs:
  data/world/nyc_1977_blueprint.json      geography data (schema v1)
  docs/geography/nyc_1977_blueprint.png   labelled province map
  docs/geography/lower_manhattan.png      Little Italy placement close-up

Frame: metres, +X east, +Z south (image down = south). Little Italy keeps its
existing coordinates exactly (translation 0,0): rect x[-218,226] z[-196,198].

Variable compression (like a tourist map): Lower Manhattan ~1:1.3, Midtown
~1:2, outer boroughs ~1:2.5-3, rivers ~1:1.5 so crossings stay meaningful.

Usage: python3 tools/geography/nyc_blueprint.py
"""
import json
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FONT_DISPLAY = os.path.join(ROOT, "assets", "fonts", "Cinzel-Variable.ttf")
FONT_UI = os.path.join(ROOT, "assets", "fonts", "Inter-Variable.ttf")

LI_RECT = (-218, -196, 226, 198)
AXIS_SLOPE = 0.42  # Manhattan's long axis leans east going north (~23 degrees)
GRID_ANGLE = math.degrees(math.atan(AXIS_SLOPE))
# One Commissioners' grid for Manhattan above Houston/14th (shared lattice).
MANHATTAN_PITCH = (220, 72)


# ---------------------------------------------------------------------------
# Landforms
# ---------------------------------------------------------------------------
def manhattan_center(z):
    return 50 + AXIS_SLOPE * (-z) if z < 0 else 50 - 0.25 * z


MAN_PROFILE = [  # z, west offset, east offset (relative to the centre line)
        (1300, -1100, 560), (900, -1330, 820), (600, -1380, 900), (300, -1330, 1010), (150, -1300, 1130),
        (0, -1310, 1070), (-400, -1180, 870), (-800, -1060, 880), (-1200, -950, 940), (-1800, -900, 900),
        (-2400, -880, 870), (-3000, -820, 830), (-3600, -770, 780), (-4200, -720, 840), (-4600, -660, 760),
        (-5200, -600, 560), (-5800, -540, 500), (-6400, -450, 430), (-6900, -330, 330), (-7250, -180, 170),
]


def shore_road(side, inset, z_from, z_to):
    """Waterfront road following Manhattan's shore `inset` metres inland."""
    pts = [(manhattan_center(z) + (w + inset if side == "west" else e - inset), z)
           for z, w, e in MAN_PROFILE if z_to <= z <= z_from]
    return pts


def manhattan():
    """Island outline built from the leaning centre line and authored widths,
    with Corlears Hook, East Harlem and the Battery shaped by hand."""
    profile = MAN_PROFILE
    west = [(manhattan_center(z) + w, z) for z, w, _ in profile]
    east = [(manhattan_center(z) + e, z) for z, _, e in profile]
    tip_south = [(-560, 1720), (-350, 1790), (-80, 1640), (200, 1480)]
    tip_north = [(manhattan_center(-7450), -7450)]
    return [tip_south[0], tip_south[1], tip_south[2], tip_south[3]] + east + tip_north + list(reversed(west))


def offset_line(points, d):
    out = []
    for i, (x, z) in enumerate(points):
        a = points[max(0, i - 1)]
        b = points[min(len(points) - 1, i + 1)]
        dx, dz = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dz) or 1
        out.append((x + dz / n * d, z - dx / n * d))
    return out


def brooklyn():
    west = [(560, 5000), (760, 4300), (640, 3500), (760, 2900), (960, 2350), (1080, 1850), (1170, 1420),
            (1420, 1100), (1580, 760), (1770, 640), (1720, 240), (1690, -150), (1760, -520), (1880, -900),
            (2040, -1180), (2160, -1430)]
    creek = [(2600, -1360), (3100, -1420), (3700, -1330), (4300, -1520)]
    queens_border = [(4700, -1100), (5200, -400), (5900, 300), (6600, 900), (7600, 1100)]
    south = [(7600, 5000)]
    return west + creek + queens_border + south


def queens():
    river = [(2160, -1430), (2330, -1980), (2450, -2560), (2640, -3150), (2860, -3620), (3020, -3950),
             (3150, -4320), (3420, -4620)]
    north = [(3900, -4760), (4500, -4840), (4760, -5180), (5280, -5320), (5900, -5300), (6200, -4980),
             (6150, -4600), (6450, -4420), (6800, -4700), (7600, -4900)]
    east = [(7600, 1100)]
    border = [(6600, 900), (5900, 300), (5200, -400), (4700, -1100), (4300, -1520), (3700, -1330), (3100, -1420),
              (2600, -1360)]
    return river + north + east + border


def bronx():
    harlem_river = [(manhattan_center(z) + e + 170, z) for z, e in
                    ((-4700, 820), (-5200, 600), (-5800, 540), (-6400, 470), (-6900, 370), (-7300, 230))]
    south = [(3350, -4980), (3900, -5150), (4150, -5650), (4500, -5400), (5100, -5800), (5800, -5880),
             (6400, -5650), (7600, -5900)]
    north = [(7600, -8900), (manhattan_center(-7300) + 230 + 170, -8900)]
    return [harlem_river[0]] + south + north + list(reversed(harlem_river[1:]))


def new_jersey():
    shore = [(manhattan_center(z) + w - 820, z) for z, w in
             ((-8900, -330), (-7250, -330), (-6400, -450), (-5200, -600), (-4200, -720), (-3000, -820),
              (-1800, -900), (-800, -1060), (0, -1310), (600, -1380), (1200, -1150))]
    shore += [(-1700, 1900), (-1500, 2800), (-1900, 3900), (-2300, 5000)]
    return shore + [(-3600, 5000), (-3600, -8900)]


def rect_poly(x0, z0, x1, z1):
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def rotated_rect(cx, cz, length, width, angle_deg):
    a = math.radians(angle_deg)
    # Long axis points "north along Manhattan": (sin a, -cos a)
    ux, uz = math.sin(a), -math.cos(a)
    vx, vz = math.cos(a), math.sin(a)
    hl, hw = length / 2, width / 2
    return [(cx + ux * hl + vx * hw, cz + uz * hl + vz * hw), (cx + ux * hl - vx * hw, cz + uz * hl - vz * hw),
            (cx - ux * hl - vx * hw, cz - uz * hl - vz * hw), (cx - ux * hl + vx * hw, cz - uz * hl + vz * hw)]


BOROUGHS = [
    {"id": "manhattan", "name": "Manhattan", "borough": "manhattan", "kind": "playable", "polygon": manhattan()},
    {"id": "brooklyn", "name": "Brooklyn", "borough": "brooklyn", "kind": "playable", "polygon": brooklyn()},
    {"id": "queens", "name": "Queens", "borough": "queens", "kind": "playable", "polygon": queens()},
    {"id": "bronx", "name": "The Bronx", "borough": "bronx", "kind": "playable", "polygon": bronx()},
    {"id": "roosevelt_island", "name": "Roosevelt Island", "borough": "manhattan", "kind": "playable",
     "polygon": rotated_rect(2210, -2700, 1300, 90, GRID_ANGLE)},
    {"id": "randalls_island", "name": "Randall's Island", "borough": "manhattan", "kind": "playable",
     "polygon": [(2980, -4520), (3280, -4560), (3360, -4880), (3120, -5000), (2900, -4800)]},
    {"id": "staten_island", "name": "Staten Island (future)", "borough": "staten_island", "kind": "future",
     "polygon": [(-3600, 5300), (-1300, 5000), (100, 5600), (0, 6400), (-3600, 6400)]},
]

PAD = 1500  # scenery land runs this far past the extent so no map edge is ever visible


def chaikin(poly, iterations=2, jitter=14.0, seed=0):
    """Rounded, slightly irregular shoreline: Chaikin corner cutting plus a
    deterministic sideways wobble on new vertices."""
    rng = random.Random(seed)
    pts = list(poly)
    for _ in range(iterations):
        out = []
        n = len(pts)
        for i in range(n):
            a, b = pts[i], pts[(i + 1) % n]
            for t in (0.25, 0.75):
                x, z = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
                dx, dz = b[0] - a[0], b[1] - a[1]
                ln = math.hypot(dx, dz) or 1.0
                w = rng.uniform(-jitter, jitter) if ln > 120 else 0.0
                out.append((x - dz / ln * w, z + dx / ln * w))
        pts = out
    return pts


def _coast_long_island():
    west = brooklyn()[:16]          # Bay Ridge -> Newtown Creek mouth
    river = queens()[:18]           # East River shore -> Flushing Bay
    return [(300, 6400 + PAD)] + west + river[1:] + [(9200 + PAD, -4500), (9200 + PAD, 6400 + PAD)]


def _coast_bronx():
    b = bronx()
    hr0 = b[0]
    south = b[1:9]
    hr_rest = b[11:]
    west_x = hr_rest[0][0]
    return [hr0] + south + [(8200, -6500), (9200 + PAD, -6900), (9200 + PAD, -8900 - PAD),
                            (west_x, -8900 - PAD)] + hr_rest


def _coast_new_jersey():
    pts = new_jersey()
    return [(x if x > -3600 else -3600 - PAD, z if z > -8900 else -8900 - PAD) for x, z in pts[:-2]] + \
        [(-2300, 6400 + PAD), (-3600 - PAD, 6400 + PAD), (-3600 - PAD, -8900 - PAD)]


COASTS = [
    {"id": "manhattan", "name": "Manhattan", "kind": "playable", "polygon": manhattan()},
    {"id": "long_island", "name": "Brooklyn / Queens / Long Island", "kind": "playable", "polygon": _coast_long_island()},
    {"id": "bronx", "name": "The Bronx / Westchester", "kind": "playable", "polygon": _coast_bronx()},
    {"id": "roosevelt_island", "name": "Roosevelt Island", "kind": "playable", "polygon": BOROUGHS[4]["polygon"]},
    {"id": "randalls_island", "name": "Randall's Island", "kind": "playable", "polygon": BOROUGHS[5]["polygon"]},
    {"id": "governors_island", "name": "Governors Island", "kind": "scenery",
     "polygon": [(200, 2250), (520, 2180), (560, 2460), (300, 2560), (150, 2420)]},
    {"id": "liberty_island", "name": "Liberty Island", "kind": "scenery",
     "polygon": [(-1150, 2620), (-1020, 2600), (-1000, 2720), (-1140, 2740)]},
    {"id": "new_jersey", "name": "New Jersey", "kind": "scenery", "polygon": _coast_new_jersey()},
    {"id": "staten_island", "name": "Staten Island", "kind": "scenery",
     "polygon": [(-3600 - PAD, 5300), (-1300, 5000), (100, 5600), (0, 6400 + PAD), (-3600 - PAD, 6400 + PAD)]},
]
for _i, _c in enumerate(COASTS):
    _c["polygon"] = chaikin(_c["polygon"], seed=_i + 1)
# Kept for the renderer: everything drawn as land.
LANDMASSES = COASTS

WATERWAYS = [
    {"id": "hudson_river", "name": "Hudson River", "label_at": (manhattan_center(-3300) - 1200, -3300), "angle": GRID_ANGLE},
    {"id": "east_river", "name": "East River", "label_at": (1500, 300), "angle": 0},
    {"id": "harlem_river", "name": "Harlem River", "label_at": (3150, -6200), "angle": GRID_ANGLE + 6},
    {"id": "upper_bay", "name": "Upper New York Bay", "label_at": (-450, 3500), "angle": 0},
    {"id": "newtown_creek", "name": "Newtown Creek", "label_at": (3200, -1460), "angle": 0},
    {"id": "flushing_bay", "name": "Flushing Bay", "label_at": (6250, -5050), "angle": 0},
    {"id": "hell_gate", "name": "Hell Gate", "label_at": (3150, -4300), "angle": 0},
]

PARKS = [
    {"id": "central_park", "name": "Central Park", "kind": "landmark_park",
     "polygon": rotated_rect(manhattan_center(-3450) - 30, -3450, 1720, 470, GRID_ANGLE),
     "lakes": [rotated_rect(manhattan_center(-3880) + 10, -3880, 380, 230, GRID_ANGLE),
               rotated_rect(manhattan_center(-3150) - 60, -3150, 160, 90, GRID_ANGLE - 30)]},
    {"id": "prospect_park", "name": "Prospect Park", "kind": "park",
     "polygon": [(2350, 2650), (3000, 2500), (3250, 3100), (2850, 3550), (2300, 3300)],
     "lakes": [[(2550, 3150), (2850, 3050), (2900, 3300), (2650, 3380)]]},
    {"id": "flushing_meadows", "name": "Flushing Meadows", "kind": "park",
     "polygon": [(5850, -3400), (6450, -3500), (6600, -2300), (6200, -1700), (5750, -2200)],
     "lakes": [[(6050, -2500), (6350, -2550), (6350, -2100), (6100, -2050)]]},
    {"id": "riverside_park", "name": "Riverside Park", "kind": "park",
     "polygon": offset_line([(manhattan_center(z) - 760, z) for z in range(-2900, -5000, -300)], 0)
     + list(reversed(offset_line([(manhattan_center(z) - 680, z) for z in range(-2900, -5000, -300)], 0)))},
    {"id": "washington_square", "name": "Washington Sq", "kind": "square",
     "polygon": rect_poly(-470, -920, -360, -830)},
    {"id": "tompkins_square", "name": "Tompkins Sq", "kind": "square",
     "polygon": rotated_rect(720, -900, 150, 120, 0)},
    {"id": "van_cortlandt", "name": "Bronx Park", "kind": "park",
     "polygon": [(4700, -7800), (5600, -7900), (5800, -7000), (5100, -6700), (4600, -7100)]},
    {"id": "mccarren_park", "name": "McCarren Park", "kind": "park",
     "polygon": [(2350, -850), (2600, -900), (2650, -650), (2400, -620)]},
]

# District seeds: districts are the land cells nearest each seed (clipped to
# their landmass); explicit polygons override (Little Italy, parks, airport).
DISTRICTS = [
    # Manhattan
    {"id": "little_italy", "name": "Little Italy", "borough": "manhattan", "seed": (4, 1), "style": "li_tenement",
     "polygon": rect_poly(*LI_RECT), "territory": "player", "preserved": True},
    {"id": "financial_district", "name": "Financial District", "borough": "manhattan", "seed": (50, 1350),
     "style": "highrise_old", "grid": {"angle": -12, "pitch": (85, 70)}, "territory": "neutral"},
    {"id": "chinatown", "name": "Chinatown", "borough": "manhattan", "seed": (150, 650), "style": "tenement",
     "grid": {"angle": 0, "pitch": (80, 92)}, "territory": "neutral"},
    {"id": "tribeca", "name": "Tribeca", "borough": "manhattan", "seed": (-750, 550), "style": "loft_industrial",
     "grid": {"angle": -8, "pitch": (110, 80)}, "territory": "rival"},
    {"id": "the_docks", "name": "The Docks", "borough": "manhattan", "seed": (-1150, 1050), "style": "waterfront",
     "grid": {"angle": -8, "pitch": (160, 120)}, "territory": "rival"},
    {"id": "soho", "name": "SoHo", "borough": "manhattan", "seed": (-560, -120), "style": "cast_iron",
     "grid": {"angle": 0, "pitch": (80, 92)}, "territory": "neutral"},
    {"id": "lower_east_side", "name": "Lower East Side", "borough": "manhattan", "seed": (640, 60),
     "style": "tenement", "grid": {"angle": 0, "pitch": (80, 92)}, "territory": "neutral"},
    {"id": "nolita", "name": "Nolita", "borough": "manhattan", "seed": (10, -470), "style": "tenement",
     "grid": {"angle": 0, "pitch": (80, 92)}, "territory": "neutral"},
    {"id": "greenwich_village", "name": "Greenwich Village", "borough": "manhattan", "seed": (-440, -860),
     "style": "village_irregular", "grid": {"angle": -38, "pitch": (70, 60), "irregular": True},
     "territory": "neutral"},
    {"id": "east_village", "name": "East Village", "borough": "manhattan", "seed": (600, -800), "style": "tenement",
     "grid": {"angle": GRID_ANGLE, "pitch": (90, 70)}, "territory": "contested"},
    {"id": "chelsea", "name": "Chelsea", "borough": "manhattan", "seed": (120, -1720), "style": "rowhouse_mix",
     "grid": {"angle": GRID_ANGLE, "pitch": MANHATTAN_PITCH}, "territory": "neutral"},
    {"id": "gramercy", "name": "Gramercy", "borough": "manhattan", "seed": (950, -1500), "style": "rowhouse_mix",
     "grid": {"angle": GRID_ANGLE, "pitch": MANHATTAN_PITCH}, "territory": "neutral"},
    {"id": "hells_kitchen", "name": "Hell's Kitchen", "borough": "manhattan", "seed": (420, -2500),
     "style": "tenement", "grid": {"angle": GRID_ANGLE, "pitch": MANHATTAN_PITCH}, "territory": "contested"},
    {"id": "midtown", "name": "Midtown", "borough": "manhattan", "seed": (1050, -2250), "style": "highrise",
     "grid": {"angle": GRID_ANGLE, "pitch": MANHATTAN_PITCH}, "territory": "neutral"},
    {"id": "times_square", "name": "Times Square", "borough": "manhattan", "seed": (700, -2150), "style": "theatre",
     "grid": {"angle": GRID_ANGLE, "pitch": MANHATTAN_PITCH}, "territory": "neutral"},
    {"id": "murray_hill", "name": "Murray Hill", "borough": "manhattan", "seed": (1500, -1950), "style": "highrise",
     "grid": {"angle": GRID_ANGLE, "pitch": MANHATTAN_PITCH}, "territory": "neutral"},
    {"id": "upper_west_side", "name": "Upper West Side", "borough": "manhattan", "seed": (950, -3600),
     "style": "prewar_apartments", "grid": {"angle": GRID_ANGLE, "pitch": MANHATTAN_PITCH}, "territory": "neutral"},
    {"id": "upper_east_side", "name": "Upper East Side", "borough": "manhattan", "seed": (2100, -3200),
     "style": "prewar_apartments", "grid": {"angle": GRID_ANGLE, "pitch": MANHATTAN_PITCH}, "territory": "neutral"},
    {"id": "harlem", "name": "Harlem", "borough": "manhattan", "seed": (2050, -4800), "style": "tenement",
     "grid": {"angle": GRID_ANGLE, "pitch": MANHATTAN_PITCH}, "territory": "contested"},
    {"id": "east_harlem", "name": "East Harlem", "borough": "manhattan", "seed": (2550, -4400), "style": "tenement",
     "grid": {"angle": GRID_ANGLE, "pitch": MANHATTAN_PITCH}, "territory": "neutral"},
    {"id": "washington_heights", "name": "Washington Heights", "borough": "manhattan", "seed": (2650, -6300),
     "style": "prewar_apartments", "grid": {"angle": GRID_ANGLE + 4, "pitch": (200, 80)}, "territory": "neutral"},
    # Brooklyn
    {"id": "brooklyn_heights", "name": "Brooklyn Heights", "borough": "brooklyn", "seed": (1450, 1700),
     "style": "brownstone", "grid": {"angle": 8, "pitch": (90, 80)}, "territory": "neutral"},
    {"id": "dumbo_navy_yard", "name": "Brooklyn Navy Yard", "borough": "brooklyn", "seed": (2000, 850),
     "style": "shipyard", "grid": {"angle": 0, "pitch": (180, 140)}, "territory": "neutral"},
    {"id": "williamsburg", "name": "Williamsburg", "borough": "brooklyn", "seed": (2350, -150),
     "style": "industrial_mix", "grid": {"angle": 26, "pitch": (120, 85)}, "territory": "contested"},
    {"id": "greenpoint", "name": "Greenpoint", "borough": "brooklyn", "seed": (2500, -1100), "style": "rowhouse_mix",
     "grid": {"angle": 0, "pitch": (100, 80)}, "territory": "contested"},
    {"id": "bushwick", "name": "Bushwick", "borough": "brooklyn", "seed": (3900, -100), "style": "rowhouse_mix",
     "grid": {"angle": 32, "pitch": (110, 80)}, "territory": "contested"},
    {"id": "bed_stuy", "name": "Bedford-Stuyvesant", "borough": "brooklyn", "seed": (3300, 1350),
     "style": "brownstone", "grid": {"angle": 0, "pitch": (230, 90)}, "territory": "contested"},
    {"id": "crown_heights", "name": "Crown Heights", "borough": "brooklyn", "seed": (3900, 2700),
     "style": "brownstone", "grid": {"angle": 0, "pitch": (230, 90)}, "territory": "neutral"},
    {"id": "park_slope", "name": "Park Slope", "borough": "brooklyn", "seed": (1900, 2700), "style": "brownstone",
     "grid": {"angle": -24, "pitch": (100, 220)}, "territory": "neutral"},
    {"id": "red_hook", "name": "Red Hook Port", "borough": "brooklyn", "seed": (1150, 2950), "style": "waterfront",
     "grid": {"angle": -24, "pitch": (160, 120)}, "territory": "neutral"},
    {"id": "east_new_york", "name": "East New York", "borough": "brooklyn", "seed": (5600, 2400),
     "style": "lowrise_residential", "grid": {"angle": 10, "pitch": (150, 90)}, "territory": "neutral"},
    {"id": "sunset_park", "name": "Sunset Park", "borough": "brooklyn", "seed": (1500, 4200),
     "style": "industrial_mix", "grid": {"angle": -24, "pitch": (100, 220)}, "territory": "neutral"},
    # Queens
    {"id": "long_island_city", "name": "Long Island City", "borough": "queens", "seed": (2850, -2250),
     "style": "industrial_mix", "grid": {"angle": 18, "pitch": (150, 100)}, "territory": "neutral"},
    {"id": "astoria", "name": "Astoria", "borough": "queens", "seed": (3400, -3500), "style": "lowrise_residential",
     "grid": {"angle": 40, "pitch": (120, 90)}, "territory": "neutral"},
    {"id": "sunnyside", "name": "Sunnyside", "borough": "queens", "seed": (3800, -2200),
     "style": "lowrise_residential", "grid": {"angle": 12, "pitch": (130, 90)}, "territory": "neutral"},
    {"id": "maspeth", "name": "Maspeth Industrial", "borough": "queens", "seed": (4300, -1150),
     "style": "heavy_industrial", "grid": {"angle": 6, "pitch": (220, 160)}, "territory": "neutral"},
    {"id": "jackson_heights", "name": "Jackson Heights", "borough": "queens", "seed": (4900, -3300),
     "style": "garden_apartments", "grid": {"angle": 0, "pitch": (160, 100)}, "territory": "neutral"},
    {"id": "elmhurst", "name": "Elmhurst", "borough": "queens", "seed": (5000, -2000),
     "style": "lowrise_residential", "grid": {"angle": -10, "pitch": (140, 90)}, "territory": "neutral"},
    {"id": "corona", "name": "Corona", "borough": "queens", "seed": (5500, -3800), "style": "lowrise_residential",
     "grid": {"angle": 0, "pitch": (130, 90)}, "territory": "neutral"},
    {"id": "flushing", "name": "Flushing", "borough": "queens", "seed": (7000, -3300), "style": "suburban_queens",
     "grid": {"angle": 0, "pitch": (170, 110)}, "territory": "neutral"},
    {"id": "laguardia", "name": "LaGuardia Airport", "borough": "queens", "seed": (5300, -4900),
     "style": "airport", "territory": "neutral",
     "polygon": [(4700, -4850), (5250, -5300), (5900, -5280), (6150, -4950), (6100, -4550), (4900, -4500)]},
    {"id": "ridgewood", "name": "Ridgewood", "borough": "queens", "seed": (5200, -600),
     "style": "lowrise_residential", "grid": {"angle": 20, "pitch": (130, 90)}, "territory": "neutral"},
    # Bronx
    {"id": "south_bronx", "name": "South Bronx", "borough": "bronx", "seed": (3600, -5700), "style": "tenement",
     "grid": {"angle": 30, "pitch": (150, 90)}, "territory": "neutral"},
    {"id": "hunts_point", "name": "Hunts Point", "borough": "bronx", "seed": (4300, -5600),
     "style": "heavy_industrial", "grid": {"angle": -10, "pitch": (200, 150)}, "territory": "neutral"},
    {"id": "concourse", "name": "Grand Concourse", "borough": "bronx", "seed": (3700, -7000),
     "style": "prewar_apartments", "grid": {"angle": 8, "pitch": (160, 90)}, "territory": "neutral"},
    {"id": "fordham", "name": "Fordham", "borough": "bronx", "seed": (4100, -8100), "style": "tenement",
     "grid": {"angle": 14, "pitch": (150, 90)}, "territory": "neutral"},
    {"id": "soundview", "name": "Soundview", "borough": "bronx", "seed": (5700, -6400), "style": "towers_in_park",
     "grid": {"angle": 0, "pitch": (220, 140)}, "territory": "neutral"},
    {"id": "throgs_neck", "name": "Throgs Neck", "borough": "bronx", "seed": (6900, -6600),
     "style": "suburban_queens", "grid": {"angle": -20, "pitch": (170, 120)}, "territory": "neutral"},
    {"id": "randalls", "name": "Randall's Island", "borough": "manhattan", "seed": (3130, -4760), "style": "park",
     "territory": "neutral"},
    {"id": "roosevelt", "name": "Roosevelt Island", "borough": "manhattan", "seed": (2210, -2700),
     "style": "towers_in_park", "territory": "neutral"},
]

# Neighbourhood generation rules for Phase 3 (palette, heights, density).
STYLES = {
    "li_tenement": {"label": "Little Italy (preserved)", "color": "#8a3f2e", "floors": [3, 6], "density": 1.0,
                    "kinds": ["midblock", "corner_left", "corner_right"]},
    "tenement": {"label": "Tenements", "color": "#7e4b3a", "floors": [4, 7], "density": 0.95},
    "highrise_old": {"label": "Financial towers", "color": "#8a8478", "floors": [12, 40], "density": 0.85},
    "highrise": {"label": "Midtown office & hotels", "color": "#8f8a80", "floors": [10, 60], "density": 0.8},
    "theatre": {"label": "Theatres & neon", "color": "#9a6a4a", "floors": [4, 30], "density": 0.9},
    "cast_iron": {"label": "Cast-iron lofts", "color": "#8a7a68", "floors": [5, 8], "density": 0.85},
    "loft_industrial": {"label": "Warehouse lofts", "color": "#6f655c", "floors": [3, 8], "density": 0.7},
    "village_irregular": {"label": "Village rowhouses", "color": "#8a5b45", "floors": [3, 6], "density": 0.85},
    "rowhouse_mix": {"label": "Rowhouses & walk-ups", "color": "#86604a", "floors": [3, 6], "density": 0.75},
    "prewar_apartments": {"label": "Pre-war apartments", "color": "#9a7d62", "floors": [6, 15], "density": 0.8},
    "brownstone": {"label": "Brownstones", "color": "#7a5240", "floors": [3, 4], "density": 0.75},
    "industrial_mix": {"label": "Mixed industry", "color": "#6c6660", "floors": [2, 6], "density": 0.6},
    "heavy_industrial": {"label": "Heavy industry & rail", "color": "#5f5b56", "floors": [1, 4], "density": 0.45},
    "shipyard": {"label": "Shipyard & docks", "color": "#5c5f63", "floors": [1, 5], "density": 0.4},
    "waterfront": {"label": "Piers & warehouses", "color": "#606468", "floors": [1, 5], "density": 0.45},
    "lowrise_residential": {"label": "Low-rise residential", "color": "#8a7462", "floors": [2, 4], "density": 0.65},
    "garden_apartments": {"label": "Garden apartments", "color": "#86765e", "floors": [3, 6], "density": 0.55},
    "suburban_queens": {"label": "Detached houses", "color": "#7d8463", "floors": [1, 2], "density": 0.4},
    "towers_in_park": {"label": "Towers in parkland", "color": "#7f8670", "floors": [12, 20], "density": 0.3},
    "airport": {"label": "Airport", "color": "#6b6e6a", "floors": [1, 3], "density": 0.1},
    "park": {"label": "Park", "color": "#4d6e38", "floors": [0, 0], "density": 0.0},
}

# Block fill rules per style (consumed by the game's BlockFiller): building
# kinds from the catalogue, corner buildings, setback, gaps between buildings,
# street trees, lawns, and whether side streets get frontages.
FILL = {
    "tenement": {"kinds": ["midblock", "walkup"], "corners": True, "gap": [0, 0], "trees": 0.55},
    "highrise_old": {"kinds": ["midblock_tall", "midblock", "apartment"], "corners": True, "gap": [0, 0], "trees": 0.2,
                     "tower_kinds": ["highrise"], "tower_chance": 0.6},
    "highrise": {"kinds": ["apartment", "midblock_tall", "midblock"], "corners": True, "gap": [0, 0], "trees": 0.25,
                 "tower_kinds": ["highrise"], "tower_chance": 0.8},
    "theatre": {"kinds": ["midblock", "midblock_tall", "midblock_low"], "corners": True, "gap": [0, 0], "trees": 0.1,
                "tower_kinds": ["highrise"], "tower_chance": 0.3},
    "cast_iron": {"kinds": ["industrial", "midblock"], "corners": False, "gap": [0, 2], "trees": 0.3},
    "loft_industrial": {"kinds": ["industrial"], "corners": False, "gap": [1, 6], "trees": 0.15},
    "village_irregular": {"kinds": ["rowhouse", "midblock"], "corners": True, "gap": [0, 0], "trees": 0.9},
    "rowhouse_mix": {"kinds": ["rowhouse", "midblock", "midblock_low", "brooklyn", "walkup"], "corners": False,
                     "gap": [0, 0], "trees": 0.75},
    "prewar_apartments": {"kinds": ["midblock_tall", "apartment", "midblock"], "corners": True, "gap": [0, 0], "trees": 0.8},
    "brownstone": {"kinds": ["rowhouse", "brooklyn"], "corners": False, "gap": [0, 0], "trees": 0.9, "primary_only": True},
    "industrial_mix": {"kinds": ["industrial", "midblock_low", "brooklyn"], "corners": False, "gap": [3, 12], "trees": 0.15},
    "heavy_industrial": {"kinds": ["industrial"], "corners": False, "gap": [6, 22], "trees": 0.05},
    "shipyard": {"kinds": ["industrial"], "corners": False, "gap": [10, 30], "trees": 0.0},
    "waterfront": {"kinds": ["industrial"], "corners": False, "gap": [6, 18], "trees": 0.0},
    "lowrise_residential": {"kinds": ["rowhouse", "house", "midblock_low", "brooklyn"], "corners": False, "gap": [1, 4],
                            "trees": 0.85},
    "garden_apartments": {"kinds": ["midblock_tall", "apartment"], "corners": False, "gap": [14, 26], "setback": 8, "trees": 0.9,
                          "lawns": True},
    "suburban_queens": {"kinds": ["house"], "corners": False, "gap": [5, 11], "setback": 7, "trees": 0.9, "lawns": True},
    "towers_in_park": {"kinds": ["midblock_tall", "apartment"], "corners": False, "gap": [24, 44], "setback": 14, "trees": 0.9,
                       "lawns": True},
    "airport": {"kinds": [], "corners": False, "gap": [0, 0], "trees": 0.0},
    "park": {"kinds": [], "corners": False, "gap": [0, 0], "trees": 0.0},
    "li_tenement": {"kinds": ["midblock"], "corners": True, "gap": [0, 0], "trees": 0.62},
}
# Block interiors behind the frontage: backyards, work yards or paved plazas.
YARDS = {"M_Grass": ["tenement", "village_irregular", "rowhouse_mix", "prewar_apartments", "brownstone",
                     "lowrise_residential", "garden_apartments", "suburban_queens", "towers_in_park"],
         "M_Gravel": ["cast_iron", "loft_industrial", "industrial_mix", "heavy_industrial", "shipyard", "waterfront"]}
for _k, _v in FILL.items():
    for _mat, _styles in YARDS.items():
        if _k in _styles:
            _v["yard"] = _mat
    STYLES[_k]["fill"] = _v

TERRITORY_COLORS = {"player": "#d9473a", "rival": "#4f8fd9", "contested": "#a36fd1"}


def mc(z, off=0.0):
    return (manhattan_center(z) + off, z)


# Major roads: grids live inside districts; these are the network spine.
ROADS = [
    {"id": "fdr_drive", "name": "FDR Drive", "class": "expressway", "width": 22, "speed": 1800,
     "path": [(120, 1400)] + shore_road("east", 110, 900, -4600)},
    {"id": "west_side_hwy", "name": "West Side Highway", "class": "expressway", "width": 22, "speed": 1800,
     "path": [(-450, 1640)] + shore_road("west", 110, 1300, -7000)},
    {"id": "broadway", "name": "Broadway", "class": "avenue", "width": 18, "speed": 1300,
     "path": [(-300, 1550), (-340, 900), (-360, 300), (-330, -300), (-250, -900), (80, -1500), (400, -1900),
              (650, -2200), (850, -2600), mc(-3000, -380), mc(-4000, -420), mc(-5000, -330), mc(-6000, -250),
              mc(-7000, -160)]},
    {"id": "bowery_3rd_ave", "name": "Bowery / Third Ave", "class": "avenue", "width": 20, "speed": 1300,
     "path": [(168, 900), (168, 198), (168, -196), (250, -700), mc(-1200, 120), mc(-2400, 230), mc(-3600, 470),
              mc(-4600, 520)]},
    {"id": "houston_st", "name": "Houston St", "class": "arterial", "width": 18, "speed": 1400,
     "path": [(-800, -560), (-500, -550), (0, -560), (500, -560), (1050, -550)]},
    {"id": "canal_st", "name": "Canal St", "class": "arterial", "width": 20, "speed": 1300,
     "path": [(-1300, 230), (-700, 180), (-218, 140), (226, 140), (420, 260)]},
    {"id": "delancey_st", "name": "Delancey St", "class": "arterial", "width": 20, "speed": 1300,
     "path": [(226, -230), (600, -260), (1000, -300)]},
    {"id": "42nd_st", "name": "42nd St", "class": "arterial", "width": 18, "speed": 1300,
     "path": [mc(-2350, -880), mc(-2350, 0), mc(-2350, 890)]},
    {"id": "125th_st", "name": "125th St", "class": "arterial", "width": 18, "speed": 1300,
     "path": [mc(-4700, -640), mc(-4700, 0), mc(-4700, 760)]},
    {"id": "bqe", "name": "Brooklyn-Queens Expwy", "class": "expressway", "width": 24, "speed": 1800,
     "path": [(1150, 3300), (1250, 2400), (1350, 1700), (1650, 1150), (2100, 800), (2250, 200), (2300, -400),
              (2450, -1000), (2700, -1500), (3300, -2100), (3900, -2800), (4300, -3500), (4400, -4300)]},
    {"id": "atlantic_ave", "name": "Atlantic Ave", "class": "arterial", "width": 20, "speed": 1400,
     "path": [(1200, 2050), (2200, 2000), (3300, 1950), (4500, 1900), (5900, 1850), (7500, 1800)]},
    {"id": "eastern_pkwy", "name": "Eastern Pkwy", "class": "parkway", "width": 22, "speed": 1500,
     "path": [(3000, 2600), (3800, 2500), (4700, 2300), (5500, 1900), (6200, 1200)]},
    {"id": "broadway_brooklyn", "name": "Broadway (Bklyn)", "class": "avenue", "width": 18, "speed": 1300,
     "path": [(1750, -350), (2600, 100), (3400, 500), (4300, 1000), (5300, 1500)]},
    {"id": "lie", "name": "Long Island Expwy", "class": "expressway", "width": 24, "speed": 1900,
     "path": [(2500, -2000), (3400, -1900), (4300, -1900), (5100, -2100), (5900, -2300), (6600, -2600),
              (7600, -2800)]},
    {"id": "queens_blvd", "name": "Queens Blvd", "class": "arterial", "width": 26, "speed": 1500,
     "path": [(2550, -2650), (3300, -2600), (4100, -2500), (4800, -2300), (5500, -1900), (6400, -1400),
              (7500, -1000)]},
    {"id": "grand_central_pkwy", "name": "Grand Central Pkwy", "class": "parkway", "width": 22, "speed": 1700,
     "path": [(3250, -4560), (3700, -4400), (4300, -4300), (4800, -4400), (5400, -4400), (5950, -3900),
              (6400, -3300), (6900, -2600), (7600, -2400)]},
    {"id": "northern_blvd", "name": "Northern Blvd", "class": "arterial", "width": 20, "speed": 1400,
     "path": [(2600, -2900), (3500, -3000), (4400, -3100), (5300, -3300), (6100, -3500), (7600, -3600)]},
    {"id": "bruckner_expwy", "name": "Bruckner Expwy", "class": "expressway", "width": 22, "speed": 1800,
     "path": [(3200, -4950), (3800, -5300), (4250, -5750), (4600, -5800), (5000, -6000), (5700, -6150), (6500, -6100),
              (7500, -6200)]},
    {"id": "major_deegan", "name": "Major Deegan Expwy", "class": "expressway", "width": 22, "speed": 1800,
     "path": [(manhattan_center(z) + e + 170 + 130, z) for z, _, e in MAN_PROFILE if -7300 <= z <= -4700]
             + [(3700, -8000), (3850, -8850)]},
    {"id": "cross_bronx", "name": "Cross Bronx Expwy", "class": "expressway", "width": 24, "speed": 1800,
     "path": [(3450, -6800), (4200, -6900), (5000, -6800), (5900, -6700), (6700, -6500), (7500, -6400)]},
    {"id": "grand_concourse", "name": "Grand Concourse", "class": "parkway", "width": 22, "speed": 1500,
     "path": [(3400, -5600), (3650, -6400), (3850, -7200), (4050, -8000), (4250, -8800)]},
]

BRIDGES = [
    {"id": "brooklyn_bridge", "name": "Brooklyn Bridge", "kind": "suspension", "width": 26, "speed": 1600,
     "path": [(520, 1080), (820, 1220), (1180, 1420), (1450, 1580)], "connects": ["financial_district", "brooklyn_heights"]},
    {"id": "manhattan_bridge", "name": "Manhattan Bridge", "kind": "suspension", "width": 28, "speed": 1600,
     "path": [(168, 300), (520, 520), (1050, 760), (1600, 900), (1950, 950)], "connects": ["chinatown", "dumbo_navy_yard"]},
    {"id": "williamsburg_bridge", "name": "Williamsburg Bridge", "kind": "suspension", "width": 28, "speed": 1600,
     "path": [(1000, -300), (1250, -330), (1700, -360), (2050, -340)], "connects": ["lower_east_side", "williamsburg"]},
    {"id": "queensboro_bridge", "name": "Queensboro Bridge", "kind": "cantilever", "width": 28, "speed": 1600,
     "path": [mc(-2600, 650), (2210, -2690), (2560, -2660), (2800, -2640)], "connects": ["midtown", "long_island_city"]},
    {"id": "triborough_bridge", "name": "Triborough Bridge", "kind": "suspension", "width": 26, "speed": 1700,
     "path": [(2640, -4500), (3000, -4650), (3200, -4700), (3500, -4600), (3800, -4450)],
     "connects": ["east_harlem", "astoria"], "branch": [(3200, -4700), (3250, -5050)]},
    {"id": "willis_ave_bridge", "name": "Willis Ave Bridge", "kind": "swing", "width": 18, "speed": 1300,
     "path": [mc(-4950, 560), mc(-4950, 800)], "connects": ["east_harlem", "south_bronx"]},
    {"id": "macombs_dam_bridge", "name": "Macombs Dam Bridge", "kind": "swing", "width": 16, "speed": 1300,
     "path": [mc(-5900, 460), mc(-5900, 720)], "connects": ["harlem", "concourse"]},
    {"id": "pulaski_bridge", "name": "Pulaski Bridge", "kind": "bascule", "width": 18, "speed": 1300,
     "path": [(2700, -1250), (2720, -1520)], "connects": ["greenpoint", "long_island_city"]},
    {"id": "kosciuszko_bridge", "name": "Kosciuszko Bridge", "kind": "truss", "width": 22, "speed": 1700,
     "path": [(3300, -1300), (3380, -1550)], "connects": ["bushwick", "maspeth"]},
]

LANDMARKS = [
    {"id": "empire_state", "name": "Empire State Bldg", "pos": mc(-2150, 330), "kind": "skyscraper"},
    {"id": "chrysler", "name": "Chrysler Bldg", "pos": mc(-2380, 560), "kind": "skyscraper"},
    {"id": "pan_am", "name": "Pan Am Bldg", "pos": mc(-2420, 330), "kind": "skyscraper"},
    {"id": "woolworth", "name": "Woolworth Bldg", "pos": (-240, 1010), "kind": "skyscraper"},
    {"id": "world_trade_center", "name": "World Trade Center", "pos": (-520, 1100), "kind": "skyscraper"},
    {"id": "statue_of_liberty", "name": "Statue of Liberty", "pos": (-1080, 2670), "kind": "monument"},
    {"id": "yankee_stadium", "name": "Yankee Stadium", "pos": (3420, -6050), "kind": "stadium"},
    {"id": "shea_stadium", "name": "Shea Stadium", "pos": (6100, -3700), "kind": "stadium"},
    {"id": "grand_central", "name": "Grand Central", "pos": mc(-2300, 380), "kind": "station"},
    {"id": "navy_yard_cranes", "name": "Navy Yard cranes", "pos": (2050, 700), "kind": "industry"},
    {"id": "maspeth_gasholders", "name": "Gas holders", "pos": (4150, -1250), "kind": "industry"},
]

# Starting territory (from the approved reference; per-district seeds).
LI_LANDMARKS = [("lm_hq_marino", (-92, -2), "hq"), ("lm_vesuvio", (-68, -30), "restaurant"),
                ("lm_bowery_auto", (158, 0), "garage"), ("lm_grand_freight", (40, -60), "warehouse"),
                ("lm_trattoria_napoli", (25, -40), "restaurant"), ("lm_blue_lantern", (-10, 70), "bar")]

EXTENT = (-3600, -8900, 9200, 6400)
PLAYABLE = [(-1500, 2100), (-1700, -400), (-700, -4000), (1200, -7800), (3300, -9700), (7600, -9700), (7600, 5000),
            (400, 5000), (-200, 2600)]


# ---------------------------------------------------------------------------
# Data export
# ---------------------------------------------------------------------------
def r2(p):
    return [round(p[0], 1), round(p[1], 1)]


def export_json(path, district_cells):
    data = {
        "id": "nyc_1977", "version": 1, "schema": "geography-v1",
        "frame": {"units": "metres", "x": "east", "z": "south",
                  "notes": "Little Italy keeps its current coordinates (translation 0,0). Variable compression: "
                           "Lower Manhattan ~1:1.3, Midtown ~1:2, outer boroughs ~1:2.5-3, rivers ~1:1.5."},
        "extent": list(EXTENT),
        "playable": [r2(p) for p in PLAYABLE],
        "chunk_size": 256,
        "anchors": {"little_italy": {"translation": [0, 0], "rect": list(LI_RECT), "district": "little_italy"}},
        "landmasses": [dict(l, polygon=[r2(p) for p in l["polygon"]]) for l in COASTS],
        "boroughs": [dict(l, polygon=[r2(p) for p in l["polygon"]]) for l in BOROUGHS],
        "waterways": [dict(w, label_at=r2(w["label_at"])) for w in WATERWAYS],
        "parks": [dict(p, polygon=[r2(q) for q in p["polygon"]], lakes=[[r2(q) for q in lake] for lake in p.get("lakes", [])])
                  for p in PARKS],
        "districts": [],
        "styles": STYLES,
        "roads": [dict(r, path=[r2(p) for p in r["path"]]) for r in ROADS],
        "bridges": [dict(b, path=[r2(p) for p in b["path"]], **({"branch": [r2(p) for p in b["branch"]]} if "branch" in b else {}))
                    for b in BRIDGES],
        "landmarks": [dict(l, pos=r2(l["pos"])) for l in LANDMARKS],
        "territory_seed": {d["id"]: d.get("territory", "neutral") for d in DISTRICTS},
        "seed": 1977, "water_level": -1.6,
        "defaults": {"sidewalk_width": 4.0, "curb_height": 0.15, "corner_radius": 3.2, "lot_depth": 20.0,
                     "lane_offset": 1.9, "street_width": 12},
    }
    for d in DISTRICTS:
        e = {k: v for k, v in d.items() if k != "seed"}
        e["seed"] = r2(d["seed"])
        if "polygon" in d:
            e["polygon"] = [r2(p) for p in d["polygon"]]
        e["area_km2"] = round(district_cells.get(d["id"], 0) * CELL * CELL / 1e6, 2)
        data["districts"].append(e)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=1)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
SCALE = 0.3   # px per metre for the province map
CELL = 20.0   # metres per district-assignment cell


def to_px(p, scale=SCALE, ext=EXTENT):
    return ((p[0] - ext[0]) * scale, (p[1] - ext[1]) * scale)


def font(path, size, weight=None):
    f = ImageFont.truetype(path, size)
    if weight:
        try:
            f.set_variation_by_axes([weight] if "Cinzel" in path else [14, weight][-1:] if False else [weight])
        except Exception:
            try:
                f.set_variation_by_axes([14, weight])
            except Exception:
                pass
    return f


def point_in_poly(x, z, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / ((zj - zi) or 1e-9) + xi:
            inside = not inside
        j = i
    return inside


def land_mask(scale, ext, kinds=("playable", "scenery")):
    w = int((ext[2] - ext[0]) * scale)
    h = int((ext[3] - ext[1]) * scale)
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    for l in LANDMASSES:
        if l["kind"] in kinds:
            d.polygon([to_px(p, scale, ext) for p in l["polygon"]], fill=255)
    return m


def assign_districts(scale, ext):
    """District map: each land pixel belongs to the nearest seed of its
    landmass's borough (explicit polygons win). Returns (index image, ids)."""
    w = int((ext[2] - ext[0]) * scale)
    h = int((ext[3] - ext[1]) * scale)
    idx = Image.new("L", (w, h), 0)
    px = idx.load()
    borough_masks = {}
    for l in BOROUGHS:
        if l["kind"] != "playable":
            continue
        m = Image.new("L", (w, h), 0)
        ImageDraw.Draw(m).polygon([to_px(p, scale, ext) for p in l["polygon"]], fill=255)
        borough_masks.setdefault(l["borough"], []).append((l["id"], m.load()))
    explicit = {}
    for i, d in enumerate(DISTRICTS):
        if "polygon" in d:
            m = Image.new("L", (w, h), 0)
            ImageDraw.Draw(m).polygon([to_px(p, scale, ext) for p in d["polygon"]], fill=255)
            explicit[i] = m.load()
    seeds = [(i, d, to_px(d["seed"], scale, ext)) for i, d in enumerate(DISTRICTS)]
    step = max(1, int(CELL * scale))
    counts = {}
    for y in range(0, h, step):
        for x in range(0, w, step):
            owner = None
            for i, m in explicit.items():
                if m[x, y]:
                    owner = i
                    break
            if owner is None:
                for borough, masks in borough_masks.items():
                    hit = next((lid for lid, m in masks if m[x, y]), None)
                    if hit is None:
                        continue
                    best = None
                    for i, d, s in seeds:
                        if d["borough"] != borough or "polygon" in d:
                            continue
                        if hit in ("roosevelt_island", "randalls_island") and d["id"] not in ("roosevelt", "randalls"):
                            continue
                        if hit == "manhattan" and d["id"] in ("roosevelt", "randalls"):
                            continue
                        dd = (s[0] - x) ** 2 + (s[1] - y) ** 2
                        if best is None or dd < best[0]:
                            best = (dd, i)
                    if best:
                        owner = best[1]
                    break
            if owner is not None:
                counts[DISTRICTS[owner]["id"]] = counts.get(DISTRICTS[owner]["id"], 0) + 1
                for yy in range(y, min(h, y + step)):
                    for xx in range(x, min(w, x + step)):
                        px[xx, yy] = owner + 1
    return idx, counts


def draw_city_fabric(img, idx_img, scale, ext, rng, dense=True):
    """Street grids per district (rotated to the district grid angle) with
    block fill and roof speckle, clipped to each district."""
    w, h = img.size
    idx = idx_img.load()
    for i, d in enumerate(DISTRICTS):
        style = STYLES[d["style"]]
        mask = Image.new("L", (w, h), 0)
        mp = mask.load()
        any_px = False
        # Build mask for this district quickly from the index image.
        mask = idx_img.point(lambda v, i=i: 255 if v == i + 1 else 0).filter(ImageFilter.GaussianBlur(1.5))
        if mask.getbbox() is None:
            continue
        any_px = True
        base = Image.new("RGB", (w, h), style["color"])
        layer = base.copy()
        ld = ImageDraw.Draw(layer)
        bbox = mask.getbbox()
        # Roof speckle: blocks of buildings
        density = style["density"]
        if d["style"] not in ("park",) and density > 0:
            for _ in range(int((bbox[2] - bbox[0]) * (bbox[3] - bbox[1]) / (60 if dense else 140) * density)):
                x = rng.uniform(bbox[0], bbox[2])
                y = rng.uniform(bbox[1], bbox[3])
                s = rng.uniform(1.0, 3.2) * (scale / 0.3)
                tone = rng.uniform(0.7, 1.25)
                c = tuple(int(min(255, int(style["color"][k:k + 2], 16) * tone)) for k in (1, 3, 5))
                ld.rectangle([x, y, x + s, y + s], fill=c)
        grid = d.get("grid")
        if grid:
            ang = math.radians(grid["angle"])
            ux, uy = math.cos(ang), math.sin(ang)
            vx, vy = -math.sin(ang), math.cos(ang)
            px_, pz_ = grid["pitch"][0] * scale, grid["pitch"][1] * scale
            cx, cy = (bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2
            span = max(bbox[2] - bbox[0], bbox[3] - bbox[1])
            street = "#c9c2b2"
            lw = max(1, int(round(10 * scale)))
            n = int(span / max(px_, 1)) + 2
            for k in range(-n, n + 1):
                ox, oy = cx + ux * k * px_, cy + uy * k * px_
                if grid.get("irregular") and rng.random() < 0.3:
                    continue
                ld.line([ox - vx * span, oy - vy * span, ox + vx * span, oy + vy * span], fill=street, width=lw)
            n = int(span / max(pz_, 1)) + 2
            for k in range(-n, n + 1):
                ox, oy = cx + vx * k * pz_, cy + vy * k * pz_
                j = rng.uniform(-0.12, 0.12) if grid.get("irregular") else 0
                ld.line([ox - (ux + j) * span, oy - (uy - j) * span, ox + (ux + j) * span, oy + (uy - j) * span],
                        fill=street, width=lw)
        img.paste(layer, (0, 0), mask)


def polyline(draw, pts, color, width, scale, ext):
    draw.line([to_px(p, scale, ext) for p in pts], fill=color, width=width, joint="curve")


def label(draw, xy, text, fnt, fill="#efe6d2", anchor="mm", stroke=3, angle=0, img=None):
    if angle and img is not None:
        tw, th = draw.textbbox((0, 0), text, font=fnt)[2:]
        tmp = Image.new("RGBA", (tw + 20, th + 20), (0, 0, 0, 0))
        td = ImageDraw.Draw(tmp)
        td.text((10, 10), text, font=fnt, fill=fill, stroke_width=stroke, stroke_fill="#0c0b0a")
        rot = tmp.rotate(angle, expand=True, resample=Image.BICUBIC)
        img.paste(rot, (int(xy[0] - rot.width / 2), int(xy[1] - rot.height / 2)), rot)
        return
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor, stroke_width=stroke, stroke_fill="#0c0b0a")


def render_province(path, counts_out):
    ext = EXTENT
    scale = SCALE
    w = int((ext[2] - ext[0]) * scale)
    h = int((ext[3] - ext[1]) * scale)
    rng = random.Random(1977)
    img = Image.new("RGB", (w, h), "#173240")
    # Water depth gradient + texture
    water = Image.effect_noise((w, h), 22).convert("L").filter(ImageFilter.GaussianBlur(3))
    img = Image.composite(Image.new("RGB", (w, h), "#1d3c4c"), img, water.point(lambda v: 90 if v > 128 else 0))
    land = land_mask(scale, ext)
    scen = land_mask(scale, ext, kinds=("scenery",))
    # Shoreline glow / shallows
    shallows = land.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(6))
    img.paste(Image.new("RGB", (w, h), "#2a5462"), (0, 0), shallows.point(lambda v: int(v * 0.6)))
    img.paste(Image.new("RGB", (w, h), "#3a3732"), (0, 0), land)
    # Scenery land: muted fabric
    fabric = Image.new("RGB", (w, h), "#34312c")
    fd = ImageDraw.Draw(fabric)
    for _ in range(int(w * h / 260)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        s = rng.uniform(1.0, 2.6)
        t = rng.randint(46, 70)
        fd.rectangle([x, y, x + s, y + s], fill=(t + 10, t, t - 8))
    img.paste(fabric, (0, 0), scen)
    idx, counts = assign_districts(scale, ext)
    counts_out.update(counts)
    draw_city_fabric(img, idx, scale, ext, rng)
    d = ImageDraw.Draw(img)
    # Parks
    for p in PARKS:
        d.polygon([to_px(q, scale, ext) for q in p["polygon"]], fill="#3f6a2e")
        pr = Image.new("L", (w, h), 0)
        ImageDraw.Draw(pr).polygon([to_px(q, scale, ext) for q in p["polygon"]], fill=255)
        trees = Image.new("RGB", (w, h), "#2f5524")
        td = ImageDraw.Draw(trees)
        bb = pr.getbbox()
        if bb:
            for _ in range(int((bb[2] - bb[0]) * (bb[3] - bb[1]) / 18)):
                x, y = rng.uniform(bb[0], bb[2]), rng.uniform(bb[1], bb[3])
                r = rng.uniform(1.0, 3.0)
                td.ellipse([x - r, y - r, x + r, y + r], fill=rng.choice(["#2c5222", "#3d6a2c", "#4f7a36", "#2a4a20"]))
            img.paste(trees, (0, 0), Image.eval(pr, lambda v: v).point(lambda v: 150 if v else 0))
        for lake in p.get("lakes", []):
            d.polygon([to_px(q, scale, ext) for q in lake], fill="#2a5462", outline="#8fb0b8")
    # Airport runways
    for a, b in (((4900, -4700), (5900, -5100)), ((5300, -4600), (5500, -5250))):
        d.line([to_px(a), to_px(b)], fill="#b9b4aa", width=int(55 * scale))
    # Territory overlays (district outlines)
    for terr, col in TERRITORY_COLORS.items():
        ids = [i for i, dd in enumerate(DISTRICTS) if dd.get("territory") == terr]
        if not ids:
            continue
        m = idx.point(lambda v, ids=ids: 255 if v - 1 in ids else 0)
        tint = Image.new("RGB", (w, h), col)
        img.paste(tint, (0, 0), m.point(lambda v: 55 if v else 0))
        edge = m.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(5))
        img.paste(tint, (0, 0), edge)
    d = ImageDraw.Draw(img)
    # Roads and bridges
    for r in ROADS:
        col = {"expressway": "#e2c27a", "parkway": "#d6b56a", "arterial": "#e8dcc0", "avenue": "#efe6d2"}[r["class"]]
        polyline(d, r["path"], "#1a1714", max(3, int(r["width"] * scale * 2.2)), scale, ext)
        polyline(d, r["path"], col, max(2, int(r["width"] * scale * 1.4)), scale, ext)
    for b in BRIDGES:
        polyline(d, b["path"], "#0c0b0a", max(5, int(b["width"] * scale * 3.0)), scale, ext)
        polyline(d, b["path"], "#c9a24a", max(3, int(b["width"] * scale * 1.8)), scale, ext)
        if "branch" in b:
            polyline(d, b["branch"], "#c9a24a", max(3, int(b["width"] * scale * 1.8)), scale, ext)
    # Little Italy: preserved district highlight + landmarks
    li = [to_px(p, scale, ext) for p in rect_poly(*LI_RECT)]
    d.polygon(li, outline="#ffd27a", width=4)
    for _, pos, _ in LI_LANDMARKS:
        x, y = to_px(pos, scale, ext)
        d.ellipse([x - 3, y - 3, x + 3, y + 3], fill="#ffd27a")
    for lm in LANDMARKS:
        x, y = to_px(lm["pos"], scale, ext)
        d.ellipse([x - 6, y - 6, x + 6, y + 6], fill="#e8c97f", outline="#0c0b0a", width=2)
    # Labels
    f_borough = font(FONT_DISPLAY, 64, 700)
    f_district = font(FONT_DISPLAY, 26, 600)
    f_water = font(FONT_UI, 30, 500)
    f_small = font(FONT_UI, 19, 600)
    for name, pos in (("MANHATTAN", (-380, -1400)), ("BROOKLYN", (3400, 3300)), ("QUEENS", (4700, -3900)),
                      ("THE BRONX", (5000, -8000)), ("NEW JERSEY", (-2800, -3500)),
                      ("STATEN ISLAND", (-2000, 5800)), ("LONG ISLAND", (8400, -1500))):
        label(d, to_px(pos, scale, ext), name, f_borough, fill="#e8c97f", stroke=5)
    for dd in DISTRICTS:
        if dd["id"] in ("randalls", "roosevelt"):
            continue
        txt = dd["name"].upper()
        pos = to_px(dd["seed"], scale, ext)
        if dd["id"] == "little_italy":
            label(d, (pos[0], pos[1] - 34), "LITTLE ITALY", font(FONT_DISPLAY, 30, 700), fill="#ffd27a", stroke=4)
            x, y = pos
            star = [(x + 16 * math.cos(math.radians(-90 + k * 36)) * (1 if k % 2 == 0 else 0.45),
                     y + 16 * math.sin(math.radians(-90 + k * 36)) * (1 if k % 2 == 0 else 0.45)) for k in range(10)]
            d.polygon(star, fill="#ffd27a", outline="#0c0b0a")
            continue
        label(d, pos, txt, f_district, stroke=4)
    for wv in WATERWAYS:
        label(d, to_px(wv["label_at"], scale, ext), wv["name"].upper(), f_water, fill="#9fc0c8", stroke=3,
              angle=(90 - wv["angle"]) if wv["angle"] else 0, img=img)
    d = ImageDraw.Draw(img)
    for p in PARKS:
        if p["kind"] == "square":
            continue
        xs = [q[0] for q in p["polygon"]]
        zs = [q[1] for q in p["polygon"]]
        c = (sum(xs) / len(xs), sum(zs) / len(zs))
        label(d, to_px(c, scale, ext), p["name"].upper(), f_small, fill="#cfe3b0", stroke=3)
    for b in BRIDGES:
        mid = b["path"][len(b["path"]) // 2]
        x, y = to_px(mid, scale, ext)
        bbox = d.textbbox((x, y + 26), b["name"].upper(), font=f_small, anchor="mm")
        d.rectangle([bbox[0] - 8, bbox[1] - 5, bbox[2] + 8, bbox[3] + 5], fill="#0c0b0a", outline="#c9a24a")
        d.text((x, y + 26), b["name"].upper(), font=f_small, fill="#efe6d2", anchor="mm")
    for lm in LANDMARKS:
        x, y = to_px(lm["pos"], scale, ext)
        label(d, (x + 12, y), lm["name"], font(FONT_UI, 17, 500), fill="#f2e3bd", anchor="lm", stroke=3)
    # Playable boundary
    # Title, legend, scale bar, compass
    panel(d, (24, 24, 650, 270))
    label(d, (337, 90), "EMPIRE", font(FONT_DISPLAY, 82, 700), fill="#e8c97f", stroke=0)
    label(d, (337, 160), "RUN NEW YORK", font(FONT_DISPLAY, 36, 600), fill="#e8c97f", stroke=0)
    label(d, (337, 222), "GEOGRAPHY BLUEPRINT  ·  NEW YORK CITY 1977", font(FONT_UI, 20, 600), fill="#cfc6b2", stroke=0)
    lx, ly = w - 560, h - 640
    panel(d, (lx, ly, w - 24, h - 24))
    label(d, (lx + 268, ly + 40), "MAP LEGEND", font(FONT_DISPLAY, 30, 700), fill="#e8c97f", stroke=0)
    items = [("#d9473a", "Your territory (Little Italy)"), ("#4f8fd9", "Rival family territory"),
             ("#a36fd1", "Contested"), ("#3f6a2e", "Park / open space"), ("#e2c27a", "Expressway / parkway"),
             ("#efe6d2", "Avenue / arterial"), ("#c9a24a", "Bridge"), ("#ffd27a", "Preserved Little Italy (1:1)"),
             ("#e8c97f", "Landmark  /  playable boundary")]
    for k, (col, txt) in enumerate(items):
        y = ly + 95 + k * 56
        d.rectangle([lx + 30, y - 14, lx + 70, y + 14], fill=col, outline="#0c0b0a")
        d.text((lx + 90, y), txt, font=font(FONT_UI, 22, 500), fill="#efe6d2", anchor="lm")
    # Scale bar (1 km)
    sx, sy = 60, 360
    km = 1000 * scale
    d.rectangle([sx - 10, sy - 60, sx + 2 * km + 120, sy + 40], fill="#0c0b0a")
    d.line([sx, sy, sx + 2 * km, sy], fill="#efe6d2", width=6)
    for t in (0, 1, 2):
        d.line([sx + t * km, sy - 12, sx + t * km, sy + 12], fill="#efe6d2", width=4)
        d.text((sx + t * km, sy - 32), "%d km" % t, font=font(FONT_UI, 20, 600), fill="#efe6d2", anchor="mm")
    d.text((sx + 2 * km + 20, sy), "game metres", font=font(FONT_UI, 18, 500), fill="#a39b8a", anchor="lm")
    cx, cy = w - 110, 130
    d.ellipse([cx - 70, cy - 70, cx + 70, cy + 70], outline="#c9a24a", width=3)
    d.polygon([(cx, cy - 64), (cx - 14, cy), (cx + 14, cy)], fill="#e8c97f")
    d.polygon([(cx, cy + 64), (cx - 14, cy), (cx + 14, cy)], fill="#6b5a35")
    d.text((cx, cy - 92), "N", font=font(FONT_DISPLAY, 34, 700), fill="#e8c97f", anchor="mm")
    img.save(path)
    return img


def panel(d, box):
    d.rectangle(box, fill="#100e0c", outline="#c9a24a", width=3)
    d.rectangle((box[0] + 8, box[1] + 8, box[2] - 8, box[3] - 8), outline="#5a4a28", width=1)


def render_lower_manhattan(path):
    """Close-up: preserved Little Italy (exact streets) inside the new
    Lower Manhattan, with its neighbours, bridge plazas and shorelines."""
    ext = (-1700, -1300, 2200, 2000)
    scale = 0.75
    w = int((ext[2] - ext[0]) * scale)
    h = int((ext[3] - ext[1]) * scale)
    img = Image.new("RGB", (w, h), "#173240")
    land = land_mask(scale, ext)
    img.paste(Image.new("RGB", (w, h), "#3a3732"), (0, 0), land)
    rng = random.Random(7)
    idx, _ = assign_districts(scale, ext)
    draw_city_fabric(img, idx, scale, ext, rng, dense=False)
    d = ImageDraw.Draw(img)
    # Exact Little Italy streets from data/districts/little_italy.json
    li = json.load(open(os.path.join(ROOT, "data", "districts", "little_italy.json")))
    x0, z0, x1, z1 = LI_RECT
    d.rectangle([*to_px((x0, z0), scale, ext), *to_px((x1, z1), scale, ext)], fill="#8a3f2e")
    for a in li["avenues"]:
        d.line([to_px((a["x"], z0), scale, ext), to_px((a["x"], z1), scale, ext)], fill="#efe6d2",
               width=max(2, int(a["width"] * scale)))
    for s in li["streets"]:
        d.line([to_px((x0, s["z"]), scale, ext), to_px((x1, s["z"]), scale, ext)], fill="#efe6d2",
               width=max(2, int(s["width"] * scale)))
    d.rectangle([*to_px((x0, z0), scale, ext), *to_px((x1, z1), scale, ext)], outline="#ffd27a", width=5)
    for r in ROADS:
        polyline(d, r["path"], "#e2c27a" if r["class"] == "expressway" else "#efe6d2",
                 max(3, int(r["width"] * scale * 0.9)), scale, ext)
    for b in BRIDGES:
        polyline(d, b["path"], "#c9a24a", max(5, int(b["width"] * scale * 1.2)), scale, ext)
    for p in PARKS:
        d.polygon([to_px(q, scale, ext) for q in p["polygon"]], fill="#3f6a2e")
    f = font(FONT_UI, 26, 600)
    names = {lm: n for lm, n in (("lm_hq_marino", "HQ: Marino Social Club"), ("lm_vesuvio", "Ristorante Vesuvio"),
                                 ("lm_bowery_auto", "Bowery Auto Body"), ("lm_grand_freight", "Grand St Freight"),
                                 ("lm_trattoria_napoli", "Trattoria Napoli (rival)"),
                                 ("lm_blue_lantern", "The Blue Lantern (rival)"))}
    layout = json.load(open(os.path.join(ROOT, "data", "districts", "little_italy.json")))
    for a in layout["avenues"]:
        x, y = to_px((a["x"], z0 - 70), scale, ext)
        label(d, (x, y), a["name"], font(FONT_UI, 20, 600), fill="#ffd27a", stroke=3, angle=90, img=img)
    d = ImageDraw.Draw(img)
    for s in layout["streets"]:
        x, y = to_px((x1 + 12, s["z"]), scale, ext)
        label(d, (x, y), s["name"], font(FONT_UI, 20, 600), fill="#ffd27a", anchor="lm", stroke=3)
    for dd in DISTRICTS:
        if ext[0] < dd["seed"][0] < ext[2] and ext[1] < dd["seed"][1] < ext[3] and dd["id"] != "little_italy":
            label(d, to_px(dd["seed"], scale, ext), dd["name"].upper(), font(FONT_DISPLAY, 30, 700), stroke=4)
    for b in BRIDGES:
        if b["path"][0][0] < ext[2] and b["path"][0][1] > ext[1]:
            x, y = to_px(b["path"][1], scale, ext)
            label(d, (x, y - 30), b["name"].upper(), font(FONT_UI, 22, 700), fill="#e8c97f", stroke=4)
    label(d, to_px((4, -330), scale, ext), "LITTLE ITALY  ·  PRESERVED 1:1  ·  381 BUILDINGS",
          font(FONT_DISPLAY, 30, 700), fill="#ffd27a", stroke=5)
    label(d, to_px((-1500, 900), scale, ext), "HUDSON RIVER", font(FONT_UI, 30, 600), fill="#9fc0c8", stroke=3)
    label(d, to_px((1550, 400), scale, ext), "EAST RIVER", font(FONT_UI, 30, 600), fill="#9fc0c8", stroke=3)
    panel(d, (20, 20, 1420, 120))
    label(d, (720, 70), "LOWER MANHATTAN  ·  LITTLE ITALY PLACEMENT (translation 0, 0)", font(FONT_DISPLAY, 28, 700),
          fill="#e8c97f", stroke=0)
    img.save(path)


def validate():
    """Checks reported with the blueprint: Little Italy inside Manhattan,
    every district seed on its borough, roads on land (except bridges)."""
    report = []
    man = next(l for l in LANDMASSES if l["id"] == "manhattan")["polygon"]
    corners = rect_poly(*LI_RECT)
    report.append(("Little Italy fully inside Manhattan", all(point_in_poly(x, z, man) for x, z in corners)))
    bad = []
    for dd in DISTRICTS:
        lms = [l for l in BOROUGHS if l["kind"] == "playable" and point_in_poly(dd["seed"][0], dd["seed"][1], l["polygon"])]
        if not lms:
            bad.append(dd["id"])
    report.append(("District seeds on land (%d districts)" % len(DISTRICTS), not bad or bad))
    water_hits = []
    for r in ROADS:
        pts = r["path"]
        for a, b in zip(pts[:-1], pts[1:]):
            for t in (0.25, 0.5, 0.75):
                x = a[0] + (b[0] - a[0]) * t
                z = a[1] + (b[1] - a[1]) * t
                if not any(point_in_poly(x, z, l["polygon"]) for l in LANDMASSES if l["kind"] == "playable"):
                    water_hits.append(r["id"])
                    break
    report.append(("Roads stay on land (bridges excepted)", sorted(set(water_hits)) or True))
    return report


def main():
    counts = {}
    os.makedirs(os.path.join(ROOT, "docs", "geography"), exist_ok=True)
    render_province(os.path.join(ROOT, "docs", "geography", "nyc_1977_blueprint.png"), counts)
    render_lower_manhattan(os.path.join(ROOT, "docs", "geography", "lower_manhattan.png"))
    export_json(os.path.join(ROOT, "data", "world", "nyc_1977.json"), counts)
    for name, ok in validate():
        print("CHECK %-45s %s" % (name, ok))
    land_area = sum(counts.values()) * CELL * CELL / 1e6
    print("Playable district land: %.1f km2 across %d districts" % (land_area, len(DISTRICTS)))


if __name__ == "__main__":
    main()
