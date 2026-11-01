shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
#define TINT_FROM_CUSTOM
#include "res://src/world/shaders/world_surface.gdshaderinc"
