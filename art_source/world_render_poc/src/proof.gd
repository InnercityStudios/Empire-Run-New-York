extends Node3D
## Isolated rendering proof. No Game/Content autoload, simulation or save API.
## Tab selects the two samples; 1/2/3 select close/medium/strategic. Wheel zooms.
const LEVELS := ["close","medium","strategic"]
const STEPS := [4,8,32]
var regions: Array = []
var data: Dictionary
var camera: Camera3D
var sun: DirectionalLight3D
var material_library := ProofMaterials.new()
var errors: Array = []
var report := {"visual_review":"pending","gpu_measurements_available":false,"regions":{},"captures":[]}
var options := {}
var active_region := 0
var active_level := 0
var _drag := false
var _yaw_offset := 0.0
var _roof_tools := {}
var _roof_materials := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=",true,1)
		options[kv[0]]=kv[1] if kv.size()>1 else ""
	data=JSON.parse_string(FileAccess.get_file_as_string("res://data/geography.json"))
	_setup_light()
	camera=Camera3D.new();camera.fov=38;camera.near=.5;camera.far=6000
	add_child(camera);camera.make_current()
	var start := Time.get_ticks_msec()
	for definition in data["regions"]:
		_build_region(definition)
	report["build_ms"]=Time.get_ticks_msec()-start
	report["renderer"]=ProjectSettings.get_setting("rendering/renderer/rendering_method")
	report["display_driver"]=DisplayServer.get_name()
	report["engine"]=Engine.get_version_info()["string"]
	report["errors"]=errors
	report["source_sha256"]=FileAccess.get_sha256("res://data/geography.json")
	_set_view(0,0)
	if options.has("check") or DisplayServer.get_name()=="headless":
		_save_report("res://results/geometry_check.json")
		print("PROOF_GEOMETRY ",JSON.stringify(report))
		if DisplayServer.get_name()=="headless" and options.has("capture-all"):
			push_error("No screenshots: the headless driver has no graphical renderer")
			get_tree().quit(2)
		else:
			get_tree().quit(0 if errors.is_empty() else 1)
		return
	if options.has("capture-all"):
		await _capture_all()

func _setup_light() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color=Color("#527492")
	sky_material.sky_horizon_color=Color("#c4c9c5")
	sky_material.ground_horizon_color=Color("#929487")
	var sky := Sky.new();sky.sky_material=sky_material
	var env := Environment.new();env.background_mode=Environment.BG_SKY;env.sky=sky
	env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY;env.ambient_light_energy=.8
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode=Environment.TONE_MAPPER_AGX;env.tonemap_exposure=1.0
	var world := WorldEnvironment.new();world.environment=env;add_child(world)
	sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-38,0)
	sun.light_color=Color(1.0,.94,.83);sun.light_energy=1.35
	sun.shadow_enabled=true;sun.directional_shadow_max_distance=700
	sun.shadow_bias=.025;sun.shadow_normal_bias=.5
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

