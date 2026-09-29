extends AudioStreamPlayer
## Background music made in code, as looping tracks: "menu" (the bouncy C, Am, F, G loop from
## the web version), "game" (quicker and punchier, for playing) and "boss" (dark and driving,
## for the Boss Battle). They're synthesized on background threads, so the game starts right
## away; each track fades in once it's ready, and switching tracks crossfades.

const RATE := 22050

## Each track: tempo, four chords (MIDI notes, two bars each), the arpeggio order, and how
## loud each part is. `kick` adds a soft thump on the beat, `offhat` moves the hi-hats
## between the beats.
const TRACKS := {
	"menu": {"bpm": 112.0, "chords": [[48, 55, 60, 64], [45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59]],
		"arp": [0, 1, 2, 3, 2, 1, 2, 3], "lead": 0.022, "bass": 0.12, "bass_every": 4, "hat": 0.02, "kick": 0.0},
	"game": {"bpm": 128.0, "chords": [[45, 52, 57, 60], [41, 48, 53, 57], [48, 55, 60, 64], [43, 50, 55, 59]],
		"arp": [0, 2, 1, 3, 0, 2, 3, 2], "lead": 0.024, "bass": 0.12, "bass_every": 2, "hat": 0.022, "kick": 0.16},
	"boss": {"bpm": 140.0, "chords": [[50, 57, 62, 65], [46, 53, 58, 62], [43, 50, 55, 58], [45, 52, 57, 61]],
		"arp": [0, 3, 2, 3, 1, 3, 2, 3], "lead": 0.02, "bass": 0.14, "bass_every": 2, "hat": 0.018, "kick": 0.2, "offhat": true},
}
const LOUD_DB := -4.0

var enabled := true
var track := "menu" # the track that should be playing
var _playing_track := ""
var _streams := {} # track -> AudioStreamWAV, once made
var _tasks := {} # track -> [task id, result box]
var _fade: Tween


func _ready() -> void:
	bus = "Master"
	volume_db = LOUD_DB
	# The menu's track first, so it's ready soonest
	for name in ["menu", "game", "boss"]:
		var box := []
		var spec: Dictionary = TRACKS[name]
		_tasks[name] = [WorkerThreadPool.add_task(func(): box.append(_synth(spec))), box]


func _process(_dt: float) -> void:
	for name in _tasks.keys():
		var id: int = _tasks[name][0]
		if not WorkerThreadPool.is_task_completed(id):
			continue
		WorkerThreadPool.wait_for_task_completion(id)
		var box: Array = _tasks[name][1]
		_tasks.erase(name)
		if box.is_empty():
			continue
		var data: PackedByteArray = box[0]
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.mix_rate = RATE
		s.stereo = false
		s.data = data
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = data.size() / 2
		_streams[name] = s
	if enabled and _playing_track != track and _streams.has(track):
		_switch()


## Asks for a track; it crossfades in as soon as it's ready
func play_track(name: String) -> void:
	if TRACKS.has(name):
		track = name


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		if _fade:
			_fade.kill()
		stop()
		_playing_track = ""


## Fades the old track out and the new one in
func _switch() -> void:
	var next: AudioStreamWAV = _streams[track]
	_playing_track = track
	if _fade:
		_fade.kill()
	_fade = create_tween()
	if playing:
		_fade.tween_property(self, "volume_db", -30.0, 0.4)
	_fade.tween_callback(func():
		stream = next
		volume_db = -30.0
		play())
	_fade.tween_property(self, "volume_db", LOUD_DB, 1.0)


static func _freq(note: int) -> float:
	return 440.0 * pow(2.0, (note - 69) / 12.0)


## Adds one note to the loop (wrapping around the end, so the loop is seamless)
static func _note(buf: PackedFloat32Array, f: float, start: int, dur: float, wave: String, vol: float) -> void:
	var n := buf.size()
	var count := int(dur * RATE)
	var decay := pow(0.0001 / vol, 1.0 / count)
	var env := vol
	var phase := 0.0
	var step := f / RATE
	var attack := int(0.01 * RATE)
	for k in count:
		phase += step
		phase -= floor(phase)
		var x := 0.0
		if wave == "square":
			x = 1.0 if phase < 0.5 else -1.0
		elif wave == "triangle":
			x = 4.0 * absf(phase - 0.5) - 1.0
		else:
			x = sin(phase * TAU)
		var a := env * (float(k) / attack if k < attack else 1.0)
		buf[(start + k) % n] += x * a
		env *= decay


## A soft kick drum: a sine that drops quickly in pitch
static func _kick(buf: PackedFloat32Array, start: int, vol: float) -> void:
	var n := buf.size()
	var count := int(0.16 * RATE)
	var phase := 0.0
	for k in count:
		var t := float(k) / RATE
		phase += (50.0 + 110.0 * exp(-t * 30.0)) / RATE
		buf[(start + k) % n] += sin(phase * TAU) * vol * exp(-t * 18.0)


## A whole track as 16-bit samples. Static and self-contained (it only touches its own
## buffers), so it's safe on a worker thread.
static func _synth(spec: Dictionary) -> PackedByteArray:
	var step_len: float = 60.0 / spec.bpm / 2.0 # eighth notes
	var chords: Array = spec.chords
	var arp: Array = spec.arp
	var steps := chords.size() * 16 # two bars per chord
	var n := int(steps * step_len * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var hat_len := int(0.05 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bass_every: int = spec.bass_every
	for s in steps:
		var chord: Array = chords[s / 16]
		var start := int(s * step_len * RATE)
		var beat := s % 8
		if beat % bass_every == 0:
			_note(buf, _freq(chord[0] - 12), start, step_len * (bass_every - 0.5), "triangle", spec.bass)
		_note(buf, _freq(chord[arp[beat]] + 12), start, step_len * 0.9, "square", spec.lead)
		if spec.kick > 0 and beat % 2 == 0:
			_kick(buf, start, spec.kick)
		# Hi-hats between the beats, and on them too in the busier tracks
		if (beat + 1) % 2 == 0 or (spec.kick > 0 and not spec.get("offhat", false)):
			var env: float = spec.hat
			for k in hat_len:
				buf[(start + k) % n] += (rng.randf() * 2.0 - 1.0) * env
				env *= 0.9995
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * 1.8, -1.0, 1.0) * 32767))
	return data
