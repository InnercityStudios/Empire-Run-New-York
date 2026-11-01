@tool
extends Node
## Autoload "Materials": shared runtime materials built from data/materials.json.
##
## Exported GLBs carry named placeholder materials; `apply_to_mesh` swaps each
## surface for the shared ShaderMaterial of the same name, so every asset that
## uses brick shares one material and one copy of its textures.

const LIBRARY_PATH := "res://data/materials.json"
const SHADERS := {
	"opaque": preload("res://src/world/shaders/world_opaque.gdshader"),
	"double": preload("res://src/world/shaders/world_double.gdshader"),
	"opaque_cutout": preload("res://src/world/shaders/world_opaque_cutout.gdshader"),
	"double_cutout": preload("res://src/world/shaders/world_double_cutout.gdshader"),
	"instanced_tint": preload("res://src/world/shaders/world_instanced_tint.gdshader"),
}
const ROAD_SHADER := preload("res://src/world/shaders/road.gdshader")
const SIGNAL_MATERIALS := ["M_SignalRed", "M_SignalAmber", "M_SignalGreen"]

var _defs: Dictionary = {}
var _materials: Dictionary = {}
var _cutout: Dictionary = {}
var _instanced: Dictionary = {}
var _road: ShaderMaterial
var _grime: Texture2D
var _fallback: StandardMaterial3D


func _init() -> void:
	_fallback = StandardMaterial3D.new()
	_fallback.albedo_color = Color(1, 0, 1)
	var text := FileAccess.get_file_as_string(LIBRARY_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MaterialLibrary: cannot parse %s" % LIBRARY_PATH)
		return
	_defs = parsed.get("materials", {})


func all_names() -> Array:
	return _defs.keys()


func has_material(mat_name: String) -> bool:
	return _defs.has(mat_name)


## Shared material for a pipeline material name.
func get_material(mat_name: String) -> Material:
	if not _materials.has(mat_name):
		_materials[mat_name] = _build(mat_name, "")
	return _materials[mat_name]


## Variant that dithers away where it hides tracked units (see OcclusionFader).
func get_cutout_material(mat_name: String) -> Material:
	if not _cutout.has(mat_name):
		_cutout[mat_name] = _build(mat_name, "_cutout")
	return _cutout[mat_name]


## Variant for MultiMesh instances with a per-instance tint in custom data.
func get_instanced_material(mat_name: String) -> Material:
	if not _instanced.has(mat_name):
		_instanced[mat_name] = _build(mat_name, "instanced")
	return _instanced[mat_name]


func get_road_material() -> ShaderMaterial:
	if _road == null:
		_road = ShaderMaterial.new()
		_road.shader = ROAD_SHADER
		# Photographic asphalt (Poly Haven asphalt_02, CC0); markings stay procedural.
		_road.set_shader_parameter("asphalt_tex", load("res://assets/textures/pbr/asphalt_02_albedo.png"))
		_road.set_shader_parameter("asphalt_normal", load("res://assets/textures/pbr/asphalt_02_normal.png"))
		_road.set_shader_parameter("tile_m", 4.0)
	return _road


## Replace placeholder surface materials of an imported mesh in place.
func apply_to_mesh(mesh: Mesh, variant := "") -> void:
	for i in mesh.get_surface_count():
		var placeholder := mesh.surface_get_material(i)
		var mat_name := material_name_of(placeholder)
		if mat_name.is_empty():
			continue
		mesh.surface_set_material(i, _material_for(mat_name, variant))


func material_name_of(mat: Material) -> String:
	if mat == null:
		return ""
	var n := mat.resource_name
	if _defs.has(n):
		return n
	# Shared materials we built carry their library name in metadata.
	return mat.get_meta("library_name", "") if mat.has_meta("library_name") else ""


## Drive the animated signal lenses: state per axis is "red", "amber" or "green".
func set_signal_state(ns_state: String, ew_state: String) -> void:
	for suffix in ["", "_EW"]:
		var state := ns_state if suffix == "" else ew_state
		for base in SIGNAL_MATERIALS:
			var lit: bool = (base == "M_SignalRed" and state == "red") or (base == "M_SignalAmber" and state == "amber") \
				or (base == "M_SignalGreen" and state == "green")
			var m := get_material(base + suffix) as ShaderMaterial
			if m:
				m.set_shader_parameter("emission_energy", 3.0 if lit else 0.0)


func _grime_texture() -> Texture2D:
	if _grime == null:
		_grime = load("res://assets/textures/grime_noise.png")
	return _grime


func _material_for(mat_name: String, variant: String) -> Material:
	match variant:
		"cutout":
			return get_cutout_material(mat_name)
		"instanced":
			return get_instanced_material(mat_name)
		_:
			return get_material(mat_name)


func _build(mat_name: String, variant: String) -> Material:
	var d: Dictionary = _defs.get(mat_name, {})
	if d.is_empty():
		push_warning("MaterialLibrary: unknown material %s" % mat_name)
		return _fallback
	var double_sided: bool = d.get("cull", "back") == "disabled"
	var key := ("double" if double_sided else "opaque") + variant
	if variant == "instanced":
		key = "instanced_tint"
	var m := ShaderMaterial.new()
	m.shader = SHADERS[key]
	m.resource_name = mat_name
	m.set_meta("library_name", mat_name)
	m.set_shader_parameter("albedo_color", Color.html(d.get("color", "#ffffff")))
	if d.has("albedo"):
		m.set_shader_parameter("albedo_tex", load(d["albedo"]))
	if d.has("normal"):
		m.set_shader_parameter("use_normal_map", true)
		m.set_shader_parameter("normal_tex", load(d["normal"]))
		m.set_shader_parameter("normal_scale", d.get("normal_scale", 1.0))
	if d.has("arm"):
		m.set_shader_parameter("use_arm", true)
		m.set_shader_parameter("arm_tex", load(d["arm"]))
	m.set_shader_parameter("uv_scale", d.get("uv_scale", 1.0))
	if d.has("orm"):
		m.set_shader_parameter("use_orm", true)
		m.set_shader_parameter("orm_tex", load(d["orm"]))
	m.set_shader_parameter("roughness", d.get("roughness", 0.8))
	m.set_shader_parameter("grime_amount", d.get("grime", 0.0))
	m.set_shader_parameter("specular_amount", d.get("specular", 0.4))
	if d.get("grime", 0.0) > 0.0:
		m.set_shader_parameter("grime_tex", _grime_texture())
	m.set_shader_parameter("metallic", d.get("metallic", 0.0))
	if d.has("emission"):
		m.set_shader_parameter("emission_color", Color.html(d["emission"]))
		m.set_shader_parameter("emission_energy", d.get("emission_energy", 0.0))
		if d.has("emission_tex"):
			m.set_shader_parameter("emission_tex", load(d["emission_tex"]))
	if mat_name == "M_Window":
		m.set_shader_parameter("night_emission", 1.6)
	return m
