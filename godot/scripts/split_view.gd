extends CanvasLayer
## 2 Players: the screen split in two (side by side when wide, top and bottom when tall),
## each half following one player. Both halves draw the same world at the screen's full
## resolution.

const CELL := 32.0

var halves: Array = [] # [{box, port, cam}, ...]
var _k := 1.0 # screen pixels per UI unit


func _ready() -> void:
	layer = 1
	for i in 2:
		var box := SubViewportContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var port := SubViewport.new()
		port.world_2d = get_viewport().world_2d
		port.handle_input_locally = false
		port.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		box.add_child(port)
		var cam := Camera2D.new()
		port.add_child(cam)
		add_child(box)
		halves.append({"box": box, "port": port, "cam": cam})
	var line := ColorRect.new()
	line.name = "Divider"
	line.color = Color("#1d2342")
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	get_viewport().size_changed.connect(layout)
	layout()


## Is the screen wide (split left and right) or tall (split top and bottom)?
func wide() -> bool:
	var vis := get_viewport().get_visible_rect().size
	return vis.x >= vis.y


## The half of the screen (in UI units) that player `i` sees
func rect(i: int) -> Rect2:
	var vis := get_viewport().get_visible_rect().size
	if wide():
		return Rect2(Vector2(vis.x / 2 * i, 0), Vector2(vis.x / 2, vis.y))
	return Rect2(Vector2(0, vis.y / 2 * i), Vector2(vis.x, vis.y / 2))


func layout() -> void:
	_k = get_viewport().get_final_transform().get_scale().x
	for i in 2:
		var r := rect(i)
		var h: Dictionary = halves[i]
		# Draw at full screen resolution: a viewport k times bigger, shown at 1/k scale
		h.port.size = Vector2i(r.size * _k)
		h.box.position = r.position
		h.box.size = r.size * _k
		h.box.scale = Vector2.ONE / _k
	var line: ColorRect = get_node("Divider")
	var vis := get_viewport().get_visible_rect().size
	line.position = Vector2(vis.x / 2 - 3, 0) if wide() else Vector2(0, vis.y / 2 - 3)
	line.size = Vector2(6, vis.y) if wide() else Vector2(vis.x, 6)


## Moves half `i`'s camera; `zoom` is in UI units, like the main camera's
func aim(i: int, pos: Vector2, zoom: float, offset: Vector2) -> void:
	var cam: Camera2D = halves[i].cam
	cam.position = pos
	cam.zoom = Vector2.ONE * zoom * _k
	cam.offset = offset
