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

## Menu dock icons (white, tinted when drawn)
const BAG := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M22 22 C22 10 42 10 42 22" fill="none" stroke="#ffffff" stroke-width="6" stroke-linecap="round"/>
<path d="M10 22 L54 22 L50 58 L14 58 Z" fill="#ffffff" stroke="#ffffff" stroke-width="4" stroke-linejoin="round"/>
</svg>"""

const TARGET := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<circle cx="32" cy="32" r="26" fill="none" stroke="#ffffff" stroke-width="6"/>
<circle cx="32" cy="32" r="14" fill="none" stroke="#ffffff" stroke-width="6"/>
<circle cx="32" cy="32" r="5" fill="#ffffff"/>
</svg>"""

const PERSON := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<circle cx="32" cy="20" r="13" fill="#ffffff"/>
<path d="M8 60 C8 44 18 36 32 36 C46 36 56 44 56 60 Z" fill="#ffffff"/>
</svg>"""

const GEAR := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<g fill="#ffffff">
<rect x="27" y="2" width="10" height="14" rx="3"/><rect x="27" y="48" width="10" height="14" rx="3"/>
<rect x="2" y="27" width="14" height="10" rx="3"/><rect x="48" y="27" width="14" height="10" rx="3"/>
<rect x="27" y="2" width="10" height="14" rx="3" transform="rotate(45 32 32)"/><rect x="27" y="48" width="10" height="14" rx="3" transform="rotate(45 32 32)"/>
<rect x="2" y="27" width="14" height="10" rx="3" transform="rotate(45 32 32)"/><rect x="48" y="27" width="14" height="10" rx="3" transform="rotate(45 32 32)"/>
</g>
<circle cx="32" cy="32" r="20" fill="#ffffff"/>
<circle cx="32" cy="32" r="8" fill="#000000" fill-opacity="0.35"/>
</svg>"""

## Trophies: gold when you have one, grey when you don't
const TROPHY := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M16 10 L48 10 L48 26 C48 36 40 42 32 42 C24 42 16 36 16 26 Z" fill="#ffffff"/>
<path d="M16 14 L6 14 C6 26 12 30 18 30 M48 14 L58 14 C58 26 52 30 46 30" fill="none" stroke="#ffffff" stroke-width="5" stroke-linecap="round"/>
<rect x="28" y="40" width="8" height="10" fill="#ffffff"/>
<rect x="18" y="50" width="28" height="8" rx="3" fill="#ffffff"/>
<ellipse cx="25" cy="19" rx="4" ry="6" fill="#000000" fill-opacity="0.12"/>
</svg>"""

const CHECK := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<circle cx="32" cy="32" r="28" fill="#2ec48a"/>
<path d="M18 33 L28 43 L47 22" fill="none" stroke="#ffffff" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""

const FLAME := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M32 4 C36 16 50 22 50 40 C50 52 42 60 32 60 C22 60 14 52 14 40 C14 30 20 24 24 18 C26 26 28 28 32 30 C32 20 30 12 32 4 Z" fill="#ff8a1f"/>
<path d="M32 30 C36 38 42 40 42 48 C42 54 38 58 32 58 C26 58 22 54 22 48 C22 42 28 40 32 30 Z" fill="#ffd23f"/>
</svg>"""

## Mode icons (white, tinted when drawn) and the lock for things not unlocked yet
const MODE_ICONS := {
	"classic": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<rect x="12" y="6" width="6" height="54" rx="3" fill="#ffffff"/>
<path d="M18 8 C30 2 38 14 54 8 L54 34 C38 40 30 28 18 34 Z" fill="#ffffff"/>
</svg>""",
	"timed": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<rect x="26" y="2" width="12" height="7" rx="3" fill="#ffffff"/>
<circle cx="32" cy="36" r="24" fill="none" stroke="#ffffff" stroke-width="6"/>
<path d="M32 36 L32 22 M32 36 L42 42" stroke="#ffffff" stroke-width="6" stroke-linecap="round"/>
</svg>""",
	"daily": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<rect x="6" y="12" width="52" height="46" rx="8" fill="#ffffff"/>
<rect x="6" y="12" width="52" height="14" rx="6" fill="#000000" fill-opacity="0.25"/>
<rect x="16" y="4" width="7" height="16" rx="3" fill="#ffffff"/><rect x="41" y="4" width="7" height="16" rx="3" fill="#ffffff"/>
<path d="M22 42 L29 49 L43 34" fill="none" stroke="#000000" stroke-opacity="0.35" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>
</svg>""",
	"teams": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<circle cx="21" cy="20" r="10" fill="#ffffff"/><path d="M2 56 C2 42 10 34 21 34 C32 34 40 42 40 56 Z" fill="#ffffff"/>
<circle cx="45" cy="18" r="9" fill="#ffffff" fill-opacity="0.8"/><path d="M34 34 C38 31 41 30 45 30 C55 30 62 38 62 52 L42 52 C42 44 39 38 34 34 Z" fill="#ffffff" fill-opacity="0.8"/>
</svg>""",
	"boss": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M6 20 L20 32 L32 10 L44 32 L58 20 L52 52 L12 52 Z" fill="#ffffff" stroke="#ffffff" stroke-width="4" stroke-linejoin="round"/>
<rect x="12" y="46" width="40" height="8" rx="3" fill="#000000" fill-opacity="0.2"/>
</svg>""",
	"duo": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<rect x="4" y="16" width="28" height="28" rx="8" fill="#ffffff"/>
<rect x="32" y="22" width="28" height="28" rx="8" fill="#ffffff" fill-opacity="0.8"/>
<circle cx="13" cy="28" r="3" fill="#000000" fill-opacity="0.4"/><circle cx="23" cy="28" r="3" fill="#000000" fill-opacity="0.4"/>
<circle cx="41" cy="34" r="3" fill="#000000" fill-opacity="0.4"/><circle cx="51" cy="34" r="3" fill="#000000" fill-opacity="0.4"/>
</svg>""",
	"hill": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M2 58 L26 22 L36 36 L44 26 L62 58 Z" fill="#ffffff"/>
<rect x="24" y="4" width="4" height="20" fill="#ffffff"/><path d="M28 5 L42 10 L28 15 Z" fill="#ffffff"/>
</svg>""",
	"online": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<circle cx="32" cy="32" r="26" fill="none" stroke="#ffffff" stroke-width="5"/>
<ellipse cx="32" cy="32" rx="11" ry="26" fill="none" stroke="#ffffff" stroke-width="4"/>
<path d="M8 24 L56 24 M8 40 L56 40" stroke="#ffffff" stroke-width="4"/>
</svg>""",
}

const LOCK := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M18 28 L18 20 C18 6 46 6 46 20 L46 28" fill="none" stroke="#ffffff" stroke-width="7"/>
<rect x="10" y="28" width="44" height="32" rx="7" fill="#ffffff"/>
<circle cx="32" cy="42" r="5" fill="#000000" fill-opacity="0.35"/><rect x="30" y="44" width="4" height="9" fill="#000000" fill-opacity="0.35"/>
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
