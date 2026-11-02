shader_type canvas_item;
// A soft diagonal light sweep across the logo (driven by `sweep`, 0..1).
uniform float sweep = -0.5;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float band = UV.x + UV.y * 0.35 - sweep * 1.35;
	float glint = exp(-band * band * 90.0) * 0.55;
	COLOR = vec4(c.rgb + vec3(1.0, 0.86, 0.6) * glint * c.a, c.a) * COLOR;
}
