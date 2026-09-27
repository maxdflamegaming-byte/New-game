class_name Cosmetics
extends RefCounted
## Everything the shop sells: skins (patterns and outfits on your square), trail effects
## (particles that stream out while your trail is out) and pets that follow you around.
## The drawing lives here, so the game and the shop's previews look exactly the same.

const SKINS := {
	"plain": {"name": "Classic", "price": 0},
	"stripes": {"name": "Stripes", "price": 150},
	"dots": {"name": "Dots", "price": 150},
	"shades": {"name": "Shades", "price": 250},
	"cat": {"name": "Kitty", "price": 300},
	"ninja": {"name": "Ninja", "price": 350},
	"robot": {"name": "Robot", "price": 400},
	"galaxy": {"name": "Galaxy", "price": 600},
	"rainbow": {"name": "Rainbow", "price": 800},
}

const TRAILS := {
	"none": {"name": "Plain", "price": 0},
	"sparkle": {"name": "Sparkles", "price": 200},
	"bubbles": {"name": "Bubbles", "price": 250},
	"hearts": {"name": "Hearts", "price": 300},
	"stars": {"name": "Stars", "price": 350},
	"confetti": {"name": "Confetti", "price": 400},
	"fire": {"name": "Fire", "price": 450},
	"rainbow": {"name": "Rainbow", "price": 600},
}

const PETS := {
	"none": {"name": "No pet", "price": 0},
	"chick": {"name": "Chick", "price": 300},
	"slime": {"name": "Slime", "price": 350},
	"ghost": {"name": "Boo", "price": 400},
	"bee": {"name": "Bee", "price": 450},
	"dragon": {"name": "Dragon", "price": 900},
}

## What each shop tab sells, and the free thing everyone starts with
const KINDS := {
	"skin": {"items": SKINS, "free": "plain", "title": "Skins"},
	"trail": {"items": TRAILS, "free": "none", "title": "Trails"},
	"pet": {"items": PETS, "free": "none", "title": "Pets"},
}

const INK := Color("#26304a")

# ---------- Sprites ----------

## Patterns laid over the body (clipped to its rounded square, drawn white and tinted)
const STRIPES := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<defs><clipPath id="c"><rect x="1" y="1" width="62" height="62" rx="15"/></clipPath></defs>
<g clip-path="url(#c)" fill="#ffffff">
<path d="M-10 18 L18 -10 L28 -10 L-10 28 Z"/><path d="M-10 42 L42 -10 L52 -10 L-10 52 Z"/>
<path d="M2 64 L66 0 L74 0 L74 8 L18 64 Z"/><path d="M26 74 L74 26 L74 36 L36 74 Z"/><path d="M50 74 L74 50 L74 60 L60 74 Z"/>
</g></svg>"""

const DOTS := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<defs><clipPath id="c"><rect x="1" y="1" width="62" height="62" rx="15"/></clipPath></defs>
<g clip-path="url(#c)" fill="#ffffff">
<circle cx="10" cy="10" r="5"/><circle cx="32" cy="8" r="5"/><circle cx="54" cy="10" r="5"/>
<circle cx="21" cy="24" r="5"/><circle cx="43" cy="24" r="5"/><circle cx="64" cy="24" r="5"/><circle cx="0" cy="24" r="5"/>
<circle cx="10" cy="40" r="5"/><circle cx="32" cy="40" r="5"/><circle cx="54" cy="40" r="5"/>
<circle cx="21" cy="56" r="5"/><circle cx="43" cy="56" r="5"/><circle cx="64" cy="56" r="5"/><circle cx="0" cy="56" r="5"/>
</g></svg>"""

