"""Phase B vertical slice data: Bay Ridge (streets-first), the Verrazzano
Bridge and Staten Island as the first estate region (terrain, lakes, stream,
woodland, country lanes, estate plots).

Called by nyc_blueprint.export_json(); everything is deterministic data that
GeographyBuilder / TerrainField consume. Coordinates: metres, +X east, +Z south.
"""
import math
import random

BAY_RIDGE = [(600, 4300), (1900, 4300), (1900, 6300), (700, 6300)]
STATEN_BOROUGH = [(-4600, 5300), (-1300, 5000), (100, 5600), (40, 7600), (-4600, 7600)]
GRASMERE = [(-1450, 5150), (-200, 5200), (60, 5700), (60, 6700), (-1350, 6750)]
ESTATE_REGION = [(-4550, 5350), (-1450, 5150), (-1350, 6750), (-700, 7550), (-4550, 7550)]
GREENBELT = [(-3650, 6250), (-2950, 6150), (-2350, 6450), (-2300, 7250), (-3000, 7450), (-3600, 7200)]

PLOT = 140.0
SPACING = 230.0


def chaikin(pts, iterations=3, closed=False):
    for _ in range(iterations):
        out = [] if closed else [pts[0]]
        n = len(pts)
        rng = range(n) if closed else range(n - 1)
        for i in rng:
            a, b = pts[i], pts[(i + 1) % n]
            out.append((a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25))
            out.append((a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75))
        if not closed:
            out.append(pts[-1])
        pts = out
    return pts


def blob(cx, cz, rx, rz, seed, n=14, wobble=0.22):
    """Irregular rounded outline (lakes, woods)."""
    rng = random.Random(seed)
    pts = []
    for i in range(n):
        a = math.tau * i / n
        r = 1.0 + rng.uniform(-wobble, wobble)
        pts.append((cx + math.cos(a) * rx * r, cz + math.sin(a) * rz * r))
    return chaikin(pts, 3, closed=True)


def wiggle(path, seed, amp=60.0):
    """Country-lane meander: perpendicular wobble, then smoothing."""
    rng = random.Random(seed)
    out = [path[0]]
    for (ax, az), (bx, bz) in zip(path[:-1], path[1:]):
        length = math.hypot(bx - ax, bz - az)
        steps = max(1, int(length / 180))
        nx, nz = -(bz - az) / length, (bx - ax) / length
        for s in range(1, steps + 1):
            t = s / steps
            off = rng.uniform(-amp, amp) if s < steps else 0.0
            out.append((ax + (bx - ax) * t + nx * off, az + (bz - az) * t + nz * off))
    return chaikin(out, 3)


def pip(x, z, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / ((zj - zi) or 1e-9) + xi:
            inside = not inside
        j = i
    return inside


def seg_closest(x, z, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[1]) * dz) / (dx * dx + dz * dz or 1)))
    return (a[0] + dx * t, a[1] + dz * t)


def path_dist(x, z, path):
    best, bp = 1e9, None
    for a, b in zip(path[:-1], path[1:]):
        q = seg_closest(x, z, a, b)
        d = math.hypot(x - q[0], z - q[1])
        if d < best:
            best, bp = d, q
    return best, bp


def poly_dist(x, z, poly):
    return min(path_dist(x, z, poly + [poly[0]])[0], 1e9)


