## NAV-PERF-01B: the one route planning service. Every route search of normal play (squad marches, abstract infantry refinements,
## vehicle routes) is a job in this queue and runs inside a work budget per rendered frame; nothing waits for a route in the frame
## it asked for one.
##
## A job owns a *runner*: an object with `step(deadline_us: int) -> bool` (true when finished; 0 = no deadline, run to the end),
## `result: Dictionary` ({ok, reason, ...}) and `reset()` (start again from scratch). The runners keep their own incremental search
## state (LocalRoutePlanner.Search, VehicleRouter.PlanRunner, StrategicRoutes.Runner), so a search stops at a checkpoint when the
## frame's budget is spent and goes on in the next frame. Jobs run one at a time (a resumed search never interleaves with another
## inside one call); between frames the most important waiting job goes first.
##
## States: PENDING (queued) -> RUNNING (started, possibly suspended) -> COMPLETED / FAILED; CANCELLED (the consumer, or a newer
## request of the same owner, replaced it); INVALIDATED (the world changed under a running search: it starts again, counted).
## Consumers get a callback on COMPLETED and FAILED only, and check their own token (the job id they stored) as well: a result
## for an order that was replaced is never applied. A job that is already finished when submit() returns (a reused result, the
## synchronous comparison mode) gets no callback: the consumer stores its token and then looks at `is_done()` itself.
##
## Priority: PLAYER, COMBAT, OPERATION, CONVOY, STRATEGIC (lower is more important). A job gains one class every `aging_s` real
## seconds it waits, so a low-priority job cannot starve. Same owner: a new request cancels the old one unless it asks for the
## same thing (then the running job is kept: no cancel-and-restart loop). Same key (same search): later requests follow the
## first one and share its result (dedupe). Completed strategic routes are kept for reuse until the world changes.
class_name RouteService
extends RefCounted

enum State { PENDING, RUNNING, COMPLETED, FAILED, CANCELLED, INVALIDATED }
const STATE_NAMES: Array[String] = ["pending", "running", "completed", "failed", "cancelled", "invalidated"]
enum Priority { PLAYER, COMBAT, OPERATION, CONVOY, STRATEGIC }
const PRIORITY_NAMES: Array[String] = ["player", "combat", "operation", "convoy", "strategic"]

## Route work per rendered frame (ms) at 1x. Under time compression a frame carries several simulation steps and the budget is per
## step (WorldSim passes at most the compression factor, never the steps a slow frame caught up, and at most `max_steps`): a route
## takes about the same simulated time to arrive at 1x and at 8x, and TimeCompression keeps the frame inside its own budget.
var frame_budget_ms := 2.0
var max_steps := 64
## A waiting job is treated as one priority class more important for every `aging_s` real seconds it has waited.
var aging_s := 1.5
## Completed results kept for reuse (strategic routes), at most this many, dropped when the world changes.
var cache_max := 256
## Turn the queue off (every request runs at once, the old synchronous behaviour): for comparisons only.
var synchronous := false


class Job:
	var id := 0
	var kind := &""
	var owner := ""
	var priority := 0
	var key := ""
	var state := 0
	var runner: Object
	var result := {}
	var reason := ""
	var callback := Callable()
	## Dedupe: the job doing the search (null for a leader) and the requests sharing it.
	var leader: Job = null
	var followers: Array = []
	var from := Vector3.INF
	var to := Vector3.INF
	var created_us := 0
	var started_us := 0
	var finished_us := 0
	var work_us := 0
	var slices := 0
	var restarts := 0
	var revision := 0
	## Rect2 the search reads (null: anywhere); a world change elsewhere does not invalidate it.
	var area: Variant = null

	func is_done() -> bool:
		return state == RouteService.State.COMPLETED or state == RouteService.State.FAILED or state == RouteService.State.CANCELLED

	func ok() -> bool:
		return state == RouteService.State.COMPLETED and bool(result.get("ok", false))

	func state_name() -> String:
		return RouteService.STATE_NAMES[state]

	func wait_ms() -> float:
		return ((started_us if started_us > 0 else Time.get_ticks_usec()) - created_us) / 1000.0


var _next_id := 1
## Every job not finished yet (leaders only), and every job by id (finished ones are dropped after their callback).
var _queue: Array = []
var _jobs := {}
var _by_owner := {}
var _by_key := {}
var _cache := {}
## World revision: road, bridge and structure changes. A running search started on an older one starts again.
var revision := 0
var last_invalidation := ""
var _active: Job = null
var _in_submit := false
var stats := {"submitted": 0, "completed": 0, "failed": 0, "cancelled": 0, "superseded": 0, "invalidated": 0, "deduped": 0,
	"cache_hits": 0, "reused_same": 0, "sync_runs": 0, "slices": 0, "overruns": 0, "frames_with_work": 0}
