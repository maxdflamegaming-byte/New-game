extends AudioStreamPlayer
## Background music made in code: a bouncy four-chord loop (C, Am, F, G) with bass, an
## arpeggio and soft hi-hats, the same as the web version's "Sunny" track. It's synthesized
## on a background thread, so the game starts right away and the music fades in when ready.

const RATE := 22050
const BPM := 112.0
const CHORDS := [[48, 55, 60, 64], [45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59]]
const ARP := [0, 1, 2, 3, 2, 1, 2, 3]

var enabled := true
var _task := -1
var _result := [] # the worker thread puts the finished loop here; nothing else is shared


func _ready() -> void:
	bus = "Master"
	volume_db = -4.0
	var out := _result
	_task = WorkerThreadPool.add_task(func(): out.append(_synth()))


func _process(_dt: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _result.is_empty():
			return
		var data: PackedByteArray = _result[0]
		_result.clear()
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.mix_rate = RATE
		s.stereo = false
		s.data = data
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = data.size() / 2
		stream = s
		set_enabled(enabled)


func set_enabled(on: bool) -> void:
	enabled = on
	if stream == null:
		return
	if on and not playing:
		volume_db = -30.0
		play()
		create_tween().tween_property(self, "volume_db", -4.0, 1.5)
	elif not on and playing:
		stop()


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


## The whole loop as 16-bit samples. Static and self-contained, so it's safe on a worker thread.
static func _synth() -> PackedByteArray:
	var step_len := 60.0 / BPM / 2.0 # eighth notes
	var steps := CHORDS.size() * 16 # two bars per chord
	var n := int(steps * step_len * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var hat_len := int(0.05 * RATE)
	var rng := RandomNumberGenerator.new()
	for s in steps:
		var chord: Array = CHORDS[s / 16]
		var start := int(s * step_len * RATE)
		var beat := s % 8
		if beat % 4 == 0:
			_note(buf, _freq(chord[0] - 12), start, step_len * 3.5, "triangle", 0.12)
		_note(buf, _freq(chord[ARP[beat]] + 12), start, step_len * 0.9, "square", 0.022)
		if (beat + 1) % 2 == 0:
			var env := 0.02
			for k in hat_len:
				buf[(start + k) % n] += (rng.randf() * 2.0 - 1.0) * env
				env *= 0.9995
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * 1.8, -1.0, 1.0) * 32767))
	return data
