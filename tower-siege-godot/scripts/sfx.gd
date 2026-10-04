extends Node
## Sound effects made in code when the game starts (the same recipes as the web version),
## so there are no audio files. Shared with Color Claim HD (godot/scripts/sfx.gd), plus a few
## Tower Siege sounds at the end of the list.

const RATE := 22050
const LOUD := 2.6 # the recipes are quiet; phone speakers need more

var muted := false
var _streams := {}
var _last := {}
var _players: Array[AudioStreamPlayer] = []

## name: [min gap between plays, [parts...]]. A part is a tone, a noise burst or an arpeggio.
var _recipes := {
	"capture": [0.1, [["arp", [523, 784], 0.06, "triangle", 0.08]]],
	"cut": [0.1, [["noise", 0.15, 0.1], ["arp", [784, 1175], 0.05, "square", 0.04]]],
	"death": [0.5, [["tone", 400, 40, 0.7, "saw", 0.1], ["noise", 0.5, 0.08]]],
	"win": [1.0, [["arp", [523, 659, 784, 1047, 1319, 1568], 0.09, "triangle", 0.09]]],
	"beep": [0.3, [["tone", 660, 660, 0.12, "square", 0.06]]],
	"go": [0.3, [["arp", [784, 1175], 0.07, "square", 0.07]]],
	"warn": [1.0, [["arp", [110, 98], 0.18, "square", 0.06]]],
	"hype": [0.25, [["arp", [659, 880, 1175], 0.05, "square", 0.045]]],
	"tap": [0.05, [["tone", 660, 990, 0.08, "triangle", 0.05]]],
	"coin": [0.05, [["arp", [988, 1319], 0.05, "square", 0.05]]],
	"speed": [0.2, [["noise", 0.25, 0.06], ["tone", 300, 1400, 0.25, "saw", 0.04]]],
	"shield": [0.2, [["arp", [392, 587, 784], 0.07, "sine", 0.09]]],
	"freeze": [0.3, [["arp", [2093, 1760, 1568, 1319], 0.05, "sine", 0.05]]],
	"ghost": [0.3, [["tone", 700, 250, 0.5, "sine", 0.07]]],
	"paint": [0.3, [["noise", 0.25, 0.12], ["arp", [392, 523, 659], 0.05, "triangle", 0.07]]],
	"bosshit": [0.2, [["tone", 520, 130, 0.25, "square", 0.07], ["noise", 0.2, 0.08]]],
	"bossdown": [1.0, [["noise", 0.9, 0.14], ["arp", [196, 262, 330, 392, 523], 0.1, "triangle", 0.09]]],
	"roar": [1.0, [["tone", 160, 60, 0.6, "saw", 0.09], ["noise", 0.4, 0.05]]],
	"hurt": [0.2, [["tone", 240, 70, 0.22, "saw", 0.08]]],
	"tick": [0.3, [["tone", 880, 880, 0.06, "square", 0.05]]],
	"portal": [0.2, [["tone", 220, 1760, 0.35, "sine", 0.09], ["arp", [880, 1320], 0.06, "triangle", 0.04]]],
	"saw": [0.3, [["noise", 0.3, 0.12], ["tone", 1400, 900, 0.3, "saw", 0.05]]],
	"storm": [1.0, [["noise", 1.2, 0.1], ["tone", 90, 45, 1.0, "saw", 0.07]]],
	"trap": [0.4, [["tone", 1200, 600, 0.08, "square", 0.05], ["noise", 0.08, 0.05]]],
	"blink": [0.4, [["arp", [1568, 1175, 784, 523], 0.05, "sine", 0.07]]],
	"boing": [0.08, [["tone", 180, 620, 0.16, "sine", 0.1], ["tone", 620, 300, 0.12, "triangle", 0.05]]],
	"hill": [0.5, [["arp", [523, 659, 784], 0.06, "triangle", 0.06]]],
	# Tower Siege (the same recipes as tower-siege/game.js uses through shared/sfx.js)
	"shoot": [0.06, [["tone", 900, 500, 0.05, "square", 0.015]]],
	"hit": [0.04, [["tone", 220, 120, 0.05, "triangle", 0.05]]],
	"pop": [0.03, [["tone", 600, 1300, 0.08, "sine", 0.05]]],
	"boom": [0.2, [["noise", 0.6, 0.18], ["tone", 120, 30, 0.5, "sine", 0.15]]],
	"trophy": [0.5, [["arp", [784, 988, 1175, 1568], 0.08, "triangle", 0.09]]],
}


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for sound in _recipes:
		_streams[sound] = _build(_recipes[sound][1])


func play(sound: String) -> void:
	if muted or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last.get(sound, -10.0) < _recipes[sound][0]:
		return
	_last[sound] = now
	for p in _players:
		if not p.playing:
			p.stream = _streams[sound]
			p.play()
			return


func _build(parts: Array) -> AudioStreamWAV:
	var voices := [] # [freq, to, dur, wave, vol, delay] and ["noise", dur, vol, delay]
	for part in parts:
		match part[0]:
			"tone":
				voices.append([part[1], part[2], part[3], part[4], part[5], 0.0])
			"noise":
				voices.append(["noise", part[1], part[2], 0.0])
			"arp":
				var notes: Array = part[1]
				for k in notes.size():
					voices.append([notes[k], notes[k], part[2] * 1.6, part[3], part[4], k * part[2]])
	var length := 0.0
	for v in voices:
		length = maxf(length, (v[3] + v[1]) if v[0] is String else (v[5] + v[2]))
	var n := int((length + 0.03) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for v in voices:
		if v[0] is String:
			_noise(buf, v[1], v[2], v[3])
		else:
			_tone(buf, v[0], v[1], v[2], v[3], v[4], v[5])
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * LOUD, -1.0, 1.0) * 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _tone(buf: PackedFloat32Array, f0: float, f1: float, dur: float, wave: String, vol: float, delay: float) -> void:
	var start := int(delay * RATE)
	var count := int(dur * RATE)
	var phase := 0.0
	for k in count:
		var i := start + k
		if i >= buf.size():
			break
		var t := float(k) / count
		var f := f0 * pow(f1 / f0, t) # exponential sweep
		phase = fmod(phase + f / RATE, 1.0)
		var x := 0.0
		match wave:
			"square":
				x = 1.0 if phase < 0.5 else -1.0
			"triangle":
				x = 4.0 * absf(phase - 0.5) - 1.0
			"saw":
				x = 2.0 * phase - 1.0
			_:
				x = sin(phase * TAU)
		var env := vol * pow(0.0001 / vol, t) # exponential fade
		if k < 60:
			env *= k / 60.0 # no click at the start
		buf[i] += x * env


func _noise(buf: PackedFloat32Array, dur: float, vol: float, delay: float) -> void:
	var start := int(delay * RATE)
	var count := int(dur * RATE)
	for k in count:
		var i := start + k
		if i >= buf.size():
			break
		buf[i] += (randf() * 2.0 - 1.0) * (1.0 - float(k) / count) * vol
