// The ground: a clean, bright battlefield (a rounded "board" with soft mowed stripes and a
// tidy edge) on darker ground where the scenery stands. On the beach map the sea, white foam
// and a sandy shore go around it instead.
shader_type spatial;
render_mode cull_back;

uniform vec3 ground : source_color = vec3(0.47, 0.81, 0.27);
uniform vec3 field : source_color = vec3(0.53, 0.86, 0.31);
uniform vec3 spot : source_color = vec3(0.42, 0.76, 0.24);
uniform vec2 field_center = vec2(450.0, 700.0);
uniform vec2 field_half = vec2(450.0, 700.0);
uniform bool water = false;
uniform bool cracks = false;
uniform float seed = 0.0;

varying vec3 world;

float hash(vec2 p) { return fract(sin(dot(p + seed, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world.xz;
	float d = round_box(w - field_center, field_half + 40.0, 90.0);
	// The board: wide soft stripes, like a freshly mowed lawn (or raked sand, or packed snow)
	float stripe = smoothstep(0.35, 0.65, abs(fract(w.y / 220.0) * 2.0 - 1.0));
	vec3 board = mix(field, field * 0.955, stripe);
	// Very gentle large patches, so it isn't perfectly flat
	board = mix(board, board * 1.04, smoothstep(0.55, 0.9, noise(w / 260.0)) * 0.6);
	// Around the board: darker ground with soft patches
	float n = noise(w / 150.0) * 0.6 + noise(w / 60.0) * 0.4;
	vec3 outside = mix(ground, spot, smoothstep(0.5, 0.85, n) * 0.6);
	vec3 c = mix(board, outside, smoothstep(-2.0, 2.0, d));
	// The board's edge: a soft shadow line and a bright rim, so it reads as a tidy playing field
	c = mix(c, c * 0.82, (1.0 - smoothstep(0.0, 14.0, d)) * smoothstep(-2.0, 1.0, d) * 0.9);
	c = mix(c, c * 1.1 + 0.04, (1.0 - smoothstep(-10.0, -2.0, d)) * smoothstep(-18.0, -10.0, d) * 0.7);
	if (cracks) {
		float k = abs(noise(w / 40.0) - 0.5);
		c = mix(c, spot * 0.85, (1.0 - smoothstep(0.0, 0.012, k)) * 0.35 * step(0.55, noise(w / 300.0 + 3.0)) * step(0.0, d));
	}
	if (water) {
		// Beyond the shore: the sea with little waves, then foam, then sand
		vec3 sea = vec3(0.12, 0.62, 0.84);
		float wave = step(0.93, fract(w.y / 26.0 + noise(w / 60.0 + TIME * 0.2) * 0.8)) * step(0.5, noise(w / 30.0));
		vec3 s = mix(sea, vec3(0.75, 0.94, 1.0), wave * 0.6);
		s = mix(s, vec3(0.55, 0.88, 0.97), smoothstep(160.0, 80.0, d));
		float foam = smoothstep(52.0, 46.0, d) * smoothstep(30.0, 38.0, d + sin(w.x / 30.0 + TIME) * 3.0);
		vec3 sand = vec3(1.0, 0.87, 0.6);
		vec3 shore = mix(sand, c, smoothstep(30.0, 0.0, d));
		c = d > 50.0 ? s : mix(shore, vec3(1.0), foam);
	}
	ALBEDO = c;
	ROUGHNESS = water && d > 50.0 ? 0.25 : 0.9;
}