var by_kind := {}
var queue_max := 0
var frame_ms_max := 0.0
var slice_ms_max := 0.0
## The longest single step per kind of search (ms): what one atomic piece of work costs.
var slice_max_by_kind := {}
## What the longest step was doing (kind, owner, the runner's own `debug_state()` before and after it).
var slice_max_info := {}
var last_frame_ms := 0.0
## Rolling samples (last 512) for percentiles: frame work, wait before start, total time to a result, search work.
var frame_samples := PackedFloat32Array()
var wait_samples := PackedFloat32Array()
var total_samples := PackedFloat32Array()
var work_samples := PackedFloat32Array()
const SAMPLES := 512
## The last finished jobs (debug overlay, tests): [{id, kind, owner, state, wait_ms, total_ms, work_ms, slices, restarts, reason}].
var recent: Array = []


## Queues a search. owner: who asked ("squad:12", "unit:40", "vehicle:7"); key: identical searches share one ("" = never shared);
## callback(job) on COMPLETED / FAILED. Returns the job (already finished when served from the cache or run synchronously).
func submit(kind: StringName, owner: String, priority: int, key: String, runner: Object, callback := Callable(), from := Vector3.INF,
		to := Vector3.INF, area: Variant = null) -> Job:
	_in_submit = true
	var job := _submit(kind, owner, priority, key, runner, callback, from, to, area)
	_in_submit = false
	return job


func _submit(kind: StringName, owner: String, priority: int, key: String, runner: Object, callback: Callable, from: Vector3,
		to: Vector3, area: Variant) -> Job:
	var now := Time.get_ticks_usec()
	var old: Job = _by_owner.get(owner)
	if old != null and not old.is_done():
		if key != "" and old.key == key:
			# The same request again (a re-issued order, a replan of the same leg): keep the search that is under way.
			old.callback = callback
			stats.reused_same += 1
			return old
		cancel(old, "superseded")
		stats.superseded += 1
	var job := Job.new()
	job.id = _next_id
	_next_id += 1
	job.kind = kind
	job.owner = owner
	job.priority = priority
	job.key = key
	job.runner = runner
	job.callback = callback
	job.from = from
	job.to = to
	job.area = area
	job.created_us = now
	job.revision = revision
	job.state = State.PENDING
	_jobs[job.id] = job
	if owner != "":
		_by_owner[owner] = job
	stats.submitted += 1
	by_kind[kind] = int(by_kind.get(kind, 0)) + 1
	if key != "":
		var hit: Dictionary = _cache.get(key, {})
		if not hit.is_empty() and int(hit.revision) == revision:
			stats.cache_hits += 1
			job.result = (hit.result as Dictionary).duplicate()
			job.started_us = now
			_finish(job, State.COMPLETED if bool(job.result.get("ok", false)) else State.FAILED)
			return job
		var lead: Job = _by_key.get(key)
		if lead != null and not lead.is_done():
			job.leader = lead
			lead.followers.append(job)
			if priority < lead.priority:
				lead.priority = priority
			stats.deduped += 1
			return job
		_by_key[key] = job
	if synchronous:
		run_now(job)
		return job
	_queue.append(job)
	queue_max = maxi(queue_max, _queue.size())
	return job


## Runs a job to its end now (a caller that cannot wait: tests, tools, the comparison mode). Counted separately.
func run_now(job: Job) -> Job:
	if job.is_done():
		return job
	if job.leader != null:
		run_now(job.leader)
		return job
	stats.sync_runs += 1
	_queue.erase(job)
	if job.started_us == 0:
		job.started_us = Time.get_ticks_usec()
	job.state = State.RUNNING
	var t := Time.get_ticks_usec()
	while not job.runner.call("step", 0):
		pass
	job.work_us += Time.get_ticks_usec() - t
	job.slices += 1
	_complete_from_runner(job)
	return job


func get_job(id: int) -> Job:
	return _jobs.get(id)


## The job's state, or CANCELLED when it is unknown (finished and forgotten counts as done: the consumer's callback ran).
func state_of(id: int) -> int:
	var j: Job = _jobs.get(id)
	return j.state if j else State.CANCELLED


func is_pending(id: int) -> bool:
	var j: Job = _jobs.get(id)
	return j != null and not j.is_done()


