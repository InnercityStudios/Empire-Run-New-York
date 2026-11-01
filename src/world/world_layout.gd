class_name WorldLayout
extends RefCounted
## Deterministic layout of a whole server world (a "province"), composed from
## neighbourhood regions, arterial roads, waterfront piers, bridges, parks and
## distant backdrop districts.
##
## - Grid regions reuse DistrictLayout; Little Italy is built from its own,
##   unchanged definition, so existing buildings keep their identities.
## - Road nodes merge by integer-centimetre position, and arterials are
##   stitched to every region road that meets them: the result is one
##   connected network whose node keys are stable as the world grows.
## - Content is indexed by stable chunk coordinates (chunk_size metres) for
##   streaming. Pure data: no nodes are created here.

const MIN_LINE_GAP := 25.0
const SEGMENT_PIECE := 128.0
const N_S_NAMES := ["Amsterdam Ave", "Columbus Ave", "West End Ave", "Riverside Dr", "Lexington Ave", "Park Ave",
	"Madison Ave", "Irving Pl", "Greenwich St", "Washington St", "Varick St", "Church St", "Water St", "Front St",
	"Pearl St", "Gansevoort St", "Hudson St", "Ave A", "Ave B", "Ave C", "Pitt St", "Clinton St", "Rutgers St",
	"Jackson St", "Montgomery St", "Gouverneur St", "Fulton St", "Beekman St", "Maiden Ln", "Old Slip"]

var id := ""
var display_name := ""
var seed_value := 1
var chunk_size := 256.0
var land: Rect2
var world_rect: Rect2
var playable: Rect2
var water_level := -1.6
var sidewalk := 4.0
var curb_height := 0.15
var corner_radius := 3.2
var lane_offset := 1.9

var regions: Array = []          ## {id, name, style, rect: Rect2, layout: DistrictLayout}
var blocks: Array = []           ## {rect, faces, region, style, sidewalks, lawn, core, col, row}
var lots: Array = []             ## DistrictLayout lots with world block indices
var props: Array = []
var parking: Array = []
var landmarks: Dictionary = {}
var road_segments: Array = []    ## {street, from, to, width, style, along0, total}
var intersections: Array = []
var graph_nodes: Array = []      ## Vector2 (metres)
var graph_edges: Array = []      ## {a, b, street, width, speed}
var streets: Dictionary = {}     ## street id -> {name, width}
var parks: Array = []            ## {rect, lake: Rect2, paths: Array[[Vector2, Vector2]], trees: Array[Vector2]}
var piers: Array = []            ## {deck: Rect2, shed: Transform3D, axis}
var bridges: Array = []          ## {from: Vector2, to: Vector2, width, towers: Array, name, leads_to}
var backdrops: Array = []        ## {rect, boxes: Array[{rect: Rect2, height: float}]}
var region_grounds: Array = []   ## {rect: Rect2, ground: String}
var portals: Array = []          ## future-city connection points {node, name}

## Geography worlds (`schema: geography-v1`, see GeographyBuilder).
var is_geo := false
var geo: GeoMap
var districts: Array = []        ## district definitions (id, name, borough, style, territory...)
var kits: Dictionary = {}        ## style -> BlockFiller kit (read-only after build)
var land_polygons: Array = []    ## {id, kind, polygon: PackedVector2Array}
var park_areas: Array = []       ## {name, polygon, lakes: Array[PackedVector2Array], paths, trees}
var bridge_paths: Array = []     ## {id, name, kind, width, path: PackedVector2Array, towers: Array[Vector2]}
var grounds: Array = []          ## {polygon: PackedVector2Array, material}
var towers: Array = []           ## landmark silhouettes {pos: Vector2, size: Vector2, height, color, yaw}
var backdrop_boxes: Array = []   ## scenery massing {pos: Vector2, size: Vector2, height, yaw}
var labels: Array = []           ## {text, pos: Vector2, kind}

var _catalog: Dictionary
var _node_index: Dictionary = {}
var _chunks: Dictionary = {}


static func build(def: Dictionary, content: GameContent) -> WorldLayout:
	var w := WorldLayout.new()
	if def.get("schema", "") == "geography-v1":
		GeographyBuilder.populate(w, def, content)
	else:
		w._build(def, content)
	return w


