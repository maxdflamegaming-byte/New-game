class_name World
extends Node3D
## The 3D look of Tower Siege: a high camera, bright cartoon colors, stacked towers in army
## colors, chibi soldiers and tanks. Every model is built in code from simple shapes
## (see mesh_kit.gd), so there are no model or texture files. It draws a Battle; it doesn't
## change it. Field (x, y) is (x, 0, y) here.

const S := 1.65                # buildings, soldiers and props are drawn this much bigger
const MAX_SOLDIERS := 1200
const MAX_TANKS := 240
const MAX_BITS := 220

const THEMES := {
	"grass": {"ground": "#5fbf36", "field": "#6fcd3e", "spot": "#53ad2d", "sky": "#bfe9ff", "props": "pine", "wall": "hedge", "flowers": true},
	"desert": {"ground": "#f2be5c", "field": "#f8cf7c", "spot": "#e3ab4c", "sky": "#ffeccc", "props": "cactus", "wall": "crate", "cracks": true},
	"snow": {"ground": "#bfe2f8", "field": "#a6d8f6", "spot": "#8ec9ee", "sky": "#e8f7ff", "props": "snowpine", "wall": "ice"},
	"beach": {"ground": "#3fcbec", "field": "#fbdc95", "spot": "#efc574", "sky": "#c9f1ff", "props": "palm", "wall": "toy", "water": true},
}
const BRIGHT := ["#ff5a5a", "#ffb92e", "#4fc3ff", "#7bdc4a", "#ff7ad1", "#9b7bff"]

var sides: Array = []          # [{color, dark, light}] as Colors
var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var level_root: Node3D
var fw := 900.0
var fh := 1400.0
var view_size := Vector2(720, 1280)

var paint_shader: Shader = preload("res://shaders/paint.gdshader")
var ground_shader: Shader = preload("res://shaders/ground.gdshader")
var road_shader: Shader = preload("res://shaders/road.gdshader")
var glow_shader: Shader = preload("res://shaders/glow.gdshader")

var models := {}               # tower id -> {node, mesh_inst, mat, flag, ring, lv, type, side, top, smoke, bounce}
var roads := {}                # key -> MeshInstance3D
var soldiers: MultiMeshInstance3D
var soldier_shadows: MultiMeshInstance3D
var tanks: MultiMeshInstance3D
var quality := 1               # 0 low, 1 medium, 2 high (see set_quality)
var bit_mm: MultiMeshInstance3D
var bits: Array = []           # flying confetti / clash bits
var puffs: Array[Sprite3D] = []
var stars: Array[Sprite3D] = []
var fires: Array[MeshInstance3D] = []
var rings: Array[MeshInstance3D] = []
var shells: Array[MeshInstance3D] = []
var plane: Node3D
var clouds: Array[MeshInstance3D] = []
var time := 0.0


func setup(side_list: Array) -> void:
	sides = side_list
	camera = Camera3D.new()
	camera.fov = 30
	camera.near = 20
	camera.far = 9000
	add_child(camera)
	sun = DirectionalLight3D.new()
	sun.light_color = Color("#fff4e0")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 5000
	add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#bfe9ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#eef6ff")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)
	_make_units()
	_make_fx()
	_make_clouds()