func _build_region(definition: Dictionary) -> void:
	var g := ProofGeography.load_region(definition)
	errors.append_array(g.errors)
	var root := Node3D.new();root.name=definition["id"];add_child(root)
	var record := {"geo":g,"root":root,"levels":[],"models":Node3D.new(),"roofs":Node3D.new(),"props":Node3D.new()}
	root.add_child(record["models"]);root.add_child(record["roofs"]);root.add_child(record["props"])
	var stats := {"lods":{},"buildings":0,"placement_checks":[],"shared_boundary_errors":0}
	var borders := {}
	var tier_borders := {}
	var curb_edges := {}
	for li in LEVELS.size():
		var tier := Node3D.new();tier.name=LEVELS[li];root.add_child(tier)
		record["levels"].append(tier)
		var tri_count := 0
		var areas := {"ground":0.0,"road":0.0,"water":0.0,"pavement":0.0}
		for kind in ["ground","water","road","pavement"]:
			if kind=="pavement" and definition["shore_kind"]!="bulkhead":continue
			var material: Material
			match kind:
				"ground":material=ProofMaterials.terrain(li==2)
				"water":material=ProofMaterials.water(li==2)
				"road":material=ProofMaterials.surface("pbr/asphalt_02_albedo",.87,Color("#aaa69e") if definition["shore_kind"]=="natural" else Color.WHITE)
				_:material=ProofMaterials.surface("sidewalk_albedo",.94)
			var z := g.bounds.position.y
			while z<g.bounds.end.y:
				var x := g.bounds.position.x
				while x<g.bounds.end.x:
					var rect := Rect2(x,z,minf(128,g.bounds.end.x-x),minf(128,g.bounds.end.y-z))
					var built := ConformingMesh.build(g,kind,rect,STEPS[li])
					errors.append_array(built["errors"])
					tri_count+=int(built["triangles"]);areas[kind]+=float(built["area"])
					if not built["arrays"].is_empty():
						var mesh := ArrayMesh.new()
						mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,built["arrays"])
						mesh.surface_set_material(0,material)
						var mi := MeshInstance3D.new();mi.mesh=mesh;mi.position=Vector3(x,0,z)
						mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						tier.add_child(mi)
						if kind=="ground":_check_boundaries(built["arrays"],rect,borders,stats,tier_borders,LEVELS[li])
						if kind=="road" and li==0:_collect_edges(built["arrays"],rect.position,curb_edges)
					x+=128
				z+=128
		stats["lods"][LEVELS[li]]={"terrain_road_water_triangles":tri_count,"areas_m2":areas,"tile_nodes":tier.get_child_count()}
	stats["edge_knots_per_lod"]={}
	for tier_name in LEVELS:
		stats["edge_knots_per_lod"][tier_name]=tier_borders[tier_name].size()
		for key in tier_borders["close"]:
			if not tier_borders[tier_name].has(key):errors.append("missing shared boundary knot in "+tier_name)
	# Every representation covers exactly the same geographic area.
	var reference: Dictionary=stats["lods"]["close"]["areas_m2"]
	for name in LEVELS:
		for layer in reference:
			var diff := absf(float(reference[layer])-float(stats["lods"][name]["areas_m2"][layer]))
			if diff>maxf(.1,float(reference[layer])*.00001):errors.append("LOD area mismatch: %s %s %s"%[g.source["id"],name,layer])
	_roof_tools.clear();_roof_materials.clear()
	for entry in definition["buildings"]:
		var model := _place_model(entry,g,record["models"],true)
		if model==null:continue
		stats["buildings"]+=1
		_check_building(model,g,stats)
		_collect_roofs(model,model.transform)
	for entry in definition["trees"]+definition["rocks"]:
		var natural := _place_model(entry,g,record["props"],false)
		if natural:_collect_roofs(natural,natural.transform)
	stats["strategic_surface_triangles"]=_commit_roofs(record["roofs"])
	if definition["shore_kind"]=="bulkhead":
		_bulkhead(g,root)
		_curbs(curb_edges,root,g.bounds)
		_road_markings(g,root)
		_street_props(g,record["props"])
	_validate_roads(g)
	_validate_reservation(g,stats)
	report["regions"][definition["id"]]=stats
	regions.append(record)

func _check_boundaries(a: Array, rect: Rect2, borders: Dictionary, stats: Dictionary, tiers: Dictionary, tier: String) -> void:
	if not tiers.has(tier):tiers[tier]={}
	var v: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=a[Mesh.ARRAY_NORMAL]
	for i in v.size():
		var p := v[i]+Vector3(rect.position.x,0,rect.position.y)
		if absf(fposmod(p.x,128))>.002 and absf(fposmod(p.z,128))>.002:continue
		var key := Vector2i(roundi(p.x*1000),roundi(p.z*1000))
		tiers[tier][key]=true
		if borders.has(key):
			if absf(p.y-float(borders[key][0]))>.001 or normals[i].distance_to(borders[key][1])>.001:
				stats["shared_boundary_errors"]+=1
		else:borders[key]=[p.y,normals[i]]
	if stats["shared_boundary_errors"]>0:errors.append("terrain shared height/normal mismatch")

