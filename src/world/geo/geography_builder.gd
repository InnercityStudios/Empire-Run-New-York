class_name GeographyBuilder
extends RefCounted
## Fills a WorldLayout from a `geography-v1` definition (data/world/nyc_1977.json).
##
## - Little Italy is built from its unchanged district definition at its
##   original coordinates, so its 381 lots, landmarks and road-node keys are
##   bit-identical (the golden fingerprint test checks this).
## - Every other district gets its own street lattice in its own frame (grid
##   angle, pitch, line jitter; the Village is irregular). Blocks are kept only
##   where they lie wholly on land inside their district and clear of parks,
##   Little Italy and arterial corridors, so grids end at shorelines and
##   district borders instead of overlapping.
## - Arterials, expressways and bridges are polylines. Arterials split each
##   other where they cross; district streets, Little Italy's boundary roads,
##   bridge ends and arterial ends are stitched to the nearest other road. Any
##   island of roads that still cannot reach Little Italy is linked or dropped,
##   so the network is one connected graph.
## - Generated blocks store no lots; BlockFiller derives them per chunk.
##
## Deterministic: every random choice is seeded from ids.

const STITCH_RADIUS := 70.0
const END_STITCH_RADIUS := 160.0
const CORRIDOR_MARGIN := 3.0
const MIN_BLOCK := 30.0
const SHRINK_STEP := 10.0
const SEG_CELL := 96.0
const LINK_RADIUS := 350.0
const PIECE := 128.0

var w: WorldLayout
var geo: GeoMap
var _lines: Array = []        ## {street, pts: PackedVector2Array, width, speed, style, group, kind, splits: Array}
var _seg_cells: Dictionary = {}
var _corridor_segs: Array = []  ## [a, b, half_width] for arterials and bridges
var _corridor_cells: Dictionary = {}
var _candidates: Array = []   ## [point, group, radius, trim]
var _li_rect: Rect2
var _li_poly: PackedVector2Array
var _tower_polys: Array = []
var stats := {}


static func populate(world: WorldLayout, def: Dictionary, content: GameContent) -> void:
	var b := GeographyBuilder.new()
	b._run(world, def, content)


func _run(world: WorldLayout, def: Dictionary, content: GameContent) -> void:
	var t0 := Time.get_ticks_msec()
	w = world
	geo = GeoMap.from_def(def)
	w.is_geo = true
	w.geo = geo
	w._catalog = content.building_catalog
	w.id = def.get("id", "world")
	w.display_name = def.get("display_name", "Greater New York 1977")
	w.seed_value = int(def.get("seed", 1977))
	w.chunk_size = float(def.get("chunk_size", 256))
	w.water_level = float(def.get("water_level", -1.6))
	var defaults: Dictionary = def.get("defaults", {})
	w.sidewalk = defaults.get("sidewalk_width", 4.0)
	w.curb_height = defaults.get("curb_height", 0.15)
	w.corner_radius = defaults.get("corner_radius", 3.2)
	w.lane_offset = defaults.get("lane_offset", 1.9)
	w.world_rect = geo.extent
	var land := Rect2()
	for b in geo.boroughs:
		if b["kind"] == "playable":
			land = (b["bounds"] as Rect2) if land.size == Vector2.ZERO else land.merge(b["bounds"])
	w.land = land
	w.playable = land
	w.districts = def["districts"]
	for style in def["styles"]:
		w.kits[style] = BlockFiller.make_kit(def["styles"][style].get("fill", {}), content.building_catalog)
	w.land_polygons = geo.coasts
	_little_italy(def, content)
	_landmark_towers(def)
	for r in def.get("roads", []):
		_add_arterial(r)
	for b in def.get("bridges", []):
		_add_bridge(b)
	_split_crossings()
	stats["arterials_ms"] = Time.get_ticks_msec() - t0
	var bounds := geo.district_bounds()
	stats["bounds_ms"] = Time.get_ticks_msec() - t0
	for g in _district_groups(bounds):
		_district_grid(g["members"], g["area"])
	stats["grids_ms"] = Time.get_ticks_msec() - t0
	_stitch()
	_emit_graph()
	_connect_islands()
	_parks()
	_airport(def)
	_backdrop()
	for d in w.districts:
		w.labels.append({"text": d["name"], "pos": Vector2(d["seed"][0], d["seed"][1]), "kind": "district"})
	w.index_chunks()
	stats["total_ms"] = Time.get_ticks_msec() - t0
	stats["blocks"] = w.blocks.size()
	stats["nodes"] = w.graph_nodes.size()
	stats["edges"] = w.graph_edges.size()


# --- Little Italy ------------------------------------------------------------------------
func _little_italy(def: Dictionary, content: GameContent) -> void:
	var anchor: Dictionary = def["anchors"]["little_italy"]
	w.add_region({"id": "little_italy", "name": "Little Italy", "district": anchor.get("district", "little_italy")}, def, content)
	_li_rect = w.regions[0]["rect"]
	_li_poly = _rect_poly(_li_rect.grow(14.0))
	# Little Italy's roads end on its bounds; those ends join the city around it.
	for p in w.graph_nodes:
		var q: Vector2 = p
		if absf(q.x - _li_rect.position.x) < 0.01 or absf(q.x - _li_rect.end.x) < 0.01 \
				or absf(q.y - _li_rect.position.y) < 0.01 or absf(q.y - _li_rect.end.y) < 0.01:
			_candidates.append([q, "little_italy", 90.0, 0.0])


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


