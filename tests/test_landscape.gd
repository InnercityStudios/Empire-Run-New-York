extends TestCase
## Regression tests use the final rendered field and final routing graph,
## rather than trusting the planning-only centre-point capacity estimates.
static var content: GameContent
static var world: WorldLayout

func before_each() -> void:
	if world==null:
		content=GameContent.load_default()
		world=WorldLayout.build(content.worlds["nyc_1977"],content)

func test_estate_capacity_and_clearance() -> void:
	var field := world.terrain
	check(field.plots.size()>=2017,"at least 2017 spatially validated plots (%d)"%field.plots.size())
	var bad_water := 0
	var bad_road := 0
	var bad_spacing := 0
	var max_height_error := 0.0
	var tiers := {}
	for plot in field.plots:
		var p: Vector2=plot["center"]
		tiers[plot["tier"]]=true
		if float(field.road_at(p,400.0)[0])<125.0:bad_road+=1
		for offset in [Vector2(-70,-70),Vector2(70,-70),Vector2(70,70),Vector2(-70,70),Vector2(115,0),Vector2(-115,0),Vector2(0,115),Vector2(0,-115)]:
			if not field.is_dry(p+offset):bad_water+=1
			max_height_error=maxf(max_height_error,absf(field.height_at(p+offset)-float(plot["elevation"])))
	for i in field.plots.size():
		for j in range(i+1,field.plots.size()):
			if field.plots[i]["center"].distance_to(field.plots[j]["center"])<230.0:bad_spacing+=1
	check_eq(bad_water,0,"entire estate/exclusion radius clear of water")
	check_eq(bad_road,0,"exclusion radius clear of public roads")
	check_eq(bad_spacing,0,"minimum centre spacing independently validated")
	check(max_height_error<.01,"flat entire footprint/exclusion disc (%f m error)"%max_height_error)
	check_eq(tiers.size(),3,"relocation capacity in all strategic tiers")

func test_adjacent_terrain_tiles_share_positions_and_normals() -> void:
	var key := Vector2i(-4,6)
	var a := TerrainMesh.arrays(world.terrain,key,16)
	var b := TerrainMesh.arrays(world.terrain,key+Vector2i.RIGHT,16)
	var n := 64
	var max_error := 0.0
	var max_normal_error := 0.0
	for z in n+1:
		var ai := z*(n+1)+n
		var bi := z*(n+1)
		var av: Vector3=a[Mesh.ARRAY_VERTEX][ai]+Vector3(key.x*1024,0,key.y*1024)
		var bv: Vector3=b[Mesh.ARRAY_VERTEX][bi]+Vector3((key.x+1)*1024,0,key.y*1024)
		max_error=maxf(max_error,av.distance_to(bv))
		max_normal_error=maxf(max_normal_error,a[Mesh.ARRAY_NORMAL][ai].distance_to(b[Mesh.ARRAY_NORMAL][bi]))
	check(max_error<.0001,"shared border vertices match")
	check(max_normal_error<.0001,"shared border normals match")
	check(a[Mesh.ARRAY_VERTEX].size()<5000,"detail tile vertex budget bounded")

func test_authored_blocks_use_road_faces_and_contained_buildings() -> void:
	var faces := 0
	var lots := 0
	var mirrored := 0
	var off_parcel := 0
	for block in world.blocks:
		if not block.has("polygon"):continue
		faces+=1
		var filled := BlockFiller.fill(block,world.sidewalk,world.curb_height,false)
		for lot in filled["lots"]:
			lots+=1
			var xf: Transform3D=lot["transform"]
			if xf.basis.determinant()<0:mirrored+=1
			var dim: Vector3=block["kit"]["dims"][lot["building"]]
			for corner in [Vector3(-dim.x*.5,0,0),Vector3(dim.x*.5,0,0),Vector3(dim.x*.5,0,-dim.z),Vector3(-dim.x*.5,0,-dim.z)]:
				var p: Vector3=xf*corner
				if not Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),block["polygon"]):off_parcel+=1
	check(faces>50,"representative city/suburbs derive bounded faces (%d)"%faces)
	check(lots>200,"street frontages receive building parcels (%d)"%lots)
	check_eq(off_parcel,0,"complete building footprints stay within parcels")
	check_eq(mirrored,0,"building transforms preserve mesh winding")

func test_planar_network_splits_crossings_t_junctions_and_duplicate_edges() -> void:
	var n := StreetNetwork.build([
		{"name":"a","width":8,"path":PackedVector2Array([Vector2(0,0),Vector2(100,0)])},
		{"name":"b","width":8,"path":PackedVector2Array([Vector2(50,-50),Vector2(50,50)])},
		{"name":"c","width":8,"path":PackedVector2Array([Vector2(25,30),Vector2(25,.8)])},
		{"name":"duplicate","width":8,"path":PackedVector2Array([Vector2(0,0),Vector2(50,0)])}])
	check_eq(n.nodes.size(),7,"crossing and snapped T are explicit shared nodes")
	check_eq(n.edges.size(),6,"duplicate collinear road is not emitted twice")
	var deg4 := 0
	var deg3 := 0
	for i in n.nodes.size():
		if n.degree(i)==4:deg4+=1
		if n.degree(i)==3:deg3+=1
	check_eq(deg4,1,"crossroads")
	check_eq(deg3,1,"T junction")

func test_roads_and_driveways_in_outer_landscape_stay_dry() -> void:
	var wet := []
	for e in world.graph_edges:
		if not String(e["street"]).begins_with("net:"):continue
		var a: Vector2=world.graph_nodes[e["a"]]
		var b: Vector2=world.graph_nodes[e["b"]]
		for k in 9:
			if not world.terrain.is_dry(a.lerp(b,k/8.0)):
				wet.append(e["street"]);break
	check(wet.is_empty(),"authored non-bridge roads stay dry (%d wet edges: %s)"%[wet.size(),str(wet.slice(0,8))])

func test_rendered_authored_roads_match_final_navigation() -> void:
	var graph := SimBootstrap.roads_for(world)
	var missing := 0
	for seg in world.road_segments:
		if not String(seg["street"]).begins_with("net:"):continue
		var p: Vector2=(seg["from"]+seg["to"])*.5
		var loc := graph.locate(Vector2i(roundi(p.x*100),roundi(p.y*100)))
		var q := Vector2(graph.location_point(loc))/100.0
		if p.distance_to(q)>.8:missing+=1
	check_eq(missing,0,"visible authored road pieces have matching navigation edges")

func test_reserved_driveways_clear_neighbour_exclusion_zones() -> void:
	var conflicts := 0
	for i in world.estate_plots.size():
		var a: Dictionary=world.estate_plots[i]
		for j in range(i+1,world.estate_plots.size()):
			var b: Dictionary=world.estate_plots[j]
			if a["center"].distance_squared_to(b["center"])>640000.0:continue
			if a["center"].distance_to(Geometry2D.get_closest_point_to_segment(a["center"],b["gate"],b["road_point"]))<118.0 \
					or b["center"].distance_to(Geometry2D.get_closest_point_to_segment(b["center"],a["gate"],a["road_point"]))<118.0:
				conflicts+=1
	check_eq(conflicts,0,"future 6m driveways do not invade another estate exclusion disc")
