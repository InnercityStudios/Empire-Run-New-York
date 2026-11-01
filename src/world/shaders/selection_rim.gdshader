shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// Additive fresnel rim drawn as a material overlay on selected models whose
// own materials cannot be modified (e.g. licensed vehicles).

uniform vec4 rim_color : source_color = vec4(0.95, 0.76, 0.38, 1.0);
uniform float strength = 0.55;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float pulse = 0.8 + 0.2 * sin(TIME * 3.0);
	ALBEDO = rim_color.rgb * rim * strength * pulse;
}