# --- Landmark silhouettes ------------------------------------------------------------------
const TOWERS := {
	"empire_state": [Vector2(46, 46), 205.0, "#8f8a80"], "chrysler": [Vector2(36, 36), 175.0, "#9a968c"],
	"world_trade_center": [Vector2(44, 44), 235.0, "#8a8d90"], "grand_central": [Vector2(90, 55), 32.0, "#9a8a70"],
	"statue_of_liberty": [Vector2(14, 14), 48.0, "#5f8f7c"], "yankee_stadium": [Vector2(170, 140), 26.0, "#8d8a80"],
	"shea_stadium": [Vector2(160, 160), 24.0, "#7d8a9a"], "navy_yard_cranes": [Vector2(16, 40), 46.0, "#6a5040"],
	"maspeth_gasholders": [Vector2(52, 52), 42.0, "#6f6a62"],
}


func _landmark_towers(def: Dictionary) -> void:
	for lm in def.get("landmarks", []):
		var spec: Array = TOWERS.get(lm["id"], [Vector2(30, 30), 60.0, "#8a8478"])
		var pos := Vector2(lm["pos"][0], lm["pos"][1])
		var di := geo.district_at(pos)
		var yaw := 0.0
		if di >= 0 and geo.districts[di].has("grid"):
			yaw = deg_to_rad(float(geo.districts[di]["grid"]["angle"]))
		var size: Vector2 = spec[0]
		# Licensed landmark models (Empire State, Chrysler...) replace the silhouette box.
		var model := "lic_" + String(lm["id"])
		if w._catalog.has(model):
			var dm: Dictionary = w._catalog[model]
			size = Vector2(float(dm["width"]), float(dm["depth"]))
			w.towers.append({"pos": pos, "size": size, "height": float(dm["height"]), "color": Color(spec[2]), "yaw": yaw,
				"id": lm["id"], "name": lm["name"], "model": model})
			var mxf := Transform2D(yaw, pos)
			var mh: Vector2 = size * 0.5 + Vector2(10, 10)
			_tower_polys.append(mxf * PackedVector2Array([-mh, Vector2(mh.x, -mh.y), mh, Vector2(-mh.x, mh.y)]))
			w.labels.append({"text": lm["name"], "pos": pos, "kind": "landmark"})
			continue
		var parts: Array = [[pos, size, float(spec[1])]]
		if lm["id"] == "world_trade_center":
			var off := Vector2(cos(yaw), sin(yaw)) * 34.0
			parts = [[pos - off, size, spec[1]], [pos + off, size, float(spec[1]) - 3.0]]
		for part in parts:
			w.towers.append({"pos": part[0], "size": part[1], "height": part[2], "color": Color(spec[2]), "yaw": yaw,
				"id": lm["id"], "name": lm["name"]})
			var xf := Transform2D(yaw, part[0])
			var half: Vector2 = (part[1] as Vector2) * 0.5 + Vector2(10, 10)
			_tower_polys.append(xf * PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]))
		w.labels.append({"text": lm["name"], "pos": pos, "kind": "landmark"})


# --- Polyline roads ------------------------------------------------------------------------
func _new_line(street: String, pts: PackedVector2Array, width: float, speed: int, style: int, group: String,
		kind: String) -> int:
	var splits: Array = []
	splits.resize(pts.size() - 1)
	for i in splits.size():
		splits[i] = []
	_lines.append({"street": street, "pts": pts, "width": width, "speed": speed, "style": style, "group": group,
		"kind": kind, "splits": splits, "cuts": []})
	var li := _lines.size() - 1
	for s in pts.size() - 1:
		var a := pts[s]
		var b := pts[s + 1]
		var c0 := Vector2i((a.min(b) / SEG_CELL).floor())
		var c1 := Vector2i((a.max(b) / SEG_CELL).floor())
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var k := Vector2i(cx, cz)
				if not _seg_cells.has(k):
					_seg_cells[k] = []
				_seg_cells[k].append([li, s])
	return li


func _add_corridor(a: Vector2, b: Vector2, half: float) -> void:
	_corridor_segs.append([a, b, half])
	var idx := _corridor_segs.size() - 1
	var m := Vector2(half + 40.0, half + 40.0)
	var c0 := Vector2i(((a.min(b) - m) / SEG_CELL).floor())
	var c1 := Vector2i(((a.max(b) + m) / SEG_CELL).floor())
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var k := Vector2i(cx, cz)
			var cell: PackedInt32Array = _corridor_cells.get(k, PackedInt32Array())
			cell.append(idx)
			_corridor_cells[k] = cell  # packed arrays are values: write back


func _add_arterial(r: Dictionary) -> void:
	var path := GeoMap.poly(r["path"])
	# Parts inside Little Italy are its own streets (Canal, Bowery): skip them.
	var runs: Array = []
	var cur := PackedVector2Array([path[0]])
	for i in path.size() - 1:
		var mid := (path[i] + path[i + 1]) * 0.5
		if _li_rect.grow(-0.5).has_point(mid):
			if cur.size() >= 2:
				runs.append(cur)
			cur = PackedVector2Array([path[i + 1]])
		else:
			cur.append(path[i + 1])
	if cur.size() >= 2:
		runs.append(cur)
	var width := float(r.get("width", 18))
	for k in runs.size():
		var pts: PackedVector2Array = runs[k]
		var li := _new_line(r["id"], pts, width, int(r.get("speed", 1300)), 2, "art:" + r["id"], "arterial")
		for s in pts.size() - 1:
			_add_corridor(pts[s], pts[s + 1], width * 0.5)
		for end in [pts[0], pts[-1]]:
			_candidates.append([end, "art:" + r["id"], END_STITCH_RADIUS, width * 0.5])
		_lines[li]["name"] = r["name"]
	w.streets[r["id"]] = {"name": r["name"], "width": width}


