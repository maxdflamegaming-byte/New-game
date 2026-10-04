class_name Characters
extends RefCounted
## The story's characters, built in code from simple shapes like everything else:
##   Captain Skye (blue): your adviser, with a peaked cap and a ponytail
##   General Grumble (red): the villain, with a bicorne hat, a huge mustache and medals
##   Duke Mustard (yellow): a top hat, a monocle and a thin curly mustache
##   Major Moss (green): a leafy helmet, goggles and freckles
## Each is an Actor: a body, a head that bobs while talking (its mouth opens and closes), and
## two arms that wave, cheer, shake a fist or point.

const CAST := {
	"skye": {"name": "Captain Skye", "side": 1, "voice": "blip"},
	"grumble": {"name": "General Grumble", "side": 2, "voice": "blip_low"},
	"mustard": {"name": "Duke Mustard", "side": 3, "voice": "blip"},
	"moss": {"name": "Major Moss", "side": 4, "voice": "blip"},
}
const SKIN := Color("#ffd3a8")
const DARK := Color("#27304a")
const GOLD := Color("#ffd23f")


## A character, standing at the origin and facing +z (scale it like a soldier)
class Actor:
	extends Node3D
	var id := ""
	var body: Node3D
	var head: Node3D
	var mouth: Node3D
	var arm_l: Node3D
	var arm_r: Node3D
	var pose := "idle"           # idle, wave, cheer, angry, point, laugh, flee, shock
	var talking := false
	var t := randf() * 10.0
	var base_y := 0.0
	var size := 1.0              # grows in when it appears
	var run_dir := Vector3.ZERO  # fleeing: where to

	func _process(dt: float) -> void:
		t += dt
		var y := 0.0
		var lift_l := 0.15
		var lift_r := -0.15
		var swing_l := 0.0
		var swing_r := 0.0
		var lean := 0.0
		var shake := 0.0
		match pose:
			"wave":
				lift_r = -2.6 + sin(t * 9.0) * 0.35
			"cheer":
				y = absf(sin(t * 7.0)) * 7.0
				lift_l = 2.7 + sin(t * 14.0) * 0.2
				lift_r = -2.7 - sin(t * 14.0) * 0.2
			"angry":
				lift_r = -2.3 + sin(t * 22.0) * 0.4
				lift_l = 0.6
				shake = sin(t * 40.0) * 0.06
			"point":
				lift_r = -0.25
				swing_r = -1.45
			"laugh":
				y = absf(sin(t * 12.0)) * 2.5
				lean = -0.18
				lift_l = 0.9 + sin(t * 12.0) * 0.15
				lift_r = -0.9 - sin(t * 12.0) * 0.15
			"flee":
				y = absf(sin(t * 16.0)) * 5.0
				swing_l = sin(t * 16.0) * 0.9
				swing_r = -sin(t * 16.0) * 0.9
				lean = 0.25
				position += run_dir * dt
			"shock":
				lift_l = 1.4
				lift_r = -1.4
				y = maxf(0.0, sin(t * 3.0)) * 3.0
			_:
				lift_l = 0.12 + sin(t * 1.6) * 0.04
				lift_r = -0.12 - sin(t * 1.6) * 0.04
		var k := minf(1.0, dt * 14.0)
		# (raising an arm turns it out to its own side)
		arm_l.rotation.z = lerpf(arm_l.rotation.z, -lift_l, k)
		arm_r.rotation.z = lerpf(arm_r.rotation.z, -lift_r, k)
		arm_l.rotation.x = lerpf(arm_l.rotation.x, swing_l, k)
		arm_r.rotation.x = lerpf(arm_r.rotation.x, swing_r, k)
		body.position.y = y
		body.rotation.x = lerpf(body.rotation.x, lean, k)
		body.rotation.y = shake
		# Breathing, and the head bobbing and the mouth moving while talking
		body.scale = Vector3(1.0, 1.0 + sin(t * 2.2) * 0.015, 1.0)
		if talking:
			head.rotation.x = sin(t * 11.0) * 0.07
			head.rotation.z = sin(t * 5.0) * 0.05
			mouth.scale.y = 0.35 + absf(sin(t * 13.0)) * 1.6
		else:
			head.rotation.x = lerpf(head.rotation.x, -0.05 if pose == "laugh" else 0.0, k)
			head.rotation.z = sin(t * 1.3) * 0.03
			mouth.scale.y = lerpf(mouth.scale.y, 1.4 if pose in ["laugh", "cheer", "shock"] else 1.0, k)


static func display_name(id: String) -> String:
	return CAST[id].name


static func side(id: String) -> int:
	return CAST[id].side