func _build(def: Dictionary, content: GameContent) -> void:
	_catalog = content.building_catalog
	id = def.get("id", "world")
	display_name = def.get("display_name", id)
	seed_value = int(def.get("seed", 1))
	chunk_size = float(def.get("chunk_size", 256))
	land = _rect(def["land"])
	world_rect = _rect(def["world"])
	playable = _rect(def["playable"])
	water_level = float(def.get("water_level", -1.6))
	var defaults: Dictionary = def.get("defaults", {})
	sidewalk = defaults.get("sidewalk_width", 4.0)
	curb_height = defaults.get("curb_height", 0.15)
	corner_radius = defaults.get("corner_radius", 3.2)
	lane_offset = defaults.get("lane_offset", 1.9)
	for r in def.get("regions", []):
		_add_region(r, def, content)
	for a in def.get("arterials", []):
		streets[a["id"]] = {"name": a["name"], "width": a["width"]}
	_stitch_arterials(def.get("arterials", []))
	for r in def.get("regions", []):
		if r.has("piers"):
			_add_piers(r)
		if r.has("park"):
			_add_park(r)
	for b in def.get("bridges", []):
		_add_bridge(b)
	for bd in def.get("backdrops", []):
		_add_backdrop(bd)
	_index_chunks()


static func _rect(a: Array) -> Rect2:
	return Rect2(Vector2(a[0], a[1]), Vector2(a[2] - a[0], a[3] - a[1]))


# --- Regions ------------------------------------------------------------------------
func add_region(r: Dictionary, def: Dictionary, content: GameContent) -> void:
	_add_region(r, def, content)


func _add_region(r: Dictionary, def: Dictionary, content: GameContent) -> void:
	var dl: DistrictLayout
	if r.has("district"):
		dl = DistrictLayout.build(content.districts[r["district"]], _catalog)
	else:
		dl = DistrictLayout.build(_region_def(r, def), _catalog)
	var rect := dl.bounds
	regions.append({"id": r["id"], "name": r.get("name", r["id"]), "style": dl.style, "rect": rect, "layout": dl})
	region_grounds.append({"rect": rect, "ground": _ground_for(dl.style)})
	for road in dl.avenues + dl.streets:
		streets[road["id"]] = {"name": road["name"], "width": road["width"]}
	var node_map: Array = []
	for p in dl.graph_nodes:
		node_map.append(_node(p))
	for e in dl.graph_edges:
		_edge(node_map[e["a"]], node_map[e["b"]], e["street"], e["width"], int(e.get("speed", 1000)))
	for seg in dl.road_segments:
		_add_segment(seg["street"], seg["from"], seg["to"], seg["width"], seg.get("style", 1))
	intersections.append_array(dl.intersections)
	var block_base := blocks.size()
	var style_info: Dictionary = DistrictLayout.STYLES.get(dl.style, {})
	for b in dl.blocks:
		blocks.append({"rect": b["rect"], "faces": b["faces"], "region": r["id"], "style": dl.style,
			"sidewalks": style_info.get("sidewalks", true), "lawn": style_info.get("lawns", false),
			"core": b["core"], "col": b["col"], "row": b["row"]})
	for lot in dl.lots:
		var l: Dictionary = lot.duplicate()
		l["block"] = int(lot["block"]) + block_base
		lots.append(l)
	for p in dl.props:
		var pp: Dictionary = p.duplicate()
		pp["block"] = int(p["block"]) + block_base
		props.append(pp)
	parking.append_array(dl.parking)
	for lm_id in dl.landmarks:
		var lm: Dictionary = dl.landmarks[lm_id].duplicate()
		lm["block"] = int(lm["block"]) + block_base
		landmarks[lm_id] = lm


func _ground_for(style: String) -> String:
	match style:
		"park", "suburban":
			return "M_Grass"
		"waterfront":
			return "M_Concrete"
	return "asphalt"


