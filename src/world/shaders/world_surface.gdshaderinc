// Shared surface model for all pipeline-built world geometry.
// Wrapper shaders set render_mode and optional defines:
//   OCCLUSION_CUTOUT  dither away fragments between camera and tracked units
//   TINT_FROM_CUSTOM  per-instance tint from MultiMesh INSTANCE_CUSTOM

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_map = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform bool use_orm = false;
uniform sampler2D orm_tex : hint_default_white, filter_linear, repeat_enable;
uniform sampler2D emission_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float night_emission = 0.0;
uniform vec3 highlight_color : source_color = vec3(0.89, 0.72, 0.36);
// Weathering: world-space grime (R blotches, G rain streaks, B speckle) scaled
// per material, plus baked vertex occlusion in COLOR.r from the asset pipeline.
uniform sampler2D grime_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float grime_amount = 0.0;
uniform float ao_strength = 1.0;
uniform float specular_amount = 0.4;

instance uniform float highlight = 0.0;
#ifndef TINT_FROM_CUSTOM
instance uniform vec4 tint : source_color = vec4(1.0);
#endif

global uniform float world_night;
#ifdef OCCLUSION_CUTOUT
global uniform vec4 occl_target_0;
global uniform vec4 occl_target_1;
#endif

varying vec3 v_world;
varying vec3 v_world_normal;
varying vec4 v_tint;
varying float v_ao;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_ao = mix(1.0, COLOR.r, ao_strength);
#ifdef TINT_FROM_CUSTOM
	v_tint = INSTANCE_CUSTOM;
#else
	v_tint = tint;
#endif
}

#ifdef OCCLUSION_CUTOUT
float occlusion_amount(vec3 wp, vec3 cam, vec4 target) {
	if (target.w <= 0.0) {
		return 0.0;
	}
	// Never cut the street level around the unit itself.
	if (wp.y < target.y + 0.6) {
		return 0.0;
	}
	vec3 seg = target.xyz - cam;
	float len2 = max(dot(seg, seg), 1e-4);
	float h = dot(wp - cam, seg) / len2;
	if (h <= 0.0 || h >= 0.985) {
		return 0.0;
	}
	float dist = length(wp - (cam + seg * h));
	// Capsule widens toward the target so the whole convoy stays visible.
	float r = target.w * mix(0.35, 1.0, h);
	return 1.0 - smoothstep(r * 0.55, r, dist);
}

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.x + i.y * 4;
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}
#endif

void fragment() {
#ifdef OCCLUSION_CUTOUT
	// Directional shadow passes are orthographic: keep shadows intact.
	if (PROJECTION_MATRIX[3][3] == 0.0) {
		float cut = max(occlusion_amount(v_world, CAMERA_POSITION_WORLD, occl_target_0),
				occlusion_amount(v_world, CAMERA_POSITION_WORLD, occl_target_1));
		if (cut * 0.88 > bayer4(FRAGCOORD.xy)) {
			discard;
		}
	}
#endif
	vec4 a = texture(albedo_tex, UV) * albedo_color;
	float r = roughness;
	float m = metallic;
	float tint_mask = 0.0;
	if (use_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		tint_mask = orm.r;
		r = orm.g;
		m = orm.b;
	}
	vec3 albedo = a.rgb * mix(vec3(1.0), v_tint.rgb, tint_mask);
	if (grime_amount > 0.0) {
		vec3 n = normalize(v_world_normal);
		float wall = 1.0 - abs(n.y);
		vec2 puv = abs(n.y) > 0.6 ? v_world.xz : (abs(n.x) > abs(n.z) ? v_world.zy : v_world.xy);
		float blot = texture(grime_tex, puv * 0.043).r;
		float streak = texture(grime_tex, vec2(puv.x * 0.31, puv.y * 0.022)).g * wall;
		float speck = texture(grime_tex, puv * 0.57).b;
		float tone = texture(grime_tex, puv * 0.0105 + vec2(0.31, 0.77)).r;
		float ground = (1.0 - smoothstep(0.15, 2.2, v_world.y)) * wall;
		float g = clamp(grime_amount * (blot * 0.32 + streak * 0.3 + ground * 0.4), 0.0, 1.0);
		// Large-scale tone shifts make neighbouring buildings read differently.
		albedo *= mix(0.9, 1.08, tone) * mix(0.93, 1.05, speck);
		albedo = mix(albedo, albedo * vec3(0.55, 0.52, 0.48), g);
		r = clamp(r + g * 0.12 - streak * 0.08 + (speck - 0.5) * 0.1, 0.04, 1.0);
	}
	ALBEDO = albedo * v_ao;
	AO = v_ao;
	AO_LIGHT_AFFECT = 0.35;
	ROUGHNESS = r;
	METALLIC = m;
	SPECULAR = specular_amount;
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	vec3 e = texture(emission_tex, UV).rgb * emission_color * (emission_energy + night_emission * world_night);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = e + highlight_color * highlight * (0.06 + rim * 1.1);
}