## Builds a character. `mat` paints it (a paint material in its army's color).
static func build(id: String, mat: Material) -> Actor:
	var a := Actor.new()
	a.id = id
	a.name = id
	a.body = Node3D.new()
	a.add_child(a.body)
	var b := MeshKit.new()
	var T := MeshKit.TEAM
	# Shoes, legs, coat, belt, buttons, collar and gold epaulettes
	for s in [-1, 1]:
		b.box(4.2, 3, 6, Vector3(s * 2.6, 1.5, 0.8), Color("#3b3b4a"))
		b.box(3.6, 8, 3.8, Vector3(s * 2.6, 7, 0), MeshKit.DARK)
		b.box(4.5, 1.5, 5, Vector3(s * 6.6, 24, 0), GOLD)
	b.box(12, 13, 8, Vector3(0, 17.5, 0), T)
	b.box(12.4, 2, 8.4, Vector3(0, 12.5, 0), Color("#5b3a26"))
	b.box(2.4, 2.4, 0.6, Vector3(0, 12.5, 4.3), GOLD)
	b.box(9, 2, 7, Vector3(0, 24.2, 0), MeshKit.LIGHT)
	for yy in [16.0, 19.5]:
		b.box(1.4, 1.4, 0.6, Vector3(0, yy, 4.1), GOLD)
	match id:
		"grumble":
			# A round belly and rows of medals
			b.sphere(7.6, Vector3(0, 16, 1.6), T, Vector3(1, 0.95, 0.85), false, 10, 6)
			for i in 3:
				b.cyl(1.2, 1.2, 0.6, 8, Vector3(-3.5 + i * 1.9, 20.5, 4.5), GOLD, Basis(Vector3.RIGHT, PI / 2))
				b.box(1.2, 1.6, 0.4, Vector3(-3.5 + i * 1.9, 22.2, 4.3), [Color("#ff5257"), Color("#4fc3ff"), Color("#7bdc4a")][i])
		"mustard":
			# A bow tie
			b.box(2.4, 2.4, 1.2, Vector3(-1.8, 23.2, 4.3), T).box(2.4, 2.4, 1.2, Vector3(1.8, 23.2, 4.3), T).box(1.4, 1.6, 1.4, Vector3(0, 23.2, 4.5), MeshKit.DARK)
		"moss":
			# A bandolier
			b.box(2.2, 15, 1, Vector3(0, 18, 4.2), Color("#6b4a2e"), 0.0)
	var bm := MeshInstance3D.new()
	bm.mesh = b.mesh()
	bm.material_override = mat
	a.body.add_child(bm)

	# Head: face, eyes with a shine, rosy cheeks, a nose, eyebrows; the mouth moves on its own
	a.head = Node3D.new()
	a.head.position = Vector3(0, 25, 0)
	a.body.add_child(a.head)
	var h := MeshKit.new()
	h.sphere(7.5, Vector3(0, 8, 0.3), SKIN, Vector3.ONE, false, 12, 7)
	for s in [-1, 1]:
		h.box(1.8, 2.4, 0.8, Vector3(s * 2.6, 8.6, 7.3), DARK)
		h.box(0.7, 0.7, 0.5, Vector3(s * 2.6 - 0.4, 9.3, 7.75), Color.WHITE)
		h.sphere(1.4, Vector3(s * 4.5, 6.3, 6.0), Color("#ffa1a1"), Vector3(1, 0.7, 0.5), false, 6, 3)
	h.sphere(1.3, Vector3(0, 7.2, 7.9), Color("#f5b98d"), Vector3.ONE, false, 6, 4)
	var brow := 0.0
	var brow_c := Color("#5b3a26")
	match id:
		"skye":
			brow = -0.15
			var hair := Color("#7a4a2a")
			h.sphere(7.9, Vector3(0, 9, -1.0), hair, Vector3(1.02, 1.0, 0.92), false, 10, 6)
			h.sphere(3.2, Vector3(0, 7, -8.6), hair, Vector3(1, 1.2, 1), false, 8, 5)
			h.box(11, 2.4, 2, Vector3(0, 12.3, 6.4), hair)
			# Peaked cap with a gold badge
			h.cyl(7.8, 7.4, 4.6, 12, Vector3(0, 14.2, 0), T)
			h.cyl(8.6, 8.6, 1.6, 12, Vector3(0, 16.8, -0.3), MeshKit.LIGHT)
			h.box(9.6, 0.8, 5, Vector3(0, 12.4, 7.3), MeshKit.DARK)
			h.box(2.2, 2.2, 0.6, Vector3(0, 15, 7.5), GOLD)
		"grumble":
			brow = 0.45
			brow_c = Color("#d8dae6")
			# A huge gray mustache and sideburns
			for s in [-1, 1]:
				h.sphere(3.0, Vector3(s * 3.2, 5.4, 7.4), Color("#e8e8ef"), Vector3(1.5, 0.65, 0.8), false, 8, 4)
				h.box(2.2, 6, 3, Vector3(s * 7.2, 7, 1.5), Color("#d8dae6"))
			# A bicorne hat with gold trim and a red cockade
			h.sphere(8.5, Vector3(0, 15.5, 0), Color("#2b2f45"), Vector3(1.45, 0.6, 0.5), false, 12, 6)
			h.box(22, 1.2, 1.2, Vector3(0, 13.4, 3.2), GOLD)
			h.sphere(1.8, Vector3(0, 16.4, 3.8), T, Vector3.ONE, false, 8, 4)
		"mustard":
			brow = -0.05
			# A thin curly mustache
			h.box(7, 1, 1, Vector3(0, 5.8, 7.6), Color("#7a4a2a"))
			for s in [-1, 1]:
				h.sphere(1.0, Vector3(s * 3.9, 6.6, 7.4), Color("#7a4a2a"), Vector3.ONE, false, 6, 3)
			# A top hat
			h.cyl(9.5, 9.5, 1.2, 14, Vector3(0, 14.4, 0), Color("#2b2f45"))
			h.cyl(5.8, 6.2, 12, 14, Vector3(0, 20.5, 0), Color("#2b2f45"))
			h.cyl(6.3, 6.3, 2.2, 14, Vector3(0, 16.2, 0), T)
		"moss":
			brow = -0.1
			for p in [Vector3(-4.6, 7.4, 6.4), Vector3(-3.6, 6.4, 6.8), Vector3(4.6, 7.4, 6.4), Vector3(3.6, 6.4, 6.8)]:
				h.box(0.6, 0.6, 0.4, p, Color("#b07a48"))
			# A helmet with leaves and goggles
			h.sphere(8.2, Vector3(0, 12, 0), MeshKit.DARK, Vector3(1, 0.85, 1), true, 12, 4)
			var leaf := Color("#4caf3c")
			for i in 6:
				var ang := i * TAU / 6
				h.sphere(2.6, Vector3(sin(ang) * 6, 17 + (i % 2) * 1.5, cos(ang) * 6), leaf.lightened(0.1 * (i % 3)), Vector3(1, 0.6, 1), false, 6, 3)
			for s in [-1, 1]:
				h.cyl(2.4, 2.4, 1.6, 10, Vector3(s * 2.8, 14.2, 6.6), GOLD, Basis(Vector3.RIGHT, PI / 2))
				h.cyl(1.7, 1.7, 1.8, 10, Vector3(s * 2.8, 14.2, 6.8), Color("#8fd8ff"), Basis(Vector3.RIGHT, PI / 2))
	for s in [-1, 1]:
		h.add(_box(3.2, 0.9, 0.8), Transform3D(Basis(Vector3.BACK, s * brow), Vector3(s * 2.6, 11.4, 7.1)), brow_c)
	if id == "mustard":
		# The monocle (in front of one eye) and its chain
		var ring := TorusMesh.new()
		ring.inner_radius = 1.6
		ring.outer_radius = 2.1
		ring.rings = 12
		ring.ring_segments = 4
		h.add(ring, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(2.6, 8.6, 7.9)), GOLD)
		h.box(0.4, 5, 0.4, Vector3(4.4, 5.6, 7.4), GOLD)
	var hm := MeshInstance3D.new()
	hm.mesh = h.mesh()
	hm.material_override = mat
	a.head.add_child(hm)
	a.mouth = Node3D.new()
	a.mouth.position = Vector3(0, 4.4 if id != "grumble" else 3.6, 7.2)
	a.head.add_child(a.mouth)
	var mm := MeshInstance3D.new()
	mm.mesh = MeshKit.new().box(3.6 if id != "moss" else 4.6, 1.3, 0.8, Vector3.ZERO, Color("#8a2a35")).mesh()
	mm.material_override = mat
	a.mouth.add_child(mm)

	# Arms: a sleeve, a cuff and a hand, hanging from the shoulder
	for s in [-1, 1]:
		var arm := Node3D.new()
		arm.position = Vector3(s * 7.4, 23, 0)
		a.body.add_child(arm)
		var k := MeshKit.new()
		k.box(3.6, 10, 3.6, Vector3(0, -5, 0), T)
		k.box(3.9, 1.5, 3.9, Vector3(0, -9.6, 0), MeshKit.LIGHT)
		k.sphere(2.1, Vector3(0, -11.6, 0), SKIN, Vector3.ONE, false, 8, 5)
		var am := MeshInstance3D.new()
		am.mesh = k.mesh()
		am.material_override = mat
		arm.add_child(am)
		if s < 0:
			a.arm_l = arm
		else:
			a.arm_r = arm
	return a


static func _box(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b
