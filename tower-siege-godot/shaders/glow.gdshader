// Effects that fade out: fireballs, rings on the ground, range circles.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 color : source_color = vec4(1.0);

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
