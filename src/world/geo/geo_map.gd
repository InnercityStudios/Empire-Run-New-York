class_name GeoMap
extends RefCounted
## Read-only geography queries over a `geography-v1` world definition:
## land/water, borough and district membership, parks. Pure data, safe to
## share with worker threads once built.
##
## District membership mirrors tools/geography/nyc_blueprint.py: explicit
## district polygons win; otherwise a point belongs to the nearest seed of the
## borough whose polygon contains it (island boroughs have their own district).

var coasts: Array = []        ## {id, kind, polygon: PackedVector2Array, bounds: Rect2}
var boroughs: Array = []      ## {id, borough, kind, polygon, bounds}
var districts: Array = []     ## district dictionaries from the definition
var district_index: Dictionary = {}  ## id -> index
var parks: Array = []         ## {id, name, kind, polygon, lakes: Array[PackedVector2Array], bounds}
var extent: Rect2

var _explicit: Array = []     ## [district index, polygon, bounds]
var _seeds_by_borough: Dictionary = {}  ## borough -> Array[[index, seed]]
var _island_district := {"roosevelt_island": "roosevelt", "randalls_island": "randalls"}


static func from_def(def: Dictionary) -> GeoMap:
	var g := GeoMap.new()
	g._build(def)
	return g


static func poly(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func poly_bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


func _build(def: Dictionary) -> void:
	var e: Array = def["extent"]
	extent = Rect2(Vector2(e[0], e[1]), Vector2(e[2] - e[0], e[3] - e[1]))
	for l in def["landmasses"]:
		var p := poly(l["polygon"])
		coasts.append({"id": l["id"], "kind": l["kind"], "polygon": p, "bounds": poly_bounds(p)})
	for b in def["boroughs"]:
		var p := poly(b["polygon"])
		boroughs.append({"id": b["id"], "borough": b["borough"], "kind": b["kind"], "polygon": p, "bounds": poly_bounds(p)})
	districts = def["districts"]
	for i in districts.size():
		var d: Dictionary = districts[i]
		district_index[d["id"]] = i
		if d.has("polygon"):
			var p := poly(d["polygon"])
			_explicit.append([i, p, poly_bounds(p)])
		else:
			var seeds: Array = _seeds_by_borough.get(d["borough"], [])
			seeds.append([i, Vector2(d["seed"][0], d["seed"][1])])
			_seeds_by_borough[d["borough"]] = seeds
	for pk in def.get("parks", []):
		var p := poly(pk["polygon"])
		var lakes: Array = []
		for lake in pk.get("lakes", []):
			lakes.append(poly(lake))
		parks.append({"id": pk["id"], "name": pk["name"], "kind": pk["kind"], "polygon": p, "lakes": lakes,
			"bounds": poly_bounds(p)})


func is_land(p: Vector2) -> bool:
	for c in coasts:
		if (c["bounds"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, c["polygon"]):
			return true
	return false


## Land that belongs to a playable borough (not New Jersey, Long Island...).
func borough_at(p: Vector2) -> Dictionary:
	for b in boroughs:
		if b["kind"] != "playable":
			continue
		if (b["bounds"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, b["polygon"]):
			return b
	return {}


## District index at a point, or -1 (water, scenery land).
func district_at(p: Vector2) -> int:
	for ex in _explicit:
		if (ex[2] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, ex[1]):
			return ex[0]
	var b := borough_at(p)
	if b.is_empty():
		return -1
	var island: String = _island_district.get(b["id"], "")
	if island != "":
		return district_index.get(island, -1)
	var best := -1
	var best_d := INF
	for s in _seeds_by_borough.get(b["borough"], []):
		var d: Dictionary = districts[s[0]]
		if d["id"] in _island_district.values():
			continue
		var dd := (s[1] as Vector2).distance_squared_to(p)
		if dd < best_d:
			best_d = dd
			best = s[0]
	return best


func park_at(p: Vector2) -> int:
	for i in parks.size():
		var pk: Dictionary = parks[i]
		if (pk["bounds"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, pk["polygon"]):
			return i
	return -1


func in_lake(p: Vector2, park: int) -> bool:
	for lake in parks[park]["lakes"]:
		if Geometry2D.is_point_in_polygon(p, lake):
			return true
	return false


## Approximate extent of each district, by sampling borough land on a grid.
func district_bounds(step := 80.0) -> Dictionary:
	var out := {}
	for b in boroughs:
		if b["kind"] != "playable":
			continue
		var r: Rect2 = b["bounds"]
		var y := r.position.y
		while y <= r.end.y:
			var x := r.position.x
			while x <= r.end.x:
				var p := Vector2(x, y)
				var di := district_at(p)
				if di >= 0:
					out[di] = (out[di] as Rect2).expand(p) if out.has(di) else Rect2(p, Vector2.ZERO)
				x += step
			y += step
	for di in out:
		out[di] = (out[di] as Rect2).grow(step * 1.5)
	return out
