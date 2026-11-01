shader_type canvas_item;

// Frosted glass panel: blurred map behind, dark tint, rounded corners and a
// hairline border. One screen copy per canvas layer; mip sampling keeps the
// blur cheap on mobile GPUs.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.055, 0.05, 0.045, 0.74);
uniform vec4 border_color : source_color = vec4(0.79, 0.64, 0.29, 0.28);
uniform float border_width = 1.0;
uniform float radius = 10.0;
uniform float blur_lod = 3.5;
uniform float top_accent = 0.0;
uniform vec2 rect_size = vec2(100.0, 100.0);

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - (half_size - vec2(r));
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV * rect_size - rect_size * 0.5;
	float d = rounded_box(p, rect_size * 0.5, radius);
	float inside = clamp(0.5 - d, 0.0, 1.0);
	vec2 px = SCREEN_PIXEL_SIZE * 6.0;
	vec3 bg = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb * 0.4;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(px.x, px.y), blur_lod).rgb * 0.15;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, px.y), blur_lod).rgb * 0.15;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(px.x, -px.y), blur_lod).rgb * 0.15;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, -px.y), blur_lod).rgb * 0.15;
	vec3 col = mix(bg, tint.rgb, tint.a);
	// Faint top sheen for depth
	col += vec3(0.035) * (1.0 - smoothstep(0.0, 0.5, UV.y));
	float edge = clamp(1.0 - abs(d + border_width * 0.5) / max(border_width, 0.5), 0.0, 1.0);
	col = mix(col, border_color.rgb, edge * border_color.a);
	// Optional gold accent along the top edge
	float accent = top_accent * (1.0 - smoothstep(0.0, 2.0, p.y + rect_size.y * 0.5)) * step(abs(p.x), rect_size.x * 0.5 - radius);
	col = mix(col, border_color.rgb, accent);
	COLOR = vec4(col, inside);
}