const GALAXY := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<defs>
<clipPath id="c"><rect x="1" y="1" width="62" height="62" rx="15"/></clipPath>
<radialGradient id="n" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#ffffff" stop-opacity="0.9"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>
</defs>
<g clip-path="url(#c)">
<ellipse cx="22" cy="44" rx="26" ry="14" fill="url(#n)" transform="rotate(-25 22 44)"/>
<ellipse cx="46" cy="18" rx="18" ry="10" fill="url(#n)" transform="rotate(-25 46 18)"/>
</g></svg>"""

const STARFIELD := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<g fill="#ffffff">
<circle cx="12" cy="14" r="1.6"/><circle cx="50" cy="42" r="1.4"/><circle cx="28" cy="52" r="1.2"/><circle cx="56" cy="12" r="1.2"/>
<circle cx="8" cy="36" r="1.1"/><circle cx="38" cy="30" r="1"/><circle cx="20" cy="30" r="0.9"/>
<path d="M44 50 L45.5 54.5 L50 56 L45.5 57.5 L44 62 L42.5 57.5 L38 56 L42.5 54.5 Z" transform="translate(-2 -2) scale(1)"/>
<path d="M18 4 L19.3 8.7 L24 10 L19.3 11.3 L18 16 L16.7 11.3 L12 10 L16.7 8.7 Z" transform="translate(16 6)"/>
</g></svg>"""

const RAINBOW := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<defs>
<clipPath id="c"><rect x="1" y="1" width="62" height="62" rx="15"/></clipPath>
<linearGradient id="r" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="#ff5d73"/><stop offset="0.2" stop-color="#ffa23c"/><stop offset="0.4" stop-color="#ffe14d"/>
<stop offset="0.6" stop-color="#4ed8a0"/><stop offset="0.8" stop-color="#4f8cff"/><stop offset="1" stop-color="#a66bff"/>
</linearGradient>
</defs>
<rect x="1" y="1" width="62" height="62" rx="15" fill="url(#r)"/>
</svg>"""

## Particles for the trail effects
const STAR := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M32 4 L40 23 L60 24 L44 37 L50 58 L32 46 L14 58 L20 37 L4 24 L24 23 Z" fill="#ffffff" stroke-linejoin="round"/>
</svg>"""

const BUBBLE := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<circle cx="32" cy="32" r="27" fill="#ffffff" fill-opacity="0.18" stroke="#ffffff" stroke-width="5"/>
<ellipse cx="22" cy="20" rx="8" ry="5" fill="#ffffff" transform="rotate(-35 22 20)"/>
</svg>"""

## Pets (drawn as they are, except the slime, which is tinted your colour)
const CHICK := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M26 6 C28 1 33 1 33 7 C36 3 40 5 36 10" fill="none" stroke="#f0a800" stroke-width="3" stroke-linecap="round"/>
<ellipse cx="32" cy="36" rx="24" ry="23" fill="#ffd93d" stroke="#e8a800" stroke-width="3"/>
<path d="M9 38 C3 34 4 44 12 46 Z" fill="#ffc21a" stroke="#e8a800" stroke-width="2.5" stroke-linejoin="round"/>
<path d="M55 38 C61 34 60 44 52 46 Z" fill="#ffc21a" stroke="#e8a800" stroke-width="2.5" stroke-linejoin="round"/>
<circle cx="23" cy="31" r="4.5" fill="#26304a"/><circle cx="41" cy="31" r="4.5" fill="#26304a"/>
<circle cx="24.5" cy="29.5" r="1.6" fill="#ffffff"/><circle cx="42.5" cy="29.5" r="1.6" fill="#ffffff"/>
<path d="M27 38 L37 38 L32 45 Z" fill="#ff8a1f" stroke="#e06a00" stroke-width="2" stroke-linejoin="round"/>
<circle cx="16" cy="40" r="4" fill="#ff9aa8" fill-opacity="0.7"/><circle cx="48" cy="40" r="4" fill="#ff9aa8" fill-opacity="0.7"/>
</svg>"""

