class_name TerrainField
extends RefCounted
## One immutable world-space field shared by terrain, banks, vegetation and
## reservation validation. Never reads render-local transforms or random state.
## City elevation and road surfaces remain at their established y=0 datum.
const CELL := 256.0
const SHORE_RANGE := 192.0
const PLOT_SIZE := 140.0
const SPACING := 230.0
const EXCLUSION := 115.0

var geo: GeoMap
var water_level := -1.6
var regions: Array = []
var plots: Array = []
var report: Dictionary = {}
var _banks: Dictionary = {}
var _lakes: Array = []
var _roads: Dictionary = {}
var _plot_cells: Dictionary = {}

static func build(world: WorldLayout, def: Dictionary) -> TerrainField:
	var f := TerrainField.new()
	f.geo = world.geo
	f.water_level = world.water_level
	for c in world.geo.coasts:
		f._index_poly(c["polygon"], f._banks, SHORE_RANGE)
	for r in def.get("estate_regions", []):
		var p := GeoMap.poly(r["polygon"])
		var region: Dictionary = r.duplicate(true)
		region["polygon"] = p
		region["bounds"] = GeoMap.poly_bounds(p)
		f.regions.append(region)
		for lake in r.get("lakes", []):
			f._add_lake(GeoMap.poly(lake["polygon"]))
		for stream in r.get("streams", []):
			var path := GeoMap.poly(stream["path"])
			var bands := Geometry2D.offset_polyline(path, float(stream["width"]) * 0.5,
				Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
			for band in bands:
				f._add_lake(band)
	for e in world.graph_edges:
		var a: Vector2 = world.graph_nodes[e["a"]]
		var b: Vector2 = world.graph_nodes[e["b"]]
		f._index_segment(a, b, float(e["width"]) * 0.5, f._roads, 90.0, e["street"])
	f._reserve(def.get("landscape", {}).get("target_capacity", 2017))
	return f

func _add_lake(poly: PackedVector2Array) -> void:
	_lakes.append({"polygon":poly,"bounds":GeoMap.poly_bounds(poly)})
	_index_poly(poly, _banks, SHORE_RANGE)

func _index_poly(poly: PackedVector2Array, buckets: Dictionary, margin: float) -> void:
	for i in poly.size():
		_index_segment(poly[i], poly[(i+1)%poly.size()], 0.0, buckets, margin, "")

func _index_segment(a: Vector2, b: Vector2, width: float, buckets: Dictionary, margin: float, street: String) -> void:
	var r := Vector2(margin, margin)
	var lo := Vector2i(((a.min(b)-r)/CELL).floor())
	var hi := Vector2i(((a.max(b)+r)/CELL).floor())
	var seg := [a,b,width,street]
	for x in range(lo.x,hi.x+1):
		for z in range(lo.y,hi.y+1):
			var key := Vector2i(x,z)
			if not buckets.has(key):buckets[key]=[]
			buckets[key].append(seg)

func is_dry(p: Vector2) -> bool:
	if not geo.is_land(p):return false
	for lake in _lakes:
		if (lake["bounds"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p,lake["polygon"]):return false
	return true

func bank_distance(p: Vector2) -> float:
	var d := SHORE_RANGE
	for s in _banks.get(Vector2i((p/CELL).floor()), []):
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p,s[0],s[1])))
	return d if is_dry(p) else -d

func road_at(p: Vector2, limit := 90.0) -> Array:
	var best := [limit, p, "", 0.0]
	var key := Vector2i((p/CELL).floor())
	var radius := ceili(limit/CELL) if limit>90.0 else 0
	for dx in range(-radius,radius+1):
		for dz in range(-radius,radius+1):
			for s in _roads.get(key+Vector2i(dx,dz), []):
				var q := Geometry2D.get_closest_point_to_segment(p,s[0],s[1])
				var d := p.distance_to(q)-float(s[2])
				if d < float(best[0]):best=[d,q,s[3],s[2]]
	return best