## Builds a DistrictLayout definition for a generated region.
func _region_def(r: Dictionary, def: Dictionary) -> Dictionary:
	var rect := _rect(r["rect"])
	var sets: Dictionary = def.get("street_sets", {})
	var grid: Dictionary = r.get("grid", {})
	var avenues: Array = []
	var streets_list: Array = []
	var name_rng := RandomNumberGenerator.new()
	name_rng.seed = hash([seed_value, r["id"], "names"])
	if r.get("avenues") is String:
		avenues = _filter_lines(sets.get(r["avenues"], []), "x", rect.position.x, rect.end.x)
	elif grid.has("x_pitch"):
		var x: float = grid["x_origin"]
		while x > rect.position.x:
			x -= grid["x_pitch"]
		var k := 0
		while x < rect.end.x:
			if x > rect.position.x + MIN_LINE_GAP and x < rect.end.x - MIN_LINE_GAP:
				avenues.append({"id": "%s_ave_%d" % [r["id"], k], "x": x, "width": grid.get("x_width", 12),
					"name": N_S_NAMES[(hash(r["id"]) + k) % N_S_NAMES.size()]})
				k += 1
			x += grid["x_pitch"]
	if r.get("streets") is String:
		streets_list = _filter_lines(sets.get(r["streets"], []), "z", rect.position.y, rect.end.y)
	elif grid.has("z_lines") or grid.has("z_pitch"):
		var zs: Array = grid.get("z_lines", [])
		if grid.has("z_pitch"):
			zs = []
			var z: float = grid["z_origin"]
			while z > rect.position.y:
				z -= grid["z_pitch"]
			while z < rect.end.y:
				zs.append(z)
				z += grid["z_pitch"]
		var k := 0
		for entry in zs:
			var e: Dictionary = entry if entry is Dictionary else {"z": float(entry)}
			var z: float = e["z"]
			if z <= rect.position.y + MIN_LINE_GAP or z >= rect.end.y - MIN_LINE_GAP:
				continue
			streets_list.append({"id": e.get("id", "%s_st_%d" % [r["id"], k]), "z": z, "width": e.get("width", 12),
				"name": e.get("name", "%s %d" % [_street_suffix(r), k + 1]), "speed": e.get("speed", 1000),
				"style": e.get("style", 1)})
			k += 1
	var d: Dictionary = def.get("defaults", {}).duplicate()
	d.merge({
		"id": r["id"], "display_name": r.get("name", r["id"]), "seed": hash([seed_value, r["id"]]),
		"bounds": r["rect"], "avenues": avenues, "streets": streets_list, "style": r.get("style", "tenement"),
		"boundary_streets": r.get("boundary_streets", {}), "extra_kinds": r.get("extra_kinds", []),
		"landmarks": r.get("landmarks", []),
	}, true)
	return d


func _street_suffix(r: Dictionary) -> String:
	return "%s St" % String(r.get("name", r["id"])).get_slice(" ", 0)


func _filter_lines(lines: Array, key: String, lo: float, hi: float) -> Array:
	var out: Array = []
	for l in lines:
		var v: float = l[key]
		if v > lo + MIN_LINE_GAP and v < hi - MIN_LINE_GAP:
			out.append(l.duplicate())
	return out


# --- Graph helpers -------------------------------------------------------------------
static func _key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 100.0), roundi(p.y * 100.0))


func node(p: Vector2) -> int:
	return _node(p)


func edge(a: int, b: int, street: String, width: float, speed := 1000) -> void:
	_edge(a, b, street, width, speed)


## `no_crossing`: (start, end) = 1 where the road does not meet a junction
## (dead ends, link roads), so no crosswalk or stop line is painted there.
func add_segment(street: String, from: Vector2, to: Vector2, width: float, style: int,
		no_crossing := Vector2.ZERO) -> void:
	var first := road_segments.size()
	_add_segment(street, from, to, width, style)
	if no_crossing != Vector2.ZERO:
		for i in range(first, road_segments.size()):
			road_segments[i]["no_crossing"] = no_crossing


func _node(p: Vector2) -> int:
	var k := _key(p)
	if _node_index.has(k):
		return _node_index[k]
	graph_nodes.append(p)
	_node_index[k] = graph_nodes.size() - 1
	return graph_nodes.size() - 1


func _edge(a: int, b: int, street: String, width: float, speed := 1000) -> void:
	if a != b:
		graph_edges.append({"a": a, "b": b, "street": street, "width": width, "speed": speed})


## Road surface pieces: long roads are split for chunk culling while keeping
## the segment's markings continuous (along0/total).
func _add_segment(street: String, from: Vector2, to: Vector2, width: float, style: int) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var pieces := maxi(1, ceili(length / SEGMENT_PIECE))
	for i in pieces:
		var a := from.lerp(to, float(i) / pieces)
		var b := from.lerp(to, float(i + 1) / pieces)
		road_segments.append({"street": street, "from": a, "to": b, "width": width, "style": style,
			"along0": length * i / pieces, "total": length, "dir": (to - from) / length, "origin": from})


