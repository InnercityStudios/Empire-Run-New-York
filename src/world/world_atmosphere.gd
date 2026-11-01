class_name WorldAtmosphere
extends Node3D
## Sun, sky, fog and grading for the city map, tuned for the Mobile renderer.
## Shadow distance follows camera zoom so shadow-map resolution is spent on
## what is on screen.

@export var sun_elevation_deg := 42.0
@export var sun_azimuth_deg := -128.0
@export var sun_color := Color(1.0, 0.88, 0.72)
@export var sun_energy := 1.55

var sun: DirectionalLight3D
var environment: Environment


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-sun_elevation_deg, sun_azimuth_deg, 0)
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.25
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.45, 0.58)
	sky_mat.sky_horizon_color = Color(0.86, 0.74, 0.58)
	sky_mat.ground_horizon_color = Color(0.62, 0.52, 0.42)
	sky_mat.ground_bottom_color = Color(0.2, 0.17, 0.14)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.85
	environment.ambient_light_sky_contribution = 0.75
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 6.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_strength = 0.9
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color(0.78, 0.68, 0.56)
	environment.fog_light_energy = 0.9
	environment.fog_depth_begin = 260.0
	environment.fog_depth_end = 900.0
	environment.fog_depth_curve = 1.4
	environment.fog_sky_affect = 0.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 0.92
	environment.adjustment_brightness = 1.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = environment
	add_child(we)


## Called by the camera when zoom changes.
func on_camera_distance(distance: float) -> void:
	if sun:
		sun.directional_shadow_max_distance = clampf(distance * 2.4, 140.0, 700.0)
	if environment:
		environment.fog_depth_begin = distance * 1.6 + 120.0
		environment.fog_depth_end = distance * 4.0 + 500.0