func _bounds(node: Node3D, xf := Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var first := true
	if node is MeshInstance3D and node.mesh:
		result=xf*node.mesh.get_aabb();first=false
	for child in node.get_children():
		if child is Node3D:
			var cb := _bounds(child,xf*child.transform)
			if cb.size.length_squared()>.00001:
				result=cb if first else result.merge(cb);first=false
	return result

func _place_model(entry: Dictionary, g: ProofGeography, parent: Node3D, building: bool) -> Node3D:
	var packed := load("res://assets/models/%s.glb"%entry["asset"]) as PackedScene
	if packed==null:
		errors.append("missing asset "+entry["asset"]);return null
	var model := packed.instantiate() as Node3D
	model.name=entry.get("id",entry["asset"])
	parent.add_child(model);material_library.apply_assets(model)
	if building:
		var outward := Vector2(entry["outward"][0],entry["outward"][1])
		model.rotation.y=atan2(outward.x,outward.y)
		var b := _bounds(model,model.transform)
		var depth := absf(outward.x)*b.size.x+absf(outward.y)*b.size.z
		var face := Vector2(entry["frontage"][0],entry["frontage"][1])
		var center := face-outward*depth*.5
		model.position=Vector3(center.x-b.get_center().x,g.height_at(center)+(.15 if g.source["shore_kind"]=="bulkhead" else 0)-b.position.y,center.y-b.get_center().z)
	else:
		var p := Vector2(entry["pos"][0],entry["pos"][1])
		model.position=Vector3(p.x,g.height_at(p),p.y)
		model.rotation.y=deg_to_rad(float(entry.get("yaw",0)))
		model.scale=Vector3.ONE*float(entry.get("scale",1.0))
	return model

func _check_building(model: Node3D, g: ProofGeography, stats: Dictionary) -> void:
	var b := _bounds(model,model.transform)
	var footprint := ConformingMesh.rect_poly(Rect2(b.position.x,b.position.z,b.size.x,b.size.z))
	var valid := true
	for band in g.road_bands:
		if not Geometry2D.intersect_polygons(footprint,band["polygon"]).is_empty():valid=false
	for p in footprint:
		if not Geometry2D.is_point_in_polygon(p,g.land):valid=false
	stats["placement_checks"].append({"id":model.name,"road_clear":valid,"footprint_m":[b.size.x,b.size.z]})
	if not valid:errors.append("building overlaps road/water: "+str(model.name))

func _collect_roofs(node: Node3D, xf: Transform3D) -> void:
	if node is MeshInstance3D and node.mesh:
		for s in node.mesh.get_surface_count():
			var arrays: Array=node.mesh.surface_get_arrays(s)
			var v: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var material: Material=node.get_active_material(s)
			var key := material.get_instance_id() if material else 0
			if not _roof_tools.has(key):
				var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
				_roof_tools[key]=st;_roof_materials[key]=material
			var st: SurfaceTool=_roof_tools[key]
			for i in range(0,idx.size(),3):
				var normal := xf.basis*(n[idx[i]]+n[idx[i+1]]+n[idx[i+2]])/3.0
				if normal.y<.4:continue
				for k in 3:
					var p: Vector3=xf*v[idx[i+k]]
					p.y=.2+maxf(p.y,0)*.025
					st.set_normal(Vector3.UP);st.set_uv(uv[idx[i+k]]);st.add_vertex(p)
	for child in node.get_children():
		if child is Node3D:_collect_roofs(child,xf*child.transform)

func _commit_roofs(parent: Node3D) -> int:
	var triangles := 0
	var mesh := ArrayMesh.new()
	for key in _roof_tools:
		var st: SurfaceTool=_roof_tools[key]
		var arrays := st.commit_to_arrays()
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX]==null or arrays[Mesh.ARRAY_VERTEX].is_empty():continue
		triangles+=arrays[Mesh.ARRAY_VERTEX].size()/3
		st.generate_tangents();st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count()-1,_roof_materials[key])
	var mi := MeshInstance3D.new();mi.mesh=mesh
	mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if triangles==0:errors.append("missing strategic roof representation")
	return triangles

func _bulkhead(g: ProofGeography, root: Node3D) -> void:
	var shore: Array=g.source["shore"]
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in shore.size()-1:
		var a := Vector3(shore[i][0],-.03,shore[i][1])
		var b := Vector3(shore[i+1][0],-.03,shore[i+1][1])
		var normal := Vector3(-1,0,0)
		for p in [a,b,b-Vector3.UP*2.8,a,b-Vector3.UP*2.8,a-Vector3.UP*2.8]:
			st.set_normal(normal);st.set_uv(Vector2(p.z/3.0,p.y/3.0));st.add_vertex(p)
	st.generate_tangents()
	var mesh := st.commit();mesh.surface_set_material(0,ProofMaterials.surface("stone_albedo",.91,Color("#8c8e86")))
	var mi := MeshInstance3D.new();mi.mesh=mesh;root.add_child(mi)

func _street_props(g: ProofGeography, parent: Node3D) -> void:
	for i in 5:
		var z := 84.0+i*26.0
		_place_model({"asset":"street_lamp","pos":[120,z]},g,parent,false)
	_place_model({"asset":"fire_hydrant","pos":[120,209]},g,parent,false)
	_place_model({"asset":"trash_can","pos":[56,142]},g,parent,false)

