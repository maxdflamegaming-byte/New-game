// A soft round shadow on the ground (under buildings, soldiers and scenery) for the graphics
// settings without real-time shadows: one see-through quad each, far cheaper on a phone than
// drawing everything a second time into a shadow map.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float strength = 0.32;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = vec3(0.02, 0.08, 0.1);
	ALPHA = strength * (1.0 - smoothstep(0.35, 1.0, r));
}
