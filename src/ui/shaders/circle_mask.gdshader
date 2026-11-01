shader_type canvas_item;
// Round crop with a soft edge (family crest in the profile ring).
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = texture(TEXTURE, UV);
	COLOR.a *= 1.0 - smoothstep(0.485, 0.5, d);
}
