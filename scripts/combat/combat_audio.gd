## TEMPORARY PLACEHOLDER SOUNDS (COMBAT-01a), synthesised at startup. No sound files
## were downloaded for this milestone; replace with approved CC0 recordings (see
## docs/COMBAT-01A_REPORT.md) by assigning streams to CombatFX instead.
class_name CombatAudio
extends RefCounted

const RATE := 44100


## Rifle shot: a short broadband crack, a decaying low-passed noise body and a low thump.
static func gunshot() -> AudioStreamWAV:
	var n := int(RATE * 0.42)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * clampf(0.55 - t * 1.2, 0.05, 0.55)
		var crack := noise * exp(-t * 900.0) * 0.9
		var body := lp * exp(-t * 16.0) * 0.85
		var thump := sin(TAU * (95.0 - 40.0 * t) * t) * exp(-t * 22.0) * 0.6
		_put(data, i, crack + body + thump)
	return _wav(data)


## Reload: magazine out, magazine in, charging handle (three metallic clicks over ~2.2 s).
static func reload_sound() -> AudioStreamWAV:
	var n := int(RATE * 2.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var data := PackedByteArray()
	data.resize(n * 2)
	var clicks := [[0.35, 2100.0, 0.5], [1.55, 1700.0, 0.7], [2.05, 2600.0, 0.6]]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for c: Array in clicks:
			var dt: float = t - c[0]
			if dt >= 0.0 and dt < 0.08:
				v += (sin(TAU * c[1] * dt) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.4) * exp(-dt * 70.0) * c[2]
		_put(data, i, v)
	return _wav(data)


## GAMEPLAY-02C: a burst (grenade, rocket): a hard crack, a long rumbling low body and debris.
static func explosion() -> AudioStreamWAV:
	var n := int(RATE * 1.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.08
		lp2 += (lp - lp2) * 0.05
		var crack := noise * exp(-t * 120.0) * 0.9
		var body := lp * 6.0 * exp(-t * 3.2) * 0.8
		var rumble := lp2 * 14.0 * exp(-t * 1.8) * 0.7
		var thump := sin(TAU * (55.0 - 25.0 * t) * t) * exp(-t * 6.0) * 0.8
		_put(data, i, clampf(crack + body + rumble + thump, -1.0, 1.0))
	return _wav(data)


## GAMEPLAY-02C: a rocket leaving the tube (a whoosh with a bang).
static func launch() -> AudioStreamWAV:
	var n := int(RATE * 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * clampf(0.15 + t * 0.3, 0.1, 0.5)
		_put(data, i, noise * exp(-t * 60.0) * 0.8 + lp * exp(-t * 3.5) * 0.9)
	return _wav(data)


## Hit confirmation tick.
static func hit_tick(kill := false) -> AudioStreamWAV:
	var n := int(RATE * (0.12 if kill else 0.05))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var f := 1500.0 if kill else 2400.0
		_put(data, i, sin(TAU * f * t) * exp(-t * (30.0 if kill else 70.0)) * 0.5)
	return _wav(data)


static func _put(data: PackedByteArray, i: int, v: float) -> void:
	data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))


static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