func _add_bridge(b: Dictionary) -> void:
	var path := GeoMap.poly(b["path"])
	var width := float(b.get("width", 26))
	var group: String = "bridge:" + b["id"]
	_new_line(b["id"], path, width, int(b.get("speed", 1600)), 2, group, "bridge")
	for s in path.size() - 1:
		_add_corridor(path[s], path[s + 1], width * 0.5)
	_candidates.append([path[0], group, END_STITCH_RADIUS, width * 0.5])
	_candidates.append([path[-1], group, END_STITCH_RADIUS, width * 0.5])
	if b.has("branch"):
		var br := GeoMap.poly(b["branch"])
		_new_line(b["id"], br, width * 0.8, int(b.get("speed", 1600)), 2, group + ":branch", "bridge")
		_candidates.append([br[0], group + ":branch", 2.0, 0.0])
		_candidates.append([br[-1], group + ":branch", END_STITCH_RADIUS, width * 0.4])
	w.streets[b["id"]] = {"name": b["name"], "width": width}
	# Towers stand in the water near each shore.
	var water_t: Array = []
	var total := 0.0
	for s in path.size() - 1:
		total += path[s].distance_to(path[s + 1])
	var steps := 60
	for i in steps + 1:
		var p := _along(path, total * i / steps)
		if not geo.is_land(p):
			water_t.append(float(i) / steps)
	var towers: Array = []
	if b.get("kind", "") in ["suspension", "cantilever"] and water_t.size() >= 4:
		var t0: float = water_t[0]
		var t1: float = water_t[-1]
		towers = [_along(path, total * lerpf(t0, t1, 0.16)), _along(path, total * lerpf(t0, t1, 0.84))]
	w.bridge_paths.append({"id": b["id"], "name": b["name"], "kind": b.get("kind", ""), "width": width, "path": path,
		"towers": towers, "length": total})
	w.labels.append({"text": b["name"], "pos": _along(path, total * 0.5), "kind": "bridge"})


static func _along(path: PackedVector2Array, d: float) -> Vector2:
	for s in path.size() - 1:
		var l := path[s].distance_to(path[s + 1])
		if d <= l:
			return path[s].lerp(path[s + 1], d / maxf(l, 0.001))
		d -= l
	return path[-1]


## Arterials that cross get a shared junction (graph split + paved box).
func _split_crossings() -> void:
	var segs: Array = []
	for li in _lines.size():
		if _lines[li]["kind"] != "arterial":
			continue
		var pts: PackedVector2Array = _lines[li]["pts"]
		for s in pts.size() - 1:
			segs.append([li, s, pts[s], pts[s + 1]])
	for i in segs.size():
		for j in range(i + 1, segs.size()):
			var a: Array = segs[i]
			var b: Array = segs[j]
			if a[0] == b[0]:
				continue
			var x: Variant = Geometry2D.segment_intersects_segment(a[2], a[3], b[2], b[3])
			if x == null:
				continue
			var p: Vector2 = x
			if (p.distance_to(a[2]) < 0.5 or p.distance_to(a[3]) < 0.5) and (p.distance_to(b[2]) < 0.5 or p.distance_to(b[3]) < 0.5):
				continue  # shared vertex: nodes merge by position already
			var la: Dictionary = _lines[a[0]]
			var lb: Dictionary = _lines[b[0]]
			_add_split(a[0], a[1], p)
			_add_split(b[0], b[1], p)
			var da: Vector2 = (a[3] - a[2]).normalized()
			var db: Vector2 = (b[3] - b[2]).normalized()
			var sin_phi := maxf(absf(da.cross(db)), 0.3)
			var cut_a := float(lb["width"]) * 0.5 / sin_phi + 0.5
			var cut_b := float(la["width"]) * 0.5 / sin_phi + 0.5
			la["cuts"].append([a[1], p, cut_a])
			lb["cuts"].append([b[1], p, cut_b])
			var hull := PackedVector2Array()
			for d in [[da, cut_a, float(la["width"]) * 0.5], [db, cut_b, float(lb["width"]) * 0.5]]:
				var dir: Vector2 = d[0]
				var n := Vector2(-dir.y, dir.x)
				for sa in [-1.0, 1.0]:
					for sn in [-1.0, 1.0]:
						hull.append(p + dir * float(d[1]) * sa + n * float(d[2]) * sn)
			_add_junction(p, Geometry2D.convex_hull(hull))


func _add_split(li: int, seg: int, p: Vector2) -> void:
	var pts: PackedVector2Array = _lines[li]["pts"]
	var a := pts[seg]
	var b := pts[seg + 1]
	var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 0.0001), 0.0, 1.0)
	(_lines[li]["splits"][seg] as Array).append([t, p])


func _add_junction(center: Vector2, poly: PackedVector2Array) -> void:
	var r := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		r = r.expand(q)
	w.intersections.append({"rect": r, "center": center, "poly": poly})


# --- District street grids -------------------------------------------------------------------
const AVENUE_NAMES := ["Amsterdam Ave", "Columbus Ave", "West End Ave", "Lexington Ave", "Park Ave", "Madison Ave",
	"Bedford Ave", "Nostrand Ave", "Flatbush Ave", "Myrtle Ave", "Metropolitan Ave", "Roosevelt Ave", "Steinway St",
	"Vernon Blvd", "Jerome Ave", "Webster Ave", "Prospect Ave", "Southern Blvd", "Kent Ave", "Wythe Ave",
	"Manhattan Ave", "Franklin Ave", "Classon Ave", "Graham Ave", "Lenox Ave", "St Nicholas Ave", "Hudson St",
	"Greenwich St", "Varick St", "Church St", "Pearl St", "Water St", "Clinton St", "Ludlow St", "Orchard St"]


## Districts with the same borough and grid share one lattice (Manhattan's
## grid runs unbroken from Houston to Harlem); each block belongs to the
## district under its centre and keeps that district's style.
func _district_groups(bounds: Dictionary) -> Array:
	var groups := {}
	var order: Array = []
	for di in geo.districts.size():
		var d: Dictionary = geo.districts[di]
		if not bounds.has(di) or not d.has("grid") or d.has("polygon") or d["style"] in ["park", "airport"]:
			continue
		var g: Dictionary = d["grid"]
		var key := "%s|%s|%s|%s" % [d["borough"], g["angle"], g["pitch"], g.get("irregular", false)]
		if not groups.has(key):
			groups[key] = {"members": [], "area": bounds[di]}
			order.append(key)
		groups[key]["members"].append(di)
		groups[key]["area"] = (groups[key]["area"] as Rect2).merge(bounds[di])
	var out: Array = []
	for k in order:
		out.append(groups[k])
	return out


