class_name ConformingMesh
extends RefCounted
## Partition first, clip against canonical vector boundaries, then triangulate.
## A grid controls interior density, never shoreline shape. Closed holes cause
## recursive subdivision, not triangulation of the hole as a filled surface.
## Every LOD keeps the same 4m tile-edge knots and analytic normals.
const TILE := 128.0
const EDGE_KNOT := 4.0
const EPS := 0.002
var g: ProofGeography
var layer: String
var step: int
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var tangents := PackedFloat32Array()
var indices := PackedInt32Array()
var _cache := {}
var origin: Vector2
var tile: Rect2
var area := 0.0
var errors: Array = []

static func build(geo: ProofGeography, kind: String, tile_rect: Rect2, spacing: int) -> Dictionary:
	var c := ConformingMesh.new()
	c.g=geo;c.layer=kind;c.step=spacing;c.tile=tile_rect;c.origin=tile_rect.position
	var z := tile_rect.position.y
	while z<tile_rect.end.y-EPS:
		var x := tile_rect.position.x
		while x<tile_rect.end.x-EPS:
			c._cell(Rect2(x,z,minf(spacing,tile_rect.end.x-x),minf(spacing,tile_rect.end.y-z)),0)
			x+=spacing
		z+=spacing
	if c.vertices.is_empty():
		return {"arrays":[],"area":0.0,"errors":c.errors,"triangles":0}
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX]=c.vertices;a[Mesh.ARRAY_NORMAL]=c.normals
	a[Mesh.ARRAY_COLOR]=c.colors;a[Mesh.ARRAY_TEX_UV]=c.uvs
	a[Mesh.ARRAY_TANGENT]=c.tangents;a[Mesh.ARRAY_INDEX]=c.indices
	return {"arrays":a,"area":c.area,"errors":c.errors,"triangles":c.indices.size()/3}

static func rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)])

func _land_parts(cell: PackedVector2Array) -> Array:
	var parts: Array=Geometry2D.intersect_polygons(cell,g.land)
	for water in g.waters:
		if not (water["bounds"] as Rect2).intersects(ProofGeography.poly_bounds(cell),true):
			continue
		var remaining := []
		for part in parts:
			remaining.append_array(Geometry2D.clip_polygons(part,water["polygon"]))
		parts=remaining
	return parts

func _union(parts: Array) -> Array:
	var out := []
	for part in parts:
		var p: PackedVector2Array=part
		var i := 0
		while i<out.size():
			var merged := Geometry2D.merge_polygons(p,out[i])
			if merged.size()==1:
				p=merged[0];out.remove_at(i);i=0
			else:
				i+=1
		out.append(p)
	return out

func _band_parts(parts: Array, bands: Array, rect: Rect2) -> Array:
	var clipped := []
	for b in bands:
		if not (b["bounds"] as Rect2).intersects(rect,true):
			continue
		for p in parts:
			clipped.append_array(Geometry2D.intersect_polygons(p,b["polygon"]))
	return _union(clipped)

func _cell(rect: Rect2, depth: int) -> void:
	var cell := rect_poly(rect)
	var parts := []
	if layer=="water":
		for water in g.waters:
			if (water["bounds"] as Rect2).intersects(rect,true):
				parts.append_array(Geometry2D.intersect_polygons(cell,water["polygon"]))
	else:
		parts=_land_parts(cell)
		if layer=="road":
			parts=_band_parts(parts,g.road_bands,rect)
		elif layer=="pavement":
			parts=_band_parts(parts,g.pavement_bands,rect)
			for band in g.road_bands:
				if not (band["bounds"] as Rect2).intersects(rect,true):continue
				var cut := []
				for p in parts:cut.append_array(Geometry2D.clip_polygons(p,band["polygon"]))
				parts=cut
	# Geometry2D's boolean contract winds inner rings clockwise. Never fill
	# such a loop as land. Subdivision opens that hole into simple polygons.
	for p in parts:
		if Geometry2D.is_polygon_clockwise(p):
			if depth>=12:
				errors.append("unresolved hole at "+str(rect));return
			var h := rect.size*.5
			for offset in [Vector2.ZERO,Vector2(h.x,0),h,Vector2(0,h.y)]:
				_cell(Rect2(rect.position+offset,h),depth+1)
			return
	for part in parts:
		_emit(_boundary_knots(part))

func _boundary_knots(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i+1)%poly.size()]
		out.append(a)
		var vertical := absf(a.x-b.x)<EPS and (absf(a.x-tile.position.x)<EPS or absf(a.x-tile.end.x)<EPS)
		var horizontal := absf(a.y-b.y)<EPS and (absf(a.y-tile.position.y)<EPS or absf(a.y-tile.end.y)<EPS)
		if not vertical and not horizontal:continue
		var a0 := a.y if vertical else a.x
		var b0 := b.y if vertical else b.x
		var values := []
		var k := ceilf(minf(a0,b0)/EDGE_KNOT)*EDGE_KNOT
		while k<maxf(a0,b0)-EPS:
			if k>minf(a0,b0)+EPS:values.append(k)
			k+=EDGE_KNOT
		if b0<a0:values.reverse()
		for v in values:out.append(a.lerp(b,(float(v)-a0)/(b0-a0)))
	return out

func _vertex(p: Vector2) -> int:
	var key := Vector2i(roundi(p.x*1000),roundi(p.y*1000))
	if _cache.has(key):return _cache[key]
	var h := g.height_at(p)
	var n := g.normal_at(p)
	var weight := g.ground_weights(p)
	if layer=="water":
		h=float(g.source["water_level"])+.003;n=Vector3.UP
		weight=Color(clampf(absf(g.water_distance(p))/16.0,0,1),0,0,1)
	elif layer=="road":
		h=.018;n=Vector3.UP
	elif layer=="pavement":
		h=.15;n=Vector3.UP
	var index := vertices.size()
	_cache[key]=index
	vertices.append(Vector3(p.x-origin.x,h,p.y-origin.y));normals.append(n);colors.append(weight)
	uvs.append((p+g.origin)/5.0)
	var tangent := Vector3(n.y,-n.x,0).normalized()
	tangents.append_array([tangent.x,tangent.y,tangent.z,1.0])
	return index

func _emit(poly: PackedVector2Array) -> void:
	if poly.size()<3:return
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		if absf(signed_area(poly))>.001:errors.append("triangulation failed: "+str(poly))
		return
	for i in range(0,tri.size(),3):
		var a := poly[tri[i]]
		var b := poly[tri[i+1]]
		var c := poly[tri[i+2]]
		var cross := (b-a).cross(c-a)
		if absf(cross)<.000001:continue
		area+=absf(cross)*.5
		var ia := _vertex(a)
		var ib := _vertex(b)
		var ic := _vertex(c)
		indices.append_array([ia,ib,ic] if cross>0.0 else [ia,ic,ib])

static func signed_area(p: PackedVector2Array) -> float:
	var value := 0.0
	for i in p.size():
		value+=p[i].cross(p[(i+1)%p.size()])
	return value*.5
