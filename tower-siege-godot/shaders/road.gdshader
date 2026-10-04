// A road: a see-through strip in the army's color with bright edges and white dots that
// march toward the target. UV.x goes across the road, UV.y along it (in steps of 30 units).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec3 color : source_color = vec3(0.24, 0.6, 1.0);
uniform float grow = 1.0;

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	vec2 g = vec2(UV.x - 0.5, (fract(UV.y - TIME * 1.4) - 0.5) * 0.42);
	float dot_ = 1.0 - smoothstep(0.1, 0.13, length(g));
	vec3 c = mix(color, vec3(1.0), dot_ * 0.95);
	float a = mix(0.6, 0.95, step(0.84, across));
	ALBEDO = c;
	ALPHA = max(a, dot_);
}