func _district_grid(members: Array, area: Rect2) -> void:
	var lead: Dictionary = geo.districts[members[0]]
	var in_group := {}
	for di in members:
		in_group[di] = true
	var grid: Dictionary = lead["grid"]
	var angle := deg_to_rad(float(grid["angle"]))
	var seed_p := Vector2(lead["seed"][0], lead["seed"][1])
	var xf := Transform2D(angle, seed_p)
	var inv := xf.affine_inverse()
	var local := Rect2(inv * area.position, Vector2.ZERO)
	for c in [Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]:
		local = local.expand(inv * c)
	var pitch_a := float(grid["pitch"][0])
	var pitch_s := float(grid["pitch"][1])
	var irregular: bool = grid.get("irregular", false)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([w.seed_value, lead["id"], "grid"])
	var wa := 16.0 if pitch_a >= 180.0 else 12.0
	var ws := 12.0
	var xs := _lines_across(local.position.x, local.end.x, pitch_a, rng, irregular)
	var zs := _lines_across(local.position.y, local.end.y, pitch_s, rng, irregular)
	var kept := {}
	var counts := {}
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var cell := Rect2(xs[i] + wa * 0.5, zs[j] + ws * 0.5, xs[i + 1] - xs[i] - wa, zs[j + 1] - zs[j] - ws)
			for r in _fit_parts(cell, xf, in_group, 3):
				_keep_block(r, xf, i, j, kept, counts)
	if kept.is_empty():
		return
	_lattice_streets(lead, xf, xs, zs, wa, ws, kept, in_group)
	for di in counts:
		stats["blocks_" + geo.districts[di]["id"]] = counts[di]


func _keep_block(r: Rect2, xf: Transform2D, i: int, j: int, kept: Dictionary, counts: Dictionary) -> void:
			var di := geo.district_at(xf * r.get_center())
			var d: Dictionary = geo.districts[di]
			var style: String = d["style"]
			var kit: Dictionary = w.kits.get(style, w.kits["tenement"])
			kept[Vector2i(i, j)] = true
			var count: int = counts.get(di, 0)
			w.blocks.append({"rect": r, "xform": xf, "gen": true, "district": d["id"], "region": d["id"], "style": style,
				"seed": hash([w.seed_value, d["id"], i, j, r.position.x]), "kit": kit, "sidewalks": true,
				"lawn": (kit["fill"] as Dictionary).get("lawns", false), "yard": (kit["fill"] as Dictionary).get("yard", ""),
				"core": true, "col": i, "row": j, "index": count})
			counts[di] = count + 1


## Streets: lattice edges next to a kept block, inside the group's districts,
## cut where they cross an arterial (the cut ends join the arterial).
func _lattice_streets(lead: Dictionary, xf: Transform2D, xs: Array, zs: Array, wa: float, ws: float, kept: Dictionary,
		in_group: Dictionary) -> void:
	var group: String = "d:" + lead["id"]
	var degree := {}
	var edges: Array = []
	for i in xs.size():
		for j in zs.size() - 1:
			if kept.has(Vector2i(i - 1, j)) or kept.has(Vector2i(i, j)):
				edges.append([Vector2i(i, j), Vector2i(i, j + 1), true])
	for j in zs.size():
		for i in xs.size() - 1:
			if kept.has(Vector2i(i, j - 1)) or kept.has(Vector2i(i, j)):
				edges.append([Vector2i(i, j), Vector2i(i + 1, j), false])
	var name_base := absi(hash(lead["id"]))
	for e in edges:
		var a := xf * Vector2(xs[e[0].x], zs[e[0].y])
		var b := xf * Vector2(xs[e[1].x], zs[e[1].y])
		var whole := _edge_clear(a, b, in_group)
		var vertical: bool = e[2]
		if not whole:
			for piece in _edge_pieces(a, b, in_group):
				var street_p := "%s_%s%d" % [lead["id"], "a" if vertical else "s", e[0].x if vertical else e[0].y]
				if not w.streets.has(street_p):
					w.streets[street_p] = {"name": "Cross St", "width": wa if vertical else ws}
				var pa: Vector2 = piece[0]
				var pb: Vector2 = piece[1]
				var trim_a := (ws if vertical else wa) * 0.5 if pa.distance_to(a) < 0.5 else 0.0
				var trim_b := (ws if vertical else wa) * 0.5 if pb.distance_to(b) < 0.5 else 0.0
				var dir_p := (pb - pa).normalized()
				var width_p := wa if vertical else ws
				if pa.distance_to(pb) > trim_a + trim_b + 2.0:
					w.add_segment(street_p, pa + dir_p * trim_a, pb - dir_p * trim_b, width_p, 2 if width_p >= 16.0 else 1)
				_new_line(street_p, PackedVector2Array([pa, pb]), width_p, 1000, 1, group, "lattice")
				for end in [[pa, a, e[0]], [pb, b, e[1]]]:
					if (end[0] as Vector2).distance_to(end[1]) < 0.5:
						degree[end[2]] = degree.get(end[2], 0) + 1
					else:
						_candidates.append([end[0], group, STITCH_RADIUS, 0.0])
			continue
		var street: String
		var width := wa if vertical else ws
		if vertical:
			street = "%s_a%d" % [lead["id"], e[0].x]
			if not w.streets.has(street):
				w.streets[street] = {"name": AVENUE_NAMES[(name_base + e[0].x) % AVENUE_NAMES.size()], "width": width}
		else:
			street = "%s_s%d" % [lead["id"], e[0].y]
			if not w.streets.has(street):
				w.streets[street] = {"name": "%s St" % _ordinal(absi(e[0].y - zs.size() / 2) + 1 + name_base % 40),
					"width": width}
		var trim := (ws if vertical else wa) * 0.5
		var dir := (b - a).normalized()
		w.add_segment(street, a + dir * trim, b - dir * trim, width, 2 if width >= 16.0 else 1)
		_new_line(street, PackedVector2Array([a, b]), width, 1000, 1, group, "lattice")
		degree[e[0]] = degree.get(e[0], 0) + 1
		degree[e[1]] = degree.get(e[1], 0) + 1
	var half := Vector2(wa, ws) * 0.5
	var quad := PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	for k in degree:
		var c := xf * Vector2(xs[k.x], zs[k.y])
		var poly := PackedVector2Array()
		for q in quad:
			poly.append(c + xf.basis_xform(q))
		_add_junction(c, poly)
		if degree[k] < 4:
			_candidates.append([c, group, STITCH_RADIUS, 0.0])


