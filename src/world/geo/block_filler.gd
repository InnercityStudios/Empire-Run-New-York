class_name BlockFiller
extends RefCounted
## On-demand contents of a generated city block: building lots, street
## furniture and kerbside parking, deterministic from the block's seed.
##
## Generated districts never store lots in the layout (the province would
## hold ~120 k buildings). Detail and mid-distance chunks call `fill()` on
## worker threads for just the blocks they draw; everything it reads (block,
## kit, catalogue) is immutable after the layout is built.
##
## Blocks are rectangles in their district's grid frame: `rect` is local,
## `xform` maps local to world (rotation + origin). Same face conventions as
## DistrictLayout: north/south are primary faces, `out` points to the street.

const CORNER_WIDTH := 12.0
const FACES := ["north", "south", "east", "west"]


## Per-style building kit (built once on the main thread, then read-only).
static func make_kit(fill: Dictionary, catalog: Dictionary) -> Dictionary:
	var ids: Array = []
	var kinds: Array = fill.get("kinds", [])
	for b in catalog.values():
		if b.get("kind") in kinds:
			ids.append(b["id"])
	ids.sort()
	var corners_l: Array = []
	var corners_r: Array = []
	for b in catalog.values():
		if b.get("kind") == "corner_left":
			corners_l.append(b["id"])
		elif b.get("kind") == "corner_right":
			corners_r.append(b["id"])
	corners_l.sort()
	corners_r.sort()
	var towers: Array = []
	for b in catalog.values():
		if b.get("kind") in fill.get("tower_kinds", []):
			towers.append(b["id"])
	towers.sort()
	var dims := {}
	for id in ids + corners_l + corners_r + towers:
		var d: Dictionary = catalog[id]
		dims[id] = Vector3(float(d["width"]), float(d.get("height", 15.0)), float(d.get("depth", 20.0)))
	var mean_h := 0.0
	for id in ids:
		mean_h += (dims[id] as Vector3).y
	mean_h = mean_h / ids.size() if not ids.is_empty() else 0.0
	var facade := Color(0, 0, 0, 0)
	for id in ids:
		facade += Color.html(catalog[id].get("facade", "#7a5a48"))
	facade = facade / ids.size() if not ids.is_empty() else Color("#7a5a48")
	facade.a = 0.5
	return {"ids": ids, "corner_left": corners_l, "corner_right": corners_r, "towers": towers, "dims": dims, "fill": fill,
		"mean_height": mean_h, "facade": facade}


## {lots: [{id, building, transform}], props: [{prop, transform}], parking: [{transform}]}
static func fill(block: Dictionary, sidewalk: float, curb_h: float, with_props := true) -> Dictionary:
	if block.has("polygon"):
		return PolygonBlockFiller.fill(block, sidewalk, curb_h, with_props)
	var out := {"lots": [], "props": [], "parking": []}
	var kit: Dictionary = block["kit"]
	var rules: Dictionary = kit["fill"]
	var ids: Array = kit["ids"]
	var inner: Rect2 = (block["rect"] as Rect2).grow(-sidewalk)
	if ids.is_empty() or inner.size.x < 12.0 or inner.size.y < 12.0:
		if with_props:
			_props(block, out, sidewalk, curb_h, rules)
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = int(block["seed"])
	var counter := [0]
	var gap: Array = rules.get("gap", [0, 0])
	var spaced := float(gap[1]) > 0.0
	var corners: bool = rules.get("corners", false)
	var primary_only: bool = rules.get("primary_only", false)
	var setback := float(rules.get("setback", 0.0))
	# Office districts: one tower through the block, fronting the south street.
	var tower_gap := []  # [face, u0, u1] frontage taken by the tower
	var towers: Array = kit.get("towers", [])
	if not towers.is_empty() and rng.randf() < float(rules.get("tower_chance", 0.0)):
		var fits: Array = towers.filter(func(id): return (kit["dims"][id] as Vector3).z <= inner.size.y - 2.0 \
			and (kit["dims"][id] as Vector3).x <= inner.size.x - CORNER_WIDTH * 2.0 - 4.0)
		if not fits.is_empty():
			var pick: String = fits[rng.randi() % fits.size()]
			var tw: float = (kit["dims"][pick] as Vector3).x
			var south := _frame(inner, "south")
			var lo := CORNER_WIDTH + tw * 0.5 + 2.0
			var hi: float = float(south["length"]) - lo
			var u := rng.randf_range(lo, maxf(lo, hi))
			_lot(block, out, counter, pick, south, u, 1.0, 0.0, curb_h)
			tower_gap = [["south", u - tw * 0.5 - 1.0, u + tw * 0.5 + 1.0],
				["north", float(south["length"]) - u - tw * 0.5 - 1.0, float(south["length"]) - u + tw * 0.5 + 1.0]]
	# Frontage depth of the primary faces decides where side-street runs start.
	var side_inset := 0.0
	for face in FACES:
		var frame := _frame(inner, face)
		var primary: bool = face == "north" or face == "south"
		var cross: float = inner.size.y if primary else inner.size.x
		var max_depth := cross * 0.5 - setback - 0.5
		var cands: Array = ids.filter(func(id): return (kit["dims"][id] as Vector3).z <= max_depth)
		if cands.is_empty():
			continue
		if primary:
			for id in cands:
				side_inset = maxf(side_inset, (kit["dims"][id] as Vector3).z + setback)
		var length: float = frame["length"]
		var u0 := 0.0
		var u1 := length
		if primary and corners and length > CORNER_WIDTH * 3.0:
			var cl: Array = kit["corner_left"]
			var cr: Array = kit["corner_right"]
			if not cl.is_empty() and not cr.is_empty():
				_lot(block, out, counter, cl[rng.randi() % cl.size()], frame, CORNER_WIDTH * 0.5, 1.0, 0.0, curb_h)
				_lot(block, out, counter, cr[rng.randi() % cr.size()], frame, length - CORNER_WIDTH * 0.5, 1.0, 0.0, curb_h)
				u0 = CORNER_WIDTH
				u1 = length - CORNER_WIDTH
		elif not primary:
			if primary_only:
				continue
			u0 = minf(side_inset, length * 0.5)
			u1 = length - u0
		var runs := [[u0, u1]]
		for g in tower_gap:
			if g[0] == face:
				runs = _subtract(runs, g[1], g[2])
		for run in runs:
			if float(run[1]) - float(run[0]) < 6.0:
				continue
			if spaced:
				_fill_spaced(block, out, counter, kit, cands, frame, run[0], run[1], rng, gap, setback, curb_h)
			else:
				_fill_packed(block, out, counter, kit, cands, frame, run[0], run[1], rng, setback, curb_h)
	if with_props:
		_props(block, out, sidewalk, curb_h, rules)
	return out


