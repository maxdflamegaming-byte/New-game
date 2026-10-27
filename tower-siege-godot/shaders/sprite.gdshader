shader_type spatial;
// Soft puffs and twinkling stars, many at once in one MultiMesh (one draw call): each
// instance faces the camera, keeps its own size, spins by INSTANCE_CUSTOM.x, and takes its
// colour and fade from the instance colour.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	float a = INSTANCE_CUSTOM.x;
	VERTEX.xy = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xy;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = texture(tex, UV).a * COLOR.a;
}
