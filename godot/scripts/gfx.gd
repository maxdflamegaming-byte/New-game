class_name Gfx
extends RefCounted
## Graphics settings: a quality level (Low, Medium, High) and a frame-rate cap (30 or 60).
## Ultra and 90/120 FPS are switched off for now while crashes on some phones are tracked
## down; the Ultra code paths stay, but nothing can pick them. Drawing code asks Gfx how much to draw, so a slower phone can trade effects
## for smoothness.

const LEVELS := ["Low", "Medium", "High"]
const LOW := 0
const MEDIUM := 1
const HIGH := 2
const ULTRA := 3
const FPS := [30, 60]
const PARTICLES := [0.35, 0.65, 1.0, 1.4] # share of particles drawn at each level

static var level := MEDIUM
static var fps := 60
static var show_fps := false


## How many particles to use for an effect designed with `n`
static func particles(n: int) -> int:
	return maxi(2, roundi(n * PARTICLES[level]))


## A safe starting level for this device: Medium (Low on phones with little memory). Players
## with fast phones can turn it up in Settings.
static func default_level() -> int:
	var mem: Dictionary = OS.get_memory_info()
	var gb: float = mem.get("physical", 0) / 1073741824.0
	if gb > 0 and gb < 3.0:
		return LOW
	return MEDIUM


## Puts the settings into effect: resolution and frame rate.
## Low and Medium draw the game at 720p and scale it up to the screen, which is much less
## work for the phone; High and Ultra draw at the screen's full resolution.
static func apply(tree: SceneTree) -> void:
	var root := tree.root
	var mode := Window.CONTENT_SCALE_MODE_VIEWPORT if level <= MEDIUM else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if root.content_scale_mode != mode:
		root.content_scale_mode = mode
	# The screen's own refresh (vsync) paces the game; a cap is only set below that rate
	var hz := screen_hz()
	Engine.max_fps = 0 if hz > 0 and fps >= hz else fps


## The screen's refresh rate right now, in Hz (0 if the phone doesn't say)
static func screen_hz() -> int:
	var hz := DisplayServer.screen_get_refresh_rate()
	return roundi(hz) if hz > 0 else 0
