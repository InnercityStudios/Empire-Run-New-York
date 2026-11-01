shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Road surface with procedural markings.
// Vertex data written by RoadBuilder:
//   UV.x  lateral offset from centreline in metres (+ = right of travel direction)
//   UV.y  distance along the segment in metres
//   UV2.x segment length in metres (0 = no markings, e.g. intersections)
//   UV2.y half width of the carriageway in metres
//   COLOR.r marking style / 2: 0 none, 1 two-way (double yellow), 2 avenue (+ lane dashes)

uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 6.0;
uniform vec4 paint_white : source_color = vec4(0.82, 0.8, 0.74, 1.0);
uniform vec4 paint_yellow : source_color = vec4(0.84, 0.62, 0.18, 1.0);
uniform float crosswalk_start = 0.6;
uniform float crosswalk_end = 4.0;
// Rain puddles: share of the road surface that holds standing water (0..1).
uniform float wetness = 0.35;

varying vec3 v_world;
varying vec2 v_info;
varying float v_style;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_info = UV2;
	v_style = COLOR.r * 2.0;
}

float band(float x, float a, float b, float aa) {
	return smoothstep(a - aa, a + aa, x) * (1.0 - smoothstep(b - aa, b + aa, x));
}

void fragment() {
	vec2 wuv = v_world.xz / tile_m;
	vec3 base = texture(asphalt_tex, wuv).rgb;
	// Large-scale variation breaks visible tiling from the strategic camera.
	float macro = texture(asphalt_tex, wuv * 0.11 + vec2(0.37, 0.71)).r;
	float macro2 = texture(asphalt_tex, wuv * 0.031 + vec2(0.13, 0.29)).r;
	base *= mix(0.82, 1.18, clamp(macro * 2.2 - 0.3, 0.0, 1.0)) * mix(0.9, 1.1, clamp(macro2 * 2.5 - 0.5, 0.0, 1.0));

	float lat = UV.x;
	float along = UV.y;
	float len = v_info.x;
	float hw = v_info.y;
	float aa = fwidth(lat) * 0.75 + 0.01;
	float aav = fwidth(along) * 0.75 + 0.01;
	float white = 0.0;
	float yellow = 0.0;
	if (len > 0.0) {
		float de = min(along, len - along);
		// Continental crosswalk bars
		if (de > crosswalk_start && de < crosswalk_end) {
			float bars = band(fract((lat + hw) / 1.1), 0.12, 0.62, aa / 1.1);
			float edge = band(de, crosswalk_start, crosswalk_end, aav);
			white = max(white, bars * edge * step(abs(lat), hw - 0.4));
		}
		// Stop lines on the approaching half of the carriageway
		float approaching_end = step(0.0, lat) * band(len - along, crosswalk_end + 0.6, crosswalk_end + 1.0, aav);
		float approaching_start = step(lat, 0.0) * band(along, crosswalk_end + 0.6, crosswalk_end + 1.0, aav);
		white = max(white, (approaching_end + approaching_start) * step(abs(lat), hw - 0.3));
		if (de > crosswalk_end + 1.2) {
			if (v_style > 0.5) {
				float alat = abs(lat);
				yellow = max(yellow, band(alat, 0.08, 0.2, aa));
			}
			if (v_style > 1.5) {
				float dash = band(fract(along / 6.0), 0.0, 0.5, aav / 6.0);
				white = max(white, band(abs(lat), hw * 0.5 - 0.07, hw * 0.5 + 0.07, aa) * dash);
			}
		}
	}
	float rough_mod = 0.0;
	if (len > 0.0) {
		float alat = abs(lat);
		// Gutter grime and debris along the kerbs.
		float gutter = 1.0 - smoothstep(0.0, 0.9, hw - alat);
		base *= mix(1.0, 0.62, gutter);
		// Polished tyre tracks in each travel lane.
		float lane_c = mod(alat, 3.7);
		float tracks = band(abs(lane_c - 1.85), 0.45, 1.1, 0.25) * step(alat, hw - 2.2);
		base *= mix(1.0, 0.86, tracks * 0.8);
		rough_mod -= tracks * 0.12;
		// Oil drip line down the middle of each lane.
		base *= mix(1.0, 0.8, band(abs(lane_c - 1.85), 0.0, 0.18, 0.12) * step(alat, hw - 2.2) * 0.7);
		// Utility trench patches running along the street.
		float patch_line = band(lat, -hw * 0.35, -hw * 0.35 + 0.9, 0.05) * step(0.5, fract(along / 37.0 + 0.2));
		base *= mix(1.0, 0.82, patch_line);
		// Manhole covers every ~24 m, alternating sides.
		float cell = floor(along / 24.0);
		float mz = cell * 24.0 + 12.0;
		float mx = (mod(cell, 2.0) < 1.0 ? -1.0 : 1.0) * hw * 0.42;
		float d = length(vec2(lat - mx, along - mz));
		float cover = 1.0 - smoothstep(0.34, 0.37, d);
		float rim = band(d, 0.33, 0.38, 0.015);
		float grid = step(0.5, fract((lat + along) * 6.0)) * 0.15;
		base = mix(base, vec3(0.13, 0.125, 0.12) * (0.9 + grid), cover * step(crosswalk_end + 2.0, min(along, len - along)));
		base = mix(base, vec3(0.32, 0.31, 0.29), rim * 0.6 * step(crosswalk_end + 2.0, min(along, len - along)));
		rough_mod -= cover * 0.35;
	}
	// Worn paint: break up markings with the asphalt texture.
	float wear = smoothstep(0.25, 0.6, texture(asphalt_tex, wuv * 3.7).r * 1.6 + macro * 0.4);
	white *= mix(0.45, 0.95, wear);
	yellow *= mix(0.5, 0.95, wear);
	vec3 col = mix(base, paint_white.rgb, white);
	col = mix(col, paint_yellow.rgb, yellow);
	// Puddles collect in the gutters and in low patches; one extra sample.
	float low = texture(asphalt_tex, wuv * 0.23 + vec2(0.61, 0.17)).r;
	float gutter_pull = len > 0.0 ? smoothstep(hw - 2.2, hw - 0.3, abs(lat)) * 0.35 : 0.0;
	float puddle = smoothstep(0.76 - wetness * 0.12, 0.8 - wetness * 0.12, (1.0 - low) * 0.75 + gutter_pull + macro2 * 0.2);
	puddle *= step(0.001, wetness);
	col = mix(col, col * 0.55, puddle);
	ALBEDO = col;
	ROUGHNESS = mix(clamp(mix(0.9, 0.7, max(white, yellow)) + rough_mod, 0.2, 1.0), 0.04, puddle);
	SPECULAR = mix(0.35, 0.7, puddle);
	NORMAL_MAP = mix(texture(asphalt_normal, wuv).rgb, vec3(0.5, 0.5, 1.0), puddle);
	NORMAL_MAP_DEPTH = 0.6;
}