func paint_material(team := Color("#9eaabd"), instance := false, walk := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = paint_shader
	m.set_shader_parameter("team_color", team)
	m.set_shader_parameter("use_instance", instance)
	m.set_shader_parameter("walk", walk)
	return m


func glow_material(c: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = glow_shader
	m.set_shader_parameter("color", c)
	return m


# ---------- Camera ----------
## A high, tilted camera, moved until the whole field fits between the HUD bars
func layout(size: Vector2, top: float, bottom: float, field_w: float, field_h: float) -> void:
	view_size = size
	fw = field_w
	fh = field_h
	var pitch := 1.0
	var target := Vector3(fw / 2, 0, fh / 2)
	var d := 2400.0
	var pad := 6.0
	var corners := [Vector3(-20, 120, -40), Vector3(fw + 20, 120, -40), Vector3(-20, 0, fh + 30), Vector3(fw + 20, 0, fh + 30)]
	for i in 40:
		camera.position = target + Vector3(0, sin(pitch) * d, cos(pitch) * d)
		camera.look_at(target, Vector3.UP)
		var x0 := INF
		var x1 := -INF
		var y0 := INF
		var y1 := -INF
		for c in corners:
			var p := camera.unproject_position(c)
			x0 = minf(x0, p.x)
			x1 = maxf(x1, p.x)
			y0 = minf(y0, p.y)
			y1 = maxf(y1, p.y)
		var avail_w := size.x - pad * 2
		var avail_h := size.y - top - bottom - pad * 2
		var k := maxf((x1 - x0) / avail_w, (y1 - y0) / avail_h)
		d *= pow(k, 0.85)
		var want_y := top + pad + avail_h / 2
		target.z += ((y0 + y1) / 2 - want_y) * (fh / maxf(1, y1 - y0)) * 0.6
	# The sun from the upper left
	sun.rotation = Vector3(deg_to_rad(-62), deg_to_rad(-38), 0)


func project(x: float, y: float, h := 0.0) -> Vector2:
	return camera.unproject_position(Vector3(x, h, y))


func ground(screen: Vector2) -> Variant:
	var o := camera.project_ray_origin(screen)
	var n := camera.project_ray_normal(screen)
	if absf(n.y) < 1e-5:
		return null
	var t := -o.y / n.y
	if t < 0:
		return null
	var p := o + n * t
	return Vector2(p.x, p.z)


func tower_top(t) -> float:
	var m = models.get(t.id)
	return m.top if m else 60.0


## Where a tower is on screen (its middle and top) and how big it looks
func tower_screen(t) -> Dictionary:
	var top := tower_top(t)
	var c := project(t.x, t.y, top * 0.5)
	var e := project(t.x + t.radius(), t.y, top * 0.5)
	var tp := project(t.x, t.y, top)
	var base := project(t.x, t.y, 0)
	return {"x": c.x, "y": c.y, "r": absf(e.x - c.x), "top_x": tp.x, "top_y": tp.y, "base": base}


func px_per_unit(x: float, y: float) -> float:
	return absf(project(x + 100, y).x - project(x, y).x) / 100.0


# ---------- Level scenery ----------
func build(seed_value: int, theme_name: String, battle: Battle) -> void:
	if level_root:
		level_root.queue_free()
	models.clear()
	roads.clear()
	level_root = Node3D.new()
	add_child(level_root)
	var th: Dictionary = THEMES.get(theme_name, THEMES.grass)
	env.background_color = Color(th.sky)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Ground: one big plane, the field and its looks drawn by a shader
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(fw + 2400, fh + 2400)
	g.mesh = pm
	g.position = Vector3(fw / 2, 0, fh / 2)
	var gm := ShaderMaterial.new()
	gm.shader = ground_shader
	gm.set_shader_parameter("ground", Color(th.ground))
	gm.set_shader_parameter("field", Color(th.field))
	gm.set_shader_parameter("spot", Color(th.spot))
	gm.set_shader_parameter("field_center", Vector2(fw / 2, fh / 2))
	gm.set_shader_parameter("field_half", Vector2(fw / 2, fh / 2))
	gm.set_shader_parameter("water", th.get("water", false))
	gm.set_shader_parameter("cracks", th.get("cracks", false))
	gm.set_shader_parameter("seed", float(seed_value % 1000))
	g.material_override = gm
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level_root.add_child(g)

	# Props around the field, and the walls that block roads
	var props := {"pine": [], "snowpine": [], "cactus": [], "palm": [], "flower": [], "rock": [], "barrel": [], "crate": [], "tire": [], "w_crate": [], "w_ice": [], "w_hedge": [], "w_toy": []}
	var avoid := func(x: float, z: float, d: float) -> bool:
		for t in battle.towers:
			if Battle.dist(t.x, t.y, x, z) < d:
				return true
		return false
	for i in 260:
		var side := rng.randi_range(0, 3)
		var out := 60 + rng.randf() * 260
		var x := 0.0
		var z := 0.0
		if side == 0:
			x = -200 + rng.randf() * (fw + 400)
			z = -out
		elif side == 1:
			x = -200 + rng.randf() * (fw + 400)
			z = fh + out
		elif side == 2:
			x = -out
			z = -200 + rng.randf() * (fh + 400)
		else:
			x = fw + out
			z = -200 + rng.randf() * (fh + 400)
		if th.get("water", false) and (x < -110 or x > fw + 110 or z < -110 or z > fh + 110):
			continue # that's the sea
		var k := rng.randf()
		var kind: String = th.props if k < 0.6 else "rock" if k < 0.7 else "barrel" if k < 0.8 else "crate" if k < 0.9 else ("flower" if th.get("flowers", false) else "tire")
		props[kind].append([x, z, 0.8 + rng.randf() * 0.7, rng.randf() * TAU, rng.randf()])
	for i in 40:
		var edge := rng.randi_range(0, 3)
		var inset := 15 + rng.randf() * 30
		var x := rng.randf() * fw
		var z := rng.randf() * fh
		if edge == 0:
			z = inset
		elif edge == 1:
			z = fh - inset
		elif edge == 2:
			x = inset
		else:
			x = fw - inset
		if avoid.call(x, z, 160):
			continue
		props[th.props].append([x, z, 0.7 + rng.randf() * 0.4, rng.randf() * TAU, rng.randf()])
	if th.get("flowers", false):
		for i in 26:
			var cx := rng.randf() * fw
			var cz := rng.randf() * fh
			if avoid.call(cx, cz, 110) or battle.rocks.any(func(w): return Battle.dist(w.x, w.y, cx, cz) < w.r + 30):
				continue
			for j in 4:
				props.flower.append([cx + (rng.randf() - 0.5) * 36, cz + (rng.randf() - 0.5) * 36, 1 + rng.randf() * 0.4, rng.randf() * TAU, rng.randf()])
	for w in battle.rocks:
		var n := maxi(2, roundi(w.r / 18))
		for i in n:
			var a := rng.randf() * TAU
			var dd := rng.randf() * w.r * 0.55
			props["w_" + th.wall].append([w.x + cos(a) * dd, w.y + sin(a) * dd, (w.r / 40) * (0.8 + rng.randf() * 0.3), roundi(rng.randf() * 4) * PI / 2 + (rng.randf() - 0.5) * 0.3, rng.randf()])
	_add_props(props)
	for t in battle.towers:
		_sync_tower(t)


func _instanced(m: Mesh, list: Array, color_fn := Callable(), shadow := true) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = m
	mm.instance_count = list.size()
	for i in list.size():
		var p: Array = list[i]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, p[3]).scaled(Vector3.ONE * p[2] * S), Vector3(p[0], 0, p[1])))
		var c: Color = color_fn.call(p[4]) if color_fn.is_valid() else Color.WHITE
		mm.set_instance_custom_data(i, c.srgb_to_linear())
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = paint_material(Color.WHITE, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level_root.add_child(mi)


func _add_props(P: Dictionary) -> void:
	var T := MeshKit.TEAM
	var trunk := Color("#b07a48")
	# Pine trees, plain or with snow on top
	for kind in ["pine", "snowpine"]:
		var k := MeshKit.new().cyl(3, 4, 10, 6, Vector3(0, 5, 0), trunk)
		k.cone(17, 22, 8, Vector3(0, 18, 0), T).cone(14, 19, 8, Vector3(0, 30, 0), T).cone(10, 16, 8, Vector3(0, 41, 0), T)
		if kind == "snowpine":
			k.cone(9, 9, 8, Vector3(0, 46, 0), Color.WHITE).cone(14, 5, 8, Vector3(0, 32, 0), Color.WHITE)
		_instanced(k.mesh(), P[kind], func(c): return Color.from_hsv(0.3 + c * 0.06, 0.6, 0.62 + c * 0.12))
	# Cacti
	_instanced(MeshKit.new().cyl(5, 5.5, 34, 8, Vector3(0, 17, 0), T).sphere(5, Vector3(0, 34, 0), T, Vector3.ONE, true)
		.cyl(3.5, 3.5, 12, 6, Vector3(9, 20, 0), T).cyl(3.5, 3.5, 6, 6, Vector3(6, 15, 0), T, Basis(Vector3.BACK, PI / 2)).mesh(),
		P.cactus, func(c): return Color.from_hsv(0.3, 0.6, 0.75 + c * 0.1))
	# Palm trees: a leaning trunk, a crown of leaves and coconuts
	var palm := MeshKit.new()
	for i in 5:
		palm.cyl(3.6 - i * 0.3, 4 - i * 0.3, 10, 7, Vector3(i * i * 0.5, 5 + i * 9.5, 0), Color("#c99a5b"))
	for i in 7:
		var a := float(i) / 7 * TAU
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.35)
		palm.add(_box_mesh(6, 1.4, 26), Transform3D(b, Vector3(8, 50, 0) + b * Vector3(0, 0, 13)), T)
	for p in [Vector3(6, 47, 2), Vector3(10, 47, -2), Vector3(8, 46, 3)]:
		palm.sphere(2.6, p, Color("#8a5a32"))
	_instanced(palm.mesh(), P.palm, func(c): return Color.from_hsv(0.3, 0.7, 0.7 + c * 0.1))
	# Flowers: a stem and a bright head
	_instanced(MeshKit.new().cyl(0.7, 0.7, 8, 4, Vector3(0, 4, 0), Color("#62c94a")).sphere(3.2, Vector3(0, 9, 0), T, Vector3(1, 0.6, 1)).mesh(),
		P.flower, func(c): return Color(BRIGHT[int(c * BRIGHT.size()) % BRIGHT.size()]), false)
	# Rocks
	_instanced(MeshKit.new().sphere(14, Vector3(0, 6, 0), T, Vector3(1, 0.7, 1), false, 7, 4).mesh(), P.rock, func(c): return Color.from_hsv(0.6, 0.06, 0.78 + c * 0.12))
	# Barrels in bright colors, crates and old tires
	_instanced(MeshKit.new().cyl(7, 7, 16, 12, Vector3(0, 8, 0), T).cyl(7.5, 7.5, 1.8, 12, Vector3(0, 4, 0), MeshKit.DARK).cyl(7.5, 7.5, 1.8, 12, Vector3(0, 12, 0), MeshKit.DARK).mesh(),
		P.barrel, func(c): return Color(BRIGHT[int(c * BRIGHT.size()) % BRIGHT.size()]))
	_instanced(MeshKit.new().box(18, 18, 18, Vector3(0, 9, 0), T).mesh(), P.crate, func(c): return Color.from_hsv(0.08, 0.6, 0.78 + c * 0.1))
	var tire := TorusMesh.new()
	tire.inner_radius = 4.5
	tire.outer_radius = 11.5
	_instanced(MeshKit.new().add(tire, Transform3D(Basis(), Vector3(0, 3.5, 0)), Color("#4a5066")).mesh(), P.tire)
	# Wall pieces: crates, ice blocks, hedges or toy blocks, depending on the map
	_instanced(MeshKit.new().box(24, 22, 24, Vector3(0, 11, 0), T).box(25, 2.5, 4, Vector3(0, 11, 12.2), MeshKit.DARK).box(25, 2.5, 4, Vector3(0, 11, -12.2), MeshKit.DARK)
		.box(4, 2.5, 25, Vector3(12.2, 11, 0), MeshKit.DARK).box(4, 2.5, 25, Vector3(-12.2, 11, 0), MeshKit.DARK).mesh(), P.w_crate, func(c): return Color.from_hsv(0.08, 0.62, 0.8 + c * 0.1))
	_instanced(MeshKit.new().box(25, 20, 25, Vector3(0, 10, 0), T).box(26, 3, 26, Vector3(0, 21.5, 0), Color("#f2fbff")).mesh(), P.w_ice, func(c): return Color.from_hsv(0.55, 0.45, 0.95 + c * 0.05))
	_instanced(MeshKit.new().sphere(15, Vector3(0, 12, 0), T, Vector3(1.1, 0.95, 1.1), false, 8, 5).mesh(), P.w_hedge, func(c): return Color.from_hsv(0.3, 0.65, 0.62 + c * 0.1))
	var toy := MeshKit.new().box(24, 22, 24, Vector3(0, 11, 0), T)
	for p in [Vector3(-6, 24, -6), Vector3(6, 24, -6), Vector3(-6, 24, 6), Vector3(6, 24, 6)]:
		toy.cyl(4, 4, 4, 10, p, T)
	_instanced(toy.mesh(), P.w_toy, func(c): return Color(BRIGHT[int(c * BRIGHT.size()) % BRIGHT.size()]))


