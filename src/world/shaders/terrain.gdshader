shader_type spatial;
render_mode specular_schlick_ggx;
// Shared world UVs avoid chunk borders. Broad colour drift and two material
// scales break repetition; bank masks come from the same field as geometry.
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap, repeat_enable;
varying vec2 world_uv;
varying vec4 mask;
void vertex() {
	world_uv = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
	mask=COLOR;
}
void fragment() {
	vec2 p=world_uv;
	vec2 uv=p/7.0;
	float broad=sin(p.x*.006+sin(p.y*.004))*cos(p.y*.005-p.x*.001);
	float grain=sin(p.x*.15+sin(p.y*.11))*0.1;
	vec3 grass=mix(texture(grass_tex,uv).rgb,texture(grass_tex,uv*.31+vec2(.31,.17)).rgb,.32);
	grass*=mix(vec3(.81,.85,.67),vec3(1.08,1.06,.88),broad*.5+.5);
	vec3 dirt=texture(dirt_tex,uv*.9).rgb;
	vec3 rock=texture(rock_tex,uv*.8).rgb;
	vec3 sand=texture(sand_tex,uv*.8).rgb;
	vec3 mud=texture(mud_tex,uv).rgb*vec3(.76,.81,.73);
	float shore=mask.r*192.0;
	float land= smoothstep(6.0+grain*9.0,35.0+grain*12.0,shore);
	float road_verge=1.0-smoothstep(4.0,14.0,mask.a*90.0);
	float rough_ground=smoothstep(.40,.85,broad)*.17+road_verge*.55;
	vec3 field=mix(grass,dirt,rough_ground);
	vec3 bank=mix(mud,sand,smoothstep(-.5,.6,broad));
	bank=mix(bank,rock,smoothstep(.7,.92,broad)*.35);
	vec3 urban=mix(dirt,rock,.35)*vec3(.70,.72,.70);
	field=mix(urban,field,smoothstep(.0,.65,mask.g));
	ALBEDO=mix(bank,field,land);
	NORMAL_MAP=texture(ground_normal,uv).rgb;
	NORMAL_MAP_DEPTH=.26;
	ROUGHNESS=mix(.68,.96,land);
	SPECULAR=.18;
}