static func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


## Grid line positions: regular pitch with gentle variation; the Village gets
## strong jitter and merged blocks.
func _lines_across(lo: float, hi: float, pitch: float, rng: RandomNumberGenerator, irregular: bool) -> Array:
	var out: Array = []
	var x := floorf(lo / pitch) * pitch - pitch
	var jitter := 0.24 if irregular else 0.07
	while x <= hi + pitch:
		var v := x + rng.randf_range(-jitter, jitter) * pitch
		if irregular and not out.is_empty() and rng.randf() < 0.2:
			x += pitch
			continue
		out.append(v)
		x += pitch
	return out


## Shrinks a block until it lies on land inside its district group and clear
## of parks, Little Italy, landmark plazas and arterial corridors, pulling in
## only the sides whose corners fail; size 0 = drop.
func _fit_block(r: Rect2, xf: Transform2D, in_group: Dictionary) -> Rect2:
	for attempt in 10:
		if r.size.x < MIN_BLOCK or r.size.y < MIN_BLOCK:
			return Rect2()
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		var bad := [false, false, false, false]
		var any_bad := false
		for k in 4:
			var p: Vector2 = xf * (corners[k] as Vector2)
			if not geo.is_land(p) or not in_group.has(geo.district_at(p)) or _point_blocked(p):
				bad[k] = true
				any_bad = true
		if not any_bad:
			if not in_group.has(geo.district_at(xf * r.get_center())):
				return Rect2()
			var poly := PackedVector2Array()
			for k in 4:
				poly.append(xf * (corners[k] as Vector2))
			return Rect2() if _blocked(poly) else r
		# Pull in the sides touching failing corners (0: x0z0, 1: x1z0, 2: x1z1, 3: x0z1).
		var x0 := r.position.x + (SHRINK_STEP if bad[0] or bad[3] else 0.0)
		var x1 := r.end.x - (SHRINK_STEP if bad[1] or bad[2] else 0.0)
		var z0 := r.position.y + (SHRINK_STEP if bad[0] or bad[1] else 0.0)
		var z1 := r.end.y - (SHRINK_STEP if bad[2] or bad[3] else 0.0)
		r = Rect2(x0, z0, x1 - x0, z1 - z0)
	return Rect2()


## A block cut by an arterial becomes the blocks either side of it.
func _fit_parts(r: Rect2, xf: Transform2D, in_group: Dictionary, depth: int) -> Array:
	if r.size.x < MIN_BLOCK or r.size.y < MIN_BLOCK:
		return []
	var poly := PackedVector2Array()
	for q in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		poly.append(xf * (q as Vector2))
	var cut := _corridor_through(poly) if depth > 0 else []
	if cut.is_empty():
		var f := _fit_block(r, xf, in_group)
		return [f] if f.size.x >= MIN_BLOCK and f.size.y >= MIN_BLOCK else []
	var inv := xf.affine_inverse()
	var a: Vector2 = inv * (cut[0] as Vector2)
	var b: Vector2 = inv * (cut[1] as Vector2)
	var gap := float(cut[2]) + CORRIDOR_MARGIN + 2.0
	var out: Array = []
	if absf(b.y - a.y) >= absf(b.x - a.x):
		# Corridor runs along local z: split across x where it crosses the block.
		var lo := INF
		var hi := -INF
		for z in [r.position.y, r.end.y]:
			var t := (float(z) - a.y) / (b.y - a.y) if absf(b.y - a.y) > 0.001 else 0.5
			var x := a.x + (b.x - a.x) * t
			lo = minf(lo, x - gap)
			hi = maxf(hi, x + gap)
		out.append_array(_fit_parts(Rect2(r.position.x, r.position.y, lo - r.position.x, r.size.y), xf, in_group, depth - 1))
		out.append_array(_fit_parts(Rect2(hi, r.position.y, r.end.x - hi, r.size.y), xf, in_group, depth - 1))
	else:
		var lo := INF
		var hi := -INF
		for x in [r.position.x, r.end.x]:
			var t := (float(x) - a.x) / (b.x - a.x) if absf(b.x - a.x) > 0.001 else 0.5
			var z := a.y + (b.y - a.y) * t
			lo = minf(lo, z - gap)
			hi = maxf(hi, z + gap)
		out.append_array(_fit_parts(Rect2(r.position.x, r.position.y, r.size.x, lo - r.position.y), xf, in_group, depth - 1))
		out.append_array(_fit_parts(Rect2(r.position.x, hi, r.size.x, r.end.y - hi), xf, in_group, depth - 1))
	return out


