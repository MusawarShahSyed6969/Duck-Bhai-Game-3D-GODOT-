class_name SFX
extends RefCounted
## Procedurally generated PLACEHOLDER sounds - no audio files needed.
## Every sound can be replaced by assigning your own AudioStream
## (WeaponData.fire_sound / reload_sound, PlayerSounds exports).

const RATE := 22050
static var _cache := {}


# ----------------------------------------------------------------------------
# Public sounds
# ----------------------------------------------------------------------------
## kind: "pistol", "rifle" or "shotgun"
static func gunshot(kind: String = "pistol") -> AudioStreamWAV:
	var key := "gun_" + kind
	if _cache.has(key):
		return _cache[key]
	var dur := 0.35
	var noise_decay := 18.0
	var thump_hz := 140.0
	var thump_decay := 22.0
	var lp := 0.35
	var vol := 0.9
	match kind:
		"rifle":
			dur = 0.30
			noise_decay = 22.0
			thump_hz = 110.0
			lp = 0.45
		"shotgun":
			dur = 0.70
			noise_decay = 7.0
			thump_hz = 70.0
			thump_decay = 9.0
			lp = 0.25
			vol = 1.0
	var buf := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var y := 0.0
	var phase := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		y += lp * (white - y)
		var f := thump_hz * (0.5 + 0.5 * exp(-t * 30.0))
		phase += TAU * f / RATE
		var noise := y * exp(-t * noise_decay) * 1.8
		var thump := sin(phase) * exp(-t * thump_decay) * 0.9
		var crack := white * exp(-t * 120.0) * 0.6
		buf[i] = (noise + thump + crack) * vol
	return _finish(key, buf)


static func click() -> AudioStreamWAV:
	if _cache.has("click"):
		return _cache["click"]
	var buf := _buf(0.1)
	_add_click(buf, 0.0, 1400.0, 0.9, 120.0)
	return _finish("click", buf)


static func switch_weapon() -> AudioStreamWAV:
	if _cache.has("switch"):
		return _cache["switch"]
	var buf := _buf(0.22)
	_add_click(buf, 0.0, 900.0, 0.8, 90.0)
	_add_click(buf, 0.09, 600.0, 0.9, 80.0)
	return _finish("switch", buf)


static func reload_weapon(duration: float = 1.5) -> AudioStreamWAV:
	var d := maxf(duration, 0.5)
	var key := "reload_%d" % int(d * 10.0)
	if _cache.has(key):
		return _cache[key]
	var buf := _buf(d + 0.2)
	_add_click(buf, d * 0.10, 500.0, 0.9, 70.0)    # magazine out
	_add_click(buf, d * 0.55, 300.0, 1.1, 50.0)    # magazine in
	_add_click(buf, d * 0.85, 800.0, 1.0, 80.0)    # bolt back
	_add_click(buf, d * 0.85 + 0.07, 1100.0, 1.0, 90.0)  # bolt forward
	return _finish(key, buf)


static func step(variant: int = 0) -> AudioStreamWAV:
	var key := "step_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var buf := _buf(0.18)
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + variant
	var lp := 0.30 + 0.08 * variant            # brighter noise = audible on laptop speakers
	var y := 0.0
	var phase := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		y += lp * (white - y)
		phase += TAU * (120.0 + 14.0 * variant) / RATE
		var scuff := y * 3.4 * exp(-t * 20.0)
		var thump := sin(phase) * 0.9 * exp(-t * 26.0)
		var tick := white * 0.5 * exp(-t * 160.0)
		buf[i] = (scuff + thump + tick) * 0.95
	return _finish(key, buf)


static func jump() -> AudioStreamWAV:
	if _cache.has("jump"):
		return _cache["jump"]
	var dur := 0.24
	var buf := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var y := 0.0
	var phase := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var k := t / dur
		var env := pow(sin(PI * k), 2.0)
		y += (0.05 + 0.25 * k) * (rng.randf_range(-1.0, 1.0) - y)
		phase += TAU * (180.0 + 120.0 * k) / RATE
		buf[i] = (y * 2.0 + sin(phase) * 0.25) * env * 0.7
	return _finish("jump", buf)