# --- Arterials -----------------------------------------------------------------------
func _stitch_arterials(arterials: Array) -> void:
	for a in arterials:
		var horizontal: bool = a["axis"] == "x"
		var at: float = a["at"]
		var half: float = a["width"] * 0.5
		var stops := {float(a["from"]): true, float(a["to"]): true}
		var crossings := {}
		for o in arterials:
			if o["axis"] == a["axis"]:
				continue
			var oc: float = o["at"]
			if oc >= a["from"] - 0.01 and oc <= a["to"] + 0.01 and at >= o["from"] - 0.01 and at <= o["to"] + 0.01:
				stops[oc] = true
				crossings[oc] = o["width"]
		# Region roads that end on this arterial's kerb line get connectors.
		var connectors := []
		for i in graph_nodes.size():
			var p: Vector2 = graph_nodes[i]
			var across := p.y - at if horizontal else p.x - at
			var along := p.x if horizontal else p.y
			if absf(absf(across) - half) < 0.75 and along > a["from"] - 0.01 and along < a["to"] + 0.01:
				connectors.append([i, along])
				stops[along] = true
		var positions := stops.keys()
		positions.sort()
		var chain: Array = []
		for s in positions:
			chain.append(_node(Vector2(s, at) if horizontal else Vector2(at, s)))
		for k in chain.size() - 1:
			_edge(chain[k], chain[k + 1], a["id"], a["width"], int(a.get("speed", 1000)))
		for c in connectors:
			var target := _node(Vector2(c[1], at) if horizontal else Vector2(at, c[1]))
			_edge(c[0], target, a["id"], a["width"], int(a.get("speed", 1000)))
		# Surface: segments between arterial crossings (intersection boxes).
		var cuts := crossings.keys()
		cuts.sort()
		var start: float = a["from"]
		for cx in cuts:
			var hw: float = crossings[cx] * 0.5
			_arterial_piece(a, start, cx - hw)
			var c := Vector2(cx, at) if horizontal else Vector2(at, cx)
			var size := Vector2(crossings[cx], a["width"]) if horizontal else Vector2(a["width"], crossings[cx])
			intersections.append({"rect": Rect2(c - size * 0.5, size), "center": c})
			start = cx + hw
		_arterial_piece(a, start, a["to"])


func _arterial_piece(a: Dictionary, s0: float, s1: float) -> void:
	if s1 - s0 < 0.5:
		return
	var at: float = a["at"]
	var from := Vector2(s0, at) if a["axis"] == "x" else Vector2(at, s0)
	var to := Vector2(s1, at) if a["axis"] == "x" else Vector2(at, s1)
	_add_segment(a["id"], from, to, a["width"], 2)


# --- Waterfront ----------------------------------------------------------------------
func _add_piers(r: Dictionary) -> void:
	var pd: Dictionary = r["piers"]
	var region: Dictionary = regions.filter(func(x): return x["id"] == r["id"])[0]
	var dl: DistrictLayout = region["layout"]
	var rect: Rect2 = region["rect"]
	var side: String = pd["side"]
	var length: float = pd["length"]
	var width: float = pd["width"]
	var skip: Array = pd.get("skip", [])
	var lines: Array = []
	if side == "south":
		for av in dl.avenues:
			lines.append(av["x"])
	else:
		for st in dl.streets:
			lines.append(st["z"])
	for line in lines:
		if skip.any(func(s): return absf(s - line) < 1.0):
			continue
		var shore: Vector2
		var out: Vector2
		var lateral: Vector2
		match side:
			"west":
				shore = Vector2(rect.position.x, line)
				out = Vector2(-1, 0)
				lateral = Vector2(0, 1)
			"east":
				shore = Vector2(rect.end.x, line)
				out = Vector2(1, 0)
				lateral = Vector2(0, -1)
			_:
				shore = Vector2(line, rect.end.y)
				out = Vector2(0, 1)
				lateral = Vector2(1, 0)
		var tip := shore + out * length
		# Pier road along the street line; the deck extends to one side for the shed.
		_edge(_node(shore), _node(tip), "%s_pier_%d" % [r["id"], roundi(line)], 12, 1000)
		streets["%s_pier_%d" % [r["id"], roundi(line)]] = {"name": "Pier %d" % (piers.size() + 1), "width": 12}
		_add_segment("%s_pier_%d" % [r["id"], roundi(line)], shore, tip, 12, 0)
		var c0 := shore + lateral * -8.0
		var c1 := tip + lateral * (width - 8.0)
		var deck := Rect2(Vector2(minf(c0.x, c1.x), minf(c0.y, c1.y)), Vector2(absf(c1.x - c0.x), absf(c1.y - c0.y)))
		# Shed: front faces the shore, depth runs out over the water.
		var shed_def: Dictionary = _catalog.get("pier_shed_a", {"width": 26.0, "depth": 150.0})
		var shed_depth := minf(float(shed_def["depth"]), length - 30.0)
		var front := shore + out * 20.0 + lateral * (8.0 + float(shed_def["width"]) * 0.5)
		var z_axis := Vector3(-out.x, 0, -out.y)
		var x_axis := Vector3.UP.cross(z_axis)
		var t := Transform3D(Basis(x_axis, Vector3.UP, z_axis * (shed_depth / float(shed_def["depth"]))), Vector3(front.x, 0.0, front.y))
		piers.append({"deck": deck, "shed": t, "out": out})