const SLIME := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M6 54 C4 36 14 12 32 12 C50 12 60 36 58 54 C58 59 54 60 50 58 C46 56 44 60 38 60 C32 60 30 56 26 58 C20 61 16 58 12 59 C8 60 6 58 6 54 Z" fill="#ffffff"/>
<ellipse cx="22" cy="24" rx="7" ry="4" fill="#ffffff" transform="rotate(-30 22 24)"/>
</svg>"""

const SLIME_FACE := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<ellipse cx="22" cy="24" rx="7" ry="4" fill="#ffffff" fill-opacity="0.7" transform="rotate(-30 22 24)"/>
<circle cx="24" cy="38" r="4.5" fill="#26304a"/><circle cx="40" cy="38" r="4.5" fill="#26304a"/>
<circle cx="25.5" cy="36.5" r="1.6" fill="#ffffff"/><circle cx="41.5" cy="36.5" r="1.6" fill="#ffffff"/>
<path d="M28 46 C30 49 34 49 36 46" fill="none" stroke="#26304a" stroke-width="2.5" stroke-linecap="round"/>
</svg>"""

const BOO := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M10 58 L10 30 C10 16 20 6 32 6 C44 6 54 16 54 30 L54 58 L47 52 L40 58 L32 52 L24 58 L17 52 Z" fill="#ffffff" stroke="#c9d2ea" stroke-width="3" stroke-linejoin="round"/>
<ellipse cx="24" cy="28" rx="4.5" ry="6" fill="#26304a"/><ellipse cx="40" cy="28" rx="4.5" ry="6" fill="#26304a"/>
<ellipse cx="32" cy="40" rx="4" ry="5" fill="#26304a"/>
<circle cx="17" cy="36" r="4" fill="#ff9aa8" fill-opacity="0.6"/><circle cx="47" cy="36" r="4" fill="#ff9aa8" fill-opacity="0.6"/>
</svg>"""

const BEE := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<defs><clipPath id="b"><ellipse cx="32" cy="38" rx="24" ry="19"/></clipPath></defs>
<ellipse cx="32" cy="38" rx="24" ry="19" fill="#ffd23f"/>
<g clip-path="url(#b)" fill="#2a2a3a"><rect x="24" y="15" width="8" height="46"/><rect x="40" y="15" width="8" height="46"/></g>
<ellipse cx="32" cy="38" rx="24" ry="19" fill="none" stroke="#2a2a3a" stroke-width="3"/>
<path d="M56 38 L63 38" stroke="#2a2a3a" stroke-width="3" stroke-linecap="round"/>
<circle cx="15" cy="34" r="4" fill="#26304a"/><circle cx="16.3" cy="32.6" r="1.4" fill="#ffffff"/>
<path d="M12 20 C10 12 6 12 5 14 M18 19 C19 11 23 10 24 12" fill="none" stroke="#2a2a3a" stroke-width="2.5" stroke-linecap="round"/>
</svg>"""

const WING := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<ellipse cx="32" cy="32" rx="28" ry="18" fill="#ffffff" fill-opacity="0.75" stroke="#b8c8e8" stroke-width="3"/>
</svg>"""

const DRAGON := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M46 50 C58 52 62 44 58 40 C56 46 50 46 46 44 Z" fill="#3cc47a" stroke="#1f8f50" stroke-width="2.5" stroke-linejoin="round"/>
<ellipse cx="34" cy="42" rx="18" ry="15" fill="#4ed88a" stroke="#1f8f50" stroke-width="3"/>
<ellipse cx="34" cy="46" rx="10" ry="8" fill="#c9f5d6"/>
<circle cx="24" cy="24" r="15" fill="#4ed88a" stroke="#1f8f50" stroke-width="3"/>
<path d="M14 14 L12 4 L20 11 M28 10 L32 1 L34 12" fill="#ffd23f" stroke="#e0a800" stroke-width="2.5" stroke-linejoin="round"/>
<ellipse cx="12" cy="28" rx="7" ry="5" fill="#6ce39e" stroke="#1f8f50" stroke-width="2.5"/>
<circle cx="10" cy="27" r="1.3" fill="#1f5f3a"/>
<circle cx="24" cy="21" r="4.5" fill="#26304a"/><circle cx="25.5" cy="19.5" r="1.6" fill="#ffffff"/>
<path d="M36 30 L40 26 L42 32 L46 29 L46 35" fill="#ff8a4d" stroke="#d65a1f" stroke-width="2" stroke-linejoin="round"/>
</svg>"""