func _box_mesh(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


# ---------- Buildings ----------
func _build_model(t, lv: int) -> Dictionary:
	var k := MeshKit.new()
	var info := {"top": 60.0, "smoke": [], "flag_at": Vector3.ZERO, "muzzle": Vector3(0, 30, 0), "range": false}
	var W := Color("#ffffff")
	var SH := Color("#cfdaea")
	var DK := Color("#46506b")
	var METAL := Color("#8792a6")
	if t.type == "barracks" or t.type == "fort":
		# A stack of hexagonal floors, one more for every level, with a colored cap
		var fort: bool = t.type == "fort"
		var R := 40.0 if fort else 34.0
		k.hex(R + 6, R + 8, 8, Vector3(0, 4, 0), SH)
		k.hex(R + 6.6, R + 6.6, 3, Vector3(0, 7, 0), MeshKit.TEAM)
		var y := 8.0
		var r := R
		var floors := 1 + ceili(lv / 2.0) if fort else lv + 1
		for i in floors:
			var h := 15.0 if fort else 14.0
			k.hex(r - 1.5, r, h, Vector3(0, y + h / 2, 0), W)
			k.hex(r + 0.6, r + 0.6, 3.5, Vector3(0, y + h - 2, 0), MeshKit.TEAM)
			# Window slits on the front faces
			var fz := (r - 1) * cos(PI / 6)
			k.box(r * 0.75, 3, 2, Vector3(0, y + 6.5, fz), DK)
			for s in [-1, 1]:
				k.box(r * 0.55, 3, 2, Basis(Vector3.UP, s * PI / 3) * Vector3(0, 0, fz) + Vector3(0, y + 6.5, 0), DK, s * PI / 3)
			y += h
			r -= 1.0 if fort else 2.0
		if fort:
			# Bunker: thick armor plates and a gun on each side
			for i in 6:
				var a := i * PI / 3 + PI / 6
				k.box(10, y - 6, 6, Vector3(sin(a) * (R + 2), (y + 4) / 2, cos(a) * (R + 2)), SH, a)
			for i in lv:
				var a := i * TAU / lv + 0.4
				var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI / 2)
				k.cyl(2.4, 2.8, 16, 6, Basis(Vector3.UP, a) * Vector3(0, 0, r + 8) + Vector3(0, y - 8, 0), METAL, b)
		# The cap: the army's color, where the number sits
		k.hex(r + 3, r + 3, 6, Vector3(0, y + 3, 0), MeshKit.DARK)
		k.hex(r - 0.5, r + 3, 5, Vector3(0, y + 8.5, 0), MeshKit.TEAM)
		var front := (R + 0.5) * cos(PI / 6)
		k.box(12, 14, 2, Vector3(0, 15, front + 1), DK)
		k.box(15, 2.5, 3, Vector3(0, 23, front + 1.2), SH)
		info.flag_at = Vector3(0, y + 11, 0)
		info.top = y + 11
	elif t.type == "factory":
		# Tank factory: a hall with a big garage door and smoking chimneys
		var h := 26.0 + lv * 2
		k.box(84, 6, 70, Vector3(0, 3, 0), SH)
		k.box(70, h, 54, Vector3(0, 6 + h / 2, 0), W)
		k.box(74, 7, 58, Vector3(0, 6 + h + 3.5, 0), MeshKit.TEAM)
		k.box(74, 3, 58, Vector3(0, 6 + h - 0.5, 0), MeshKit.DARK)
		k.box(34, 20, 2, Vector3(0, 16, 27.5), DK)
		for i in 4:
			k.box(34, 1.2, 2.4, Vector3(0, 9 + i * 4.5, 28), SH)
		k.box(38, 3, 3, Vector3(0, 27.5, 28), MeshKit.TEAM)
		for i in mini(3, lv):
			var b := Basis(Vector3.RIGHT, PI / 2)
			k.cyl(4, 4, 14, 10, Vector3(-20 + i * 13, 6 + h + 10, 22), METAL, b)
		for i in mini(3, lv):
			var ch := 44.0 + i * 6
			var x := 22.0 - i * 10
			k.cyl(4.5, 5.5, ch, 10, Vector3(x, 6 + ch / 2, -16), METAL)
			k.cyl(5.5, 5.5, 3, 10, Vector3(x, 6 + ch, -16), DK)
			info.smoke.append(Vector3(x, 6 + ch + 3, -16))
		info.flag_at = Vector3(-26, 6 + h + 7, 18)
		info.top = 6 + h + 12
	else:
		# Watchtower: a lookout on four legs with a pointed roof; it shoots enemies in its circle
		var leg_h := 34.0 + lv * 4
		for p in [Vector2(-14, -14), Vector2(14, -14), Vector2(-14, 14), Vector2(14, 14)]:
			k.box(4.5, leg_h, 4.5, Vector3(p.x, leg_h / 2, p.y), W)
		for yy in [leg_h * 0.35, leg_h * 0.7]:
			k.box(30, 2.5, 2.5, Vector3(0, yy, 14), SH).box(30, 2.5, 2.5, Vector3(0, yy, -14), SH)
			k.box(2.5, 2.5, 30, Vector3(14, yy, 0), SH).box(2.5, 2.5, 30, Vector3(-14, yy, 0), SH)
		k.box(40, 4, 40, Vector3(0, leg_h + 2, 0), W)
		k.box(40, 9, 3, Vector3(0, leg_h + 8.5, 18.5), MeshKit.TEAM).box(40, 9, 3, Vector3(0, leg_h + 8.5, -18.5), MeshKit.TEAM)
		k.box(3, 9, 40, Vector3(18.5, leg_h + 8.5, 0), MeshKit.TEAM).box(3, 9, 40, Vector3(-18.5, leg_h + 8.5, 0), MeshKit.TEAM)
		for p in [Vector2(-17, -17), Vector2(17, -17), Vector2(-17, 17), Vector2(17, 17)]:
			k.box(3, 14, 3, Vector3(p.x, leg_h + 11, p.y), W)
		k.cone(33, 22, 4, Vector3(0, leg_h + 29, 0), MeshKit.TEAM, Basis(Vector3.UP, PI / 4))
		k.box(46, 2, 46, Vector3(0, leg_h + 18, 0), MeshKit.DARK)
		info.flag_at = Vector3(0, leg_h + 38, 0)
		info.top = leg_h + 42
		info.muzzle = Vector3(0, leg_h + 10, 0)
		info.range = true
	info.mesh = k.mesh()
	return info


