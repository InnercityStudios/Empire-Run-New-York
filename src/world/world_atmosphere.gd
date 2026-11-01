class_name WorldAtmosphere
extends Node3D
## Sun, sky, fog and grading for the city map, tuned for the Mobile renderer.
## Shadow distance follows camera zoom so shadow-map resolution is spent on
## what is on screen.

@export var sun_elevation_deg := 47.0
@export var sun_azimuth_deg := -132.0
@export var sun_color := Color(1.0, 0.91, 0.8)
@export var sun_energy := 1.45

var sun: DirectionalLight3D
var environment: Environment


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-sun_elevation_deg, sun_azimuth_deg, 0)
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.8
	# Partial shadow opacity stands in for the bounce light the Mobile
	# renderer cannot compute, so shaded streets stay readable.
	sun.shadow_opacity = 0.8
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.25
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.68)
	sky_mat.sky_horizon_color = Color(0.8, 0.77, 0.7)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.6, 0.56, 0.5)
	sky_mat.ground_bottom_color = Color(0.3, 0.28, 0.25)
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.05
	environment.ambient_light_sky_contribution = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.12
	environment.glow_enabled = true
	environment.glow_intensity = 0.25
	environment.glow_strength = 0.85
	environment.glow_bloom = 0.02
	environment.glow_hdr_threshold = 1.25
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color(0.7, 0.73, 0.76)
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.18
	environment.fog_depth_begin = 260.0
	environment.fog_depth_end = 900.0
	environment.fog_depth_curve = 1.4
	environment.fog_sky_affect = 0.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.05
	environment.adjustment_saturation = 1.04
	environment.adjustment_brightness = 1.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = environment
	add_child(we)
	# One-shot reflection probe: glass, chrome and paint reflect the street.
	if QualityFlags.off("probe"):
		return
	var probe := ReflectionProbe.new()
	probe.name = "StreetReflections"
	probe.size = Vector3(900, 120, 900)
	probe.position = Vector3(0, 30, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.75
	probe.max_distance = 600.0
	probe.box_projection = false
	add_child(probe)


## Called by the camera when zoom changes.
func on_camera_distance(distance: float) -> void:
	if sun:
		sun.directional_shadow_max_distance = clampf(distance * 2.4, 140.0, 700.0)
	if environment:
		environment.fog_depth_begin = distance * 1.6 + 120.0
		environment.fog_depth_end = distance * 4.0 + 500.0
