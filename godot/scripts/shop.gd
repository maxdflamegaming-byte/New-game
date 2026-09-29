extends Control
## The shop: spend the coins you win on skins, trail effects and pets. A showcase at the top
## shows your square driving around in what you're wearing; tap anything to try it on (if it's
## yours) or buy it (if you have the coins).

var m # the main scene (for its UI helpers, sounds, wallet and save)
var tab := "skin"
var showcase: Control
var grid: GridContainer
var scroller: ScrollContainer
var wallet_label: Label
var info: Label
var tabs := {}
var cards := [] # [button, kind, id, preview, price_row]
var _emitter: CPUParticles2D
var _emitter_fx := ""
var _path := PackedVector2Array() # the showcase square's trail
var _pet_pos := Vector2.INF
var _pet_face := 1.0
var _clock := 0.0


func build(main) -> void:
	m = main
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var safe: Vector4 = m._safe_margins()
	m._dim(self, Color(0.11, 0.14, 0.26, 0.9), Color(0.08, 0.1, 0.2, 0.97))

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 20 + safe.x
	col.offset_right = -20 - safe.z
	col.offset_top = 16 + safe.y
	col.offset_bottom = -16 - safe.w
	col.add_theme_constant_override("separation", 14)
	add_child(col)

	# Top bar: back, title, wallet
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	col.add_child(bar)
	var back: Button = m._button("Back", Color(1, 1, 1, 0.92), m.INK, Color("#c7cfe0"), 30)
	back.custom_minimum_size = Vector2(150, 76)
	back.pressed.connect(close)
	bar.add_child(back)
	var title: Label = m._label("SHOP", 64, m.YELLOW, 18, m.NAVY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	var wcard: PanelContainer = m._card(Color(1, 1, 1, 0.92))
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	var coin := TextureRect.new()
	coin.texture = Art.tex(Art.COIN, 64)
	coin.custom_minimum_size = Vector2(32, 32)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrow.add_child(coin)
	wallet_label = m._label("0", 30, Color("#b07800"))
	wrow.add_child(wallet_label)
	wcard.add_child(wrow)
	wcard.custom_minimum_size.x = 150
	bar.add_child(wcard)

	# The showcase: your square driving round in its outfit
	showcase = Control.new()
	showcase.custom_minimum_size = Vector2(0, 270)
	showcase.clip_contents = true
	showcase.draw.connect(_draw_showcase)
	col.add_child(showcase)

	# Tabs
	var trow := HBoxContainer.new()
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	trow.add_theme_constant_override("separation", 10)
	col.add_child(trow)
	for kind in Cosmetics.KINDS:
		var b := Button.new()
		b.text = Cosmetics.KINDS[kind].title
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(200, 70)
		b.add_theme_font_override("font", m.font)
		b.add_theme_font_size_override("font_size", 30)
		b.pressed.connect(func():
			m.sfx.play("tap")
			show_tab(kind))
		trow.add_child(b)
		tabs[kind] = b
	info = m._label("", 24, Color(1, 1, 1, 0.85), 0, m.INK, m.font_med)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(600, 34)
	col.add_child(info)

	scroller = ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroller)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(center)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	center.add_child(grid)


func open() -> void:
	m._show(self)
	_path.clear()
	_pet_pos = Vector2.INF
	show_tab(tab)


func close() -> void:
	visible = false
	m._show(m.menu)
	m._start_demo() # so the menu shows you in your new look


func show_tab(kind: String) -> void:
	tab = kind
	for c in grid.get_children():
		c.queue_free()
	cards.clear()
	for id in Cosmetics.items(kind):
		_add_card(kind, id)
	scroller.scroll_vertical = 0
	info.text = {"skin": "Patterns and outfits for your square.",
		"trail": "Effects that stream out behind you while your trail is out.",
		"pet": "A little buddy that follows you everywhere."}[kind]
	refresh()


