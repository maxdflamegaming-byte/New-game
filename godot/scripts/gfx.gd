class_name Gfx
extends RefCounted
## Graphics settings: a quality level (Low, Medium, High, Ultra) and a frame-rate cap
## (30 to 120). Drawing code asks Gfx how much to draw, so a slower phone can trade effects
## for smoothness.

const LEVELS := ["Low", "Medium", "High", "Ultra"]
const LOW := 0
const MEDIUM := 1
const HIGH := 2
const ULTRA := 3
const FPS := [30, 60, 90, 120]
const PARTICLES := [0.35, 0.65, 1.0, 1.4] # share of particles drawn at each level

static var level := HIGH
static var fps := 60
static var show_fps := false


## How many particles to use for an effect designed with `n`
static func particles(n: int) -> int:
	return maxi(2, roundi(n * PARTICLES[level]))


## A sensible starting level for this device, from how much memory it has
static func default_level() -> int:
	var mem: Dictionary = OS.get_memory_info()
	var gb: float = mem.get("physical", 0) / 1073741824.0
	if gb <= 0:
		return HIGH # unknown (desktop tests)
	if gb < 3.0:
		return LOW
	if gb < 5.0:
		return MEDIUM
	return HIGH


## Puts the settings into effect: resolution, anti-aliasing and frame rate
static func apply(tree: SceneTree) -> void:
	var root := tree.root
	# Low draws at 720p and scales up; the others draw at the screen's full resolution
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if level == LOW else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.msaa_2d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][level]
	Engine.max_fps = fps
	_request_refresh_rate(fps)


## The screen's refresh rate right now, in Hz (0 if the phone doesn't say)
static func screen_hz() -> int:
	var hz := DisplayServer.screen_get_refresh_rate()
	return roundi(hz) if hz > 0 else 0


## Android picks the screen's refresh rate for each app. Ask for the one we want, so a
## 90 or 120 Hz screen can run the game that fast (Android 11 and newer; older phones and
## other systems simply keep their normal rate).
static func _request_refresh_rate(hz: int) -> void:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return
	# Surface.setFrameRate needs Android 11 (the version may come as "11" or as SDK "30")
	var v := OS.get_version().to_int()
	if v < 11 or (v > 16 and v < 30):
		return
	var runtime = Engine.get_singleton("AndroidRuntime")
	var activity = runtime.getActivity()
	if activity == null:
		return
	var fragment = activity.getGodotFragment()
	if fragment == null:
		return
	var godot = fragment.getGodot()
	if godot == null:
		return
	var render_view = godot.getRenderView()
	if render_view == null:
		return
	var view = render_view.getView()
	if view == null:
		return
	var holder = view.getHolder()
	if holder == null:
		return
	var surface = holder.getSurface()
	if surface == null:
		return
	surface.setFrameRate(float(hz), 0)