func cancel(job: Variant, why := "cancelled") -> void:
	var j: Job = job if job is Job else _jobs.get(int(job))
	if j == null or j.is_done():
		return
	j.reason = why
	if j.leader != null:
		j.leader.followers.erase(j)
		_finish(j, State.CANCELLED)
		return
	if not j.followers.is_empty():
		# Others still want this search: one of them takes it over.
		var heir: Job = j.followers.pop_front()
		heir.leader = null
		heir.runner = j.runner
		heir.state = j.state
		heir.started_us = j.started_us
		heir.work_us = j.work_us
		heir.slices = j.slices
		heir.followers = j.followers
		for f: Job in heir.followers:
			f.leader = heir
		j.followers = []
		var qi := _queue.find(j)
		if qi >= 0:
			_queue[qi] = heir
		if _by_key.get(j.key) == j:
			_by_key[j.key] = heir
		if _active == j:
			_active = heir
	else:
		_queue.erase(j)
		if _active == j:
			_active = null
	_finish(j, State.CANCELLED)


func cancel_owner(owner: String, why := "cancelled") -> void:
	var j: Job = _by_owner.get(owner)
	if j != null:
		cancel(j, why)


## Every job, for a load or a reset (consumers re-request what they still need).
func cancel_all(why := "reset") -> void:
	for j: Job in _jobs.values().duplicate():
		if not j.is_done():
			cancel(j, why)
	_cache.clear()


## The world changed (roads, a bridge, structures; `area` where, null: anywhere). Cached results are dropped; a running search whose
## area is touched starts again (state INVALIDATED for the record, then pending again with its place in the queue kept).
func invalidate(why: String, area: Variant = null) -> void:
	revision += 1
	last_invalidation = why
	_cache.clear()
	for j: Job in _queue:
		if j.state != State.RUNNING:
			j.revision = revision
			continue
		if area != null and j.area != null and not (j.area as Rect2).intersects(area as Rect2):
			j.revision = revision
			continue
		j.state = State.INVALIDATED
		stats.invalidated += 1
		j.restarts += 1
		j.runner.call("reset")
		j.revision = revision
		j.state = State.PENDING


## Called once per rendered frame: runs jobs, most important first, until the budget is spent.
func step(steps := 1) -> void:
	if _queue.is_empty():
		last_frame_ms = 0.0
		return
	var budget_us := int(frame_budget_ms * clampi(steps, 1, max_steps) * 1000.0)
	var t0 := Time.get_ticks_usec()
	var deadline := t0 + budget_us
	while not _queue.is_empty():
		var job := _pick()
		if job.state == State.PENDING:
			if job.started_us == 0:
				job.started_us = Time.get_ticks_usec()
				_sample(wait_samples, job.wait_ms())
			job.state = State.RUNNING
		_active = job
		var before: Variant = job.runner.call("debug_state") if job.runner.has_method("debug_state") else null
		var s0 := Time.get_ticks_usec()
		var done: bool = job.runner.call("step", deadline)
		var s1 := Time.get_ticks_usec()
		var cur: Job = _active if _active != null else job
		cur.work_us += s1 - s0
		cur.slices += 1
		stats.slices += 1
		slice_ms_max = maxf(slice_ms_max, (s1 - s0) / 1000.0)
		slice_max_by_kind[cur.kind] = maxf(float(slice_max_by_kind.get(cur.kind, 0.0)), (s1 - s0) / 1000.0)
		if (s1 - s0) / 1000.0 >= slice_ms_max:
			slice_max_info = {"kind": String(cur.kind), "owner": cur.owner, "ms": snappedf((s1 - s0) / 1000.0, 0.01), "before": before,
				"after": cur.runner.call("debug_state") if cur.runner.has_method("debug_state") else null}
		_active = null
		if done and not cur.is_done():
			_queue.erase(cur)
			_complete_from_runner(cur)
		if Time.get_ticks_usec() >= deadline:
			break
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	last_frame_ms = ms
	frame_ms_max = maxf(frame_ms_max, ms)
	stats.frames_with_work += 1
	if ms > budget_us / 1000.0 * 1.5:
		stats.overruns += 1
	_sample(frame_samples, ms)


func _pick() -> Job:
	var now := Time.get_ticks_usec()
	var best: Job = null
	var best_p := INF
	for j: Job in _queue:
		var p := float(j.priority) - floorf((now - j.created_us) / 1.0e6 / aging_s)
		# A started search goes on before a new one of the same class (its work is not thrown away by switching).
		if j.state == State.RUNNING:
			p -= 0.5
		if p < best_p or (p == best_p and best != null and j.created_us < best.created_us):
			best = j
			best_p = p
	return best


