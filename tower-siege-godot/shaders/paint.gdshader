// Everything solid in Tower Siege: buildings, soldiers, tanks, trees and props.
// Colors come from the mesh's vertex colors. A vertex color with alpha below 0.9 means
// "the army's color" instead: alpha 0.5 = the color, 0.25 = its dark shade, 0.75 = its light
// shade. The army's color is a uniform for buildings, or each instance's custom data in a
// MultiMesh (rgb = color, a = a 0-1 phase for the walk). Faces are drawn flat, for a low-poly look.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec3 team_color : source_color = vec3(0.62, 0.67, 0.74);
uniform bool use_instance = false;
uniform bool walk = false;          // soldiers: UV2.x 1 = left leg, 2 = right leg; UV2.y = hip height
uniform float rough = 0.55;
uniform float hit_flash = 0.0;      // white flash when a building is hit

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
