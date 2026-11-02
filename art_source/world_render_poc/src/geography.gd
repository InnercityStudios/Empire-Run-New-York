class_name ProofGeography
extends RefCounted
## Runtime geometry contract: explicit metre coordinates and stable IDs.
## This class never loads a bitmap, the province generator or game state.
const EPSILON := 0.001
var source: Dictionary
var origin: Vector2
var bounds: Rect2
var land: PackedVector2Array
var waters: Array = []
var roads: Array = []
var road_bands: Array = []
var pavement_bands: Array = []
var parks: Array = []
var errors: Array = []

static func polygon(points: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for xy in points:
		p.append(Vector2(float(xy[0]),float(xy[1])))
	if Geometry2D.is_polygon_clockwise(p):
		p.reverse()
	return p

static func load_region(data: Dictionary) -> ProofGeography:
	var g := ProofGeography.new()
	g.source = data
	g.origin = Vector2(data["origin"][0],data["origin"][1])
	var b: Array = data["bounds"]
	g.bounds = Rect2(b[0],b[1],b[2]-b[0],b[3]-b[1])
	g.land = polygon(data["land"])
	for w in data["waters"]:
		var p := polygon(w["polygon"])
		g.waters.append({"id":w["id"],"polygon":p,"bounds":poly_bounds(p)})
	for p in data.get("parks",[]):
		g.parks.append(polygon(p))
	for road in data["roads"]:
		var path := PackedVector2Array()
		for xy in road["path"]:
			path.append(Vector2(xy[0],xy[1]))
		var from: Array = data["nodes"][road["from"]]
		var to: Array = data["nodes"][road["to"]]
		if path[0].distance_to(Vector2(from[0],from[1]))>EPSILON or path[-1].distance_to(Vector2(to[0],to[1]))>EPSILON:
			g.errors.append("road endpoints disagree with nodes: "+road["id"])
		g.roads.append({"id":road["id"],"from":road["from"],"to":road["to"],"path":path,"width":float(road["width"])})
		for band in Geometry2D.offset_polyline(path,float(road["width"])*0.5,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND):
			g.road_bands.append({"polygon":band,"bounds":poly_bounds(band)})
		if data["shore_kind"]=="bulkhead":
			for band in Geometry2D.offset_polyline(path,float(road["width"])*0.5+3.4,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND):
				g.pavement_bands.append({"polygon":band,"bounds":poly_bounds(band)})
	return g

static func poly_bounds(p: PackedVector2Array) -> Rect2:
	var b := Rect2(p[0],Vector2.ZERO)
	for v in p:
		b=b.expand(v)
	return b

static func edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var d := INF
	for i in poly.size():
		d=minf(d,p.distance_to(Geometry2D.get_closest_point_to_segment(p,poly[i],poly[(i+1)%poly.size()])))
	return d

func water_distance(p: Vector2) -> float:
	var d := 10000.0
	for w in waters:
		if not (w["bounds"] as Rect2).grow(30.0).has_point(p):
			continue
		var v := edge_distance(p,w["polygon"])
		if Geometry2D.is_point_in_polygon(p,w["polygon"]):
			return -v
		d=minf(d,v)
	return d

func road_distance(p: Vector2) -> float:
	var d := INF
	for r in roads:
		var path: PackedVector2Array=r["path"]
		for i in path.size()-1:
			d=minf(d,p.distance_to(Geometry2D.get_closest_point_to_segment(p,path[i],path[i+1]))-float(r["width"])*0.5)
	return d

func height_at(p: Vector2) -> float:
	if source["shore_kind"]=="bulkhead":
		return -0.03
	var t: Dictionary=source["terrain"]
	var h := float(t["datum"])
	for hill in t["hills"]:
		var d := p.distance_to(Vector2(hill[0],hill[1]))/float(hill[3])
		h+=float(hill[2])*exp(-d*d*2.0)
	for field in t["fields"]:
		var poly := polygon(field)
		var d := edge_distance(p,poly)
		if Geometry2D.is_point_in_polygon(p,poly):
			h=float(t["field_height"])
		else:
			h=lerpf(float(t["field_height"]),h,smoothstep(0.0,55.0,d))
	var road := road_distance(p)
	h=lerpf(0.0,h,smoothstep(1.0,22.0,road))
	var bank := water_distance(p)
	if bank<30.0:
		h=lerpf(float(source["water_level"]),h,smoothstep(0.0,float(t["bank_width"]),maxf(bank,0.0)))
	return h

func normal_at(p: Vector2) -> Vector3:
	var dx := (height_at(p+Vector2(.25,0))-height_at(p-Vector2(.25,0)))*2.0
	var dz := (height_at(p+Vector2(0,.25))-height_at(p-Vector2(0,.25)))*2.0
	return Vector3(-dx,1.0,-dz).normalized()

func ground_weights(p: Vector2) -> Color:
	var shore := 1.0-smoothstep(1.0,12.0,absf(water_distance(p)))
	var verge := 1.0-smoothstep(0.0,5.0,road_distance(p))
	var grass := 1.0
	if source["shore_kind"]=="bulkhead":
		grass=0.0
		for park in parks:
			if Geometry2D.is_point_in_polygon(p,park):
				grass=smoothstep(0.0,1.5,edge_distance(p,park))
	return Color(grass,shore,verge,1.0)
