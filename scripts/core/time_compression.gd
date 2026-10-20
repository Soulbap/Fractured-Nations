## Time compression with a fixed simulation step (WORLD-SANDBOX-01 / 01B).
##
## Engine.time_scale alone stretches every physics step (8 x = 0.13 s steps), which makes
## movement, collisions and fights coarser than at 1 x. Raising the physics tick rate with
## the scale keeps every step at 1/60 s: k x runs k times as many normal steps per second.
## The machine may not manage that many; the speed actually reached is measured (sample(),
## reached) and shown, never assumed from k.
##
## Used by the player's controls (CoreDemo.set_time_speed) and by the accelerated test
## scenarios, so both run the same simulation. The player's setting adapts the steps per
## rendered frame to a frame budget (WORLD-PLAYTEST-01; it was a fixed 16): when the CPU
## cannot keep up the war runs a little slower but the screen stays responsive (64 steps
## per frame gave frames of 300-440 ms at 8 x). Tests may fix the number for throughput.

class_name TimeCompression
extends RefCounted

const BASE_TICKS := 60
## Speed actually reached (simulated seconds per real second), smoothed over ~2 s.
static var reached := 1.0
static var _last_real_us := 0
static var _last_sim := 0.0
## WORLD-PLAYTEST-01: the player's setting adapts the steps per frame to a frame budget
## instead of a fixed 16: with the war running a step costs ~1.4 ms, so 16 steps plus the
## frame (~27 ms) capped 16 x at ~10 x even when the screen could take longer frames. The
## budget keeps the view responsive (~20 fps at worst) and never changes a step's length.
static var frame_budget_ms := 50.0
static var _adaptive := false
static var _k := 1.0
static var _last_ticks := 0
static var _frame_ms := 16.0


## k x speed with 1/60 s steps. max_steps: physics steps allowed per rendered frame
## (> 0: fixed, for tests; default: adapted to frame_budget_ms by sample()).
static func apply(k: float, max_steps := -1) -> void:
	Engine.physics_ticks_per_second = maxi(int(round(BASE_TICKS * k)), 1)
	Engine.time_scale = k
	_k = k
	_adaptive = max_steps <= 0 and k > 1.0
	Engine.max_physics_steps_per_frame = max_steps if max_steps > 0 else clampi(int(2.0 * k), 8, 16)


static func reset() -> void:
	apply(1.0)


## Simulated seconds per physics step.
static func step_s() -> float:
	return Engine.time_scale / float(Engine.physics_ticks_per_second)


## Called once per rendered frame with the simulation clock; updates `reached`.
static func sample(sim_time: float) -> void:
	var now := Time.get_ticks_usec()
	var ticks := Engine.get_physics_frames()
	if _last_real_us > 0:
		var dt := (now - _last_real_us) / 1.0e6
		if dt > 0.0 and dt < 1.0:
			reached = lerpf(reached, (sim_time - _last_sim) / dt, clampf(dt / 2.0, 0.0, 1.0))
			_frame_ms = lerpf(_frame_ms, dt * 1000.0, 0.2)
			if _adaptive:
				var cap := Engine.max_physics_steps_per_frame
				var used := ticks - _last_ticks
				# Steps were capped and the frame has room: allow more; over budget: fewer.
				if used >= cap and _frame_ms < frame_budget_ms * 0.85:
					cap += 2
				elif _frame_ms > frame_budget_ms * 1.15:
					cap -= 2
				Engine.max_physics_steps_per_frame = clampi(cap, 8, maxi(int(4.0 * _k), 8))
	_last_real_us = now
	_last_sim = sim_time
	_last_ticks = ticks


## "8x" or "8x (reached 5.6x)" when the machine falls clearly short.
static func label() -> String:
	var k := Engine.time_scale
	if k > 1.0 and reached < k * 0.9:
		return "%dx (reached %.1fx)" % [int(k), reached]
	return "%dx" % int(k)
