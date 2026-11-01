shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

// Harbour and river water: two scrolling normal layers, depth-free colour
// (cheap on mobile), Fresnel sky reflection via the environment.

uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 deep_color : source_color = vec4(0.05, 0.11, 0.13, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.12, 0.2, 0.2, 1.0);
uniform float wave_scale = 0.045;
uniform float wave_speed = 0.012;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_world.xz * wave_scale;
	vec3 n1 = texture(wave_normal, uv + vec2(TIME * wave_speed, TIME * wave_speed * 0.6)).rgb;
	vec3 n2 = texture(wave_normal, uv * 2.7 + vec2(-TIME * wave_speed * 1.3, TIME * wave_speed * 0.4)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.55;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, fres * 0.6);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