func _add_bridge(b: Dictionary) -> void:
	var from := Vector2(b["from"][0], b["from"][1])
	var to := Vector2(b["to"][0], b["to"][1])
	var a := _node(from)
	var e := _node(to)
	_edge(a, e, b["id"], b["width"], int(b.get("speed", 1600)))
	streets[b["id"]] = {"name": b["name"], "width": b["width"]}
	_add_segment(b["id"], from, to, b["width"], 2)
	bridges.append({"from": from, "to": to, "width": b["width"], "towers": b.get("towers", []), "name": b["name"],
		"leads_to": b.get("leads_to", "")})
	portals.append({"node": e, "name": b.get("leads_to", "")})


# --- Parks and backdrops --------------------------------------------------------------
func _add_park(r: Dictionary) -> void:
	var pk: Dictionary = r["park"]
	var rect := _rect(r["rect"]).grow(-sidewalk)
	var lake := _rect(pk["lake"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, r["id"], "park"])
	var paths: Array = []
	for i in int(pk.get("paths", 6)):
		var a := Vector2(rng.randf_range(rect.position.x, rect.end.x), rect.position.y if i % 2 == 0 else rect.end.y)
		var b := Vector2(rng.randf_range(rect.position.x, rect.end.x), rect.end.y if i % 2 == 0 else rect.position.y)
		if i % 3 == 2:
			a = Vector2(rect.position.x, rng.randf_range(rect.position.y, rect.end.y))
			b = Vector2(rect.end.x, rng.randf_range(rect.position.y, rect.end.y))
		paths.append([a, b])
	var region: Dictionary = regions.filter(func(x): return x["id"] == r["id"])[0]
	var dl: DistrictLayout = region["layout"]
	var trees: Array = []
	var cell := 11.0
	var x := rect.position.x + cell * 0.5
	while x < rect.end.x:
		var z := rect.position.y + cell * 0.5
		while z < rect.end.y:
			var p := Vector2(x + rng.randf_range(-4, 4), z + rng.randf_range(-4, 4))
			var meadow := sin(p.x * 0.011 + 1.3) * cos(p.y * 0.017) > 0.25
			var ok := not meadow and not lake.grow(6.0).has_point(p) and rng.randf() < 0.7
			if ok:
				for st in dl.streets:
					if absf(p.y - float(st["z"])) < float(st["width"]) * 0.5 + 5.0:
						ok = false
			if ok:
				for path in paths:
					if _dist_to_segment(p, path[0], path[1]) < 4.0:
						ok = false
						break
			if ok:
				trees.append(p)
			z += cell
		x += cell
	parks.append({"rect": rect, "lake": lake, "paths": paths, "trees": trees, "name": r.get("name", "")})


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _add_backdrop(bd: Dictionary) -> void:
	var rect := _rect(bd["rect"])
	var hr: Array = bd.get("height", [10, 30])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, bd["id"]])
	var boxes: Array = []
	var bx := 70.0
	var bz := 60.0
	var x := rect.position.x
	while x < rect.end.x - 20:
		var z := rect.position.y
		while z < rect.end.y - 20:
			# City blocks of a few buildings each, separated by streets.
			var n := rng.randi_range(2, 4)
			for i in n:
				var w := (bx - 14.0) / n
				var r2 := Rect2(Vector2(x + 7 + i * w, z + 7), Vector2(w - 1.0, bz - 14.0))
				boxes.append({"rect": r2, "height": rng.randf_range(hr[0], hr[1]) * (1.6 if rng.randf() < 0.08 else 1.0)})
			z += bz
		x += bx
	backdrops.append({"rect": rect, "boxes": boxes, "id": bd["id"]})


# --- Chunk index -----------------------------------------------------------------------
func chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / chunk_size), floori(p.y / chunk_size))


