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
var kills := 0
var respawn := 0.0
var shield := 0.0
var blocked := false
var squash := 0.0
var blink := 2.0

# Bot brain
var persona := "wildcard"
var greed := 40.0
var aggro := 0.3
var loop_scale := 1.0
var flee := 5.0
var mode := "idle"
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