## First arterial/bridge corridor crossing a polygon: [a, b, half_width] or [].
func _corridor_through(poly: PackedVector2Array) -> Array:
	var bb := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		bb = bb.expand(q)
	var c0 := Vector2i((bb.position / SEG_CELL).floor())
	var c1 := Vector2i((bb.end / SEG_CELL).floor())
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for idx in _corridor_cells.get(Vector2i(cx, cz), PackedInt32Array()):
				var s: Array = _corridor_segs[idx]
				if not Geometry2D.intersect_polygons(poly, _band(s[0], s[1], float(s[2]) + CORRIDOR_MARGIN)).is_empty():
					return s
	return []


## Clear stretches of a street edge (on land, in its districts, off arterials).
func _edge_pieces(a: Vector2, b: Vector2, in_group: Dictionary) -> Array:
	var length := a.distance_to(b)
	var steps := maxi(2, int(length / 4.0))
	var out: Array = []
	var start := -1
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps)
		var ok := _sample_clear(p, in_group)
		if ok and start < 0:
			start = k
		if (not ok or k == steps) and start >= 0:
			var end := k if ok else k - 1
			if end > start and length * float(end - start) / steps >= 10.0:
				out.append([a.lerp(b, float(start) / steps), a.lerp(b, float(end) / steps)])
			start = -1
	return out


func _sample_clear(p: Vector2, in_group: Dictionary) -> bool:
	if not geo.is_land(p) or not in_group.has(geo.district_at(p)) or _li_rect.grow(8.0).has_point(p) or geo.park_at(p) >= 0:
		return false
	for idx in _corridor_cells.get(Vector2i((p / SEG_CELL).floor()), PackedInt32Array()):
		var s: Array = _corridor_segs[idx]
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, s[0], s[1])) < float(s[2]) + 2.0:
			return false
	return true


func _point_blocked(p: Vector2) -> bool:
	if Geometry2D.is_point_in_polygon(p, _li_poly):
		return true
	for tp in _tower_polys:
		if Geometry2D.is_point_in_polygon(p, tp):
			return true
	if geo.park_at(p) >= 0:
		return true
	for idx in _corridor_cells.get(Vector2i((p / SEG_CELL).floor()), PackedInt32Array()):
		var s: Array = _corridor_segs[idx]
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, s[0], s[1])) < float(s[2]) + CORRIDOR_MARGIN + 2.0:
			return true
	return false


func _blocked(poly: PackedVector2Array) -> bool:
	if not Geometry2D.intersect_polygons(poly, _li_poly).is_empty():
		return true
	for tp in _tower_polys:
		if not Geometry2D.intersect_polygons(poly, tp).is_empty():
			return true
	var bb := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		bb = bb.expand(q)
	for pk in geo.parks:
		if (pk["bounds"] as Rect2).intersects(bb) and not Geometry2D.intersect_polygons(poly, pk["polygon"]).is_empty():
			return true
	var seen := {}
	var c0 := Vector2i((bb.position / SEG_CELL).floor())
	var c1 := Vector2i((bb.end / SEG_CELL).floor())
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for idx in _corridor_cells.get(Vector2i(cx, cz), PackedInt32Array()):
				if seen.has(idx):
					continue
				seen[idx] = true
				var s: Array = _corridor_segs[idx]
				if not Geometry2D.intersect_polygons(poly, _band(s[0], s[1], float(s[2]) + CORRIDOR_MARGIN)).is_empty():
					return true
	return false


static func _band(a: Vector2, b: Vector2, half: float) -> PackedVector2Array:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * half
	var e := d * half * 0.25
	return PackedVector2Array([a - e + n, b + e + n, b + e - n, a - e - n])


func _edge_clear(a: Vector2, b: Vector2, in_group: Dictionary) -> bool:
	for k in 5:
		var p := a.lerp(b, k / 4.0)
		if not geo.is_land(p) or not in_group.has(geo.district_at(p)) or _li_rect.grow(8.0).has_point(p) or geo.park_at(p) >= 0:
			return false
		for idx in _corridor_cells.get(Vector2i((p / SEG_CELL).floor()), PackedInt32Array()):
			var s: Array = _corridor_segs[idx]
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, s[0], s[1])) < float(s[2]) + 2.0:
				return false
	return true


# --- Stitching and graph emission ------------------------------------------------------------
func _stitch() -> void:
	var connectors := 0
	for c in _candidates:
		var p: Vector2 = c[0]
		var group: String = c[1]
		var radius: float = c[2]
		var best: Array = []
		var best_d := radius
		var c0 := Vector2i(((p - Vector2(radius, radius)) / SEG_CELL).floor())
		var c1 := Vector2i(((p + Vector2(radius, radius)) / SEG_CELL).floor())
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				for ref in _seg_cells.get(Vector2i(cx, cz), []):
					var line: Dictionary = _lines[ref[0]]
					if line["group"] == group or line["group"].begins_with(group + ":") or group.begins_with(line["group"] + ":"):
						continue
					var pts: PackedVector2Array = line["pts"]
					var q := Geometry2D.get_closest_point_to_segment(p, pts[ref[1]], pts[ref[1] + 1])
					var dist := p.distance_to(q)
					# Bridges only connect at their ends (no ramps off the span).
					if line["kind"] == "bridge" and dist > 2.0:
						continue
					if dist < best_d - 0.01:
						best_d = dist
						best = [ref[0], ref[1], q]
		if best.is_empty():
			continue
		var q: Vector2 = best[2]
		if best_d > 0.3:
			if not geo.is_land((p + q) * 0.5) or _crosses_li(p, q):
				continue
		_add_split(best[0], best[1], q)
		if best_d <= 0.3:
			continue
		var target: Dictionary = _lines[best[0]]
		var street := "link_%d" % connectors
		w.streets[street] = {"name": target.get("name", w.street_name(target["street"])), "width": 12.0}
		_new_line(street, PackedVector2Array([p, q]), 12.0, 1000, 1, "link", "connector")
		var dir := (q - p).normalized()
		var start_trim := 6.0 if group.begins_with("d:") else float(c[3])
		var end_trim := float(target["width"]) * 0.5
		if best_d > start_trim + end_trim + 1.0:
			w.add_segment(street, p + dir * start_trim, q - dir * end_trim, 12.0, 1)
		connectors += 1
	stats["connectors"] = connectors