const DRAGON_WING := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M6 58 C8 30 24 8 58 6 C50 16 54 24 46 30 C48 38 40 42 38 48 C30 48 22 52 6 58 Z" fill="#8cf0b4" stroke="#1f8f50" stroke-width="3" stroke-linejoin="round"/>
<path d="M12 52 C24 36 36 22 54 10 M20 50 C30 42 38 36 44 30" fill="none" stroke="#1f8f50" stroke-width="2" stroke-linecap="round"/>
</svg>"""

const PET_SVGS := {"chick": CHICK, "slime": SLIME, "ghost": BOO, "bee": BEE, "dragon": DRAGON}


static func items(kind: String) -> Dictionary:
	return KINDS[kind].items


static func price(kind: String, id: String) -> int:
	return items(kind).get(id, {}).get("price", 0)


## Bots get dressed up too, so you can see what the shop has
static func dress_bot(p: Player) -> void:
	p.skin = _pick(SKINS, 0.55)
	p.trail_fx = _pick(TRAILS, 0.35)
	p.pet = _pick(PETS, 0.25)


static func _pick(from: Dictionary, chance: float) -> String:
	var keys := from.keys()
	if randf() > chance:
		return keys[0]
	return keys[1 + randi() % (keys.size() - 1)]


## Colour of a rainbow that shifts over time (`u` is 0..1 along the trail)
static func rainbow(t: float, u: float = 0.0) -> Color:
	return Color.from_hsv(fposmod(t * 0.35 + u, 1.0), 0.68, 1.0)


# ---------- Drawing the square ----------

## Draws a square player (body, skin, gloss, eyes and outfit) on `ci`, centred on `at`.
## `extra` colours are washed over the body after the gloss (frozen, hit flash).
static func draw_square(ci: CanvasItem, at: Vector2, s: float, color: Color, dark: Color, skin: String,
		look: Vector2, t: float, rot := 0.0, squash := 0.0, blink := false, extra: Array = []) -> void:
	var px := 128 if s < 80 and Gfx.level < Gfx.ULTRA else 256
	var body := Art.tex(Art.BODY, px)
	var side := Art.tex(Art.SIDE, px)
	var r := Rect2(-s / 2, -s / 2, s, s)
	ci.draw_set_transform(at, rot, Vector2(1 + squash * 0.12, 1 - squash * 0.12))
	var base := color
	var under := dark
	if skin == "galaxy":
		base = Color("#2b2458").lerp(color, 0.25)
		under = base.darkened(0.45)
	# Cat ears poke out behind the top edge
	if skin == "cat":
		for sx: float in [-1.0, 1.0]:
			var ear := PackedVector2Array([Vector2(sx * s * 0.42, -s * 0.3), Vector2(sx * s * 0.34, -s * 0.72), Vector2(sx * s * 0.08, -s * 0.44)])
			ci.draw_colored_polygon(ear, dark)
			var inner := PackedVector2Array([Vector2(sx * s * 0.36, -s * 0.36), Vector2(sx * s * 0.32, -s * 0.6), Vector2(sx * s * 0.16, -s * 0.44)])
			ci.draw_colored_polygon(inner, Color("#ff9aa8"))
	# Robot antenna with a blinking light
	if skin == "robot":
		ci.draw_line(Vector2(0, -s * 0.5), Vector2(0, -s * 0.78), Color("#8d97ab"), maxf(2.0, s * 0.06), true)
		var on := fmod(t, 1.0) < 0.5
		ci.draw_circle(Vector2(0, -s * 0.82), s * 0.09, Color("#ff3c50") if on else Color("#8a2030"), true, -1, true)
	ci.draw_texture_rect(side, Rect2(r.position + Vector2(0, s * 0.17), r.size), false, under)
	ci.draw_texture_rect(body, r, false, base)
	match skin:
		"stripes":
			ci.draw_texture_rect(Art.tex(STRIPES, px), r, false, Color(1, 1, 1, 0.38))
		"dots":
			ci.draw_texture_rect(Art.tex(DOTS, px), r, false, Color(dark, 0.55))
		"galaxy":
			ci.draw_texture_rect(Art.tex(GALAXY, px), r, false, Color(color, 0.8))
			ci.draw_texture_rect(Art.tex(STARFIELD, px), r, false, Color(1, 1, 1, 0.65 + 0.35 * sin(t * 3.0)))
		"rainbow":
			# The colours slide round as it moves
			var k := 0.55 + 0.2 * sin(t * 2.0)
			ci.draw_texture_rect(Art.tex(RAINBOW, px), r, false, Color(1, 1, 1, k))
		"robot":
			# Panel lines and bolts
			ci.draw_rect(Rect2(-s * 0.36, s * 0.14, s * 0.72, s * 0.2), Color(0.1, 0.12, 0.2, 0.25), true)
			for k in 4:
				ci.draw_line(Vector2(-s * 0.26 + k * s * 0.17, s * 0.16), Vector2(-s * 0.26 + k * s * 0.17, s * 0.32), Color(1, 1, 1, 0.5), maxf(1.5, s * 0.03), true)
			for c in [Vector2(-0.38, -0.38), Vector2(0.38, -0.38), Vector2(-0.38, 0.38), Vector2(0.38, 0.38)]:
				ci.draw_circle(c * s, s * 0.04, Color(0.1, 0.12, 0.2, 0.4), true, -1, true)
	ci.draw_texture_rect(Art.tex(Art.GLOSS, px), r, false)
	for c in extra:
		ci.draw_texture_rect(side, r, false, c)
	# Ninja headband across the forehead, its tails flapping behind
	if skin == "ninja":
		var band := Color("#e8283c")
		ci.draw_rect(Rect2(-s / 2, -s * 0.3, s, s * 0.17), band, true)
		ci.draw_rect(Rect2(-s / 2, -s * 0.3, s, s * 0.04), band.lightened(0.3), true)
		var back := -look if look.length() > 0.1 else Vector2(1, 0)
		var knot := Vector2(clampf(back.x, -1, 1) * s * 0.46, -s * 0.22)
		for k: float in [-1.0, 1.0]:
			var wave := sin(t * 14.0 + k) * s * 0.08
			var tip := knot + back * s * 0.5 + back.orthogonal() * (k * s * 0.12 + wave)
			ci.draw_line(knot, tip, band, maxf(2.0, s * 0.09), true)
	# Eyes look the way it's heading
	var e_y := -s * 0.05
	for sx: float in [-1.0, 1.0]:
		var e := Vector2(sx * s * 0.2, e_y) + look * s * 0.08
		if skin == "robot":
			ci.draw_rect(Rect2(e - Vector2(s * 0.12, s * 0.09), Vector2(s * 0.24, s * 0.18)), INK, true)
			var glow := Color("#5df2ff") if not blink else Color("#2a6f78")
			ci.draw_rect(Rect2(e - Vector2(s * 0.08, s * 0.05) + look * s * 0.03, Vector2(s * 0.16, s * 0.1)), glow, true)
		elif blink:
			ci.draw_rect(Rect2(e - Vector2(s * 0.11, s * 0.025), Vector2(s * 0.22, s * 0.05)), INK)
		else:
			ci.draw_circle(e, s * 0.14, Color.WHITE, true, -1, true)
			ci.draw_circle(e + look * s * 0.06, s * 0.07, INK, true, -1, true)
			ci.draw_circle(e + look * s * 0.06 + Vector2(-s * 0.025, -s * 0.03), s * 0.025, Color.WHITE, true, -1, true)
	match skin:
		"shades":
			var off := look * s * 0.06
			for sx: float in [-1.0, 1.0]:
				var c := Vector2(sx * s * 0.2, e_y) + off
				ci.draw_rect(Rect2(c - Vector2(s * 0.17, s * 0.11), Vector2(s * 0.34, s * 0.22)), Color("#15182a"), true)
				ci.draw_line(c + Vector2(-s * 0.1, -s * 0.06), c + Vector2(-s * 0.02, -s * 0.06), Color(1, 1, 1, 0.55), maxf(1.5, s * 0.035), true)
			ci.draw_line(Vector2(-s * 0.04, e_y - s * 0.05) + off, Vector2(s * 0.04, e_y - s * 0.05) + off, Color("#15182a"), maxf(2.0, s * 0.05), true)
		"cat":
			var nose := Vector2(0, s * 0.1) + look * s * 0.06
			ci.draw_circle(nose, s * 0.045, Color("#ff7a8f"), true, -1, true)
			for sx: float in [-1.0, 1.0]:
				for k: float in [-1.0, 1.0]:
					ci.draw_line(nose + Vector2(sx * s * 0.1, 0), nose + Vector2(sx * s * 0.34, k * s * 0.06), Color(INK, 0.7), maxf(1.2, s * 0.022), true)
	ci.draw_set_transform(Vector2.ZERO)


# ---------- Pets ----------

## Draws a pet `s` wide at `at`, facing left or right, flapping and bobbing with time
static func draw_pet(ci: CanvasItem, at: Vector2, s: float, pet: String, color: Color, t: float, facing := 1.0) -> void:
	if not PET_SVGS.has(pet):
		return
	var px := 128 if s < 80 else 256
	var bob := sin(t * 5.0) * s * 0.08
	var flip := Vector2(-1 if facing < 0 else 1, 1)
	# A little shadow on the ground under it
	ci.draw_set_transform(at + Vector2(0, s * 0.62), 0, Vector2(1, 0.4))
	ci.draw_circle(Vector2.ZERO, s * 0.32 - bob * 0.5, Color(0.06, 0.08, 0.16, 0.16), true, -1, true)
	match pet:
		"slime":
			# Squishes as it hops
			var sq := absf(sin(t * 6.0))
			var sc := Vector2(1.0 + (1.0 - sq) * 0.14, 0.86 + sq * 0.14)
			ci.draw_set_transform(at + Vector2(0, s * 0.5 * (1 - sc.y)), 0, sc * flip)
			ci.draw_texture_rect(Art.tex(SLIME, px), Rect2(-s / 2, -s / 2, s, s), false, Color(color.lightened(0.25), 0.9))
			ci.draw_texture_rect(Art.tex(SLIME_FACE, px), Rect2(-s / 2, -s / 2, s, s), false)
		"ghost":
			ci.draw_set_transform(at + Vector2(0, bob * 1.6 - s * 0.1), sin(t * 2.0) * 0.12, flip)
			ci.draw_texture_rect(Art.tex(BOO, px), Rect2(-s / 2, -s / 2, s, s), false, Color(1, 1, 1, 0.78 + 0.18 * sin(t * 3.0)))
		"bee":
			var buzz := Vector2(sin(t * 9.0) * s * 0.06, sin(t * 13.0) * s * 0.08 - s * 0.2)
			ci.draw_set_transform(at + buzz, 0, flip)
			var flap := 0.5 + 0.5 * sin(t * 50.0)
			ci.draw_texture_rect(Art.tex(WING, px), Rect2(-s * 0.1, -s * (0.45 + 0.1 * flap), s * 0.42, s * (0.26 + 0.12 * flap)), false)
			ci.draw_texture_rect(Art.tex(BEE, px), Rect2(-s / 2, -s / 2, s, s), false)
			ci.draw_texture_rect(Art.tex(WING, px), Rect2(s * 0.02, -s * (0.4 + 0.1 * flap), s * 0.4, s * (0.24 + 0.1 * flap)), false, Color(1, 1, 1, 0.8))
		"dragon":
			ci.draw_set_transform(at + Vector2(0, bob * 1.4 - s * 0.14), 0, flip)
			var flap := sin(t * 8.0)
			var wing := Art.tex(DRAGON_WING, px)
			ci.draw_set_transform(at + Vector2(flip.x * s * 0.1, bob * 1.4 - s * 0.2), flip.x * (-0.3 + flap * 0.35), flip)
			ci.draw_texture_rect(wing, Rect2(-s * 0.05, -s * 0.62, s * 0.62, s * 0.62), false, Color(0.8, 0.9, 0.85))
			ci.draw_set_transform(at + Vector2(0, bob * 1.4 - s * 0.14), 0, flip)
			ci.draw_texture_rect(Art.tex(DRAGON, px), Rect2(-s / 2, -s / 2, s, s), false)
			ci.draw_set_transform(at + Vector2(flip.x * s * 0.14, bob * 1.4 - s * 0.2), flip.x * (-0.1 + flap * 0.4), flip)
			ci.draw_texture_rect(wing, Rect2(-s * 0.05, -s * 0.62, s * 0.62, s * 0.62), false)
		_:
			ci.draw_set_transform(at + Vector2(0, -absf(sin(t * 6.0)) * s * 0.14), sin(t * 6.0) * 0.08, flip)
			ci.draw_texture_rect(Art.tex(PET_SVGS[pet], px), Rect2(-s / 2, -s / 2, s, s), false)
	ci.draw_set_transform(Vector2.ZERO)


# ---------- Trail effects ----------

## A particle emitter for a trail effect (or null for none and the rainbow, which colours the
## trail itself). It works in world space, so particles stay where they were dropped.
static func make_emitter(fx: String, scale: float, color: Color) -> CPUParticles2D:
	if fx == "none" or fx == "rainbow" or not TRAILS.has(fx):
		return null
	var e := CPUParticles2D.new()
	e.local_coords = false
	e.emitting = false
	e.amount = 28
	e.lifetime = 0.9
	e.explosiveness = 0.0
	e.gravity = Vector2.ZERO
	e.spread = 180.0
	e.initial_velocity_min = 8.0 * scale
	e.initial_velocity_max = 28.0 * scale
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 10.0 * scale
	e.scale_amount_min = 0.22 * scale
	e.scale_amount_max = 0.4 * scale
	var fade := Curve.new()
	fade.add_point(Vector2(0, 0.3))
	fade.add_point(Vector2(0.2, 1))
	fade.add_point(Vector2(1, 0))
	e.scale_amount_curve = fade
	var ramp := Gradient.new()
	ramp.set_color(0, Color.WHITE)
	ramp.set_color(1, Color(1, 1, 1, 0))
	e.color_ramp = ramp
	e.texture = Art.tex(Art.SPARK, 64)
	match fx:
		"sparkle":
			e.color = Color("#fff4b0")
			e.angular_velocity_min = -180.0
			e.angular_velocity_max = 180.0
		"bubbles":
			e.texture = Art.tex(BUBBLE, 64)
			e.color = Color("#bfe9ff")
			e.gravity = Vector2(0, -40.0 * scale)
			e.lifetime = 1.3
			e.amount = 18
		"hearts":
			e.texture = Art.tex(Art.HEART, 64)
			e.color = Color("#ff6b9a")
			e.gravity = Vector2(0, -30.0 * scale)
			e.amount = 16
			e.lifetime = 1.1
		"stars":
			e.texture = Art.tex(STAR, 64)
			e.color = Color("#ffd23f")
			e.angular_velocity_min = -220.0
			e.angular_velocity_max = 220.0
			e.amount = 18
		"confetti":
			e.texture = Art.tex(Art.TILE, 32)
			var colors := Gradient.new()
			colors.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
			colors.colors = PackedColorArray([Color("#ff5d73"), Color("#ffd23f"), Color("#4ed8a0"), Color("#4f8cff"), Color("#a66bff")])
			e.color_initial_ramp = colors
			e.angular_velocity_min = -400.0
			e.angular_velocity_max = 400.0
			e.gravity = Vector2(0, 50.0 * scale)
			e.scale_amount_min = 0.14 * scale
			e.scale_amount_max = 0.24 * scale
			e.amount = 36
		"fire":
			e.texture = Art.tex(Art.GLOW, 64)
			var flame := Gradient.new()
			flame.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
			flame.colors = PackedColorArray([Color("#fff1a8"), Color("#ff8a1f"), Color(0.9, 0.15, 0.1, 0.0)])
			e.color_ramp = flame
			e.gravity = Vector2(0, -60.0 * scale)
			e.scale_amount_min = 0.5 * scale
			e.scale_amount_max = 0.9 * scale
			e.amount = 40
			e.lifetime = 0.7
	e.amount = Gfx.particles(e.amount)
	return e
