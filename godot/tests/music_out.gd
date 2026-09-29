extends SceneTree
## Writes each music track to a WAV file, to listen to:
##   godot --headless --path godot -s tests/music_out.gd -- OUT_DIR

func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var M = load("res://scripts/music.gd")
	for name in M.TRACKS:
		var t0 := Time.get_ticks_msec()
		var data: PackedByteArray = M._synth(M.TRACKS[name])
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.mix_rate = M.RATE
		s.data = data
		s.save_to_wav("%s/%s.wav" % [out, name])
		print("%s: %.1f s of music, made in %d ms" % [name, data.size() / 2.0 / M.RATE, Time.get_ticks_msec() - t0])
	quit()
