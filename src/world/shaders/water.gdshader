shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

// Harbour and river water: two scrolling normal layers, depth-free colour
// (cheap on mobile), Fresnel sky reflection via the environment.

uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 deep_color : source_color = vec4(0.05, 0.11, 0.13, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.12, 0.2, 0.2, 1.0);
uniform float wave_scale = 0.045;
uniform float wave_speed = 0.012;

uniform bool shore_enabled = false;
uniform sampler2D shore_mask : filter_linear, repeat_disable;
uniform vec4 world_bounds = vec4(-8500.0,-14500.0,27000.0,24000.0);
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_world.xz * wave_scale;
	vec3 n1 = texture(wave_normal, uv + vec2(TIME * wave_speed, TIME * wave_speed * 0.6)).rgb;
	vec3 n2 = texture(wave_normal, uv * 2.7 + vec2(-TIME * wave_speed * 1.3, TIME * wave_speed * 0.4)).rgb;
	NORMAL_MAP = mix(n1, n2, 0.5);
	NORMAL_MAP_DEPTH = 0.24;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec2 world_uv=(v_world.xz-world_bounds.xy)/world_bounds.zw;
	float in_frame=step(0.0,world_uv.x)*step(world_uv.x,1.0)*step(0.0,world_uv.y)*step(world_uv.y,1.0);
	float shore=shore_enabled ? texture(shore_mask,world_uv).r*in_frame : 0.0;
	float broad=sin(v_world.x*.004+sin(v_world.z*.006))*.5+.5;
	vec3 deep=deep_color.rgb*mix(.88,1.12,broad);
	ALBEDO = mix(deep, shallow_color.rgb, clamp(shore*1.8+fres*.35,0.0,.95));
	ROUGHNESS = 0.19;
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