func _flag_mesh() -> ArrayMesh:
	return MeshKit.new().box(14, 9, 0.8, Vector3(7.4, 0, 0), MeshKit.TEAM).mesh()


func _pole_mesh() -> ArrayMesh:
	return MeshKit.new().cyl(0.9, 0.9, 22, 6, Vector3(0, 11, 0), Color("#b4bdcc")).sphere(1.8, Vector3(0, 23, 0), Color("#ffd23f")).mesh()


var _flag_m: ArrayMesh
var _pole_m: ArrayMesh
var _ring_m: Mesh


func _ring_mesh() -> Mesh:
	if _ring_m == null:
		var t := TorusMesh.new()
		t.inner_radius = 0.9
		t.outer_radius = 1.0
		t.rings = 48
		t.ring_segments = 4
		_ring_m = t
	return _ring_m


func _sync_tower(t) -> Dictionary:
	var lv: int = t.level()
	var info = models.get(t.id)
	if info == null or info.lv != lv or info.type != t.type:
		var grew: bool = info != null and info.type == t.type
		if info != null:
			info.node.queue_free()
		var built := _build_model(t, lv)
		var node := Node3D.new()
		var holder := Node3D.new() # scaled with S and the bounce
		node.add_child(holder)
		var mi := MeshInstance3D.new()
		mi.mesh = built.mesh
		var mat := paint_material(_team_lin(t.owner))
		mi.material_override = mat
		holder.add_child(mi)
		if _flag_m == null:
			_flag_m = _flag_mesh()
			_pole_m = _pole_mesh()
		var pole := MeshInstance3D.new()
		pole.mesh = _pole_m
		pole.material_override = mat
		pole.position = built.flag_at
		holder.add_child(pole)
		var flag := MeshInstance3D.new()
		flag.mesh = _flag_m
		flag.material_override = mat
		flag.position = built.flag_at + Vector3(0, 18, 0)
		holder.add_child(flag)
		var range_ring: MeshInstance3D = null
		if built.range:
			range_ring = MeshInstance3D.new()
			range_ring.mesh = _ring_mesh()
			range_ring.scale = Vector3(Battle.WATCH_RANGE, 1, Battle.WATCH_RANGE)
			range_ring.position.y = 0.8
			range_ring.material_override = glow_material(Color(1, 1, 1, 0.75))
			range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(range_ring)
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh()
		ring.position.y = 1.5
		ring.visible = false
		ring.material_override = glow_material(Color.WHITE)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(ring)
		level_root.add_child(node)
		info = {"node": node, "holder": holder, "mat": mat, "flag": flag, "ring": ring, "range": range_ring,
			"lv": lv, "type": t.type, "side": t.owner, "top": built.top * S, "smoke": built.smoke,
			"muzzle": built.muzzle * S, "bounce": 0.0, "smoke_t": randf()}
		models[t.id] = info
		if grew:
			info.bounce = 1.0
			sparkle(t.x, t.y, sides[t.owner].light)
	if info.side != t.owner:
		info.mat.set_shader_parameter("team_color", _team_lin(t.owner))
		info.side = t.owner
	info.node.position = Vector3(t.x, 0, t.y)
	return info


