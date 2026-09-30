extends MenuScreen
## Choosing what to play: big cards for the modes, pictures of the maps, the bosses and how
## tough the bots are. Modes and maps open up as you level up (see Unlocks); locked ones show
## the level they open at, and new ones are marked NEW until you've seen them here.

## Each mode's card colour and a short line about it
const LOOK := {
	"classic": {"color": "#3d7bea", "line": "Claim 50% of the map"},
	"online": {"color": "#2fbf71", "line": "Play people worldwide"},
	"timed": {"color": "#ff8a1f", "line": "Biggest after 3 minutes wins"},
	"duo": {"color": "#ff5d9e", "line": "2 players, one screen"},
	"teams": {"color": "#8d5cf6", "line": "4 vs 4: team up to 50%"},
	"daily": {"color": "#14b8a6", "line": "The same map for everyone today"},
	"hill": {"color": "#e0a800", "line": "Hold the hill to score"},
	"boss": {"color": "#e5484d", "line": "Beat the King, Queen and Wizard"},
}
const ORDER := ["classic", "online", "timed", "duo", "teams", "daily", "hill", "boss"]

static var _previews := {} # map id -> Texture2D
var _changed := false # a new mode or map: the menu's background game restarts on the way out


func build(main) -> void:
	frame(main, "PLAY")


func close() -> void:
	# Everything new has been seen now
	if not m.new_unlocks.is_empty():
		m.new_unlocks.clear()
		m._save()
	super()
	if _changed:
		_changed = false
		m._start_demo()


func refresh() -> void:
	super()
	clear()
	var lvl: int = m.prog.level
	heading("MODE")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	body.add_child(grid)
	for id in ORDER:
		if id == "online" and OnlineConfig.server_url() == "":
			continue
		grid.add_child(_mode_card(id, lvl))
	var mode_id: String = m.mode_id
	if mode_id == "boss":
		_bosses()
	_maps(mode_id, lvl)
	if mode_id != "online":
		_bots()
	var nxt := Unlocks.next_after(lvl)
	if not nxt.is_empty():
		var name: String = m.world.MODES[nxt[2]].name if nxt[1] == "mode" else m.world.MAPS[nxt[2]]
		var t: Label = m._label(tr("Next unlock: %s at level %d") % [tr(name), nxt[0]], 22, Color(1, 1, 1, 0.7), 0, m.INK, m.font_med)
		body.add_child(t)
	var play: Button = m._button("PLAY", m.YELLOW, Color("#5a3200"), Color("#d27a06"), 56)
	play.custom_minimum_size = Vector2(0, 110)
	play.pressed.connect(func():
		m.sfx.play("tap")
		close()
		m.start_game())
	body.add_child(play)


# ---------- Modes ----------

func _mode_card(id: String, lvl: int) -> Button:
	var open := Unlocks.mode_open(id, lvl)
	var picked: bool = id == m.mode_id
	var col := Color(LOOK[id].color) if open else Color("#4a5270")
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 176)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["normal", "hover", "pressed"]:
		var st := StyleBoxFlat.new()
		st.bg_color = col.darkened(0.05) if k == "pressed" else col
		st.set_corner_radius_all(26)
		st.anti_aliasing = true
		st.border_width_bottom = 3 if k == "pressed" else 8
		st.border_color = col.darkened(0.3)
		if picked:
			st.border_width_left = 6
			st.border_width_right = 6
			st.border_width_top = 6
			st.border_color = Color.WHITE
		b.add_theme_stylebox_override(k, st)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18
	v.offset_right = -14
	v.offset_top = 14
	v.offset_bottom = -16
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	b.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	top.add_child(icon(Art.MODE_ICONS[id] if open else Art.LOCK, 50, Color.WHITE if open else Color(1, 1, 1, 0.6)))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	if open and m.new_unlocks.has("mode:" + id):
		top.add_child(_tag("NEW", Color("#ff3c50"), Color.WHITE))
	elif picked:
		top.add_child(icon(Art.CHECK, 40))
	var name: Label = m._label(m.world.MODES[id].name, 30, Color.WHITE if open else Color(1, 1, 1, 0.75), 6, col.darkened(0.4))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name)
	var line: Label = m._label(tr(LOOK[id].line) if open else tr("Unlocks at level %d") % Unlocks.mode_level(id),
		19, Color(1, 1, 1, 0.92) if open else Color(1, 1, 1, 0.6), 0, m.INK, m.font_med)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(line)
	b.pressed.connect(func():
		if not open:
			_nope(b)
			return
		m.sfx.play("tap")
		m.mode_id = id
		m._save()
		_changed = true
		refresh())
	b.pivot_offset = Vector2(160, 88)
	return b


