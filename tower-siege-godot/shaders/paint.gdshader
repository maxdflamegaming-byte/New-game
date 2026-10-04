// Everything solid in Tower Siege: buildings, soldiers, tanks, trees and props.
// Colors come from the mesh's vertex colors. A vertex color with alpha below 0.9 means
// "the army's color" instead: alpha 0.5 = the color, 0.25 = its dark shade, 0.75 = its light
// shade. The army's color is a uniform for buildings, or each instance's custom data in a
// MultiMesh (rgb = color, a = a 0-1 phase for the walk). Faces are drawn flat, for a low-poly look.
// Animation: soldiers' legs swing (UV2.x 1 or 2), flags flutter (UV2.x 3), and plants sway in
// the wind (the `sway` uniform, more the higher up the plant).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec3 team_color : source_color = vec3(0.62, 0.67, 0.74);
uniform bool use_instance = false;
uniform bool walk = false;          // soldiers: UV2.x 1 = left leg, 2 = right leg; UV2.y = hip height
uniform float rough = 0.55;
uniform float hit_flash = 0.0;      // white flash when a building is hit
uniform float sway = 0.0;           // trees and flowers bending in the wind

varying vec3 v_team;

void vertex() {
	vec3 tc = team_color;
	float phase = 0.0;
	if (use_instance) {
		tc = INSTANCE_CUSTOM.rgb;
		phase = INSTANCE_CUSTOM.a;
	}
	v_team = tc;
	if (walk) {
		float t = TIME * 14.0 + phase * 6.2831;
		if (UV2.x > 0.5) {
			float swing = sin(t) * 0.8 * (UV2.x > 1.5 ? -1.0 : 1.0);
			vec3 v = VERTEX;
			v.y -= UV2.y;
			float c = cos(swing), s = sin(swing);
			v = vec3(v.x, v.y * c - v.z * s, v.y * s + v.z * c);
			v.y += UV2.y;
			VERTEX = v;
		}
		VERTEX.y += abs(sin(t)) * 2.0;
		// A little sway from side to side while marching
		VERTEX.x += sin(t * 0.5) * 0.06 * VERTEX.y;
	}
	if (UV2.x > 2.5) {
		// A flag: ripples run out from the pole, bigger at the free end
		VERTEX.z += sin(TIME * 7.0 - VERTEX.x * 0.45) * VERTEX.x * 0.09;
		VERTEX.y += sin(TIME * 5.0 - VERTEX.x * 0.3) * VERTEX.x * 0.03;
	}
	if (sway > 0.0) {
		vec3 o = MODEL_MATRIX[3].xyz;
		float ph = o.x * 0.011 + o.z * 0.017;
		float h = max(VERTEX.y, 0.0) / 40.0;
		VERTEX.x += sin(TIME * 1.7 + ph) * sway * h * h * 3.0;
		VERTEX.z += cos(TIME * 1.3 + ph * 1.7) * sway * h * h * 1.5;
	}
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (COLOR.a < 0.9) {
		if (COLOR.a > 0.6) c = mix(v_team, vec3(1.0), 0.55);
		else if (COLOR.a > 0.4) c = v_team;
		else c = v_team * 0.62;
	}
	ALBEDO = mix(c, vec3(1.0), hit_flash * 0.5);
	ROUGHNESS = rough;
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
}
