class_name TerrainStreamer
extends Node3D
## Resident 128 m terrain samples; 16 m samples streamed on workers. Resident
## coarse tiles are hidden only once their replacement is ready. One upload
## per frame, bounded pending jobs, hysteresis and deterministic vegetation.
const MAX_TASKS := 2
const RADIUS := 1600.0
var field: TerrainField
var camera: StrategyCamera
var coarse := {}
var detail := {}
var tasks := {}
var tree_meshes := {}
var stats := {"coarse_tiles":0,"detail_tiles":0,"max_tasks":0,"vegetation_instances":0}

func build(world: WorldLayout) -> void:
	field=world.terrain
	TerrainMesh.material()
	for id in ["tree_oak","tree_birch","tree_maple","tree_pine_far","rock_a","bush_a","reeds"]:
		tree_meshes[id]=AssetLibrary.prop_mesh(id)
	var lo := Vector2i((world.world_rect.position/TerrainMesh.TILE).floor())
	var hi := Vector2i((world.world_rect.end/TerrainMesh.TILE).floor())
	for x in range(lo.x,hi.x+1):
		for z in range(lo.y,hi.y+1):
			var key := Vector2i(x,z)
			# Open-water tiles need no terrain. Keep land and shoreline tiles.
			var rect := Rect2(Vector2(key)*TerrainMesh.TILE,Vector2.ONE*TerrainMesh.TILE).grow(192.0)
			var land := false
			for c in world.geo.coasts:
				if (c["bounds"] as Rect2).intersects(rect):land=true;break
			if not land:continue
			var mi := TerrainMesh.instance(TerrainMesh.arrays(field,key,128),key)
			mi.name="Coarse_%d_%d"%[x,z]
			add_child(mi);coarse[key]=mi
	stats["coarse_tiles"]=coarse.size()

func _distance(key: Vector2i, p: Vector2) -> float:
	var r := Rect2(Vector2(key)*TerrainMesh.TILE,Vector2.ONE*TerrainMesh.TILE)
	return p.distance_to(p.clamp(r.position,r.end))

func _process(_delta: float) -> void:
	if camera==null:return
	var focus := Vector2(camera.focus.x,camera.focus.z)
	var radius := RADIUS if camera.distance<2400.0 else 0.0
	var applied := false
	for key in tasks.keys():
		var entry: Array = tasks[key]
		if not WorkerThreadPool.is_task_completed(entry[0]) or applied:continue
		WorkerThreadPool.wait_for_task_completion(entry[0])
		tasks.erase(key)
		if radius==0.0 or _distance(key,focus)>radius+256.0:continue
		var root := Node3D.new()
		root.name="Terrain_%d_%d"%[key.x,key.y]
		add_child(root)
		root.add_child(TerrainMesh.instance(entry[1][0],key))
		_vegetation(root,key)
		detail[key]=root
		coarse[key].visible=false
		applied=true
	for key in detail.keys():
		if radius==0.0 or _distance(key,focus)>radius+512.0:
			stats["vegetation_instances"]-=int(detail[key].get_meta("vegetation_count",0))
			detail[key].queue_free();detail.erase(key);coarse[key].visible=true
	var wanted := []
	if radius>0.0:
		for key in coarse:
			if not detail.has(key) and not tasks.has(key) and _distance(key,focus)<=radius:
				wanted.append([_distance(key,focus),key])
	wanted.sort_custom(func(a,b):return a[0]<b[0])
	for request in wanted:
		if tasks.size()>=MAX_TASKS:break
		var key: Vector2i=request[1]
		var holder := []
		var task := WorkerThreadPool.add_task(func():holder.append(TerrainMesh.arrays(field,key,16)),false,"terrain")
		tasks[key]=[task,holder]
	stats["detail_tiles"]=detail.size()
	stats["max_tasks"]=maxi(stats["max_tasks"],tasks.size())

func _vegetation(root: Node3D, key: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=hash([key,"meadow1977"])
	var buckets := {}
	for i in 650:
		var p := Vector2(key)*TerrainMesh.TILE+Vector2(rng.randf(),rng.randf())*TerrainMesh.TILE
		if field.rural_at(p)<.5:continue
		var bank := field.bank_distance(p)
		var road := float(field.road_at(p)[0])
		if bank<3.0 or road<6.0:continue
		var reserved := false
		var cell := Vector2i((p/TerrainField.CELL).floor())
		for dx in range(-1,2):
			for dz in range(-1,2):
				for j in field._plot_cells.get(cell+Vector2i(dx,dz),[]):
					if p.distance_to(field.plots[j]["center"])<TerrainField.EXCLUSION+8.0:reserved=true
		if reserved:continue
		var cluster := sin(p.x*.012+sin(p.y*.008))*cos(p.y*.014)
		var id := ""
		if bank<14.0:id="reeds" if rng.randf()<.7 else "rock_a"
		elif cluster>.43:id=["tree_oak","tree_birch","tree_maple"][rng.randi()%3]
		elif cluster>.25 and rng.randf()<.3:id="bush_a"
		elif rng.randf()<.012:id="rock_a"
		if id=="":continue
		var scale := rng.randf_range(.72,1.32)
		var xf := Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale),
			Vector3(p.x,field.height_at(p),p.y))
		if not buckets.has(id):buckets[id]=[]
		buckets[id].append(xf)
	var count := 0
	for id in buckets:
		count+=buckets[id].size()
		var mm := MultiMesh.new()
		mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=tree_meshes[id]
		mm.instance_count=buckets[id].size()
		for i in mm.instance_count:mm.set_instance_transform(i,buckets[id][i])
		var mi := MultiMeshInstance3D.new();mi.multimesh=mm
		mi.visibility_range_end=2600.0
		mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	root.set_meta("vegetation_count",count)
	stats["vegetation_instances"]+=count

func _exit_tree() -> void:
	for entry in tasks.values():WorkerThreadPool.wait_for_task_completion(entry[0])
	tasks.clear()