# --- Bay Ridge: streets-first network ---------------------------------------------------------
def bay_ridge_network(land):
    ang = math.radians(-14)
    d_av = (math.sin(-ang) * -1, math.cos(ang))  # avenues run roughly north-south
    d_av = (-math.sin(ang), math.cos(ang))
    d_st = (math.cos(ang), math.sin(ang))
    origin = (1250, 5300)
    ok = lambda x, z: pip(x, z, BAY_RIDGE) and pip(x, z, land) and poly_dist(x, z, land) > 70

    def clip(p0, d, half):
        runs, cur = [], None
        steps = int(half * 2 / 4)
        for s in range(steps + 1):
            t = -half + s * 4
            x, z = p0[0] + d[0] * t, p0[1] + d[1] * t
            if ok(x, z):
                cur = cur or [(x, z)]
                cur = [cur[0], (x, z)]
            elif cur:
                runs.append(cur)
                cur = None
        if cur:
            runs.append(cur)
        return [r for r in runs if math.hypot(r[1][0] - r[0][0], r[1][1] - r[0][1]) > 60]

    roads = []
    avenues = [("Colonial Rd", 12, -3), ("Ridge Blvd", 14, -2), ("3rd Ave", 14, -1), ("4th Ave", 22, 0),
               ("5th Ave", 14, 1), ("Fort Hamilton Pkwy", 16, 2)]
    for name, width, k in avenues:
        p0 = (origin[0] + d_st[0] * k * 205, origin[1] + d_st[1] * k * 205)
        for run in clip(p0, d_av, 1400):
            roads.append({"name": name, "class": "avenue" if width >= 16 else "street", "width": width,
                          "speed": 1400 if width >= 20 else 1100, "path": run})
    for i in range(-13, 14):
        p0 = (origin[0] + d_av[0] * i * 78, origin[1] + d_av[1] * i * 78)
        num = 81 + i
        width = 16 if num in (86, 69, 92) else 12
        for run in clip(p0, d_st, 900):
            roads.append({"name": "%dth St" % num if num % 10 not in (1, 2, 3) else "%d St" % num, "class": "street",
                          "width": width, "speed": 1000, "path": run})
    # Shore Road follows the Narrows 60 m inland, with a park between it and the water.
    shore = []
    for z in range(4400, 6200, 60):
        best = None
        for x in range(400, 1500, 5):
            if pip(x, z, land):
                best = x
                break
        if best is not None:
            shore.append((best + 65, z))
    shore = chaikin(shore, 2)
    # Boundary streets close the outer blocks (blocks are faces of the network).
    north = [(shore[0][0], 4330), (1880, 4330)]
    east = [(1880, 4330), (1880, 6200)]
    south = [(shore[-1][0], shore[-1][1]), (1880, 6200)]
    for name, path, w in (("65th St", north, 14), ("7th Ave", east, 14), ("Fort Hamilton Ave", south, 14)):
        roads.append({"name": name, "class": "street", "width": w, "speed": 1100, "path": path})
    roads.append({"name": "Shore Rd", "class": "avenue", "width": 16, "speed": 1300, "path": shore})
    park = [(p[0] - 55, p[1]) for p in shore] + [(p[0] - 8, p[1]) for p in reversed(shore)]
    return roads, {"id": "shore_road_park", "name": "Shore Road Park", "kind": "park", "polygon": park, "lakes": []}


# --- Staten Island ------------------------------------------------------------------------------
LAKES = [
    {"id": "silver_lake", "name": "Silver Lake", "polygon": blob(-2650, 5720, 230, 130, 11)},
    {"id": "clove_lakes", "name": "Clove Lakes", "polygon": blob(-1900, 5470, 120, 75, 12)},
    {"id": "todt_pond", "name": "Todt Hill Pond", "polygon": blob(-3350, 6950, 95, 70, 13)},
    {"id": "richmond_pond", "name": "Richmond Creek Pond", "polygon": blob(-4050, 7250, 150, 95, 14)},
]
STREAMS = [{"id": "richmond_creek", "path": chaikin([(-3350, 6950), (-3700, 7100), (-4050, 7250), (-4400, 7420),
                                                      (-4700, 7600)], 3), "width": 7}]