static func land() -> AudioStreamWAV:
	if _cache.has("land"):
		return _cache["land"]
	var buf := _buf(0.26)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var y := 0.0
	var phase := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		y += 0.2 * (white - y)
		phase += TAU * 85.0 / RATE
		buf[i] = (y * 3.6 * exp(-t * 16.0) + sin(phase) * 1.1 * exp(-t * 14.0) + white * 0.4 * exp(-t * 120.0)) * 0.95
	return _finish("land", buf)


static func hurt() -> AudioStreamWAV:
	if _cache.has("hurt"):
		return _cache["hurt"]
	return _voice("hurt", 0.32, 220.0, 130.0, 7.0, 0.9)


static func death() -> AudioStreamWAV:
	if _cache.has("death"):
		return _cache["death"]
	return _voice("death", 0.9, 180.0, 70.0, 3.0, 1.0)


## High pitched ringing after a blinding flash.
static func flash_ring() -> AudioStreamWAV:
	if _cache.has("flash_ring"):
		return _cache["flash_ring"]
	var buf := _buf(2.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var p1 := 0.0
	var p2 := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		p1 += TAU * 3100.0 / RATE
		p2 += TAU * 4400.0 / RATE
		var env := minf(t / 0.02, 1.0) * exp(-t * 1.1)
		buf[i] = (sin(p1) * 0.35 + sin(p2) * 0.2 + rng.randf_range(-1.0, 1.0) * 0.1 * exp(-t * 6.0)) * env
	return _finish("flash_ring", buf)


static func zombie_groan() -> AudioStreamWAV:
	if _cache.has("z_groan"):
		return _cache["z_groan"]
	return _voice("z_groan", 1.1, 95.0, 70.0, 1.6, 0.9, 6.0, 0.25)


static func zombie_hurt() -> AudioStreamWAV:
	if _cache.has("z_hurt"):
		return _cache["z_hurt"]
	return _voice("z_hurt", 0.35, 130.0, 80.0, 7.0, 0.9, 0.0, 0.2)


static func zombie_attack() -> AudioStreamWAV:
	if _cache.has("z_attack"):
		return _cache["z_attack"]
	return _voice("z_attack", 0.45, 150.0, 90.0, 5.0, 1.0, 14.0, 0.35)


static func zombie_death() -> AudioStreamWAV:
	if _cache.has("z_death"):
		return _cache["z_death"]
	return _voice("z_death", 1.2, 110.0, 40.0, 2.2, 1.0, 5.0, 0.3)


# ----------------------------------------------------------------------------
# Internals
# ----------------------------------------------------------------------------
## Crude "voice": glide down in pitch, a few harmonics, softened + breath noise.
static func _voice(key: String, dur: float, f_start: float, f_end: float, decay: float, vol: float, am_hz: float = 0.0, noise_amt: float = 0.12) -> AudioStreamWAV:
	var buf := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var phase := 0.0
	var y := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var k := t / dur
		phase += TAU * lerpf(f_start, f_end, k) / RATE
		var tone := 0.0
		for h in range(1, 6):
			tone += sin(phase * h) / h
		var env := minf(t / 0.015, 1.0) * exp(-t * decay)
		if am_hz > 0.0:
			env *= 0.65 + 0.35 * sin(TAU * am_hz * t)    # growl wobble
		var x := (tone * 0.7 + rng.randf_range(-1.0, 1.0) * noise_amt) * env
		y += 0.3 * (x - y)
		buf[i] = y * 1.8 * vol
	return _finish(key, buf)


static func _add_click(buf: PackedFloat32Array, at: float, freq: float, amp: float, decay: float) -> void:
	var start := int(at * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = start + 7
	var n := mini(int(0.12 * RATE), buf.size() - start)
	var y := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * freq / RATE
		y += 0.5 * (rng.randf_range(-1.0, 1.0) - y)
		buf[start + i] += (y * 0.7 + sin(phase) * 0.5) * exp(-t * decay) * amp


static func _buf(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	return buf


static func _finish(key: String, buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(tanh(buf[i]) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	_cache[key] = w
	return w