func _team_lin(side: int) -> Color:
	return sides[side].color


# ---------- Soldiers and tanks ----------
func _make_units() -> void:
	var T := MeshKit.TEAM
	# Chibi soldier: a big head, a big helmet in the army's color, a small body, marching legs
	var k := MeshKit.new()
	k.box(9, 9, 6.5, Vector3(0, 11.5, 0), T)
	k.box(9.4, 1.8, 6.9, Vector3(0, 9, 0), Color.WHITE)
	k.sphere(5.6, Vector3(0, 21, 0.4), Color("#ffd3a8"), Vector3.ONE, false, 8, 4)
	k.sphere(6.4, Vector3(0, 22.2, 0), MeshKit.LIGHT, Vector3(1, 0.85, 1), true, 8, 3)
	k.cyl(7.2, 7.2, 1.4, 8, Vector3(0, 22.4, 0), MeshKit.DARK, Basis(Vector3.UP, PI / 8))
	k.box(1.6, 1.8, 0.6, Vector3(-2, 20.6, 5.7), Color("#27304a"))
	k.box(1.6, 1.8, 0.6, Vector3(2, 20.6, 5.7), Color("#27304a"))
	k.box(2, 2.4, 15, Vector3(5.8, 12, 3), Color("#46506b"))
	k.box(3.4, 7, 3.4, Vector3(-2.4, 3.5, 0), Color("#5a6278"), 0.0, Vector2(1, 7))
	k.box(3.4, 7, 3.4, Vector3(2.4, 3.5, 0), Color("#5a6278"), 0.0, Vector2(2, 7))
	soldiers = _unit_mm(k.mesh(), MAX_SOLDIERS, true)
	soldiers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Soldiers' shadows come from a few plain boxes in the same places, which is much cheaper
	var sh := MeshKit.new()
	sh.box(9, 16, 6.5, Vector3(0, 12, 0), Color.WHITE)
	sh.box(12, 9, 11, Vector3(0, 22, 0), Color.WHITE)
	sh.box(8, 6, 3.4, Vector3(0, 3, 0), Color.WHITE)
	soldier_shadows = _unit_mm(sh.mesh(), MAX_SOLDIERS, false)
	soldier_shadows.material_override = StandardMaterial3D.new()
	soldier_shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# Tank
	var tk := MeshKit.new()
	tk.box(20, 8, 28, Vector3(0, 8, 0), T).box(16, 3, 8, Vector3(0, 9, 15), T)
	tk.box(6, 8, 30, Vector3(-12.5, 5, 0), Color("#5a6278")).box(6, 8, 30, Vector3(12.5, 5, 0), Color("#5a6278"))
	tk.box(14, 7, 14, Vector3(0, 15.5, -2), MeshKit.LIGHT)
	tk.cyl(1.8, 2, 20, 8, Vector3(0, 15.5, 14), Color("#b4bdcc"), Basis(Vector3.RIGHT, PI / 2))
	tanks = _unit_mm(tk.mesh(), MAX_TANKS, false)


func _unit_mm(m: Mesh, count: int, walk: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = m
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = paint_material(Color.WHITE, true, walk)
	mi.extra_cull_margin = 16000
	add_child(mi)
	return mi


func _draw_units(units: Array) -> void:
	var smm := soldiers.multimesh
	var shm := soldier_shadows.multimesh
	var shadows := soldier_shadows.visible
	var tmm := tanks.multimesh
	var s := 0
	var k := 0
	for u in units:
		var dx: float = u.to.x - u.from.x
		var dz: float = u.to.y - u.from.y
		var ang := atan2(dx, dz)
		var team: Color = sides[u.owner].color.srgb_to_linear()
		if u.power > 1:
			if k >= MAX_TANKS:
				continue
			tmm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, ang).scaled(Vector3.ONE * 1.55 * S), Vector3(u.x, absf(sin(time * 20 + u.id)) * 0.6, u.y)))
			tmm.set_instance_custom_data(k, Color(team.r, team.g, team.b, 0))
			k += 1
		else:
			if s >= MAX_SOLDIERS:
				continue
			var xf := Transform3D(Basis(Vector3.UP, ang).scaled(Vector3.ONE * 1.75 * S), Vector3(u.x, 0, u.y))
			smm.set_instance_transform(s, xf)
			if shadows:
				shm.set_instance_transform(s, xf)
			smm.set_instance_custom_data(s, Color(team.r, team.g, team.b, fmod(u.id * 0.137, 1.0)))
			s += 1
	smm.visible_instance_count = s
	shm.visible_instance_count = s if shadows else 0
	tmm.visible_instance_count = k


