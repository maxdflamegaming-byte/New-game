class_name Replays
extends RefCounted
## Replays of your last battles. While a battle plays, what's on the field is written down ten
## times a second, the same way an online match sends it to the guest (every 10th update in
## full, the rest only what changed), with the moments worth showing (captures, clashes,
## watchtower shots). When it ends it's kept on the phone (the last MAX), compressed. Watching
## one rebuilds the field from those updates, through the same code that shows a guest the
## host's battle (net.gd), so nobody can change what happens.

const MAX := 8
const DIR := "user://replays"
const EVERY := 0.1
const KEY_EVERY := 10

var main
var rec := {}                 # the battle being written down
var _t := 0.0
var _task := -1               # the last replay being saved on a background thread


func _init(m) -> void:
	main = m


## A battle starts: meta has what's needed to set the field up again
func begin(meta: Dictionary) -> void:
	rec = {"meta": meta, "frames": [], "events": [], "sent": {}, "sent_tw": {}, "n": 0}
	_t = 0.0


func recording() -> bool:
	return not rec.is_empty()


func event(e: Array) -> void:
	if not rec.is_empty() and (e[0] != "cl" or rec.events.size() < 60):
		rec.events.append(e)


func tick(b: Battle, dt: float) -> void:
	if rec.is_empty():
		return
	_t -= dt
	if _t > 0:
		return
	_t = EVERY
	var f := {"tm": snappedf(b.time, 0.01), "ev": rec.events}
	rec.events = []
	var key: bool = rec.n % KEY_EVERY == 0
	var tw := []
	var tc := []
	for t in b.towers:
		var row := [roundi(t.units * 10), t.owner, t.roads.map(func(r): return r.to.id)]
		var sig := str(row)
		tw.append(row)
		if rec.sent_tw.get(t.id) != sig:
			tc.append([t.id] + row)
		rec.sent_tw[t.id] = sig
	var now := {}
	for u in b.units:
		now[u.id] = u.power
	if key:
		f.k = 1
		f.tw = tw
		f.u = b.units.map(func(u): return [u.id, u.from.id, u.to.id, roundi(u.d), u.power, u.owner, roundi(u.lane)])
	else:
		if not tc.is_empty():
			f.tc = tc
		var nu := []
		var pw := []
		var x := []
		for u in b.units:
			if not rec.sent.has(u.id):
				nu.append([u.id, u.from.id, u.to.id, roundi(u.d), u.power, u.owner, roundi(u.lane)])
			elif rec.sent[u.id] != u.power:
				pw.append([u.id, u.power])
		for id in rec.sent:
			if not now.has(id):
				x.append(id)
		if not nu.is_empty():
			f.nu = nu
		if not pw.is_empty():
			f.pw = pw
		if not x.is_empty():
			f.x = x
	rec.sent = now
	rec.n += 1
	rec.frames.append(f)


## The battle is over: keep it (result: "won", "lost", "draw" ...)
func finish(result: String) -> void:
	if rec.is_empty():
		return
	var r := rec
	rec = {}
	if r.frames.size() < 20:
		return # too short to be worth watching
	r.meta.result = result
	r.meta.secs = float(r.frames[-1].tm)
	# Packing and compressing a long battle took long enough to freeze a phone for a moment
	# just as the battle ended, so it's written on a background thread (the recording is only
	# numbers and arrays, which nothing else touches any more)
	wait()
	var path := "%s/%d.rep" % [DIR, int(Time.get_unix_time_from_system() * 1000)]
	_task = WorkerThreadPool.add_task(_write.bind(path, {"meta": r.meta, "frames": r.frames}))


static func _write(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	# Written under another name first, so a half-written file is never listed
	var tmp := path + ".part"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_var(data)
	f.close()
	DirAccess.rename_absolute(tmp, path)
	# Only the newest MAX are kept
	var files := _files()
	for i in range(MAX, files.size()):
		DirAccess.remove_absolute(DIR + "/" + files[i])


## Waits for a replay still being saved (before reading the list, or saving another)
func wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func stop() -> void:
	rec = {}


## Saved replays, newest first: file names
static func _files() -> Array:
	var d := DirAccess.open(DIR)
	if d == null:
		return []
	var out := Array(d.get_files()).filter(func(n): return n.ends_with(".rep"))
	out.sort()
	out.reverse()
	return out


## What each saved replay is: [{file, title, result, secs, when}], newest first
func list() -> Array:
	wait()
	var out := []
	for n in _files():
		var r = load_file(n, true)
		if r is Dictionary:
			out.append({"file": n, "title": r.meta.get("title", ""), "result": r.meta.get("result", ""),
				"secs": float(r.meta.get("secs", 0)), "when": int(r.meta.get("when", 0))})
	return out


func load_file(name: String, _meta_only := false) -> Variant:
	wait()
	var f := FileAccess.open_compressed(DIR + "/" + name, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	var v = f.get_var()
	f.close()
	return v if v is Dictionary and v.has("meta") and v.has("frames") else null
