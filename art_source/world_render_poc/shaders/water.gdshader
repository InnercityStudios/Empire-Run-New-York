shader_type spatial;
render_mode specular_schlick_ggx;
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool strategic = false;
varying float depth;
void vertex() { depth=COLOR.r; }
void fragment() {
	float t=TIME*.004;
	if (!strategic) {
		vec3 a=texture(ripples,UV*.4+vec2(t,t*.4)).rgb;
		vec3 b=texture(ripples,UV*.9+vec2(-t*.6,t*.3)).rgb;
		NORMAL_MAP=mix(a,b,.5); NORMAL_MAP_DEPTH=.16;
	}
	vec3 shallow=vec3(.15,.235,.20);
	vec3 deep=vec3(.055,.115,.135);
	float fres=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),4.0);
	ALBEDO=mix(shallow,deep,smoothstep(0.0,.9,depth));
	ALBEDO=mix(ALBEDO,vec3(.25,.32,.35),fres*.24);
	ROUGHNESS=.22; SPECULAR=.55;
}
