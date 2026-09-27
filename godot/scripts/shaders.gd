class_name Shaders
extends RefCounted
## Shaders that draw the whole board's land (and the minimap) from a small texture of who
## owns each cell, one texel per cell. The graphics card does per cell what would otherwise be
## thousands of rectangles, and the land redraws for free when someone claims more.

## Land as raised tiles: the owner's colour on top, a darker band below each patch (`depth`,
## in cells), light rims on top and left edges, soft shading at bottom edges and a slow shine
## sweeping across (each switched on by the graphics level).
const LAND := """
shader_type canvas_item;

uniform sampler2D ids : filter_nearest; // owner of each cell (id / 255)
uniform sampler2D pal : filter_nearest; // row 0: colour of each id, row 1: its dark edge
uniform float n = 80.0;
uniform float depth = 0.3;
uniform float rims = 1.0;
uniform float shade = 0.0;
uniform float shine = 0.0;

int id_at(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= int(n) || c.y >= int(n)) {
		return 0;
	}
	return int(texelFetch(ids, c, 0).r * 255.0 + 0.5);
}

void fragment() {
	vec2 p = UV * vec2(n, n + depth);
	ivec2 c = ivec2(floor(p));
	int id = p.y < n ? id_at(c) : 0;
	if (id > 0) {
		vec4 col = texelFetch(pal, ivec2(id, 0), 0);
		vec2 f = fract(p);
		if (rims > 0.5) {
			if (f.y < 0.14 && id_at(c - ivec2(0, 1)) != id) {
				col.rgb = mix(col.rgb, vec3(1.0), 0.32);
			}
			if (f.x < 0.1 && id_at(c - ivec2(1, 0)) != id) {
				col.rgb = mix(col.rgb, vec3(1.0), 0.16);
			}
		}
		if (shade > 0.5) {
			if (f.y > 0.8 && id_at(c + ivec2(0, 1)) != id) {
				col.rgb *= 1.0 - 0.5 * (f.y - 0.8);
			}
			if (f.x > 0.86 && id_at(c + ivec2(1, 0)) != id) {
				col.rgb *= 1.0 - 0.4 * (f.x - 0.86);
			}
		}
		if (shine > 0.5) {
			float band = sin((p.x + p.y) * 0.12 - TIME * 1.4);
			col.rgb += vec3(0.1) * smoothstep(0.93, 1.0, band);
		}
		COLOR = col;
	} else {
		int up = depth > 0.0 ? id_at(ivec2(floor(p - vec2(0.0, depth)))) : 0;
		if (up > 0) {
			COLOR = texelFetch(pal, ivec2(up, 1), 0);
		} else {
			COLOR = vec4(0.0);
		}
	}
}
"""

## The minimap: land, then trails, walls and the sea, one texel per cell
const MINIMAP := """
shader_type canvas_item;

uniform sampler2D ids : filter_nearest;
uniform sampler2D trails : filter_nearest;
uniform sampler2D walls : filter_nearest;
uniform sampler2D pal : filter_nearest;
uniform float n = 80.0;
uniform float sea = 0.0;

void fragment() {
	ivec2 c = clamp(ivec2(floor(UV * n)), ivec2(0), ivec2(int(n) - 1));
	int id = int(texelFetch(ids, c, 0).r * 255.0 + 0.5);
	if (id == 0) {
		id = int(texelFetch(trails, c, 0).r * 255.0 + 0.5);
	}
	int wall = int(texelFetch(walls, c, 0).r * 255.0 + 0.5);
	vec4 col;
	if (id > 0) {
		col = texelFetch(pal, ivec2(id, 0), 0);
	} else if (wall == 1) {
		col = vec4(107.0, 118.0, 144.0, 255.0) / 255.0;
	} else if (wall == 2) {
		col = sea > 0.5 ? vec4(124.0, 199.0, 232.0, 255.0) / 255.0 : vec4(200.0, 207.0, 222.0, 120.0) / 255.0;
	} else {
		col = vec4(235.0, 239.0, 248.0, 255.0) / 255.0;
	}
	COLOR = col;
}
"""

static var _cache := {}


static func material(code: String) -> ShaderMaterial:
	if not _cache.has(code):
		var sh := Shader.new()
		sh.code = code
		_cache[code] = sh
	var m := ShaderMaterial.new()
	m.shader = _cache[code]
	return m


## A texture of one byte per cell (land owners, trails or walls)
class Grid:
	var img: Image
	var tex: ImageTexture

	func set_bytes(n: int, data: PackedByteArray) -> void:
		var fresh := img == null or img.get_width() != n
		img = Image.create_from_data(n, n, false, Image.FORMAT_R8, data)
		if fresh or tex == null:
			tex = ImageTexture.create_from_image(img)
		else:
			tex.update(img)