func _validate_roads(g: ProofGeography) -> void:
	var seen := {g.roads[0]["from"]:true}
	var changed := true
	while changed:
		changed=false
		for road in g.roads:
			if seen.has(road["from"]) or seen.has(road["to"]):
				if not seen.has(road["from"]) or not seen.has(road["to"]):changed=true
				seen[road["from"]]=true;seen[road["to"]]=true
	if seen.size()!=g.source["nodes"].size():errors.append("disconnected proof road graph")
	for road in g.roads:
		for p in road["path"]:
			if g.water_distance(p)<float(road["width"])*.5:errors.append("road enters water: "+road["id"])

func _validate_reservation(g: ProofGeography, stats: Dictionary) -> void:
	if not g.source.has("reservation"):return
	var plot: Dictionary=g.source["reservation"]
	var center := Vector2(plot["center"][0],plot["center"][1])-g.origin
	var max_error := 0.0
	for i in 48:
		var p := center+Vector2.from_angle(TAU*i/48.0)*float(plot["exclusion_radius"])
		max_error=maxf(max_error,absf(g.height_at(p)-float(plot["elevation"])))
	stats["retained_estate"]={"id":plot["id"],"world_center":plot["center"],"max_height_error_m":max_error}
	if max_error>.03:errors.append("estate proof no longer flat across exclusion zone")

func _set_view(region: int, level: int) -> void:
	active_region=region;active_level=level
	for i in regions.size():
		var r: Dictionary=regions[i]
		r["root"].visible=i==region
		for li in LEVELS.size():r["levels"][li].visible=li==level
		r["models"].visible=level<2;r["roofs"].visible=level==2;r["props"].visible=level<2
	var view: Dictionary=regions[region]["geo"].source["views"][LEVELS[level]]
	var target := Vector3(view["target"][0],view["target"][1],view["target"][2])
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL if level==2 else Camera3D.PROJECTION_PERSPECTIVE
	camera.size=float(view.get("size",400))
	var pitch := deg_to_rad(float(view["pitch"]))
	var yaw := deg_to_rad(float(view["yaw"])+_yaw_offset)
	var distance := float(view.get("distance",1300))
	camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.look_at(target,Vector3.FORWARD if level==2 else Vector3.UP)
	get_viewport().mesh_lod_threshold=1.0 if level==0 else 2.5
	sun.shadow_enabled=level<2

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_TAB:_set_view((active_region+1)%regions.size(),active_level)
		if event.keycode in [KEY_1,KEY_2,KEY_3]:_set_view(active_region,event.keycode-KEY_1)
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:_drag=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var v: Dictionary=regions[active_region]["geo"].source["views"][LEVELS[active_level]]
			var factor := .9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1
			v["distance"]=clampf(float(v.get("distance",1000))*factor,80,2600)
			v["size"]=clampf(float(v.get("size",1000))*factor,80,2600)
			_set_view(active_region,active_level)
	if event is InputEventMouseMotion and _drag:
		_yaw_offset+=event.relative.x*.2;_set_view(active_region,active_level)

func _capture_all() -> void:
	var output: String=options.get("output",ProjectSettings.globalize_path("res://results/captures"))
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for ri in regions.size():
		for li in LEVELS.size():
			_set_view(ri,li)
			await get_tree().create_timer(1.5).timeout
			var times := []
			var draws := 0
			var primitives := 0
			var viewport := get_viewport().get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(viewport,true)
			var gpu_ms := 0.0
			var render_cpu_ms := 0.0
			var last := Time.get_ticks_usec()
			for frame in 120:
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				times.append(float(now-last)/1000.0);last=now
				gpu_ms+=RenderingServer.viewport_get_measured_render_time_gpu(viewport)
				render_cpu_ms+=RenderingServer.viewport_get_measured_render_time_cpu(viewport)
				draws=maxi(draws,RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
				primitives=maxi(primitives,RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
			times.sort()
			await RenderingServer.frame_post_draw
			var path := output.path_join(regions[ri]["geo"].source["id"]+"_"+LEVELS[li]+".png")
			var err := get_viewport().get_texture().get_image().save_png(path)
			if err!=OK:errors.append("screenshot write failed "+path)
			report["captures"].append({"file":path,"region":ri,"lod":LEVELS[li],"max_draw_calls":draws,"max_primitives":primitives,
				"gpu_average_ms":gpu_ms/120.0,"render_cpu_average_ms":render_cpu_ms/120.0,"frame_p50_ms":times[60],"frame_p95_ms":times[114],"vram_mb":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)/1048576.0})
	report["gpu_measurements_available"]=true;report["errors"]=errors
	_save_report(output.path_join("capture_report.json"))
	get_tree().quit(0 if errors.is_empty() else 1)

func _save_report(path: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"  "))


