## Time compression with a fixed simulation step (WORLD-SANDBOX-01 / 01B).
##
## Engine.time_scale alone stretches every physics step (8 x = 0.13 s steps), which makes
## movement, collisions and fights coarser than at 1 x. Raising the physics tick rate with
## the scale keeps every step at 1/60 s: k x runs k times as many normal steps per second.
## The machine may not manage that many; the speed actually reached is measured (sample(),
## reached) and shown, never assumed from k.
##
## Used by the player's controls (CoreDemo.set_time_speed) and by the accelerated test
## scenarios, so both run the same simulation. The player's setting allows at most 16
## steps per rendered frame: when the CPU cannot keep up the war runs a little slower but
## the screen stays responsive (64 steps per frame gave frames of 300-440 ms at 8 x with
## the war running in the abstract tier). Tests may allow more for throughput.

class_name TimeCompression
extends RefCounted

const BASE_TICKS := 60
## Speed actually reached (simulated seconds per real second), smoothed over ~2 s.
static var reached := 1.0
static var _last_real_us := 0
static var _last_sim := 0.0


## k x speed with 1/60 s steps. max_steps: physics steps allowed per rendered frame.
static func apply(k: float, max_steps := -1) -> void:
	Engine.physics_ticks_per_second = maxi(int(round(BASE_TICKS * k)), 1)
	Engine.time_scale = k
	Engine.max_physics_steps_per_frame = max_steps if max_steps > 0 else clampi(int(2.0 * k), 8, 16)


static func reset() -> void:
	apply(1.0)


## Simulated seconds per physics step.
static func step_s() -> float:
	return Engine.time_scale / float(Engine.physics_ticks_per_second)


## Called once per rendered frame with the simulation clock; updates `reached`.
static func sample(sim_time: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_real_us > 0:
		var dt := (now - _last_real_us) / 1.0e6
		if dt > 0.0 and dt < 1.0:
			reached = lerpf(reached, (sim_time - _last_sim) / dt, clampf(dt / 2.0, 0.0, 1.0))
	_last_real_us = now
	_last_sim = sim_time


## "8x" or "8x (reached 5.6x)" when the machine falls clearly short.
static func label() -> String:
	var k := Engine.time_scale
	if k > 1.0 and reached < k * 0.9:
		return "%dx (reached %.1fx)" % [int(k), reached]
	return "%dx" % int(k)