func chunk_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c) * chunk_size, Vector2.ONE * chunk_size)


func _chunk(c: Vector2i) -> Dictionary:
	if not _chunks.has(c):
		_chunks[c] = {"blocks": [], "lots": [], "props": [], "parking": [], "roads": [], "intersections": [],
			"trees": [], "piers": [], "backdrop": []}
	return _chunks[c]


func index_chunks() -> void:
	_index_chunks()


func _index_chunks() -> void:
	for bi in blocks.size():
		_chunk(chunk_of(block_center(blocks[bi])))["blocks"].append(bi)
	for li in lots.size():
		var lot: Dictionary = lots[li]
		if lot["landmark"] != "":
			continue
		_chunk(chunk_of(blocks[lot["block"]]["rect"].get_center()))["lots"].append(li)
	for p in props:
		_chunk(chunk_of(blocks[p["block"]]["rect"].get_center()))["props"].append(p)
	for s in parking:
		var t: Transform3D = s["transform"]
		_chunk(chunk_of(Vector2(t.origin.x, t.origin.z)))["parking"].append(s)
	for seg in road_segments:
		_chunk(chunk_of((seg["from"] + seg["to"]) * 0.5))["roads"].append(seg)
	for inter in intersections:
		_chunk(chunk_of(inter["center"]))["intersections"].append(inter)
	for pk in parks:
		for t in pk["trees"]:
			_chunk(chunk_of(t))["trees"].append(t)
	for pk in park_areas:
		for t in pk["trees"]:
			_chunk(chunk_of(t))["trees"].append(t)
	for pr in piers:
		_chunk(chunk_of((pr["deck"] as Rect2).get_center()))["piers"].append(pr)
	for bd in backdrops:
		for box in bd["boxes"]:
			_chunk(chunk_of((box["rect"] as Rect2).get_center()))["backdrop"].append(box)
	_node_cells.clear()
	for i in graph_nodes.size():
		var c := Vector2i(((graph_nodes[i] as Vector2) / NODE_CELL).floor())
		var cell: PackedInt32Array = _node_cells.get(c, PackedInt32Array())
		cell.append(i)
		_node_cells[c] = cell  # packed arrays are values: write back


const NODE_CELL := 128.0
var _node_cells: Dictionary = {}


## Road nodes within `radius` metres of `p` (spatial index, sorted by index).
func nodes_near(p: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c0 := Vector2i(((p - Vector2(radius, radius)) / NODE_CELL).floor())
	var c1 := Vector2i(((p + Vector2(radius, radius)) / NODE_CELL).floor())
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for i in _node_cells.get(Vector2i(cx, cz), PackedInt32Array()):
				if (graph_nodes[i] as Vector2).distance_to(p) <= radius:
					out.append(i)
	out.sort()
	return out


## World-space corners of a block (generated blocks are rotated rectangles).
static func block_corners(b: Dictionary) -> PackedVector2Array:
	var r: Rect2 = b["rect"]
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	if b.has("xform"):
		var x: Transform2D = b["xform"]
		for i in 4:
			pts[i] = x * pts[i]
	return pts


static func block_center(b: Dictionary) -> Vector2:
	var c: Vector2 = (b["rect"] as Rect2).get_center()
	return (b["xform"] as Transform2D) * c if b.has("xform") else c


func chunk_keys() -> Array:
	var k := _chunks.keys()
	k.sort()
	return k


func chunk(c: Vector2i) -> Dictionary:
	return _chunks.get(c, {})


# --- Queries used by gameplay and presentation ------------------------------------------
func street_name(street_id: String) -> String:
	return streets.get(street_id, {}).get("name", "")


func street_widths() -> Dictionary:
	var out := {}
	for k in streets:
		out[k] = streets[k]["width"]
	return out


## District (geography worlds) or region (legacy province) under a point.
func district_name_at(p: Vector2) -> String:
	if is_geo:
		var di := geo.district_at(p)
		return districts[di]["name"] if di >= 0 else ""
	return region_at(p).get("name", "")


func region_at(p: Vector2) -> Dictionary:
	for r in regions:
		if (r["rect"] as Rect2).has_point(p):
			return r
	return {}


## Number of road edges meeting at each node (signals go where >= 3 meet).
func node_degrees() -> PackedInt32Array:
	var deg := PackedInt32Array()
	deg.resize(graph_nodes.size())
	for e in graph_edges:
		deg[e["a"]] += 1
		deg[e["b"]] += 1
	return deg