func _crosses_li(a: Vector2, b: Vector2) -> bool:
	var r := _li_rect.grow(-1.0)
	if r.has_point(a.lerp(b, 0.5)):
		return true
	var poly := _rect_poly(r)
	for k in 4:
		if Geometry2D.segment_intersects_segment(a, b, poly[k], poly[(k + 1) % 4]) != null:
			var x: Vector2 = Geometry2D.segment_intersects_segment(a, b, poly[k], poly[(k + 1) % 4])
			if x.distance_to(a) > 1.0 and x.distance_to(b) > 1.0:
				return true
	return false


func _emit_graph() -> void:
	for line in _lines:
		var pts: PackedVector2Array = line["pts"]
		for s in pts.size() - 1:
			var splits: Array = line["splits"][s]
			splits.sort_custom(func(x, y): return x[0] < y[0])
			var chain := [w.node(pts[s])]
			for sp in splits:
				chain.append(w.node(sp[1]))
			chain.append(w.node(pts[s + 1]))
			for k in chain.size() - 1:
				w.edge(chain[k], chain[k + 1], line["street"], line["width"], line["speed"])
		if line["kind"] in ["arterial", "bridge"]:
			_emit_polyline_surface(line)


## Road surface for a polyline: 128 m pieces with continuous markings, mitred
## joints at bends and gaps where other arterials cross.
func _emit_polyline_surface(line: Dictionary) -> void:
	var pts: PackedVector2Array = line["pts"]
	var hw: float = float(line["width"]) * 0.5
	var total := 0.0
	for s in pts.size() - 1:
		total += pts[s].distance_to(pts[s + 1])
	var trims := []  # [start trim, end trim] per segment
	trims.resize(pts.size() - 1)
	for s in trims.size():
		trims[s] = [0.0, 0.0]
	for v in range(1, pts.size() - 1):
		var d0 := (pts[v] - pts[v - 1]).normalized()
		var d1 := (pts[v + 1] - pts[v]).normalized()
		var turn := acos(clampf(d0.dot(d1), -1.0, 1.0))
		if turn < 0.01:
			continue
		var t := minf(hw * tan(turn * 0.5) + 0.3, minf(pts[v].distance_to(pts[v - 1]), pts[v].distance_to(pts[v + 1])) * 0.45)
		trims[v - 1][1] = t
		trims[v][0] = t
		var n0 := Vector2(-d0.y, d0.x) * hw
		var n1 := Vector2(-d1.y, d1.x) * hw
		var p := pts[v]
		_add_junction(p, Geometry2D.convex_hull(PackedVector2Array([p - d0 * t + n0, p - d0 * t - n0, p + d1 * t + n1,
			p + d1 * t - n1, p + n0, p - n0, p + n1, p - n1])))
	var along := 0.0
	for s in pts.size() - 1:
		var a := pts[s]
		var b := pts[s + 1]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var intervals := [[trims[s][0], length - trims[s][1]]]
		for cut in line["cuts"]:
			if cut[0] != s:
				continue
			var u := (cut[1] as Vector2 - a).dot(dir)
			intervals = _subtract(intervals, u - float(cut[2]), u + float(cut[2]))
		for iv in intervals:
			var u0: float = iv[0]
			var u1: float = iv[1]
			var pieces := maxi(1, ceili((u1 - u0) / PIECE))
			for k in pieces:
				var p0 := lerpf(u0, u1, float(k) / pieces)
				var p1 := lerpf(u0, u1, float(k + 1) / pieces)
				if p1 - p0 < 0.3:
					continue
				w.road_segments.append({"street": line["street"], "from": a + dir * p0, "to": a + dir * p1,
					"width": line["width"], "style": line["style"], "along0": along + p0, "total": total + 1000.0,
					"dir": dir, "origin": a})
		along += length


static func _subtract(intervals: Array, a: float, b: float) -> Array:
	var out := []
	for iv in intervals:
		if b <= iv[0] or a >= iv[1]:
			out.append(iv)
			continue
		if a > iv[0]:
			out.append([iv[0], a])
		if b < iv[1]:
			out.append([b, iv[1]])
	return out