def staten_roads(bridge_end):
    sie = [bridge_end, (-500, 5990), (-1000, 6060), (-1600, 6170), (-2300, 6120), (-3000, 5980), (-3700, 6020),
           (-4500, 6080)]
    roads = [
        {"name": "Staten Island Expwy", "class": "expressway", "width": 22, "speed": 1800, "path": chaikin(sie, 2)},
        {"name": "Victory Blvd", "class": "avenue", "width": 14, "speed": 1300,
         "path": wiggle([(-1200, 5420), (-2000, 5330), (-2900, 5450), (-3800, 5480), (-4450, 5600)], 3, 40)},
        {"name": "Todt Hill Rd", "class": "lane", "width": 9, "speed": 1100,
         "path": wiggle([(-1650, 6160), (-1800, 6600), (-2050, 7000), (-2200, 7450)], 4, 70)},
        {"name": "Richmond Rd", "class": "lane", "width": 10, "speed": 1200,
         "path": wiggle([(-1350, 6720), (-2200, 7450), (-3000, 7520), (-3900, 6800), (-4450, 6600)], 5, 60)},
        {"name": "Manor Rd", "class": "lane", "width": 9, "speed": 1100,
         "path": wiggle([(-2950, 5460), (-3100, 5980)], 6, 40)},
        {"name": "Rockland Ave", "class": "lane", "width": 9, "speed": 1100,
         "path": wiggle([(-3700, 6030), (-3900, 6800)], 7, 50)},
        {"name": "Clove Rd", "class": "lane", "width": 10, "speed": 1200,
         "path": wiggle([(-1250, 5440), (-1300, 6050)], 8, 30)},
    ]
    return roads


def grasmere_network():
    """Suburban streets by the bridge: curving residential lanes."""
    lines = [
        [(-1300, 5300), (-900, 5260), (-500, 5330), (-150, 5500)],
        [(-1300, 5560), (-950, 5520), (-600, 5600), (-250, 5760), (0, 5860)],
        [(-1300, 5820), (-1000, 5790), (-700, 5840)],
        [(-1300, 6330), (-950, 6290), (-600, 6340), (-250, 6420), (20, 6450)],
        [(-1150, 5260), (-1130, 5560), (-1160, 5820), (-1120, 6050)],
        [(-700, 5280), (-720, 5600), (-700, 5840), (-680, 6070), (-640, 6340)],
        [(-300, 5420), (-320, 5760), (-260, 6070), (-250, 6420)],
        [(-1120, 6050), (-1110, 6330)],
    ]
    names = ["Hylan Blvd", "Narrows Rd", "Sand Ln", "Fingerboard Rd", "Clove Ave", "Grasmere Dr", "Lily Pond Ave",
             "Steuben St"]
    return [{"name": names[i], "class": "street", "width": 12 if i else 16, "speed": 1100,
             "path": chaikin(l, 2)} for i, l in enumerate(lines)]


def sample_plots(lanes, seed=4242, all_roads=()):
    rng = random.Random(seed)
    pts = []
    xs = [p[0] for p in ESTATE_REGION]
    zs = [p[1] for p in ESTATE_REGION]
    for _ in range(6000):
        x, z = rng.uniform(min(xs), max(xs)), rng.uniform(min(zs), max(zs))
        if not pip(x, z, ESTATE_REGION) or poly_dist(x, z, ESTATE_REGION) < 110:
            continue
        if pip(x, z, GREENBELT) or poly_dist(x, z, GREENBELT) < 60:
            continue
        if any(pip(x, z, l["polygon"]) or poly_dist(x, z, l["polygon"]) < 120 for l in LAKES):
            continue
        if any(path_dist(x, z, s["path"])[0] < 120 for s in STREAMS):
            continue
        dists = [path_dist(x, z, r["path"]) + (r,) for r in lanes]
        d, q, lane = min(dists, key=lambda v: v[0])
        if d < PLOT * 0.5 + 18 + lane["width"] or d > 320:
            continue
        # Clear of every road (the expressway too): the whole footprint plus a verge.
        if any(path_dist(x, z, r["path"])[0] < PLOT * 0.71 + r["width"] * 0.5 + 10 for r in all_roads if r is not lane):
            continue
        if any((x - p["pos"][0]) ** 2 + (z - p["pos"][1]) ** 2 < SPACING ** 2 for p in pts):
            continue
        yaw = math.atan2(q[0] - x, q[1] - z)  # mansion front faces its lane
        gate = (x + math.sin(yaw) * PLOT * 0.5, z + math.cos(yaw) * PLOT * 0.5)
        pts.append({"pos": [round(x, 1), round(z, 1)], "yaw": round(yaw, 4), "gate": [round(gate[0], 1), round(gate[1], 1)],
                    "lane_point": [round(q[0], 1), round(q[1], 1)], "lane": lane["name"]})
    pts.sort(key=lambda p: (p["pos"][0], p["pos"][1]))
    for i, p in enumerate(pts):
        p["id"] = "estate:staten:%d" % i
        p["state"] = "empty"
    return pts