## A locked card wobbles when tapped
func _nope(c: Control) -> void:
	m.sfx.play("beep")
	c.pivot_offset = c.size / 2
	var tw := c.create_tween()
	for k in 3:
		tw.tween_property(c, "rotation", 0.04, 0.05)
		tw.tween_property(c, "rotation", -0.04, 0.05)
	tw.tween_property(c, "rotation", 0.0, 0.05)


func _tag(text: String, bg: Color, fg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.set_corner_radius_all(12)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 2
	st.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(m._label(text, 18, fg))
	return p


# ---------- Maps ----------

func _maps(mode_id: String, lvl: int) -> void:
	heading("MAP")
	if mode_id == "daily" or mode_id == "online":
		var box := card()
		var map_name: String
		var text: String
		if mode_id == "daily":
			var h: int = absi(m.world.today().hash())
			var id: String = m.world.MAPS.keys()[h % m.world.MAPS.size()]
			map_name = id
			text = tr("Today's map: %s") % tr(m.world.MAPS[id]) + ". " + tr("The same for everyone, all day.")
		else:
			text = tr("A new map every round, picked by the server.")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		box.add_child(row)
		if map_name != "":
			var pic := TextureRect.new()
			pic.texture = preview(map_name)
			pic.custom_minimum_size = Vector2(96, 96)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			row.add_child(pic)
		var l: Label = m._label(text, 24, m.INK, 0, m.INK, m.font_med)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(l)
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	for id in _maps_by_level():
		grid.add_child(_map_card(id, lvl))


func _maps_by_level() -> Array:
	var ids: Array = m.world.MAPS.keys()
	ids.sort_custom(func(a, b): return Unlocks.map_level(a) < Unlocks.map_level(b) or (Unlocks.map_level(a) == Unlocks.map_level(b) and ids.find(a) < ids.find(b)))
	return ids


func _map_card(id: String, lvl: int) -> Button:
	var open := Unlocks.map_open(id, lvl)
	var picked: bool = id == m.map_id
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 196)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["normal", "hover", "pressed"]:
		var st := StyleBoxFlat.new()
		st.bg_color = Color(1, 1, 1, 0.95) if open else Color(1, 1, 1, 0.14)
		st.set_corner_radius_all(22)
		st.anti_aliasing = true
		st.border_width_bottom = 6
		st.border_color = Color("#c7cfe0") if open else Color(1, 1, 1, 0.08)
		if picked:
			st.set_border_width_all(6)
			st.border_color = m.YELLOW
		b.add_theme_stylebox_override(k, st)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 10
	v.offset_bottom = -12
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	b.add_child(v)
	var pic := TextureRect.new()
	pic.texture = preview(id)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not open:
		pic.modulate = Color(1, 1, 1, 0.25)
		var lock := icon(Art.LOCK, 44, Color(1, 1, 1, 0.85))
		lock.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		pic.add_child(lock)
	elif m.new_unlocks.has("map:" + id):
		var tag := _tag("NEW", Color("#ff3c50"), Color.WHITE)
		pic.add_child(tag)
	v.add_child(pic)
	var name: Label = m._label(m.world.MAPS[id] if open else tr("Level %d") % Unlocks.map_level(id), 22,
		m.INK if open else Color(1, 1, 1, 0.6), 0, m.INK, m.font)
	name.clip_text = true
	v.add_child(name)
	b.pressed.connect(func():
		if not open:
			_nope(b)
			return
		m.sfx.play("tap")
		m.map_id = id
		m._save()
		_changed = true
		refresh())
	return b


