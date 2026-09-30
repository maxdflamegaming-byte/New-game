class_name Player
extends RefCounted
## One square: you or a bot. Positions are in cells.

var id: int
var name: String
var color: Color
var dark: Color
var is_bot: bool

var pos := Vector2.ZERO
var cell := Vector2i.ZERO
var angle := 0.0
var desired := 0.0
var turning := 0.0 # -1..1, how hard it's turning this frame
var alive := false
var trail := PackedInt32Array()
var path := PackedVector2Array() # where it actually drove while outside its land (for drawing)
var path_breaks := PackedInt32Array() # where the path jumps (through a portal): a new piece starts
var portal_cd := 0.0 # a moment after using a portal before the next one works
var kills := 0
var respawn := 0.0
var shield := 0.0
var fx := {"speed": 0.0, "freeze": 0.0, "ghost": 0.0} # seconds left on each power-up
var blocked := false
var squash := 0.0
var blink := 2.0
var team := 0 # in Teams, 0 is yours; otherwise everyone is on their own
var lives := 1 # Boss Battle gives you 3

# The Boss Battle's King
var is_boss := false
var hp := 0
var max_hp := 0
var rage := false
var hit_flash := 0.0
var size := 1.0 # drawn size (the King is bigger)
var boss_kind := "" # king, queen or wizard
var power_timer := 2.0 # the Queen's traps and the Wizard's blink
var harmless := false # the tutorial's practice bot can't knock you out

# Looks from the shop
var skin := "plain"
var trail_fx := "none"
var pet := "none"

# Bot brain
var persona := "wildcard"
var greed := 40.0
var aggro := 0.3
var loop_scale := 1.0
var flee := 5.0
var grab_chance := 0.5 # how keen it is on power-ups (collectors also go for coins)
var mode := "idle"
# Skill level (bots): "rookie", "regular" or "pro"; empty for people, bosses and the coach
var skill := ""
var think_every := 0.25 # seconds between decisions
var look := 16 # how far ahead (in 0.05 s steps) it checks it won't hit its own trail
var wobble := 0.0 # how far its aim drifts (radians)
var drift := 0.0
var skill_speed := 1.0
var wp: Array[Vector2] = []
var think := 0.0
var route = null # PackedInt32Array of cells home, or null
var route_timer := 0.0


func _init(p_id: int, p_name: String, p_color: Color, bot: bool) -> void:
	id = p_id
	name = p_name
	color = p_color
	dark = p_color.darkened(0.3)
	is_bot = bot
	greed = randf_range(25, 60)
	aggro = randf_range(0.1, 0.5)
	loop_scale = randf_range(0.8, 1.5)
