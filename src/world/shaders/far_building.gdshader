shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Distant-city LOD: one box per building. Facade colour comes from COLOR
// (sampled from the building's real material), windows are procedural in
// world space, roofs use COLOR.a as a roof-tone switch. ~10 triangles per
// building, no textures beyond a shared noise.

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 roof_color : source_color = vec4(0.33, 0.32, 0.3, 1.0);
uniform float floor_h = 3.1;
uniform float window_pitch = 2.05;
global uniform float world_night;

varying vec3 v_world;
varying vec3 v_world_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = v_world_normal;
	vec3 col = COLOR.rgb;
	float rough = 0.9;
	vec3 emit = vec3(0.0);
	if (n.y > 0.5) {
		float t = texture(noise_tex, v_world.xz * 0.02).r;
		col = mix(roof_color.rgb * 0.75, roof_color.rgb * 1.35, mix(t, COLOR.a, 0.6));
	} else {
		float along = abs(n.x) > abs(n.z) ? v_world.z : v_world.x;
		vec2 cell = vec2(along / window_pitch, (v_world.y - 0.6) / floor_h);
		vec2 f = fract(cell);
		float win = step(0.3, f.x) * step(f.x, 0.72) * step(0.32, f.y) * step(f.y, 0.86) * step(4.0, v_world.y);
		float lit = step(0.78, texture(noise_tex, floor(cell) * 0.137).r);
		vec3 glass = mix(vec3(0.07, 0.08, 0.09), vec3(0.42, 0.47, 0.52), 0.25);
		col = mix(col, glass, win * 0.85);
		rough = mix(0.9, 0.2, win);
		emit = vec3(1.0, 0.78, 0.45) * win * lit * world_night * 1.5;
		col *= 0.75 + 0.25 * smoothstep(0.0, 3.0, v_world.y);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	EMISSION = emit;
}
