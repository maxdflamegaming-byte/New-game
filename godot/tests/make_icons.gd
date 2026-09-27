extends SceneTree
## Draws the app icon from SVG and saves every size the builds and the store need:
##   godot --headless --path godot -s tests/make_icons.gd -- OUT_DIR
## assets/icon.png (512, the launcher and Google Play), assets/icon_fg.png, icon_bg.png and
## icon_mono.png (432, Android's adaptive and themed icon layers).

const DEFS := """<defs>
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#4f8cff"/><stop offset="1" stop-color="#8c5cff"/></linearGradient>
<linearGradient id="body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe07a"/><stop offset="1" stop-color="#ffac2e"/></linearGradient>
<radialGradient id="shine" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#ffffff" stop-opacity="0.9"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>
</defs>"""

## The background: a bright gradient with two patches of claimed land (drawn on a 432 canvas)
const BACK := """<rect width="432" height="432" fill="url(#bg)"/>
<g fill="#ffffff" fill-opacity="0.07">
<rect x="0" y="0" width="54" height="54"/><rect x="108" y="0" width="54" height="54"/><rect x="216" y="0" width="54" height="54"/><rect x="324" y="0" width="54" height="54"/>
<rect x="54" y="54" width="54" height="54"/><rect x="162" y="54" width="54" height="54"/><rect x="270" y="54" width="54" height="54"/><rect x="378" y="54" width="54" height="54"/>
<rect x="0" y="108" width="54" height="54"/><rect x="108" y="108" width="54" height="54"/><rect x="216" y="108" width="54" height="54"/><rect x="324" y="108" width="54" height="54"/>
<rect x="54" y="162" width="54" height="54"/><rect x="162" y="162" width="54" height="54"/><rect x="270" y="162" width="54" height="54"/><rect x="378" y="162" width="54" height="54"/>
<rect x="0" y="216" width="54" height="54"/><rect x="108" y="216" width="54" height="54"/><rect x="216" y="216" width="54" height="54"/><rect x="324" y="216" width="54" height="54"/>
<rect x="54" y="270" width="54" height="54"/><rect x="162" y="270" width="54" height="54"/><rect x="270" y="270" width="54" height="54"/><rect x="378" y="270" width="54" height="54"/>
<rect x="0" y="324" width="54" height="54"/><rect x="108" y="324" width="54" height="54"/><rect x="216" y="324" width="54" height="54"/><rect x="324" y="324" width="54" height="54"/>
<rect x="54" y="378" width="54" height="54"/><rect x="162" y="378" width="54" height="54"/><rect x="270" y="378" width="54" height="54"/><rect x="378" y="378" width="54" height="54"/>
</g>
<path d="M-20 262 L150 262 L150 316 L204 316 L204 452 L-20 452 Z" fill="#d27a06"/>
<path d="M-20 244 L150 244 L150 298 L204 298 L204 452 L-20 452 Z" fill="#ffb84d"/>
<path d="M-20 244 L150 244 L150 252 L-20 252 Z M150 298 L204 298 L204 306 L150 306 Z" fill="#ffffff" fill-opacity="0.35"/>
<path d="M270 -20 L452 -20 L452 150 L324 150 L324 112 L270 112 Z" fill="#1c9488"/>
<path d="M270 -20 L452 -20 L452 132 L324 132 L324 94 L270 94 Z" fill="#2ec4b6"/>
<path d="M270 94 L324 94 L324 102 L270 102 Z M324 132 L452 132 L452 140 L324 140 Z" fill="#ffffff" fill-opacity="0"/>
<path d="M340 370 L452 370 L452 452 L340 452 Z" fill="#c42f4d"/>
<path d="M340 352 L452 352 L452 452 L340 452 Z" fill="#ff5d73"/>
<path d="M340 352 L452 352 L452 360 L340 360 Z" fill="#ffffff" fill-opacity="0.35"/>"""

## The hero: a glossy square leaving a trail, centred in the safe zone of the icon
const HERO := """<path d="M150 262 C 150 150, 232 110, 262 170" fill="none" stroke="#ffc43d" stroke-opacity="0.92" stroke-width="44" stroke-linecap="round"/>
<path d="M150 262 C 150 150, 232 110, 262 170" fill="none" stroke="#ffffff" stroke-opacity="0.75" stroke-width="10" stroke-linecap="round"/>
<rect x="176" y="176" width="136" height="136" rx="32" fill="#c26a00"/>
<rect x="176" y="160" width="136" height="136" rx="32" fill="url(#body)"/>
<ellipse cx="212" cy="184" rx="26" ry="11" fill="url(#shine)" transform="rotate(-20 212 184)"/>
<circle cx="220" cy="226" r="21" fill="#ffffff"/><circle cx="270" cy="226" r="21" fill="#ffffff"/>
<circle cx="226" cy="222" r="11" fill="#26304a"/><circle cx="276" cy="222" r="11" fill="#26304a"/>
<circle cx="222" cy="218" r="4" fill="#ffffff"/><circle cx="272" cy="218" r="4" fill="#ffffff"/>
<path d="M232 258 C 240 268, 252 268, 260 258" fill="none" stroke="#26304a" stroke-width="6" stroke-linecap="round"/>"""

## The themed (monochrome) icon: the same shapes in white; Android tints them
const MONO := """<path d="M150 262 C 150 150, 232 110, 262 170" fill="none" stroke="#ffffff" stroke-opacity="0.6" stroke-width="44" stroke-linecap="round"/>
<path fill-rule="evenodd" fill="#ffffff" d="M208 160 L280 160 Q312 160 312 192 L312 264 Q312 296 280 296 L208 296 Q176 296 176 264 L176 192 Q176 160 208 160 Z M220 205 A21 21 0 1 0 220.1 205 Z M270 205 A21 21 0 1 0 270.1 205 Z"/>"""


func _svg(body: String) -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 432 432">' + DEFS + body + "</svg>"


func _save(svg: String, px: int, path: String) -> void:
	var img := Image.new()
	img.load_svg_from_string(svg, px / 432.0)
	img.save_png(path)
	print("saved ", path, " ", img.get_size())


func _initialize() -> void:
	var out := "res://assets"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	_save(_svg(BACK), 432, out + "/icon_bg.png")
	_save(_svg(HERO), 432, out + "/icon_fg.png")
	_save(_svg(MONO), 432, out + "/icon_mono.png")
	_save(_svg(BACK + HERO), 512, out + "/icon.png")
	quit()
