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

## Power-up icons (drawn inside a white disc with a coloured ring)
const ICONS := {
	"speed": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M37 4 L14 36 L29 36 L24 60 L50 26 L34 26 Z" fill="#ffb84d" stroke="#d27a06" stroke-width="3" stroke-linejoin="round"/>
</svg>""",
	"shield": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M32 5 L54 13 L54 30 C54 45 44 55 32 60 C20 55 10 45 10 30 L10 13 Z" fill="#4f8cff" stroke="#2f5fbf" stroke-width="3" stroke-linejoin="round"/>
<path d="M22 32 L29 39 L43 24" fill="none" stroke="#ffffff" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>""",
	"freeze": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<g stroke="#1fa6d6" stroke-width="5" stroke-linecap="round" fill="none">
<path d="M32 6 V58 M9.5 19 L54.5 45 M9.5 45 L54.5 19"/>
<path d="M25 11 L32 18 L39 11 M25 53 L32 46 L39 53 M11 29 L20 31 L17 22 M53 35 L44 33 L47 42 M11 35 L20 33 L17 42 M53 29 L44 31 L47 22"/>
</g>
</svg>""",
	"ghost": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M12 58 L12 30 C12 17 21 8 32 8 C43 8 52 17 52 30 L52 58 L45 52 L38 58 L32 52 L26 58 L19 52 Z" fill="#8d7bd6" stroke="#6a57b8" stroke-width="3" stroke-linejoin="round"/>
<circle cx="24" cy="29" r="5" fill="#ffffff"/><circle cx="40" cy="29" r="5" fill="#ffffff"/>
<circle cx="25" cy="30" r="2.5" fill="#26304a"/><circle cx="41" cy="30" r="2.5" fill="#26304a"/>
</svg>""",
	"paint": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<g fill="#ff5d9e" stroke="#d6307a" stroke-width="2.5">
<circle cx="32" cy="34" r="16"/><circle cx="14" cy="20" r="6"/><circle cx="52" cy="18" r="5"/><circle cx="54" cy="46" r="6"/><circle cx="12" cy="48" r="5"/><circle cx="32" cy="8" r="4"/>
</g>
<ellipse cx="26" cy="28" rx="5" ry="3" fill="#ffffff" fill-opacity="0.6" transform="rotate(-30 26 28)"/>
</svg>""",
}

const COIN := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<circle cx="32" cy="34" r="28" fill="#c98a00"/>
<circle cx="32" cy="31" r="28" fill="#ffc93c"/>
<circle cx="32" cy="31" r="20" fill="none" stroke="#e6a800" stroke-width="4"/>
<path d="M28 20 L28 42 M36 20 L36 42" stroke="#e6a800" stroke-width="4" stroke-linecap="round"/>
<ellipse cx="22" cy="18" rx="8" ry="4" fill="#ffffff" fill-opacity="0.6" transform="rotate(-35 22 18)"/>
</svg>"""

const HEART := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M32 56 C8 40 4 28 4 20 C4 10 12 4 20 4 C26 4 30 8 32 12 C34 8 38 4 44 4 C52 4 60 10 60 20 C60 28 56 40 32 56 Z" fill="#ffffff"/>
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