func _add_card(kind: String, id: String) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(206, 232)
	b.mouse_filter = Control.MOUSE_FILTER_PASS # so a drag still scrolls the list
	b.pressed.connect(func(): tap(kind, id))
	grid.add_child(b)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 8
	v.offset_bottom = -10
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var prev := Control.new()
	prev.custom_minimum_size = Vector2(0, 140)
	prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prev.draw.connect(func(): _draw_preview(prev, kind, id))
	v.add_child(prev)
	var name_l: Label = m._label(Cosmetics.items(kind)[id].name, 28, m.INK)
	v.add_child(name_l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var icon := TextureRect.new()
	icon.texture = Art.tex(Art.COIN, 64)
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var price_l: Label = m._label("", 26, Color("#b07800"))
	row.add_child(price_l)
	cards.append([b, kind, id, prev, row, icon, price_l])


## Tap a card: wear it if it's yours, buy it if you can afford it
func tap(kind: String, id: String) -> void:
	var item_name: String = Cosmetics.items(kind)[id].name
	if m.owned[kind].has(id):
		m.equipped[kind] = id
		m.sfx.play("tap")
		info.text = tr("Now using %s.") % tr(item_name)
	elif Cosmetics.unlock_level(kind, id) > 0:
		# The reward track: earned by levelling up, never sold
		m.sfx.play("warn")
		info.text = tr("Reach level %d to unlock %s. It's free!") % [Cosmetics.unlock_level(kind, id), tr(item_name)]
		_shake(kind, id)
		return
	else:
		var cost := Cosmetics.price(kind, id)
		if m.wallet < cost:
			m.sfx.play("warn")
			info.text = tr("%s costs %d coins. You need %d more: win games and grab coins to earn them!") % [tr(item_name), cost, cost - m.wallet]
			_shake(kind, id)
			return
		m.wallet -= cost
		m.owned[kind].append(id)
		m.equipped[kind] = id
		m.sfx.play("coin")
		m.sfx.play("win")
		info.text = tr("You got %s! It's on now.") % tr(item_name)
		for r in m.prog.award("shopper"):
			m.wallet += r.coins
			info.text += "  " + tr("%s: +%d coins!") % [r.text, r.coins]
		_celebrate(kind, id)
	m._save()
	if kind == "trail":
		_path.clear()
	refresh()


func refresh() -> void:
	wallet_label.text = str(m.wallet)
	for kind in tabs:
		var on: bool = kind == tab
		var st: StyleBoxFlat = m._style(m.YELLOW if on else Color(1, 1, 1, 0.14), 20)
		st.content_margin_top = 6
		st.content_margin_bottom = 6
		for k in ["normal", "hover", "pressed"]:
			tabs[kind].add_theme_stylebox_override(k, st)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			tabs[kind].add_theme_color_override(k, Color("#5a3200") if on else Color.WHITE)
	for c in cards:
		var b: Button = c[0]
		var kind: String = c[1]
		var id: String = c[2]
		var using: bool = m.equipped[kind] == id
		var mine: bool = m.owned[kind].has(id)
		var st: StyleBoxFlat = m._style(Color.WHITE if mine else Color(0.93, 0.95, 1.0), 24, 8,
				Color("#d27a06") if using else Color("#c7cfe0"))
		if using:
			st.set_border_width_all(6)
			st.border_width_bottom = 10
			st.border_color = m.YELLOW
		for k in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(k, st)
		var icon: TextureRect = c[5]
		var price_l: Label = c[6]
		icon.visible = not mine and not using
		# Reward-track items show a star (earned by levelling up) instead of a coin
		icon.texture = Art.tex(Cosmetics.STAR, 64) if Cosmetics.unlock_level(kind, id) > 0 else Art.tex(Art.COIN, 64)
		icon.modulate = Color("#8d7bd6") if Cosmetics.unlock_level(kind, id) > 0 else Color.WHITE
		if using:
			price_l.text = "Using"
			price_l.label_settings.font_color = Color("#d27a06")
		elif mine:
			price_l.text = "Owned" if Cosmetics.price(kind, id) > 0 or Cosmetics.unlock_level(kind, id) > 0 else "Free"
			price_l.label_settings.font_color = Color("#2a9d5c")
		elif Cosmetics.unlock_level(kind, id) > 0:
			price_l.text = tr("Level %d") % Cosmetics.unlock_level(kind, id)
			price_l.label_settings.font_color = Color("#6a57b8")
		else:
			var cost := Cosmetics.price(kind, id)
			price_l.text = str(cost)
			price_l.label_settings.font_color = Color("#b07800") if m.wallet >= cost else Color("#c0485a")


func _card_of(kind: String, id: String) -> Array:
	for c in cards:
		if c[1] == kind and c[2] == id:
			return c
	return []


func _shake(kind: String, id: String) -> void:
	var c := _card_of(kind, id)
	if c.is_empty():
		return
	var b: Button = c[0]
	var x := b.position.x
	var tw := b.create_tween()
	for k in [-12.0, 10.0, -6.0, 3.0, 0.0]:
		tw.tween_property(b, "position:x", x + k, 0.05)


func _celebrate(kind: String, id: String) -> void:
	var c := _card_of(kind, id)
	if c.is_empty():
		return
	var b: Button = c[0]
	b.pivot_offset = b.size / 2
	b.scale = Vector2(1.15, 1.15)
	b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var burst := CPUParticles2D.new()
	burst.position = b.size / 2
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 30
	burst.lifetime = 0.8
	burst.spread = 180.0
	burst.gravity = Vector2(0, 500)
	burst.initial_velocity_min = 250.0
	burst.initial_velocity_max = 500.0
	burst.scale_amount_min = 0.2
	burst.scale_amount_max = 0.45
	burst.texture = Art.tex(Art.COIN, 64)
	b.add_child(burst)
	burst.emitting = true
	get_tree().create_timer(1.2).timeout.connect(burst.queue_free)


func _process(dt: float) -> void:
	if not visible:
		return
	_clock += dt
	showcase.queue_redraw()
	for c in cards:
		c[3].queue_redraw()


# ---------- Drawing ----------

func _me_color() -> Color:
	return m.world.COLORS[m.my_color]


## The showcase square drives a figure of eight, with its trail, trail effect and pet
func _draw_showcase() -> void:
	var sz := showcase.size
	var t := _clock
	# A little patch of floor
	var floor_s: StyleBoxFlat = m._style(Color("#f5f7fc"), 30)
	showcase.draw_style_box(floor_s, Rect2(Vector2.ZERO, sz))
	var tile := 34.0
	for y in int(sz.y / tile) + 1:
		for x in int(sz.x / tile) + 1:
			if (x + y) % 2 == 0:
				showcase.draw_rect(Rect2(x * tile, y * tile, tile, tile), Color("#ebeff8"))
	var color := _me_color()
	var dark := color.darkened(0.3)
	# Home land in the middle
	var home := Rect2(sz.x / 2 - 70, sz.y / 2 - 50, 140, 100)
	showcase.draw_rect(Rect2(home.position + Vector2(0, 8), home.size), dark)
	showcase.draw_rect(home, color.lightened(0.15))
	# Where the square is on its figure of eight
	var a := t * 1.3
	var c := sz / 2
	var pos := c + Vector2(sin(a) * sz.x * 0.36, sin(a * 2.0) * sz.y * 0.28)
	var nxt := c + Vector2(sin(a + 0.05) * sz.x * 0.36, sin((a + 0.05) * 2.0) * sz.y * 0.28)
	var look := (nxt - pos).normalized()
	var outside := not home.grow(10).has_point(pos)
	if outside:
		_path.append(pos)
		if _path.size() > 60:
			_path.remove_at(0)
	else:
		_path.clear()
	var trail_fx: String = m.equipped.trail
	if _path.size() > 1:
		var pts := _path.duplicate()
		pts.append(pos)
		if trail_fx == "rainbow":
			for i in pts.size() - 1:
				var u := float(i) / pts.size()
				showcase.draw_line(pts[i], pts[i + 1], Color(Cosmetics.rainbow(-t, u), 0.3), 40, true)
				showcase.draw_line(pts[i], pts[i + 1], Color(Cosmetics.rainbow(-t, u), 0.9), 24, true)
		else:
			showcase.draw_polyline(pts, Color(color, 0.2), 40, true)
			showcase.draw_polyline(pts, Color(color, 0.7), 24, true)
		showcase.draw_polyline(pts, Color(1, 1, 1, 0.35), 6, true)
	# The trail effect's particles (a real emitter, like in the game)
	if trail_fx != _emitter_fx:
		_emitter_fx = trail_fx
		if _emitter:
			_emitter.queue_free()
		_emitter = Cosmetics.make_emitter(trail_fx, 1.4, color)
		if _emitter:
			showcase.add_child(_emitter)
	if _emitter:
		_emitter.position = pos
		_emitter.emitting = outside
	# The pet follows behind
	var pet: String = m.equipped.pet
	if pet != "none":
		var goal := pos - look * 70 + look.orthogonal() * 34
		if _pet_pos == Vector2.INF:
			_pet_pos = goal
		var old := _pet_pos
		_pet_pos = _pet_pos.lerp(goal, 0.1)
		if absf(_pet_pos.x - old.x) > 0.2:
			_pet_face = signf(_pet_pos.x - old.x)
		Cosmetics.draw_pet(showcase, _pet_pos, 56, pet, color, t, _pet_face)
	showcase.draw_set_transform(pos + Vector2(0, 26), 0, Vector2(1, 0.35))
	showcase.draw_circle(Vector2.ZERO, 40, Color(0.06, 0.08, 0.16, 0.15), true, -1, true)
	showcase.draw_set_transform(Vector2.ZERO)
	Cosmetics.draw_square(showcase, pos, 64, color, dark, m.equipped.skin, look, t,
			look.x * 0.1, 0.0, fmod(t, 3.0) < 0.12)


func _draw_preview(c: Control, kind: String, id: String) -> void:
	var t := _clock
	var color := _me_color()
	var dark := color.darkened(0.3)
	var mid := c.size / 2 + Vector2(0, 4)
	match kind:
		"skin":
			var look := Vector2.from_angle(sin(t * 0.8 + mid.x) * 1.2)
			Cosmetics.draw_square(c, mid, 88, color, dark, id, look, t, 0.0, 0.0, fmod(t + mid.x, 3.0) < 0.12)
		"pet":
			if id == "none":
				c.draw_arc(mid, 40, 0, TAU, 40, Color(0.5, 0.55, 0.7, 0.4), 4, true)
				c.draw_line(mid + Vector2(-28, 28), mid + Vector2(28, -28), Color(0.5, 0.55, 0.7, 0.4), 4, true)
			else:
				Cosmetics.draw_pet(c, mid, 100, id, color, t + mid.x)
		"trail":
			# A wavy trail with a few of its particles
			var pts := PackedVector2Array()
			for i in 12:
				var x := lerpf(20, c.size.x - 50, i / 11.0)
				pts.append(Vector2(x, mid.y + sin(x * 0.05 + t * 3.0) * 18))
			if id == "rainbow":
				for i in pts.size() - 1:
					c.draw_line(pts[i], pts[i + 1], Cosmetics.rainbow(-t, i / 11.0), 18, true)
			else:
				c.draw_polyline(pts, Color(color, 0.2), 30, true)
				c.draw_polyline(pts, Color(color, 0.75), 18, true)
			var end := pts[pts.size() - 1]
			_draw_trail_bits(c, id, pts, t)
			Cosmetics.draw_square(c, end, 46, color, dark, "plain", Vector2.RIGHT, t)


## A few particles scattered along a preview trail
func _draw_trail_bits(c: Control, id: String, pts: PackedVector2Array, t: float) -> void:
	var svg := ""
	var tint := Color.WHITE
	match id:
		"sparkle":
			svg = Art.SPARK
			tint = Color("#fff4b0")
		"bubbles":
			svg = Cosmetics.BUBBLE
			tint = Color("#bfe9ff")
		"hearts":
			svg = Art.HEART
			tint = Color("#ff6b9a")
		"stars":
			svg = Cosmetics.STAR
			tint = Color("#ffd23f")
		"confetti":
			svg = Art.TILE
		"fire":
			svg = Art.GLOW
			tint = Color("#ff8a1f")
		"snow":
			svg = Cosmetics.SNOWFLAKE
			tint = Color("#e8f7ff")
		"lightning":
			svg = Cosmetics.BOLT
			tint = Color("#8ff4ff")
		_:
			return
	var tex := Art.tex(svg, 64)
	var confetti := [Color("#ff5d73"), Color("#ffd23f"), Color("#4ed8a0"), Color("#4f8cff"), Color("#a66bff")]
	for k in 6:
		var i := 1 + k * 1.6
		var p: Vector2 = pts[int(i)]
		var life := fmod(t * 0.8 + k * 0.37, 1.0)
		var drift := Vector2(sin(k * 7.0) * 14, -life * 26 if id in ["bubbles", "hearts", "fire"] else life * 22 if id == "snow" else cos(k * 5.0) * 14)
		var s := (22.0 + 8 * sin(k * 3.0)) * (1.0 - life * 0.6) * (1.8 if id == "fire" else 1.0)
		var col := tint
		if id == "confetti":
			col = confetti[k % confetti.size()]
			s *= 0.6
		col.a = 1.0 - life
		c.draw_set_transform(p + drift, t * 2.0 + k if id in ["stars", "sparkle", "confetti", "snow"] else 0.0)
		c.draw_texture_rect(tex, Rect2(-s / 2, -s / 2, s, s), false, col)
	c.draw_set_transform(Vector2.ZERO)