## Extract the actual road-union perimeter, cancelling tile-internal edges.
## Kerbs follow that perimeter rather than a second independent road lattice.
func _collect_edges(arrays: Array, origin: Vector2, edges: Dictionary) -> void:
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	for i in range(0,indices.size(),3):
		for k in 3:
			var a := vertices[indices[i+k]]+Vector3(origin.x,0,origin.y)
			var b := vertices[indices[i+(k+1)%3]]+Vector3(origin.x,0,origin.y)
			var ka := "%d,%d"%[roundi(a.x*1000),roundi(a.z*1000)]
			var kb := "%d,%d"%[roundi(b.x*1000),roundi(b.z*1000)]
			var key := ka+":"+kb if ka<kb else kb+":"+ka
			if edges.has(key):edges[key]["count"]+=1
			else:edges[key]={"count":1,"a":a,"b":b}

func _curbs(edges: Dictionary, root: Node3D, bounds: Rect2) -> void:
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for edge in edges.values():
		if edge["count"]!=1:continue
		var a: Vector3=edge["a"]
		var b: Vector3=edge["b"]
		var midpoint := Vector2((a.x+b.x)*.5,(a.z+b.z)*.5)
		if midpoint.x<bounds.position.x+.01 or midpoint.x>bounds.end.x-.01 or midpoint.y<bounds.position.y+.01 or midpoint.y>bounds.end.y-.01:continue
		var delta := b-a
		var normal := Vector3(delta.z,0,-delta.x).normalized()
		var high_a := Vector3(a.x,.15,a.z)
		var high_b := Vector3(b.x,.15,b.z)
		for p in [a,high_a,high_b,a,high_b,b]:
			st.set_normal(normal);st.set_uv(Vector2((p.x+p.z)/3.0,p.y/3.0));st.add_vertex(p)
		count+=2
	if count==0:return
	st.generate_tangents()
	var mesh := st.commit();mesh.surface_set_material(0,ProofMaterials.surface("stone_albedo",.9,Color("#b3b1a6")))
	var mi := MeshInstance3D.new();mi.mesh=mesh;root.add_child(mi)


func _paint_quad(st: SurfaceTool, a: Vector2, b: Vector2, half: float, color: Color) -> void:
	var d := (b-a).normalized()
	var side := Vector2(-d.y,d.x)*half
	var points := [a-side,b-side,b+side,a+side]
	for i in [0,1,2,0,2,3]:
		st.set_normal(Vector3.UP);st.set_color(color)
		st.add_vertex(Vector3(points[i].x,.025,points[i].y))

func _road_markings(g: ProofGeography, root: Node3D) -> void:
	var degree := {}
	for road in g.roads:
		degree[road["from"]]=degree.get(road["from"],0)+1
		degree[road["to"]]=degree.get(road["to"],0)+1
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yellow := Color("#bfa157")
	var white := Color("#c9c8b8")
	for road in g.roads:
		if float(road["width"])<10.0:continue
		var path: PackedVector2Array=road["path"]
		for i in path.size()-1:
			var a := path[i]
			var b := path[i+1]
			var d := (b-a).normalized()
			var side := Vector2(-d.y,d.x)
			var start := 10.0 if i==0 and degree[road["from"]]>=3 else 0.0
			var end := 10.0 if i==path.size()-2 and degree[road["to"]]>=3 else 0.0
			for offset in [-.16,.16]:
				_paint_quad(st,a+d*start+side*offset,b-d*end+side*offset,.055,yellow)
		for end in [[path[0],path[1],road["from"]],[path[-1],path[-2],road["to"]]]:
			if degree[end[2]]<3:continue
			var toward := ((end[1] as Vector2)-(end[0] as Vector2)).normalized()
			var side := Vector2(-toward.y,toward.x)
			for stripe in range(-5,6):
				var p: Vector2=end[0]+toward*7.0+side*stripe*.85
				_paint_quad(st,p,p+toward*2.1,.21,white)
	var mesh := st.commit()
	var material := StandardMaterial3D.new();material.vertex_color_use_as_albedo=true;material.roughness=.94
	mesh.surface_set_material(0,material)
	var mi := MeshInstance3D.new();mi.mesh=mesh;root.add_child(mi)
