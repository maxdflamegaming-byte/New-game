class_name MenuScreen
extends Control
## A full screen reached from the menu's dock: a dark backdrop, a top bar (Back, the title and
## your coins) and a scrolling column of cards. Missions, Profile and Settings build on it.

var m # the main scene (for its UI helpers, sounds, wallet and save)
var body: VBoxContainer
var wallet_label: Label
var scroller: ScrollContainer


func frame(main, title: String) -> void:
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
	col.add_theme_constant_override("separation", 16)
	add_child(col)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	col.add_child(bar)
	var back: Button = m._button("Back", Color(1, 1, 1, 0.92), m.INK, Color("#c7cfe0"), 30)
	back.custom_minimum_size = Vector2(150, 76)
	back.pressed.connect(close)
	bar.add_child(back)
	var t: Label = m._label(title, 56, m.YELLOW, 16, m.NAVY)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(t)
	var wcard: PanelContainer = m._card(Color(1, 1, 1, 0.92))
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	wrow.add_child(icon(Art.COIN, 32))
	wallet_label = m._label("0", 30, Color("#b07800"))
	wrow.add_child(wallet_label)
	wcard.add_child(wrow)
	wcard.custom_minimum_size.x = 150
	bar.add_child(wcard)
	scroller = ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroller)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroller.add_child(body)


func open() -> void:
	m._show(self)
	scroller.scroll_vertical = 0
	refresh()


func close() -> void:
	visible = false
	m._show(m.menu)
	m._refresh_menu()


## Redraws what can change (override, but call this too)
func refresh() -> void:
	wallet_label.text = str(m.wallet)


# ---------- Helpers ----------

func icon(svg: String, px: int, tint := Color.WHITE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Art.tex(svg, 64 if px <= 48 else 128)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func heading(text: String) -> Label:
	var l: Label = m._label(text, 26, Color(1, 1, 1, 0.75))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.add_child(l)
	return l


## A white card in the column, with a box inside to fill
func card(vertical := true) -> BoxContainer:
	var c: PanelContainer = m._card(Color(1, 1, 1, 0.95))
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(c)
	var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	c.add_child(box)
	return box


## A thin progress bar (0..1) drawn in `color`
func bar(fill: float, color: Color, height := 16) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_meta("fill", fill)
	c.draw.connect(func():
		var r := Rect2(Vector2.ZERO, c.size)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.12, 0.15, 0.27, 0.12)
		bg.set_corner_radius_all(int(c.size.y / 2))
		c.draw_style_box(bg, r)
		var f: float = clampf(c.get_meta("fill", 0.0), 0.0, 1.0)
		if f > 0:
			var fg := StyleBoxFlat.new()
			fg.bg_color = color
			fg.set_corner_radius_all(int(c.size.y / 2))
			c.draw_style_box(fg, Rect2(r.position, Vector2(maxf(c.size.y, r.size.x * f), r.size.y))))
	return c


func clear() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
