shader_type spatial;
render_mode specular_schlick_ggx;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool strategic = false;
varying vec4 weights;
void vertex() { weights=COLOR; }
void fragment() {
	vec3 meadow=texture(grass_tex,UV).rgb;
	float macro=texture(grass_tex,UV*.09+vec2(.27,.53)).r;
	meadow*=mix(vec3(.84,.89,.72),vec3(1.04,1.05,.86),clamp(macro*2.0,0.0,1.0));
	vec3 soil=texture(dirt_tex,UV).rgb;
	vec3 sand=texture(sand_tex,UV*.8).rgb;
	vec3 stone=texture(stone_tex,UV).rgb*vec3(.74,.75,.73);
	vec3 land=mix(stone,meadow,weights.r);
	land=mix(land,soil,weights.b*.46);
	land=mix(land,mix(soil*.71,sand,.24),weights.g*.86);
	ALBEDO=land;
	if (!strategic) { NORMAL_MAP=texture(ground_normal,UV).rgb; NORMAL_MAP_DEPTH=.22; }
	ROUGHNESS=.94;
	SPECULAR=.15;
}
