shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Animated art-deco selection ring. UV.x = angle 0..1, UV.y = 0 inner .. 1 outer.

uniform vec4 ring_color : source_color = vec4(0.95, 0.76, 0.38, 1.0);
uniform float intensity = 1.4;
uniform float dash_count = 24.0;
uniform float speed = 0.06;

void fragment() {
	float edge = smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.82, 1.0, UV.y));
	float outer_line = smoothstep(0.72, 0.8, UV.y) * (1.0 - smoothstep(0.9, 0.98, UV.y));
	float dash = step(0.35, fract((UV.x + TIME * speed) * dash_count));
	float pulse = 0.75 + 0.25 * sin(TIME * 3.0);
	float a = max(outer_line, edge * dash * 0.55) * pulse;
	ALBEDO = ring_color.rgb * intensity * a;
	ALPHA = a;
}