## A small picture of a map's layout (walls, water, ice, belts, hazards)
static func preview(id: String) -> Texture2D:
	if _previews.has(id):
		return _previews[id]
	var w = load("res://scripts/world.gd").new()
	var n: int = w.N
	w.map_id = id
	w._build_map()
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var floor_c := Color("#e9eef8")
	for y in n:
		for x in n:
			var i := y * n + x
			var c := floor_c
			if ((x / 8) + (y / 8)) % 2 == 0:
				c = Color("#dde4f2")
			if w.ice[i]:
				c = Color("#bfe9ff")
			if w.belt[i]:
				c = Color("#9aa6c4")
			if w.tracks[i]:
				c = Color("#ffc9cf")
			if w.avoid[i]:
				c = Color("#b89cff")
			if w.wall[i] == 1:
				c = Color("#3b4466")
			elif w.wall[i] == 2:
				c = Color(0, 0, 0, 0)
			img.set_pixel(x, y, c)
	for bm in w.bumpers:
		_dot(img, bm.pos, 4.0, Color("#ff5d9e"))
	if w.storm_r > 0:
		for k in 720:
			var p: Vector2 = Vector2(n / 2.0, n / 2.0) + Vector2.from_angle(k * TAU / 720) * minf(w.storm_r, n / 2.0 - 1)
			_dot(img, p, 1.5, Color("#e5484d"))
	w.free()
	var tex := ImageTexture.create_from_image(img)
	_previews[id] = tex
	return tex


static func _dot(img: Image, at: Vector2, r: float, c: Color) -> void:
	for y in range(int(at.y - r), int(at.y + r) + 1):
		for x in range(int(at.x - r), int(at.x + r) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and Vector2(x + 0.5, y + 0.5).distance_to(at) <= r:
				img.set_pixel(x, y, c)


# ---------- Bosses and bots ----------

func _bosses() -> void:
	heading("BOSS")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var prev := ""
	for id in m.world.BOSSES:
		var bd: Dictionary = m.world.BOSSES[id]
		var open: bool = m.boss_unlocked(id)
		var picked: bool = id == m.boss_kind
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 150)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := Color(bd.color) if open else Color("#4a5270")
		for k in ["normal", "hover", "pressed"]:
			var st := StyleBoxFlat.new()
			st.bg_color = col
			st.set_corner_radius_all(22)
			st.border_width_bottom = 8
			st.border_color = col.darkened(0.35)
			if picked:
				st.set_border_width_all(6)
				st.border_color = Color.WHITE
			b.add_theme_stylebox_override(k, st)
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_top = 10
		v.offset_bottom = -14
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var ic := icon(Art.MODE_ICONS.boss if open else Art.LOCK, 44, Color.WHITE if open else Color(1, 1, 1, 0.6))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		v.add_child(m._label(bd.name, 26, Color.WHITE if open else Color(1, 1, 1, 0.7)))
		var hearts: int = bd.hearts + (2 if Events.current() == "giants" else 0)
		var sub: Label = m._label(tr("%d hearts") % hearts if open else tr("Beat the %s") % tr(m.world.BOSSES[prev].name), 18,
			Color(1, 1, 1, 0.85 if open else 0.6), 0, m.INK, m.font_med)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(sub)
		b.pressed.connect(func():
			if not open:
				_nope(b)
				return
			m.sfx.play("tap")
			m.boss_kind = id
			m._save()
			refresh())
		row.add_child(b)
		prev = id


func _bots() -> void:
	heading("BOTS")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	for id in m.world.DIFFICULTY:
		var d: Dictionary = m.world.DIFFICULTY[id]
		var picked: bool = id == m.difficulty
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 96)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for k in ["normal", "hover", "pressed"]:
			var st := StyleBoxFlat.new()
			st.bg_color = Color.WHITE if picked else Color(1, 1, 1, 0.14)
			st.set_corner_radius_all(20)
			st.border_width_bottom = 6
			st.border_color = Color("#c7cfe0") if picked else Color(1, 1, 1, 0.08)
			b.add_theme_stylebox_override(k, st)
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_bottom = -6
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 0)
		b.add_child(v)
		v.add_child(m._label(d.name, 26, m.INK if picked else Color.WHITE))
		v.add_child(m._label(tr("Coins x%s") % str(d.coins), 18, m.MUTED if picked else Color(1, 1, 1, 0.6), 0, m.INK, m.font_med))
		b.pressed.connect(func():
			m.sfx.play("tap")
			m.difficulty = id
			m._save()
			refresh())
		row.add_child(b)