# ---------- Roads ----------
func _road_mesh(a, b, grow: float) -> ArrayMesh:
	var dx: float = b.x - a.x
	var dz: float = b.y - a.y
	var L := maxf(1.0, sqrt(dx * dx + dz * dz))
	var ux := dx / L
	var uz := dz / L
	var nx := -uz
	var nz := ux
	var end := maxf(1.0, L * grow)
	var w := 25.0
	var x1: float = a.x + ux * end
	var z1: float = a.y + uz * end
	var v1 := end / 30.0
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(a.x + nx * w, 0, a.y + nz * w), Vector3(a.x - nx * w, 0, a.y - nz * w),
		Vector3(x1 + nx * w, 0, z1 + nz * w), Vector3(x1 - nx * w, 0, z1 - nz * w)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, v1), Vector2(1, v1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 1, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


var _road_mats := {}


func _sync_roads(towers: Array, game_time: float) -> void:
	var seen := {}
	var order := 0
	for t in towers:
		for r in t.roads:
			var key := "%d>%d:%d" % [t.id, r.to.id, t.owner]
			seen[key] = true
			var grow := minf(1.0, (game_time - r.born) / 0.25)
			var mi: MeshInstance3D = roads.get(key)
			if mi == null:
				if not _road_mats.has(t.owner):
					var m := ShaderMaterial.new()
					m.shader = road_shader
					m.set_shader_parameter("color", sides[t.owner].color)
					_road_mats[t.owner] = m
				mi = MeshInstance3D.new()
				mi.mesh = _road_mesh(t, r.to, grow)
				mi.material_override = _road_mats[t.owner]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.set_meta("grow", grow)
				level_root.add_child(mi)
				roads[key] = mi
			elif mi.get_meta("grow") < 1.0:
				mi.mesh = _road_mesh(t, r.to, grow)
				mi.set_meta("grow", grow)
			mi.position.y = 1.0 + (order % 6) * 0.15
			order += 1
	for key in roads.keys():
		if not seen.has(key):
			roads[key].queue_free()
			roads.erase(key)


# ---------- Effects ----------
func _soft_texture(star := false) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dx := (x - 31.5) / 32.0
			var dy := (y - 31.5) / 32.0
			var a := 0.0
			if star:
				var ang := atan2(dy, dx) + PI / 2
				var rr := sqrt(dx * dx + dy * dy)
				var k := absf(fmod(ang * 5 / TAU + 100.5, 1.0) - 0.5) * 2 # 0 at a point, 1 between points
				var edge := lerpf(0.95, 0.38, k)
				a = clampf((edge - rr) * 20, 0, 1)
			else:
				a = clampf(1.0 - sqrt(dx * dx + dy * dy), 0, 1)
				a = a * a * (3 - 2 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _sprite(tex: Texture2D) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.transparent = true
	sp.no_depth_test = false
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.visible = false
	sp.pixel_size = 1.0 / 64.0
	add_child(sp)
	return sp


func _make_fx() -> void:
	var soft := _soft_texture()
	var star := _soft_texture(true)
	for i in 160:
		puffs.append(_sprite(soft))
	for i in 60:
		stars.append(_sprite(star))
	var ball := SphereMesh.new()
	ball.radius = 1
	ball.height = 2
	ball.radial_segments = 10
	ball.rings = 6
	for i in 30:
		var m := MeshInstance3D.new()
		m.mesh = ball
		m.material_override = glow_material(Color("#ffb347"))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		fires.append(m)
	for i in 16:
		var m := MeshInstance3D.new()
		m.mesh = _ring_mesh()
		m.material_override = glow_material(Color.WHITE)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		rings.append(m)
	var shell := SphereMesh.new()
	shell.radius = 3
	shell.height = 6
	var dark := paint_material(Color("#27304a"))
	for i in 40:
		var m := MeshInstance3D.new()
		m.mesh = shell
		m.material_override = dark
		m.visible = false
		add_child(m)
		shells.append(m)
	# Confetti and clash bits: one MultiMesh, colored per bit
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = MeshKit.new().box(6, 1, 4, Vector3.ZERO, MeshKit.TEAM).mesh()
	mm.instance_count = MAX_BITS
	mm.visible_instance_count = 0
	bit_mm = MultiMeshInstance3D.new()
	bit_mm.multimesh = mm
	bit_mm.material_override = paint_material(Color.WHITE, true)
	bit_mm.extra_cull_margin = 16000
	bit_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bit_mm)
	# The airstrike plane
	var p := MeshKit.new()
	p.cyl(5, 7, 52, 10, Vector3.ZERO, Color.WHITE, Basis(Vector3.RIGHT, PI / 2))
	p.cone(5, 12, 10, Vector3(0, 0, 32), Color.WHITE, Basis(Vector3.RIGHT, PI / 2))
	p.box(80, 2, 14, Vector3(0, 0, 2), MeshKit.TEAM).box(28, 1.6, 8, Vector3(0, 1, -23), MeshKit.TEAM)
	p.box(1.6, 14, 10, Vector3(0, 7, -23), MeshKit.TEAM).box(6, 3.5, 10, Vector3(0, 4.5, 14), Color("#46506b"))
	var pm := MeshInstance3D.new()
	pm.mesh = p.mesh()
	plane = pm
	plane.visible = false
	add_child(plane)


func set_plane_color(c: Color) -> void:
	(plane as MeshInstance3D).material_override = paint_material(c)


func _take(pool: Array):
	for p in pool:
		if not p.visible:
			return p
	return null


func puff(x: float, y: float, z: float, color: Color, size: float, life: float, vy := 30.0) -> void:
	var p: Sprite3D = _take(puffs)
	if p == null:
		return
	p.visible = true
	p.position = Vector3(x, y, z)
	p.modulate = color
	p.set_meta("fx", {"life": life, "max": life, "size": size, "vy": vy, "vx": (randf() - 0.5) * 14, "vz": (randf() - 0.5) * 14})
	p.scale = Vector3.ONE * size * 0.4


func fireball(x: float, y: float, z: float, size: float, color := Color("#ffb347")) -> void:
	var f: MeshInstance3D = _take(fires)
	if f == null:
		return
	f.visible = true
	f.position = Vector3(x, y, z)
	f.set_meta("fx", {"life": 0.45, "max": 0.45, "size": size, "color": color})


func ring(x: float, z: float, color: Color, size: float) -> void:
	var r: MeshInstance3D = _take(rings)
	if r == null:
		return
	r.visible = true
	r.position = Vector3(x, 2, z)
	r.set_meta("fx", {"life": 0.7, "max": 0.7, "size": size, "color": color})


func chunks(x: float, z: float, color: Color, n: int, speed := 90.0) -> void:
	for i in n:
		if bits.size() >= MAX_BITS:
			return
		var a := randf() * TAU
		var v := speed * (0.4 + randf() * 0.6)
		bits.append({"p": Vector3(x, 16, z), "v": Vector3(cos(a) * v, 60 + randf() * 70, sin(a) * v), "life": 0.9, "spin": randf() * 10, "rot": randf() * TAU, "c": color.srgb_to_linear()})


func explode(x: float, y: float, big: bool) -> void:
	var s := 50.0 if big else 18.0
	fireball(x, s * 0.4, y, s)
	fireball(x + (randf() - 0.5) * s, s * 0.3, y + (randf() - 0.5) * s, s * 0.6, Color("#ff7b29"))
	for i in (10 if big else 3):
		puff(x + (randf() - 0.5) * s, 6, y + (randf() - 0.5) * s, Color("#7a7a7a"), s * 1.4, 1.1 + randf() * 0.6, 26)
	if big:
		ring(x, y, Color("#ffd28a"), 140)


func clash(x: float, y: float, a: int, b: int) -> void:
	chunks(x, y, sides[a].color, 3)
	chunks(x, y, sides[b].color, 3)


func hit(x: float, y: float, side: int) -> void:
	chunks(x, y, sides[side].color, 4, 70)


func capture(x: float, y: float, side: int) -> void:
	ring(x, y, sides[side].color, 120)
	ring(x, y, Color.WHITE, 90)
	chunks(x, y, sides[side].color, 14, 150)
	for c in ["#ffd23f", "#ff7ad1", "#ffffff", "#4fc3ff"]:
		chunks(x, y, Color(c), 5, 150)
	sparkle(x, y, Color("#fff3a0"))
	for i in 8:
		var a := float(i) / 8 * TAU
		puff(x + cos(a) * 46, 4, y + sin(a) * 46, Color.WHITE, 30, 0.8, 14)


## Twinkling stars that float up from a building
func sparkle(x: float, y: float, color: Color) -> void:
	for i in 7:
		var p: Sprite3D = _take(stars)
		if p == null:
			return
		var a := randf() * TAU
		var d := 20 + randf() * 40
		p.visible = true
		p.position = Vector3(x + cos(a) * d, 40 + randf() * 60, y + sin(a) * d)
		p.modulate = color
		p.set_meta("fx", {"life": 0.9 + randf() * 0.4, "max": 1.3, "size": 16 + randf() * 12})


func muzzle(t, tx: float, ty: float) -> void:
	var info = models.get(t.id)
	var y: float = info.muzzle.y if info else 30.0
	var a := atan2(ty - t.y, tx - t.x)
	fireball(t.x + cos(a) * 18, y, t.y + sin(a) * 18, 6, Color("#ffe08a"))


func _update_fx(dt: float, towers: Array) -> void:
	for p in puffs:
		if not p.visible:
			continue
		var u: Dictionary = p.get_meta("fx")
		u.life -= dt
		if u.life <= 0:
			p.visible = false
			continue
		var k: float = 1.0 - u.life / u.max
		p.position += Vector3(u.vx, u.vy, u.vz) * dt
		p.scale = Vector3.ONE * u.size * (0.4 + k * 0.9)
		p.modulate.a = (1.0 - k) * 0.8
	for p in stars:
		if not p.visible:
			continue
		var u: Dictionary = p.get_meta("fx")
		u.life -= dt
		if u.life <= 0:
			p.visible = false
			continue
		var k: float = 1.0 - u.life / u.max
		p.position.y += 40 * dt
		p.rotation.z += dt * 3
		p.scale = Vector3.ONE * u.size * sin(minf(1.0, k * 1.4) * PI)
	for f in fires:
		if not f.visible:
			continue
		var u: Dictionary = f.get_meta("fx")
		u.life -= dt
		if u.life <= 0:
			f.visible = false
			continue
		var k: float = 1.0 - u.life / u.max
		f.scale = Vector3.ONE * u.size * (0.3 + k * 0.8)
		var c: Color = u.color
		c.a = 1.0 - k
		f.material_override.set_shader_parameter("color", c)
	for r in rings:
		if not r.visible:
			continue
		var u: Dictionary = r.get_meta("fx")
		u.life -= dt
		if u.life <= 0:
			r.visible = false
			continue
		var k: float = 1.0 - u.life / u.max
		var sz: float = 20 + u.size * k
		r.scale = Vector3(sz, 1, sz)
		var c: Color = u.color
		c.a = (1.0 - k) * 0.9
		r.material_override.set_shader_parameter("color", c)
	# Confetti
	var live := []
	for b in bits:
		b.life -= dt
		if b.life <= 0:
			continue
		b.v.y -= 300 * dt
		b.p += b.v * dt
		if b.p.y < 1.5:
			b.p.y = 1.5
			b.v.x *= 0.8
			b.v.z *= 0.8
		b.rot += b.spin * dt
		live.append(b)
	bits = live
	var mm := bit_mm.multimesh
	for i in bits.size():
		var b = bits[i]
		var sc := minf(1.0, b.life * 3)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3(1, 1, 0).normalized(), b.rot).scaled(Vector3.ONE * sc), b.p))
		mm.set_instance_custom_data(i, b.c)
	mm.visible_instance_count = bits.size()
	# Chimney smoke from tank factories
	for t in towers:
		var info = models.get(t.id)
		if info == null or info.smoke.is_empty() or t.owner == 0:
			continue
		info.smoke_t -= dt
		if info.smoke_t <= 0:
			info.smoke_t = 0.4
			for s in info.smoke:
				puff(t.x + s.x * S, s.y * S, t.y + s.z * S, Color.WHITE, 20, 1.6, 26)