static func _subtract(runs: Array, a: float, b: float) -> Array:
	var out := []
	for r in runs:
		if b <= r[0] or a >= r[1]:
			out.append(r)
			continue
		if a > r[0]:
			out.append([r[0], a])
		if b < r[1]:
			out.append([b, r[1]])
	return out


static func _frame(b: Rect2, face: String) -> Dictionary:
	match face:
		"south":
			return {"origin": Vector2(b.position.x, b.end.y), "right": Vector2(1, 0), "out": Vector2(0, 1), "length": b.size.x}
		"north":
			return {"origin": Vector2(b.end.x, b.position.y), "right": Vector2(-1, 0), "out": Vector2(0, -1), "length": b.size.x}
		"east":
			return {"origin": Vector2(b.end.x, b.end.y), "right": Vector2(0, -1), "out": Vector2(1, 0), "length": b.size.y}
		_:
			return {"origin": Vector2(b.position.x, b.position.y), "right": Vector2(0, 1), "out": Vector2(-1, 0), "length": b.size.y}


static func _xf(block: Dictionary, frame: Dictionary, u: float, scale_x: float, inset: float, y: float) -> Transform3D:
	var xform: Transform2D = block["xform"]
	var r: Vector2 = frame["right"]
	var o: Vector2 = frame["out"]
	var p: Vector2 = xform * ((frame["origin"] as Vector2) + r * u - o * inset)
	var rw := xform.basis_xform(r)
	var ow := xform.basis_xform(o)
	return Transform3D(Basis(Vector3(rw.x, 0, rw.y) * scale_x, Vector3.UP, Vector3(ow.x, 0, ow.y)), Vector3(p.x, y, p.y))


static func _lot(block: Dictionary, out: Dictionary, counter: Array, building: String, frame: Dictionary, u: float,
		scale_x: float, setback: float, curb_h: float) -> void:
	var t := _xf(block, frame, u, scale_x, setback, curb_h)
	if block.has("exclude"):
		# Keep landmark parcels free: test the footprint centre and front corners.
		var depth: float = (block["kit"]["dims"][building] as Vector3).z if block["kit"]["dims"].has(building) else 20.0
		var half_w := (block["kit"]["dims"][building] as Vector3).x * scale_x * 0.5 if block["kit"]["dims"].has(building) else 5.0
		var fwd := Vector2(t.basis.z.x, t.basis.z.z).normalized()
		var right := Vector2(t.basis.x.x, t.basis.x.z).normalized()
		var o := Vector2(t.origin.x, t.origin.z)
		for poly in block["exclude"]:
			for p in [o - fwd * depth * 0.5, o - fwd * 1.0 + right * (half_w - 1.0), o - fwd * 1.0 - right * (half_w - 1.0),
					o - fwd * (depth - 1.0)]:
				if Geometry2D.is_point_in_polygon(p, poly):
					counter[0] += 1  # keep later lot ids stable
					return
	out["lots"].append({"id": "%s:%d:%d" % [block["district"], block["index"], counter[0]], "building": building,
		"transform": t})
	counter[0] += 1


