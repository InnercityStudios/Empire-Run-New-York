class_name ProofMaterials
extends RefCounted
## Reuses existing asset materials without involving the game's autoloads.
var definitions: Dictionary
var cache := {}

func _init() -> void:
	definitions=JSON.parse_string(FileAccess.get_file_as_string("res://data/materials.json"))

func asset_material(name: String, original: Material) -> Material:
	if cache.has(name):return cache[name]
	if not definitions.has(name):return original
	var d: Dictionary=definitions[name]
	var m: BaseMaterial3D
	if d.has("orm") or d.has("arm"):
		var orm := ORMMaterial3D.new()
		orm.orm_texture=load(d.get("orm",d.get("arm")))
		m=orm
	else:
		var standard := StandardMaterial3D.new()
		standard.roughness=float(d.get("roughness",.85))
		standard.metallic=float(d.get("metallic",0.0))
		m=standard
	m.resource_name=name
	m.albedo_color=Color.html(d.get("color","#ffffff"))
	if d.has("albedo"):m.albedo_texture=load(d["albedo"])
	if d.has("normal"):
		m.normal_enabled=true;m.normal_texture=load(d["normal"])
		m.normal_scale=float(d.get("normal_scale",.5))
	if d.has("emission_tex"):
		m.emission_enabled=true;m.emission_texture=load(d["emission_tex"])
		m.emission=Color.WHITE;m.emission_energy_multiplier=.25
	if d.get("cull","")=="disabled":m.cull_mode=BaseMaterial3D.CULL_DISABLED
	m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var scale := float(d.get("uv_scale",1.0))
	m.uv1_scale=Vector3(scale,scale,1.0)
	cache[name]=m
	return m

func apply_assets(root: Node) -> void:
	if root is MeshInstance3D:
		for i in root.mesh.get_surface_count():
			var old: Material=root.mesh.surface_get_material(i)
			if old!=null:root.set_surface_override_material(i,asset_material(old.resource_name,old))
	for child in root.get_children():apply_assets(child)

static func terrain(strategic: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader=load("res://shaders/ground.gdshader")
	for pair in [["grass_tex","terrain_grass_albedo"],["dirt_tex","terrain_dirt_albedo"],["sand_tex","terrain_sand_albedo"],
		["stone_tex","stone_albedo"],["ground_normal","terrain_grass_normal"]]:
		m.set_shader_parameter(pair[0],load("res://assets/textures/%s.png"%pair[1]))
	m.set_shader_parameter("strategic",strategic)
	return m

static func water(strategic: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader=load("res://shaders/water.gdshader")
	m.set_shader_parameter("ripples",load("res://assets/textures/water_normal.png"))
	m.set_shader_parameter("strategic",strategic)
	return m

static func surface(texture: String, roughness: float, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture=load("res://assets/textures/"+texture+".png")
	m.albedo_color=tint;m.roughness=roughness
	m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