func _complete_from_runner(job: Job) -> void:
	job.result = job.runner.get("result")
	var good := bool(job.result.get("ok", false))
	if good and job.key != "" and job.kind == &"infantry":
		if _cache.size() >= cache_max:
			_cache.clear()
		_cache[job.key] = {"revision": job.revision, "result": job.result}
	_finish(job, State.COMPLETED if good else State.FAILED)
	for f: Job in job.followers:
		if f.is_done():
			continue
		f.result = job.result.duplicate()
		f.started_us = job.started_us
		_finish(f, job.state)
	job.followers = []


func _finish(job: Job, st: int) -> void:
	job.state = st
	job.finished_us = Time.get_ticks_usec()
	if st != State.CANCELLED and job.reason == "":
		job.reason = String(job.result.get("reason", ""))
	match st:
		State.COMPLETED: stats.completed += 1
		State.FAILED: stats.failed += 1
		State.CANCELLED: stats.cancelled += 1
	if _by_key.get(job.key) == job:
		_by_key.erase(job.key)
	if _by_owner.get(job.owner) == job:
		_by_owner.erase(job.owner)
	if st != State.CANCELLED:
		_sample(total_samples, (job.finished_us - job.created_us) / 1000.0)
		if job.leader == null and job.work_us > 0:
			_sample(work_samples, job.work_us / 1000.0)
	recent.append({"id": job.id, "kind": String(job.kind), "owner": job.owner, "state": job.state_name(), "prio": PRIORITY_NAMES[clampi(job.priority, 0, 4)],
		"wait_ms": snappedf(job.wait_ms(), 0.1), "total_ms": snappedf((job.finished_us - job.created_us) / 1000.0, 0.1),
		"work_ms": snappedf(job.work_us / 1000.0, 0.01), "slices": job.slices, "restarts": job.restarts, "reason": job.reason,
		"shared": job.leader != null})
	if recent.size() > 64:
		recent.pop_front()
	_jobs.erase(job.id)
	if st != State.CANCELLED and not _in_submit and job.callback.is_valid():
		job.callback.call(job)


static func _sample(arr: PackedFloat32Array, v: float) -> void:
	arr.append(v)
	if arr.size() > SAMPLES:
		arr.remove_at(0)


static func percentiles(arr: PackedFloat32Array) -> Dictionary:
	if arr.is_empty():
		return {"n": 0, "avg": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var v := arr.duplicate()
	v.sort()
	var sum := 0.0
	for x in v:
		sum += x
	return {"n": v.size(), "avg": snappedf(sum / v.size(), 0.01), "p95": snappedf(v[mini(int(v.size() * 0.95), v.size() - 1)], 0.01),
		"p99": snappedf(v[mini(int(v.size() * 0.99), v.size() - 1)], 0.01), "max": snappedf(v[v.size() - 1], 0.01)}


func queue_length() -> int:
	return _queue.size()


## Waiting and running jobs by kind (overlay).
func queue_summary() -> Dictionary:
	var out := {}
	for j: Job in _queue:
		var k := "%s/%s" % [String(j.kind), STATE_NAMES[j.state]]
		out[k] = int(out.get(k, 0)) + 1
	return out


func report() -> Dictionary:
	return {"budget_ms": frame_budget_ms, "queue": _queue.size(), "queue_max": queue_max, "revision": revision, "stats": stats.duplicate(),
		"by_kind": by_kind.duplicate(), "frame_ms": percentiles(frame_samples), "frame_ms_max": snappedf(frame_ms_max, 0.01),
		"slice_ms_max": snappedf(slice_ms_max, 0.01), "slice_max_by_kind": slice_max_by_kind.duplicate(), "slice_max_info": slice_max_info.duplicate(true), "wait_ms": percentiles(wait_samples), "total_ms": percentiles(total_samples),
		"work_ms": percentiles(work_samples)}


## Clears the measurements (tests measure one workload at a time); jobs and the queue are kept.
func reset_stats() -> void:
	for k in stats:
		stats[k] = 0
	by_kind.clear()
	queue_max = _queue.size()
	frame_ms_max = 0.0
	slice_ms_max = 0.0
	slice_max_by_kind.clear()
	slice_max_info = {}
	frame_samples.clear()
	wait_samples.clear()
	total_samples.clear()
	work_samples.clear()
	recent.clear()