# ---------- Cloud shadows (the clouds are invisible; only their shadows show) ----------
func _make_clouds() -> void:
	for i in 4:
		var k := MeshKit.new()
		for j in 5:
			k.sphere(70 + randf() * 50, Vector3((j - 2) * 80, 0, (randf() - 0.5) * 80), Color.WHITE, Vector3(1, 0.4, 1), false, 8, 5)
		var m := MeshInstance3D.new()
		m.mesh = k.mesh()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		m.set_meta("cloud", {"speed": 18 + randf() * 14, "z": randf(), "x": randf()})
		add_child(m)
		clouds.append(m)


func _move_clouds() -> void:
	for c in clouds:
		var u: Dictionary = c.get_meta("cloud")
		var span := fw + 1400
		var x := fmod(u.x * span + time * u.speed, span) - 700
		c.position = Vector3(x, 520, u.z * (fh + 400) - 200)


# ---------- Each frame ----------
## highlight: Callable(tower) -> "" / "source" / "over" / "bad" / "target"
func render(dt: float, battle: Battle, highlight: Callable, shells_list: Array) -> void:
	time += dt
	if level_root == null:
		return
	for t in battle.towers:
		var info := _sync_tower(t)
		# Squash and stretch: a springy bounce after growing, a squash when hit
		var pop: float = 1.0 + t.pop * 0.06
		var sy: float = 1.0 - t.flash * 0.06
		var sx: float = 1.0 + t.flash * 0.03
		if info.bounce > 0:
			info.bounce = maxf(0, info.bounce - dt * 1.8)
			var b: float = sin((1.0 - info.bounce) * PI * 3) * info.bounce * 0.18
			sy += b
			sx -= b * 0.5
		info.holder.scale = Vector3(S * pop * sx, S * pop * sy, S * pop * sx)
		info.mat.set_shader_parameter("hit_flash", t.flash)
		info.flag.rotation.y = sin(time * 4 + t.id) * 0.4
		if info.range:
			var rc: Color = Color.WHITE if t.owner == 0 else sides[t.owner].light
			rc.a = 0.75
			info.range.material_override.set_shader_parameter("color", rc)
		var hl: String = highlight.call(t)
		var threat: bool = t.owner == Battle.PLAYER and battle.threat_on(t) > 0
		info.ring.visible = hl != "" or threat
		if info.ring.visible:
			var bad := hl == "bad" or hl == "target" or (hl == "" and threat)
			var c := Color("#ff4a3a") if bad else Color.WHITE
			c.a = 0.95 if hl != "" and hl != "target" else 0.45 + 0.35 * sin(time * 8)
			info.ring.material_override.set_shader_parameter("color", c)
			var rs: float = t.radius() + 20
			info.ring.scale = Vector3(rs, 1, rs)
	_sync_roads(battle.towers, battle.time)
	_draw_units(battle.units)
	# Watchtower shots fly in a little arc
	for i in shells.size():
		var m := shells[i]
		if i >= shells_list.size():
			m.visible = false
			continue
		var s = shells_list[i]
		var k: float = 1.0 - s.time / s.dur
		m.visible = true
		m.position = Vector3(s.x1 + (s.x2 - s.x1) * k, s.h * (1 - k) + 10 * k + 18 * sin(k * PI), s.y1 + (s.y2 - s.y1) * k)
	# Airstrike: a plane flies over the target and the bombs fall
	plane.visible = not battle.strikes.is_empty()
	if plane.visible:
		var st = battle.strikes[0]
		var k: float = 1.0 - st.time / st.dur
		var dir := Vector3(0.6, 0, -0.8)
		var along := (k - 0.8) * 1500
		plane.position = Vector3(st.t.x, 170, st.t.y) + dir * along
		plane.rotation = Vector3(0, atan2(dir.x, dir.z), sin(time * 4) * 0.1)
		if k > 0.55 and randf() < 0.5:
			puff(plane.position.x, 160, plane.position.z, Color.WHITE, 14, 0.6, 0)
	_update_fx(dt, battle.towers)
	_move_clouds()


## Graphics quality. Low: the 3D drawn at about 640 pixels across and scaled up, hard shadows
## from buildings only, no smoothing. Medium: about 900 pixels across, soft shadows, soldiers'
## shadows, smoothing. High: the screen's full resolution and the softest shadows.
## The HUD and labels are always drawn at full resolution.
func set_quality(q: int) -> void:
	quality = clampi(q, 0, 2)
	var vp := get_viewport()
	var short := float(mini(vp.size.x, vp.size.y))
	var target: float = [640.0, 900.0, 100000.0][quality]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(target / maxf(short, 1.0), 0.5, 1.0)
	vp.msaa_3d = Viewport.MSAA_DISABLED if quality == 0 else Viewport.MSAA_2X
	sun.shadow_blur = [0.0, 1.0, 1.5][quality]
	RenderingServer.directional_shadow_atlas_set_size(1024 if quality == 0 else 2048, true)
	soldier_shadows.visible = quality > 0
	for c in clouds:
		c.visible = quality > 0


func lower_quality() -> bool:
	if quality == 0:
		return false
	set_quality(quality - 1)
	return true
