// A road: a soft lane in the army's colour with white edges, and chevrons that flow toward the
// building it leads to. UV.x goes across the road, UV.y along it (in steps of 30 units).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec3 color : source_color = vec3(0.24, 0.6, 1.0);
uniform float grow = 1.0;

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	// Chevrons pointing along the road (their middle leads), drifting forward
	float f = fract(UV.y * 0.42 - across * 0.32 - TIME * 0.9);
	float chevron = smoothstep(0.0, 0.06, f) * (1.0 - smoothstep(0.2, 0.26, f)) * (1.0 - smoothstep(0.62, 0.7, across));
	float edge = smoothstep(0.8, 0.86, across) * (1.0 - smoothstep(0.96, 1.0, across));
	vec3 c = mix(color, vec3(1.0), max(chevron * 0.85, edge * 0.9));
	ALBEDO = c;
	ALPHA = clamp(0.5 + chevron * 0.4 + edge * 0.45, 0.0, 0.95) * (1.0 - smoothstep(0.97, 1.0, across));
}
