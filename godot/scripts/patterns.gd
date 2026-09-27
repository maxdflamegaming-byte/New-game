class_name Patterns
extends RefCounted
## Colourblind mode: every player colour also gets its own pattern (stripes, dots, rings...)
## on its land, trail and square, so players can be told apart without colour.

static var on := false

## The shapes of each pattern on a 64 x 64 tile (two cells), drawn white and tinted
const SHAPES := [
	# 0: diagonal stripes
	'<path d="M-8 24 L24 -8 L36 -8 L-8 36 Z M-8 56 L56 -8 L68 -8 L-8 68 Z M24 72 L72 24 L72 36 L36 72 Z"/>',
	# 1: dots
	'<circle cx="16" cy="16" r="7"/><circle cx="48" cy="48" r="7"/><circle cx="48" cy="16" r="3"/><circle cx="16" cy="48" r="3"/>',
	# 2: horizontal stripes
	'<rect x="0" y="6" width="64" height="9"/><rect x="0" y="38" width="64" height="9"/>',
	# 3: vertical stripes
	'<rect x="6" y="0" width="9" height="64"/><rect x="38" y="0" width="9" height="64"/>',
	# 4: small squares
	'<rect x="6" y="6" width="18" height="18"/><rect x="38" y="38" width="18" height="18"/>',
	# 5: crosses
	'<path d="M13 4 H19 V13 H28 V19 H19 V28 H13 V19 H4 V13 H13 Z M45 36 H51 V45 H60 V51 H51 V60 H45 V51 H36 V45 H45 Z"/>',
	# 6: rings
	'<circle cx="16" cy="16" r="9" fill="none" stroke="#ffffff" stroke-width="5"/><circle cx="48" cy="48" r="9" fill="none" stroke="#ffffff" stroke-width="5"/>',
	# 7: zigzag
	'<path d="M0 22 L16 8 L32 22 L48 8 L64 22 L64 30 L48 16 L32 30 L16 16 L0 30 Z M0 54 L16 40 L32 54 L48 40 L64 54 L64 62 L48 48 L32 62 L16 48 L0 62 Z"/>',
]

static var _cache := {}


## Which pattern a player has: one per player colour (`colors` is the world's palette)
static func index_of(p: Player, colors: Array) -> int:
	for k in colors.size():
		if colors[k].is_equal_approx(p.color):
			return k % SHAPES.size()
	return p.id % SHAPES.size()


## The pattern as a tile that repeats (for land and trails)
static func tile(i: int) -> Texture2D:
	return _tex("t%d" % i, '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><g fill="#ffffff">' + SHAPES[i % SHAPES.size()] + '</g></svg>')


## The pattern cut to the shape of a square's body
static func body(i: int) -> Texture2D:
	return _tex("b%d" % i, '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><defs><clipPath id="c"><rect x="1" y="1" width="62" height="62" rx="15"/></clipPath></defs><g clip-path="url(#c)" fill="#ffffff">' + SHAPES[i % SHAPES.size()] + '</g></svg>')


static func _tex(key: String, svg: String) -> Texture2D:
	if not _cache.has(key):
		var img := Image.new()
		img.load_svg_from_string(svg, 1.0)
		img.generate_mipmaps()
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]