def add_slice(data, land_long_island):
    """Extends the exported geography with the vertical slice."""
    br_roads, shore_park = bay_ridge_network(land_long_island)
    # Bridge: Fort Hamilton to the Staten Island shore at Fort Wadsworth.
    shore_rd = next(r for r in br_roads if r["name"] == "Shore Rd")
    bridge_start = min(shore_rd["path"], key=lambda p: abs(p[1] - 5900))
    bridge_start = (bridge_start[0] + 70, 5900)
    bridge_end = (-160, 5960)
    data["bridges"].append({"id": "verrazzano_bridge", "name": "Verrazzano-Narrows Bridge", "kind": "suspension",
                            "width": 30, "speed": 1800, "path": [list(bridge_start), [260, 5925], list(bridge_end)],
                            "connects": ["bay_ridge", "grasmere"]})
    data["roads"].append({"id": "gowanus_expwy", "name": "Gowanus Expwy", "class": "expressway", "width": 22,
                          "speed": 1800, "path": [[1150, 3300], [1080, 3800], [1020, 4290]]})
    staten = staten_roads(bridge_end)
    grasmere = grasmere_network()
    lanes = [r for r in staten if r["class"] in ("lane", "avenue")]
    plots = sample_plots(lanes, all_roads=staten)
    # Example estates: two allied families inside one territory, a rival outside.
    by_dist = lambda target: min(plots, key=lambda p: (p["pos"][0] - target[0]) ** 2 + (p["pos"][1] - target[1]) ** 2)
    marino = by_dist((-2150, 6650))
    marino.update(state="occupied", owner="marino", landmark="lm_estate_marino")
    rizzo = min((p for p in plots if p["state"] == "empty"),
                key=lambda p: abs(math.hypot(p["pos"][0] - marino["pos"][0], p["pos"][1] - marino["pos"][1]) - 520))
    rizzo.update(state="occupied", owner="rizzo", landmark="lm_estate_rizzo")
    moretti = by_dist((-4100, 5950))
    moretti.update(state="occupied", owner="moretti", landmark="lm_estate_moretti")
    reserved = min((p for p in plots if p["state"] == "empty"),
                   key=lambda p: (p["pos"][0] + 3000) ** 2 + (p["pos"][1] - 6300) ** 2)
    reserved["state"] = "reserved"
    for net_id, roads, blocks in (("bay_ridge", br_roads, True), ("grasmere", grasmere, True),
                                  ("staten_roads", staten, False)):
        data.setdefault("networks", []).append({"id": net_id, "blocks": blocks, "roads": [
            dict(r, path=[[round(p[0], 1), round(p[1], 1)] for p in r["path"]]) for r in roads]})
    data["parks"].append(dict(shore_park, polygon=[[round(p[0], 1), round(p[1], 1)] for p in shore_park["polygon"]]))
    data["estate_regions"] = [{
        "id": "staten", "name": "Staten Island", "tier": "prime",
        "polygon": [list(p) for p in ESTATE_REGION], "plot_size": PLOT, "plot_spacing": SPACING,
        "terrain": {"coast": "staten_island", "hills": 16.0, "hill_scale": 650.0, "summit": [-2350, 6700, 34.0, 700.0],
                    "fields": 0.55, "shore_depth": 4.5},
        "woods": [[list(p) for p in chaikin(GREENBELT, 3, closed=True)]],
        "lakes": [dict(l, polygon=[[round(p[0], 1), round(p[1], 1)] for p in l["polygon"]]) for l in LAKES],
        "streams": [dict(s, path=[[round(p[0], 1), round(p[1], 1)] for p in s["path"]]) for s in STREAMS],
        "hamlets": [{"id": "richmondtown", "name": "Richmondtown", "pos": [-3880, 6820], "buildings": 9}],
        "plots": plots,
    }]
    return {"plots": len(plots), "bay_ridge_roads": len(br_roads), "staten_roads": len(staten)}