## Links road islands to the network around Little Italy, or drops them.
func _connect_islands() -> void:
	var n := w.graph_nodes.size()
	var adj: Array = []
	adj.resize(n)
	for i in n:
		adj[i] = []
	for e in w.graph_edges:
		adj[e["a"]].append(e["b"])
		adj[e["b"]].append(e["a"])
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var sizes: Array = []
	for start in n:
		if comp[start] >= 0:
			continue
		var id := sizes.size()
		var stack := [start]
		comp[start] = id
		var count := 0
		while not stack.is_empty():
			var v: int = stack.pop_back()
			count += 1
			for u in adj[v]:
				if comp[u] < 0:
					comp[u] = id
					stack.append(u)
		sizes.append(count)
	var main := comp[0]  # node 0 is Little Italy
	# Spatial buckets of main-component nodes.
	var cells := {}
	for i in n:
		if comp[i] == main:
			var k := Vector2i(((w.graph_nodes[i] as Vector2) / 128.0).floor())
			if not cells.has(k):
				cells[k] = []
			cells[k].append(i)
	var linked := 0
	for cid in sizes.size():
		if cid == main:
			continue
		var best := [-1, -1]
		var best_d := LINK_RADIUS
		for i in n:
			if comp[i] != cid:
				continue
			var p: Vector2 = w.graph_nodes[i]
			var k0 := Vector2i(((p - Vector2(LINK_RADIUS, LINK_RADIUS)) / 128.0).floor())
			var k1 := Vector2i(((p + Vector2(LINK_RADIUS, LINK_RADIUS)) / 128.0).floor())
			for kx in range(k0.x, k1.x + 1):
				for kz in range(k0.y, k1.y + 1):
					for j in cells.get(Vector2i(kx, kz), []):
						var d := p.distance_to(w.graph_nodes[j])
						if d < best_d and geo.is_land((p + (w.graph_nodes[j] as Vector2)) * 0.5) \
								and not _crosses_li(p, w.graph_nodes[j]):
							best_d = d
							best = [i, j]
		if best[0] >= 0:
			var street := "link_island_%d" % linked
			w.streets[street] = {"name": "Service Rd", "width": 12.0}
			w.edge(best[0], best[1], street, 12.0, 1000)
			w.add_segment(street, w.graph_nodes[best[0]], w.graph_nodes[best[1]], 12.0, 1)
			linked += 1
			for i in n:
				if comp[i] == cid:
					comp[i] = main
	# Anything still unreachable is removed so every node can be routed to.
	var keep := PackedInt32Array()
	keep.resize(n)
	var remap := 0
	var new_nodes: Array = []
	for i in n:
		if comp[i] == main:
			keep[i] = remap
			new_nodes.append(w.graph_nodes[i])
			remap += 1
		else:
			keep[i] = -1
	var new_edges: Array = []
	for e in w.graph_edges:
		if keep[e["a"]] >= 0 and keep[e["b"]] >= 0:
			var ne: Dictionary = e.duplicate()
			ne["a"] = keep[e["a"]]
			ne["b"] = keep[e["b"]]
			new_edges.append(ne)
	stats["islands_linked"] = linked
	stats["nodes_dropped"] = n - remap
	w.graph_nodes = new_nodes
	w.graph_edges = new_edges
	w._node_index.clear()
	for i in new_nodes.size():
		w._node_index[WorldLayout._key(new_nodes[i])] = i


# --- Parks, airport, scenery -------------------------------------------------------------------
func _parks() -> void:
	for pi in geo.parks.size():
		var pk: Dictionary = geo.parks[pi]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([w.seed_value, pk["id"], "park"])
		var poly: PackedVector2Array = pk["polygon"]
		var paths: Array = []
		if poly.size() >= 4 and pk["kind"] != "square":
			for i in mini(6, poly.size()):
				var a := poly[rng.randi() % poly.size()]
				var b := poly[rng.randi() % poly.size()]
				if a.distance_to(b) > 120.0:
					paths.append([a.lerp(b, 0.04), b.lerp(a, 0.04)])
		var trees: Array = []
		var r: Rect2 = pk["bounds"]
		var cell := 12.0
		var x := r.position.x + cell * 0.5
		while x < r.end.x:
			var z := r.position.y + cell * 0.5
			while z < r.end.y:
				var p := Vector2(x + rng.randf_range(-4, 4), z + rng.randf_range(-4, 4))
				var meadow := sin(p.x * 0.011 + 1.3) * cos(p.y * 0.017) > 0.3
				if not meadow and rng.randf() < 0.68 and Geometry2D.is_point_in_polygon(p, poly) \
						and not geo.in_lake(p, pi) and _clear_of_lakes(p, pk["lakes"], 6.0):
					var ok := true
					for path in paths:
						if p.distance_to(Geometry2D.get_closest_point_to_segment(p, path[0], path[1])) < 4.0:
							ok = false
							break
					if ok:
						trees.append(p)
				z += cell
			x += cell
		w.park_areas.append({"name": pk["name"], "polygon": poly, "lakes": pk["lakes"], "paths": paths, "trees": trees})
		w.grounds.append({"polygon": poly, "material": "M_Grass"})
		w.labels.append({"text": pk["name"], "pos": r.get_center(), "kind": "park"})


static func _clear_of_lakes(p: Vector2, lakes: Array, margin: float) -> bool:
	for lake in lakes:
		var poly: PackedVector2Array = lake
		for k in poly.size():
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[k], poly[(k + 1) % poly.size()])) < margin:
				return false
	return true


func _airport(def: Dictionary) -> void:
	for d in def["districts"]:
		if d.get("style", "") == "airport" and d.has("polygon"):
			var poly := GeoMap.poly(d["polygon"])
			w.grounds.append({"polygon": poly, "material": "M_Concrete"})
			var c := GeoMap.poly_bounds(poly).get_center()
			for rw in [[Vector2(-480, 180), Vector2(520, -200)], [Vector2(-60, 260), Vector2(140, -330)]]:
				w.road_segments.append({"street": "runway", "from": c + (rw[0] as Vector2), "to": c + (rw[1] as Vector2),
					"width": 46.0, "style": 0, "along0": 0.0, "total": 2000.0})


## Low-cost massing on scenery land (New Jersey, Long Island, Westchester,
## Staten Island) so every horizon is city, never a map edge.
func _backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([w.seed_value, "backdrop"])
	var area := geo.extent.grow(1100.0)
	var step := 135.0
	var z := area.position.y
	while z < area.end.y:
		var x := area.position.x
		while x < area.end.x:
			var p := Vector2(x, z)
			if geo.is_land(p) and _far_from_boroughs(p):
				var n := rng.randi_range(1, 2)
				for i in n:
					var q := p + Vector2(rng.randf_range(-30, 30), rng.randf_range(-28, 28))
					w.backdrop_boxes.append({"pos": q, "size": Vector2(rng.randf_range(22, 46), rng.randf_range(18, 40)),
						"height": rng.randf_range(8.0, 26.0) * (2.2 if rng.randf() < 0.05 else 1.0), "yaw": 0.0})
			x += step
		z += step


func _far_from_boroughs(p: Vector2) -> bool:
	for o in [Vector2.ZERO, Vector2(140, 0), Vector2(-140, 0), Vector2(0, 140), Vector2(0, -140)]:
		if not geo.borough_at(p + o).is_empty():
			return false
	return true
