class_name Art
extends RefCounted
## Sprites drawn as SVG and turned into textures when the game starts, at the size the screen
## needs them, so they stay sharp on any display. White parts get tinted with each player's
## colour when drawn.

const BODY := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#ffffff"/><stop offset="0.55" stop-color="#f2f2f2"/><stop offset="1" stop-color="#cfcfcf"/>
</linearGradient></defs>
<rect x="1" y="1" width="62" height="62" rx="15" fill="url(#g)"/>
</svg>"""

## The darker block under the body that makes it look raised
const SIDE := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<rect x="1" y="1" width="62" height="62" rx="15" fill="#ffffff"/>
</svg>"""

## Light from the top left: a soft shine and a glossy spot (drawn untinted, on top)
const GLOSS := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<defs>
<linearGradient id="t" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#ffffff" stop-opacity="0.45"/><stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/>
</linearGradient>
<radialGradient id="s" cx="0.5" cy="0.5" r="0.5">
<stop offset="0" stop-color="#ffffff" stop-opacity="0.85"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
</radialGradient>
</defs>
<rect x="1" y="1" width="62" height="62" rx="15" fill="url(#t)"/>
<ellipse cx="20" cy="15" rx="13" ry="6" fill="url(#s)" transform="rotate(-20 20 15)"/>
<rect x="2" y="2" width="60" height="60" rx="14" fill="none" stroke="#ffffff" stroke-opacity="0.35" stroke-width="2"/>
</svg>"""

const GLOW := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<defs><radialGradient id="g" cx="0.5" cy="0.5" r="0.5">
<stop offset="0" stop-color="#ffffff" stop-opacity="1"/><stop offset="0.35" stop-color="#ffffff" stop-opacity="0.55"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
</radialGradient></defs>
<circle cx="32" cy="32" r="32" fill="url(#g)"/>
</svg>"""

const SHADOW := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<defs><radialGradient id="g" cx="0.5" cy="0.5" r="0.5">
<stop offset="0" stop-color="#101428" stop-opacity="0.45"/><stop offset="1" stop-color="#101428" stop-opacity="0"/>
</radialGradient></defs>
<circle cx="32" cy="32" r="32" fill="url(#g)"/>
</svg>"""

const SPARK := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M32 2 C35 24 40 29 62 32 C40 35 35 40 32 62 C29 40 24 35 2 32 C24 29 29 24 32 2Z" fill="#ffffff"/>
</svg>"""

const TILE := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<rect x="4" y="4" width="56" height="56" rx="12" fill="#ffffff"/>
</svg>"""

const CROWN := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M6 50 L6 16 L20 30 L32 10 L44 30 L58 16 L58 50 Z" fill="#ffc93c" stroke="#c98a00" stroke-width="4" stroke-linejoin="round"/>
<circle cx="32" cy="36" r="5" fill="#ff5d73"/>
</svg>"""

static var _cache := {}


## Texture of an SVG above, rendered at `px` pixels square (with mipmaps, so it also looks
## smooth when drawn smaller)
static func tex(svg: String, px: int) -> Texture2D:
	var key := "%d@%d" % [svg.hash(), px]
	if _cache.has(key):
		return _cache[key]
	var img := Image.new()
	img.load_svg_from_string(svg, px / 64.0)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t
