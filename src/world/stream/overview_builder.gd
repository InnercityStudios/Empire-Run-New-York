class_name OverviewBuilder
extends RefCounted
## Province-overview tier: every city block as two to four massing boxes,
## scenery backdrop and landmark towers, instanced into one MultiMesh per
## 1 km tile. Always resident (about 12 triangles per box).
##
## Boxes are listed per streaming chunk so the streamer can hide a chunk's
## boxes when its mid-distance or detail tier is loaded (`set_chunk_visible`).

const TILE := 1024.0
const SHADER := preload("res://src/world/shaders/overview_building.gdshader")

var chunk_instances: Dictionary = {}   ## chunk key -> Array[[MultiMesh, index, Transform3D]]
var instance_count := 0
var tiles := 0
var _hidden: Dictionary = {}


static func build(world: WorldLayout, parent: Node3D) -> OverviewBuilder:
	var ob := OverviewBuilder.new()
	ob._build(world, parent)
	return ob


static func unit_box() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	WorldShellBuilder._box(st, Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 1.0, 0.5), 4.0)
	return st.commit()


func _build(world: WorldLayout, parent: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("noise_tex", load("res://assets/textures/grime_noise.png"))
	var box := unit_box()
	box.surface_set_material(0, mat)
	# Collect instances per tile: [transform, colour, chunk key or null].
	var per_tile := {}
	var add := func(pos: Vector2, size: Vector2, height: float, yaw: float, col: Color, key: Variant) -> void:
		var t := Transform3D(Basis(Vector3.UP, -yaw).scaled(Vector3(size.x, height, size.y)), Vector3(pos.x, 0.0, pos.y))
		var tk := Vector2i((pos / TILE).floor())
		if not per_tile.has(tk):
			per_tile[tk] = []
		per_tile[tk].append([t, col, key])
	for b in world.blocks:
		if b.has("polygon"):
			var actual := BlockFiller.fill(b,world.sidewalk,world.curb_height,false)
			for lot in actual["lots"]:
				var t: Transform3D=lot["transform"]
				var dims: Vector3=b["kit"]["dims"][lot["building"]]
				var center: Vector3=t*Vector3(0,0,-dims.z*.5)
				var col := Color.html(world._catalog[lot["building"]].get("facade","#7a5a48"))
				add.call(Vector2(center.x,center.z),Vector2(dims.x,dims.z),dims.y,t.basis.z.signed_angle_to(Vector3.BACK,Vector3.UP),col,
					world.chunk_of(WorldLayout.block_center(b)))
			continue
		var kit: Dictionary = world.kits.get(b["style"], world.kits.get("li_tenement", {})) if world.is_geo else {}
		var mean_h: float = kit.get("mean_height", 18.0) if not kit.is_empty() else 18.0
		if mean_h <= 0.0:
			continue
		var col: Color = kit.get("facade", Color("#7a5a48"))
		var spaced := float((kit.get("fill", {}) as Dictionary).get("gap", [0, 0])[1]) > 0.0 if not kit.is_empty() else false
		var rect: Rect2 = (b["rect"] as Rect2).grow(-world.sidewalk - 1.0)
		if rect.size.x < 6.0 or rect.size.y < 6.0:
			continue
		var xf: Transform2D = b.get("xform", Transform2D.IDENTITY)
		var yaw := xf.get_rotation()
		var key := world.chunk_of(WorldLayout.block_center(b))
		var rng := RandomNumberGenerator.new()
		rng.seed = int(b.get("seed", hash(rect)))
		var long_x := rect.size.x >= rect.size.y
		var long_len := rect.size.x if long_x else rect.size.y
		var n := clampi(int(long_len / 45.0), 1, 4)
		for i in n:
			var f0 := float(i) / n
			var f1 := float(i + 1) / n
			var part := Rect2(rect.position + Vector2(rect.size.x * f0, 0), Vector2(rect.size.x * (f1 - f0), rect.size.y)) if long_x \
				else Rect2(rect.position + Vector2(0, rect.size.y * f0), Vector2(rect.size.x, rect.size.y * (f1 - f0)))
			var s := part.size * (0.7 if spaced else 0.96)
			var h := mean_h * rng.randf_range(0.72, 1.25) * (0.9 if spaced else 1.0)
			var c := col.lightened(rng.randf_range(-0.08, 0.08))
			c.a = rng.randf()
			add.call(xf * part.get_center(), s, h, yaw, c, key)
	for bb in world.backdrop_boxes:
		var tone := Color.html(["#6f4a3a", "#8a7560", "#5a4136", "#9c8f7c"][absi(hash(bb["pos"])) % 4])
		tone.a = 0.5
		add.call(bb["pos"], bb["size"], bb["height"], bb["yaw"], tone, null)
	var root := Node3D.new()
	root.name = "Overview"
	parent.add_child(root)
	var keys := per_tile.keys()
	keys.sort()
	for tk in keys:
		var list: Array = per_tile[tk]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = box
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_custom_data(i, list[i][1])
			if list[i][2] != null:
				var ck: Vector2i = list[i][2]
				if not chunk_instances.has(ck):
					chunk_instances[ck] = []
				chunk_instances[ck].append([mm, i, list[i][0]])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Tile_%d_%d" % [tk.x, tk.y]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		instance_count += list.size()
		tiles += 1
	_towers(world, root, box)


## Landmark silhouettes (Empire State, Chrysler, Trade Center...) with stepped
## setbacks; always visible and shadow-casting so they read from any zoom.
func _towers(world: WorldLayout, root: Node3D, box: ArrayMesh) -> void:
	if world.towers.all(func(t): return t.has("model")):
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = box
	var parts: Array = []
	for t in world.towers:
		if t.has("model"):
			continue  # drawn as the real model by WorldStreamer
		var size: Vector2 = t["size"]
		var h: float = t["height"]
		var steps: Array = [[1.0, 0.45], [0.74, 0.8], [0.46, 1.0]] if h > 100.0 else [[1.0, 1.0]]
		for st in steps:
			var c: Color = t["color"]
			c.a = 0.55
			parts.append([Transform3D(Basis(Vector3.UP, -float(t["yaw"])).scaled(Vector3(size.x * st[0], h * st[1], size.y * st[0])),
				Vector3(t["pos"].x, 0.0, t["pos"].y)), c])
	mm.instance_count = parts.size()
	for i in parts.size():
		mm.set_instance_transform(i, parts[i][0])
		mm.set_instance_custom_data(i, parts[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Landmarks"
	mmi.multimesh = mm
	root.add_child(mmi)
	instance_count += parts.size()


## Hide or show a chunk's boxes (when its mid or detail tier is on screen).
func set_chunk_visible(key: Vector2i, visible: bool) -> void:
	if visible == not _hidden.has(key):
		return
	for entry in chunk_instances.get(key, []):
		var mm: MultiMesh = entry[0]
		mm.set_instance_transform(entry[1], entry[2] if visible else Transform3D(Basis().scaled(Vector3.ZERO), (entry[2] as Transform3D).origin))
	if visible:
		_hidden.erase(key)
	else:
		_hidden[key] = true
