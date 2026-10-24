class_name UISkin
extends RefCounted
## The look of buttons and panels: drawn once in code as small pictures (a glossy face with a
## light-to-dark gradient, a shine across the top, a darker "lip" underneath that makes it look
## pressable, an outline and a soft shadow) and stretched to any size without stretching the
## rounded corners. No image files.

## Each button colour: the face's top and bottom, the lip under it, the outline, and the
## outline for text on it
const COLORS := {
	"yellow": {"top": "#ffe766", "bottom": "#ffb21a", "lip": "#e08a0c", "line": "#9c5200", "text": "#a85d00"},
	"green": {"top": "#93f26c", "bottom": "#40c23a", "lip": "#2b9530", "line": "#1d6623", "text": "#22742a"},
	"red": {"top": "#ff8f80", "bottom": "#f2474c", "lip": "#c22f3c", "line": "#86182a", "text": "#a3202b"},
	"blue": {"top": "#86d8ff", "bottom": "#3a9df3", "lip": "#2468c8", "line": "#163f8c", "text": "#1b4ea0"},
	"orange": {"top": "#ffb36b", "bottom": "#ff7f2a", "lip": "#d65d14", "line": "#8f3a06", "text": "#a3480b"},
	"purple": {"top": "#c6a6ff", "bottom": "#8a63f2", "lip": "#6343c4", "line": "#3d2585", "text": "#4a2fa3"},
	"white": {"top": "#ffffff", "bottom": "#e3ecfa", "lip": "#b4c3dd", "line": "#7f93b8", "text": "#2160b8"},
	"gray": {"top": "#d4deec", "bottom": "#aebdd3", "lip": "#8596b2", "line": "#5f7091", "text": "#56678a"},
}
const PANEL := {"top": "#4fb0ff", "bottom": "#2a7ee4", "rim": "#b3e1ff", "line": "#123f91"}

const SIZE := 80          # the pictures are SIZE x SIZE (plus room for the shadow)
const RADIUS := 26.0
const LIP := 8.0
const PAD := 8            # transparent room around the picture for the shadow

static var _cache := {}


## A button's look in one colour: "normal", "hover", "pressed" or "disabled"
static func button(color: String, state := "normal") -> StyleBoxTexture:
	var key := "btn:%s:%s" % [color, state]
	if _cache.has(key):
		return _cache[key]
	var c: Dictionary = COLORS.get(color, COLORS.blue)
	if state == "disabled":
		c = COLORS.gray
	var top := Color(c.top)
	var bottom := Color(c.bottom)
	if state == "hover":
		top = top.lightened(0.08)
		bottom = bottom.lightened(0.08)
	var pressed := state == "pressed"
	var lip := 3.0 if pressed else LIP
	var img := _draw(top, bottom, Color(c.lip), Color(c.line), lip, LIP - lip, true, 0.22)
	var sb := _box(img, RADIUS, LIP)
	sb.content_margin_top = 8 + (LIP - lip)
	sb.content_margin_bottom = 10 + lip
	_cache[key] = sb
	return sb


## A panel (the cards the screens are made of): blue glass with a light rim
static func panel() -> StyleBoxTexture:
	if _cache.has("panel"):
		return _cache.panel
	var img := _draw(Color(PANEL.top), Color(PANEL.bottom), Color(PANEL.bottom).darkened(0.25), Color(PANEL.line), 6.0, 0.0, false, 0.3, Color(PANEL.rim))
	var sb := _box(img, RADIUS, 6.0)
	sb.set_content_margin_all(22)
	sb.content_margin_bottom = 28
	_cache.panel = sb
	return sb


## A small flat-topped pill for numbers (coins, level, time): one of COLORS, no shine
static func pill(color: String) -> StyleBoxTexture:
	var key := "pill:" + color
	if _cache.has(key):
		return _cache[key]
	var c: Dictionary = COLORS.get(color, COLORS.blue)
	var img := _draw(Color(c.top), Color(c.bottom), Color(c.lip), Color(c.line), 4.0, 0.0, false, 0.2, Color(0, 0, 0, 0), 15.0)
	var sb := _box(img, 15.0, 4.0)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 4
	sb.content_margin_bottom = 8
	_cache[key] = sb
	return sb


static func _box(img: Image, r: float, lip: float) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	var m := r + PAD + 2
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m + lip
	# The shadow room is drawn outside the control's own rectangle
	sb.expand_margin_left = PAD
	sb.expand_margin_right = PAD
	sb.expand_margin_top = PAD
	sb.expand_margin_bottom = PAD
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	return sb


## Draws the picture: a soft shadow, then the lip, then the face with its gradient and shine,
## all inside one rounded rectangle with an outline. drop: how far the face sits lower
## (a pressed button). rim: an inner light line (panels).
static func _draw(top: Color, bottom: Color, lip_c: Color, line: Color, lip: float, drop: float, shine: bool, shadow_a: float, rim := Color(0, 0, 0, 0), radius := RADIUS) -> Image:
	var w := SIZE + PAD * 2
	var h := SIZE + PAD * 2
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var x0 := float(PAD)
	var y0 := float(PAD) + drop
	var x1 := float(PAD + SIZE)
	var y1 := float(PAD + SIZE)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# The shadow: the whole shape, a little lower, softly blurred
			var ds := _rbox(p - Vector2(0, 4), x0, y0, x1, y1, radius)
			var col := Color(0.04, 0.08, 0.2, shadow_a * (1.0 - smoothstep(-3.0, 6.0, ds)))
			var d_all := _rbox(p, x0, y0, x1, y1, radius)
			if d_all < 1.0:
				var d_face := _rbox(p, x0, y0, x1, y1 - lip, radius)
				var c := lip_c
				if d_face < 1.0:
					var t := clampf((p.y - y0) / maxf(1.0, y1 - lip - y0), 0.0, 1.0)
					var face := top.lerp(bottom, t * t * (3.0 - 2.0 * t))
					if shine:
						# A soft shine across the top half
						var ds2 := _rbox(p, x0 + 7, y0 + 5, x1 - 7, y0 + (y1 - lip - y0) * 0.46, radius - 8)
						face = face.lerp(Color.WHITE, 0.28 * (1.0 - smoothstep(-1.0, 1.0, ds2)))
					if rim.a > 0:
						face = face.lerp(rim, 1.0 - smoothstep(2.5, 4.0, -d_face))
					c = lip_c.lerp(face, 1.0 - smoothstep(-0.5, 0.5, d_face))
				# The outline
				c = c.lerp(line, smoothstep(-4.0, -2.5, d_all))
				var a := 1.0 - smoothstep(-0.5, 0.5, d_all)
				col = Color(c.r, c.g, c.b, 1.0).lerp(col, 1.0 - a) if a < 1.0 else Color(c.r, c.g, c.b, 1.0)
				col.a = maxf(a, col.a)
			img.set_pixel(x, y, col)
	return img


## Signed distance from p to a rounded rectangle (negative inside)
static func _rbox(p: Vector2, x0: float, y0: float, x1: float, y1: float, r: float) -> float:
	var c := Vector2((x0 + x1) / 2, (y0 + y1) / 2)
	var half := Vector2((x1 - x0) / 2, (y1 - y0) / 2)
	var q := (p - c).abs() - half + Vector2(r, r)
	return Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0.0) - r