func rural_at(p: Vector2) -> float:
	for r in regions:
		if (r["bounds"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p,r["polygon"]):
			var d := 300.0
			var poly: PackedVector2Array = r["polygon"]
			for i in poly.size():d=minf(d,p.distance_to(Geometry2D.get_closest_point_to_segment(p,poly[i],poly[(i+1)%poly.size()])))
			return smoothstep(0.0, 180.0, d)
	return 0.0 if not geo.borough_at(p).is_empty() else 1.0

func _base_height(p: Vector2, bank: float, rural: float, road_distance := INF) -> float:
	if bank < 0.0:return water_level - 0.3 - minf(-bank * 0.06, 5.0)
	# Broad low relief, only a few metres over hundreds of metres. The city
	# datum is preserved. Banks descend continuously beneath the water plane.
	var relief := 2.2 + 1.2*sin(p.x*.0021 + sin(p.y*.0013)) + 0.8*cos(p.y*.0026-p.x*.0007)
	var ground := -0.03 + rural * relief
	ground = lerpf(water_level - 0.3, ground, smoothstep(0.0, 48.0, bank))
	if is_inf(road_distance):road_distance=float(road_at(p)[0])
	ground = lerpf(-0.03,ground,smoothstep(3.0,65.0,road_distance))
	return ground

func height_at(p: Vector2) -> float:
	return _flatten_height(p,_base_height(p,bank_distance(p),rural_at(p)))

func _flatten_height(p: Vector2, base_height: float) -> float:
	var h := base_height
	# Smooth circular blending, never square terrain pads. Whole estate plus
	# exclusion disc is flat; a 65 m shoulder blends into the surrounding field.
	var key := Vector2i((p/CELL).floor())
	for dx in range(-1,2):
		for dz in range(-1,2):
			for i in _plot_cells.get(key+Vector2i(dx,dz), []):
				var plot: Dictionary = plots[i]
				var d := p.distance_to(plot["center"])
				if d < EXCLUSION+65.0:
					h = lerpf(float(plot["elevation"]), h, smoothstep(EXCLUSION,EXCLUSION+65.0,d))
	return h

func sample(p: Vector2) -> Vector4:
	var bank := bank_distance(p)
	var rural := rural_at(p)
	var road_distance := float(road_at(p)[0])
	return Vector4(_flatten_height(p,_base_height(p,bank,rural,road_distance)),bank,rural,road_distance)

func _reserve(target: int) -> void:
	var candidates := []
	# Include authored slice reservations without interpreting example owners
	# as gameplay. Revalidate each against the actual final landscape.
	for r in regions:
		for old in r.get("plots", []):
			candidates.append([Vector2(old["pos"][0],old["pos"][1]),r,old["id"]])
		var rect: Rect2 = r["bounds"]
		var row := 0
		var z := ceilf(rect.position.y / 212.0) * 212.0
		while z < rect.end.y:
			var x := floorf(rect.position.x / 245.0) * 245.0 + (122.5 if row%2 else 0.0)
			while x < rect.end.x:
				var h := absi(hash([int(x),int(z),r["id"]]))
				var p := Vector2(x+float(h%11)-5.0,z+float((h/11)%11)-5.0)
				candidates.append([p,r,"estate:%s:%d:%d"%[r["id"],roundi(x),roundi(z)]])
				x+=245.0
			z+=212.0
			row+=1
	# A second deterministic phase fills otherwise unused meadow pockets.
	# Existing accepted IDs remain stable; every new candidate undergoes the
	# identical clearance and spacing checks below.
	var second_pass := []
	for c in candidates:
		if String(c[2]).count(":")<3:continue
		second_pass.append([c[0]+Vector2(81,71),c[1],String(c[2])+":infill"])
		second_pass.append([c[0]+Vector2(-81,71),c[1],String(c[2])+":infill2"])
	candidates.append_array(second_pass)
	var rejected := {"boundary_water":0,"road":0,"spacing":0,"access":0,"slope":0}
	var tiers := {}
	for c in candidates:
		var p: Vector2 = c[0]
		var r: Dictionary = c[1]
		if not Geometry2D.is_point_in_polygon(p,r["polygon"]):continue
		var boundary := INF
		var poly: PackedVector2Array = r["polygon"]
		for i in poly.size():boundary=minf(boundary,p.distance_to(Geometry2D.get_closest_point_to_segment(p,poly[i],poly[(i+1)%poly.size()])))
		if boundary < EXCLUSION or bank_distance(p) < EXCLUSION+12.0:
			rejected["boundary_water"]+=1;continue
		# Query footprint clearance wider than the normal terrain road shoulder.
		# _roads buckets include the whole 115m exclusion margin (see build).
		var access := road_at(p,400.0)
		if float(access[0]) < EXCLUSION+10.0:
			rejected["road"]+=1;continue
		if access[2] == "" or float(access[0]) > 330.0:
			rejected["access"]+=1;continue
		var key := Vector2i((p/CELL).floor())
		var spaced := true
		for dx in range(-1,2):
			for dz in range(-1,2):
				for i in _plot_cells.get(key+Vector2i(dx,dz),[]):
					if p.distance_to(plots[i]["center"]) < SPACING:spaced=false
		if not spaced:rejected["spacing"]+=1;continue
		# Straight future driveway must stay on dry land and clear other
		# reservations. No driveway geometry or ownership is created now.
		var q: Vector2 = access[1]
		var gate := p+(q-p).normalized()*70.0
		var valid := true
		for other in plots:
			if p.distance_squared_to(other["center"])>640000.0:continue
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p,other["gate"],other["road_point"]))<EXCLUSION+3.0 \
					or other["center"].distance_to(Geometry2D.get_closest_point_to_segment(other["center"],gate,q))<EXCLUSION+3.0:
				valid=false;break
		if not valid:rejected["access"]+=1;continue
		# Analytic edge intersections catch even a narrow pond between samples.
		for lake in _lakes:
			var shore: PackedVector2Array=lake["polygon"]
			for i in shore.size():
				if Geometry2D.segment_intersects_segment(gate,q,shore[i],shore[(i+1)%shore.size()])!=null:
					valid=false;break
			if not valid:break
		for k in range(1,17):
			var v := p.lerp(q,k/16.0)
			if not is_dry(v):valid=false;break
		if not valid:rejected["access"]+=1;continue
		var elevation := _base_height(p,bank_distance(p),rural_at(p))
		var slope := 0.0
		for corner in [Vector2(-70,-70),Vector2(70,-70),Vector2(70,70),Vector2(-70,70)]:
			var v: Vector2 = p+corner
			slope=maxf(slope,absf(_base_height(v,bank_distance(v),rural_at(v))-elevation)/corner.length())
		if slope > 0.035:rejected["slope"]+=1;continue
		var dir := (q-p).normalized()
		var plot := {"id":c[2],"region":r["id"],"tier":r.get("tier","prime"),"center":p,"size":PLOT_SIZE,"yaw":atan2(dir.x,dir.y),
			"exclusion_radius":EXCLUSION,"elevation":0.12,"gate":p+dir*70.0,"road_point":q,"street":access[2]}
		if not _plot_cells.has(key):_plot_cells[key]=[]
		_plot_cells[key].append(plots.size())
		plots.append(plot)
		tiers[plot["tier"]]=tiers.get(plot["tier"],0)+1
	# Keep all spatially valid capacity; the target is a requirement, not a
	# reason to misreport or fabricate additional plots.
	report={"target":target,"validated":plots.size(),"shortfall":maxi(0,target-plots.size()),"tiers":tiers,"rejected":rejected,
		"plot_m":PLOT_SIZE,"spacing_m":SPACING,"exclusion_radius_m":EXCLUSION}
	print("TerrainField: reservations ",report)