static func _fill_packed(block: Dictionary, out: Dictionary, counter: Array, kit: Dictionary, cands: Array,
		frame: Dictionary, u0: float, u1: float, rng: RandomNumberGenerator, setback: float, curb_h: float) -> void:
	var length := u1 - u0
	var chosen: Array = []
	var total := 0.0
	var last := ""
	for guard in 64:
		var fits: Array = cands.filter(func(i): return i != last and total + (kit["dims"][i] as Vector3).x <= length + 0.01)
		if fits.is_empty():
			break
		var pick: String = fits[rng.randi() % fits.size()]
		chosen.append(pick)
		total += (kit["dims"][pick] as Vector3).x
		last = pick
	if chosen.is_empty():
		return
	# Low buildings stretch to close the frontage; tall ones keep their
	# proportions (stretched towers read as repeated slabs).
	var tall := false
	for pick in chosen:
		tall = tall or (kit["dims"][pick] as Vector3).y > 30.0
	var s := minf(length / total, 1.08) if tall else length / total
	var u := u0 + (length - total * s) * 0.5
	for pick in chosen:
		var w: float = (kit["dims"][pick] as Vector3).x * s
		_lot(block, out, counter, pick, frame, u + w * 0.5, s, setback, curb_h)
		u += w


static func _fill_spaced(block: Dictionary, out: Dictionary, counter: Array, kit: Dictionary, cands: Array,
		frame: Dictionary, u0: float, u1: float, rng: RandomNumberGenerator, gap: Array, setback: float,
		curb_h: float) -> void:
	var u := u0 + rng.randf_range(float(gap[0]), float(gap[1])) * 0.5
	var last := ""
	for guard in 64:
		var fits: Array = cands.filter(func(i): return i != last and u + (kit["dims"][i] as Vector3).x <= u1)
		if fits.is_empty():
			break
		var pick: String = fits[rng.randi() % fits.size()]
		var w: float = (kit["dims"][pick] as Vector3).x
		_lot(block, out, counter, pick, frame, u + w * 0.5, 1.0, setback, curb_h)
		u += w + rng.randf_range(float(gap[0]), float(gap[1]))
		last = pick


## Street lamps, trees, hydrants and kerbside parking along every face.
static func _props(block: Dictionary, out: Dictionary, sidewalk: float, curb_h: float, rules: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(block["seed"]) ^ 0x5bd1e995
	var rect: Rect2 = (block["rect"] as Rect2).grow(-sidewalk)
	var tree_chance := float(rules.get("trees", 0.5))
	for face in FACES:
		var frame := _frame(rect, face)
		var length: float = frame["length"]
		var used: Array = []
		var lamp_u := 7.0
		while lamp_u < length - 4.0:
			out["props"].append({"prop": "street_lamp", "transform": _xf(block, frame, lamp_u, 1.0, -(sidewalk - 0.55), curb_h)})
			used.append(lamp_u)
			lamp_u += 26.0
		var tree_u := 5.0 + rng.randf() * 4.0
		while tree_u < length - 5.0:
			if not used.any(func(x): return absf(x - tree_u) < 3.5) and rng.randf() < tree_chance:
				var t := _xf(block, frame, tree_u, 1.0, -(sidewalk - 1.1), curb_h)
				t.basis = t.basis.rotated(Vector3.UP, rng.randf() * TAU)
				out["props"].append({"prop": "tree_a" if rng.randf() < 0.5 else "tree_b", "transform": t})
				used.append(tree_u)
			tree_u += 9.0 + rng.randf() * 4.0
		if rng.randf() < 0.5:
			out["props"].append({"prop": "fire_hydrant", "transform": _xf(block, frame, 6.0, 1.0, -(sidewalk - 0.5), curb_h)})
		# Kerbside parking: vehicles face along the street (-Z forward).
		var pu := 9.0
		while pu < length - 9.0:
			if rng.randf() < 0.36:
				var xform: Transform2D = block["xform"]
				var r: Vector2 = xform.basis_xform(frame["right"])
				var p: Vector2 = xform * ((frame["origin"] as Vector2) + (frame["right"] as Vector2) * pu
					+ (frame["out"] as Vector2) * (sidewalk + 1.2))
				var fwd := -Vector3(r.x, 0, r.y)
				out["parking"].append({"transform": Transform3D(Basis(fwd.cross(Vector3.UP), Vector3.UP, -fwd), Vector3(p.x, 0.0, p.y))})
			pu += 6.4 + rng.randf() * 1.5
