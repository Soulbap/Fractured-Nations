## Autonomous soldier combat: perception, target choice, firing (COMBAT-01b) and basic
## tactical reactions to incoming fire (COMBAT-02).
##
## Works on UnitState records only - never on bodies, proxies or the camera - so a
## soldier fights the same way in the detailed and the abstract tier and nothing changes
## when it is promoted, demoted, saved or loaded. Every shot goes through
## CombatSim.request_fire(..., Source.AI): the same weapon, ammunition, reload, spread,
## damage and line-of-fire resolution as the player's rifle. The possessed soldier is
## never touched.
##
## Combat state per soldier (UnitState.ai_state and the target fields):
##   IDLE / OBSERVING -> ENGAGING (visible enemy) -> LOST_TARGET (hidden, remembered for
##   target_memory_s) -> OBSERVING (looks at the last known position) -> IDLE;
##   RELOADING while a magazine change runs; DEAD; PLAYER while possessed.
##
## Tactical reaction per soldier (UnitState.tactic, COMBAT-02):
##   NONE -> (under fire: shots passing close, hits, a squad mate under fire) a local cover
##   search -> SEEK_COVER (walking to it) -> IN_COVER (fights from there) -> back to NONE
##   when the reaction's time is up (Move / Follow / Regroup) or, holding an area, after a
##   calm period through RETURNING to the held spot. The reaction moves the soldier only
##   through UnitState.react_target, a temporary goal the body / abstract step prefers to
##   the order; the order itself and the squad's order are never changed here, and any
##   new player order ends the reaction (WorldState.issue_move / halt).
##
## Cost: perception runs perception_hz times per second per soldier, staggered over the
## physics frames (round robin) with at most los_budget sight checks per frame. Candidates
## come from a per-faction grid, nearest first, without sorting everyone. Per frame only
## soldiers with something to do (a target, a reload, a reaction, a look direction) are
## processed. Cover searches are spread over frames (cover_budget evaluations per frame).
## Vegetation cells are filled ahead of sight lines (warm_cells_per_frame), so the first
## look into a forest does not stall a frame.
class_name CombatBrain
extends RefCounted

# --- Perception ------------------------------------------------------------------------
var enabled := true
## Perception updates per soldier per second.
var perception_hz := 3.0
## Farthest distance at which an enemy can be noticed (m).
var sight_range := 400.0
## Total field of view (degrees) around the direction the soldier looks.
var fov_deg := 150.0
## Enemies closer than this are noticed in any direction (hearing, peripheral).
var awareness_m := 25.0
## Sight checks for new candidates per soldier per update (the current target is extra).
var max_candidates := 3
## Sight checks per physics frame for all soldiers together; the rest wait a frame.
var los_budget := 24
## A hidden target is remembered (last known position) this long, then dropped (s).
var target_memory_s := 6.0
## A visible target is only replaced by one closer than this fraction of its distance.
var switch_ratio := 0.6
## After a target is lost, the soldier keeps looking at its last position this long (s).
var watch_after_lost_s := 8.0
## Enemy shots heard within this distance make a soldier look towards the shooter (m).
var hearing_m := 150.0
## Squad mates within this distance are told where a newly seen enemy is (m).
var contact_share_m := 120.0
## Idle soldiers' attention sweeps this far to each side of their heading, once per
## idle_scan_s (degrees, seconds).
var idle_scan_deg := 110.0
var idle_scan_s := 8.0
## Vegetation cells filled per physics frame ahead of sight lines.
var warm_cells_per_frame := 1
## Soldiers farther than far_m from the observer (the active camera's focus or the
## possessed soldier) perceive at half rate. Saves time in distant battles; the outcome
## of a distant fight then depends a little on where the camera was (off: identical
## wherever the camera is).
var distance_lod := true
var far_m := 700.0

# --- Engagement ------------------------------------------------------------------------
## Targets farther than this are tracked but not fired at (m).
var engage_range := 350.0
## Time from acquiring a target to the first shot: base + per 100 m (s).
var reaction_s := 0.45
var reaction_per_100m_s := 0.15
## Aim error (degrees, one standard deviation) on top of the weapon's spread: base,
## growth with distance, and a penalty while the shooter walks. GAMEPLAY-05B: the growth with distance was 0.20 deg per 100 m,
## which made the miss in metres grow with the square of the distance (one sigma 4 m at 300 m: rifles hit nothing beyond 200 m);
## now 0.05 (a smaller, farther target is still harder to hold). Values from AIM_PROFILES.
var aim_error_base_deg := 0.26
var aim_error_per_100m_deg := 0.05
var aim_error_moving_deg := 1.2
## GAMEPLAY-04C aim settling: on a new target (or after moving) the aim error is this many times its settled value and falls
## to it over the weapon's aim_time_s (WeaponDef), scaled by the soldier's proficiency. aim_time_default_s for weapons without one.
var aim_first_mult := 2.0
## ... and settles to this multiple of the GAMEPLAY-03 aim error (a settled, steady aim is a little better than before).
var aim_settled_mult := 0.9
var aim_time_default_s := 0.8
## False: the GAMEPLAY-03 model (no settling, no proficiency, one engage and sight range for every weapon) - for the before /
## after measurements of the accuracy arena only (`--legacy-aim`).
var aim_model := true
## The aim follows a moving target with this delay (s): a walking target is trailed.
var track_lag_s := 0.2
## Extra clearance kept around friends in the line of fire (m), for the weapon spread.
var friendly_margin_m := 0.5
## At most this many AI shots per physics frame; a soldier over the budget fires one
## frame later (its fire interval is kept). Bursts of many shooters falling on the same
## frame were the largest frame spikes at 100 v 100.
var ai_shot_budget := 10
## A partly emptied magazine is refilled when no enemy is in sight below this fraction.
var tactical_reload_fraction := 0.5

# --- Tactical reactions (COMBAT-02) ---------------------------------------------------
var tactics_enabled := true
## A shot passing this close (or a hit) puts a soldier under fire (m).
var near_miss_m := 3.0
## Under fire lasts this long after the last such shot (s).
var under_fire_s := 6.0
## Squad mates this close to a soldier that comes under fire are alerted too (m).
var squad_alert_m := 30.0
## Cover search radius and reaction time per order: holding an area / walking a Move
## order / following / regrouping. Holding has no time limit (it returns when calm).
var cover_radius_hold := 12.0
var cover_radius_move := 6.0
var cover_radius_follow := 8.0
var cover_radius_regroup := 5.0
var react_s_move := 5.0
var react_s_follow := 8.0
var react_s_regroup := 4.0
## A brief Move / Regroup reaction is not repeated before this pause (s).
var move_react_cooldown_s := 12.0
## No threat for this long: the reaction ends (holding: back to the held spot) (s).
var calm_s := 10.0
## Cover is kept at least this long before a better spot is considered (s), and its
## protection re-checked this often.
var min_dwell_s := 6.0
var recheck_s := 4.0
## Cover candidate evaluations per physics frame for all soldiers together (in units of eval_cost).
var cover_budget := 16
## COMBAT-COVER-03: what one evaluation costs of cover_budget - CoverEval.judge follows the eye line up to fire_check_m and
## both shoulders (~0.27 ms against ~0.1 ms before), so the budget per frame stays about the same in time.
var eval_cost := 2
## Cover counts when the blocker is this close to the soldier (m): structures, rocks and
## trunks / terrain (a reverse slope protects from a little farther).
var cover_contact_m := 6.0
var cover_terrain_m := 15.0
## A cover spot that could not be reached is not chosen again for this long (s).
var bad_cover_s := 30.0
var max_cover_candidates := 14
## Two soldiers do not take cover spots closer than this (m).
var cover_spacing_m := 1.1

# --- Suppression (AI-SQUAD-01) --------------------------------------------------------
## Added to a soldier's suppression by a shot passing within near_miss_m (scaled by how
## close) and by a hit.
var suppression_per_shot := 0.11
var suppression_per_hit := 0.30
## Suppression from which a soldier stays down: a cover search even without a dash order,
## fewer and later bursts, no dashes across open ground. Aim error grows by up to
## suppression_aim_mult x the value, acquisition slows by suppression_acquire_s x it.
var suppressed_at := 0.35
var pinned_at := 0.6
var suppression_aim_mult := 4.0
var suppression_acquire_s := 0.9
## Fire missions at a reported position: burst size, pause between bursts (s) and the
## fraction of a full load below which they slow down / stop (a magazine is always kept).
var mission_burst := 3
var mission_pause_s := 1.3
## AI-ASSAULT-01: a rifleman's fire mission is sustained fire - two rounds every ~2 s (about 60 a minute, a third of the
## old rate, which emptied a rifleman's 150 rounds in a minute and left the assault without ammunition); machine guns and
## marksman rifles keep their own bursts at mission_pause_s.
var rifle_mission_burst := 2
var rifle_mission_pause_s := 2.0
var mission_slow_ammo := 0.5
var mission_stop_ammo := 0.2
## Cover reactions of a soldier standing at a squad-assigned post stay within this (m).
var cover_radius_post := 3.5
## A hold-fire soldier hit within this long ago returns fire at enemies closer than
## self_defence_m (self-defence).
var self_defence_s := 6.0
var self_defence_m := 100.0
## AI-ASSAULT-01: target distribution - a newly seen enemy that crowd_n soldiers already shoot at is passed over for the next
## visible one up to crowd_ratio times as far (never one that is shooting at this soldier); fire otherwise piles onto the
## nearest man while the others shoot freely. Arma / CoH spread fire by target assignment; this is the cheap individual form.
var crowd_n := 3
var crowd_ratio := 1.6
var crowd_skips := 0
## AI-ASSAULT-01: a soldier on the move holds aimed fire at targets beyond move_fire_m (unless just hit): 143 shots on the move
## at 300+ m hit nothing and emptied magazines before the assault. Both sides, the same rule.
var move_fire_m := 120.0
var move_holds := 0

# --- Concealment and posture (COMBAT-01) ---------------------------------------------
## Grass at the target slows noticing it (never hides it): the share of its shape the grass covers (Concealment, against
## Posture.top) times conceal_base_s + conceal_per_150m_s x distance / 150 m. A smaller shape is noticed a little later even
## on bare ground (posture_notice_s per 100 m). Within notice_close_m nothing delays; a moving target is noticed sooner, a
## firing one much sooner, one the soldier was told / heard about somewhat sooner; one it saw in the last notice_recall_s
## is picked up again at once. false = the binary COMBAT-01b rule (--no-concealment).
var conceal_on := true
var concealment := Concealment.new()
var conceal_base_s := 1.0
var conceal_per_150m_s := 4.5
## AI-COMBAT-02: seconds of observation per 100 m a target needs to be noticed by its shape alone (standing, crouched, prone).
## COMBAT-01 had [0, 0.25, 0.8]: a man standing still on bare ground was noticed at once at any distance in the field of view.
var posture_notice_s: Array[float] = [0.55, 1.2, 2.6]
var notice_close_m := 15.0
## A target moving at full walking speed (4.5 m/s, faster counts the same) is noticed in this fraction of the time.
var notice_moving_mult := 0.4
## A target that fired in the last 2.5 s: within notice_fire_near_m in this fraction, at notice_fire_far_m and beyond in
## notice_firing_far_mult (the flash and the dust of a shot are seen close, a distant rifle mostly heard).
var notice_firing_mult := 0.15
var notice_firing_far_mult := 0.45
var notice_fire_near_m := 80.0
var notice_fire_far_m := 300.0
## Looking where it was told / heard / suspected: only a target within notice_told_deg of that direction is noticed sooner.
var notice_told_mult := 0.6
var notice_told_deg := 20.0
## AI-COMBAT-02: off the centre of the observer's attention (notice_centre_deg) up to notice_edge_mult times longer at the
## edge of the field of view; each tree crown the sight line passes (thinner than a blocking stand) notice_foliage_mult more;
## a suppressed observer up to notice_supp_mult (at full suppression) longer; a walking observer notice_moving_obs_mult.
var notice_centre_deg := 25.0
var notice_edge_mult := 2.2
var notice_foliage_mult := 0.6
var notice_supp_mult := 1.5
var notice_moving_obs_mult := 1.3
## A target seen in the last notice_recall_s is picked up again at once - AI-COMBAT-02: only near where it was last seen
## (recall_slack_m + recall_speed_ms per second of absence); one that moved away has to be found again.
var notice_recall_s := 12.0
var recall_slack_m := 6.0
var recall_speed_ms := 2.0
## AI-COMBAT-02 suspicion: a target in view for suspect_frac of the time it needs makes the soldier look at the place (blurred
## by suspect_blur of the distance) - he turns to it before he has seen anyone; the look also speeds noticing (told).
var suspect_frac := 0.4
var suspect_blur := 0.06
var suspicions := 0
## AI-COMBAT-02: heard gunfire gives a bearing, not a point: the place an idle soldier turns to is off by up to heard_blur of
## the distance sideways (the faction's report keeps its own wide blur, IntelSim.report_heard).
var heard_blur := 0.12
## Posture choice of the AI (COMBAT-01): crouch in cover and when alert, prone when pinned in the open or when a machine gun
## / marksman rifle engages from prone_engage_m; each choice is kept posture_hold_s at least (prone longer).
var posture_ai := true
var prone_engage_m := 120.0
var posture_hold_s := 3.0
var prone_hold_s := 6.0
## observer id -> {target id: [seconds in view so far, last seen, last acquired]} (runtime: a perception detail, not saved).
var _spot := {}
var notice_waits := 0
var posture_changes := 0

# --- Measurements ---------------------------------------------------------------------
var suppression_events := 0
var mission_shots := 0
var mission_holds := 0
var sight_checks := 0
var sight_usec := 0
var perception_updates := 0
var update_usec := 0
var update_usec_max := 0
var frames := 0
var ai_shots := 0
var friendly_holds := 0
var own_cover_holds := 0
var acquisitions := 0
var target_switches := 0
var dropped_targets := 0
var cover_searches := 0
var cover_evals := 0
var cover_found := 0
var cover_none := 0
var cover_unreachable := 0
var warm_cells := 0
var warm_waits := 0
var last_frame_checks := 0
## Profiling (usec totals since reset_stats): where update() spends its time.
var prof := {"perceive": 0, "engage": 0, "fire": 0, "friendly": 0, "grid": 0, "cover": 0, "warm": 0, "shot_events": 0}
## Largest single-frame time per section (usec) since reset_stats.
var prof_max := {"perceive": 0, "engage": 0, "cover": 0, "warm": 0}
var last_frame_usec := 0
## Recent decisions for the debug overlay / log: {t, unit, text}. Short ring buffer.
var events: Array[Dictionary] = []
var log_events := false

var sim: WorldSim
var _queue: PackedInt32Array = PackedInt32Array()
var _queue_dirty := true
var _qi := 0
var _accum := 0.0
## 64 m cells -> soldiers (all factions), and per faction 128 m cells -> soldiers.
var _grid := {}
var _fgrid := {}
var _grid_frame := -1
## Cover searches in progress: unit id -> {cands, i, accepted, mode, center, radius, limit, threat}.
var _searches := {}
## unit id -> [[position, until], ...] cover spots that could not be reached.
var _bad_cover := {}
var _warm_queue: Array[Vector2i] = []
var _warm_set := {}
var _extent := {}
var _lod_skip := {}
## Reserved cover spots [position, unit] (rebuilt with the grid every frame; a soldier
## walking to its cover is far from the spot, so the position grid does not find it).
var _covers: Array = []
## AI-ASSAULT-01: target id -> soldiers aiming at it with it in sight (rebuilt with the grid, once a physics frame).
var _aimers := {}
var _shots_left := 0
var _ei := 0
var budget_waits := 0
## Recent shots [origin, shooter faction, time] for hearing (checked by soldiers without
## a target at their perception update instead of every shot scanning every listener).
var _recent_shots: Array = []
const GRID := 64.0
const FGRID := 128.0
const MAX_EVENTS := 200


## COMBAT-COVER-03: the one cover judgement (protection level, fire) shared with the squad tactics and the player's placement.
var cover_eval: CoverEval


func _init(p_sim: WorldSim) -> void:
	sim = p_sim
	cover_eval = CoverEval.new(p_sim)
	_apply_aim_args(OS.get_cmdline_user_args())
	conceal_on = not "--no-concealment" in OS.get_cmdline_user_args()
	if "--legacy-perception" in OS.get_cmdline_user_args():
		legacy_perception(true)
	firing_moves = not "--no-stalemate" in OS.get_cmdline_user_args()


## AI-COMBAT-02 comparison switch (`--legacy-perception`, tests): the COMBAT-01 noticing rule - shape-only delays [0, 0.25, 0.8] s
## per 100 m, no field-of-view, foliage, observer or suspicion terms, recall anywhere, the old movement and firing factors.
## Difficulty still applies (tests set HARD for the old aim).
var _perception_now := {}


func legacy_perception(on: bool) -> void:
	var keys := ["posture_notice_s", "notice_moving_mult", "notice_firing_far_mult", "notice_edge_mult", "notice_foliage_mult",
		"notice_supp_mult", "notice_moving_obs_mult", "notice_told_deg", "suspect_frac", "recall_slack_m"]
	if on:
		if _perception_now.is_empty():
			for k: String in keys:
				_perception_now[k] = get(k)
		var old: Array[float] = [0.0, 0.25, 0.8]
		posture_notice_s = old
		notice_moving_mult = 0.45
		notice_firing_far_mult = notice_firing_mult
		notice_edge_mult = 1.0
		notice_foliage_mult = 0.0
		notice_supp_mult = 1.0
		notice_moving_obs_mult = 1.0
		notice_told_deg = 180.0
		suspect_frac = 1000.0
		recall_slack_m = 1.0e6
	elif not _perception_now.is_empty():
		for k: String in _perception_now:
			set(k, _perception_now[k])


## GAMEPLAY-05B aim profiles (the distance growth of the aim error and the suppression penalty). "g05b" is the game's; "g04" is
## the GAMEPLAY-04 model, kept for before / after measurements (--aim=g04). --aim-base= / --aim-per100= / --aim-supp= override
## single values (balance experiments only).
## "weapon_aim": WeaponDef id -> aim factor replacing WeaponDef.aim_mult (with the flatter distance growth the machine guns' bursts
## became precise at 100 m - 49 % - so they hold a wider aim; they stay suppression weapons).
const AIM_PROFILES := {
	"g04": {"base": 0.25, "per100": 0.20, "supp": 2.2, "weapon_aim": {}},
	"g05b": {"base": 0.26, "per100": 0.05, "supp": 4.0, "weapon_aim": {&"lmg": 1.3, &"gpmg": 1.3}},
	# COMBAT-01: a settled, trained rifleman has a credible chance at 200-300 m (about one in five / one in ten aimed shots
	# standing, more prone), the marksman rifle a clear edge; a fresh aim is rougher (first) but no longer twice as rough.
	"c01": {"base": 0.16, "per100": 0.035, "supp": 4.0, "first": 1.6, "weapon_aim": {&"lmg": 1.3, &"gpmg": 1.3, &"dmr": 0.55}},
}
var weapon_aim := {}
var aim_profile := "c01"


func _apply_aim_args(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--aim=") and AIM_PROFILES.has(a.trim_prefix("--aim=")):
			aim_profile = a.trim_prefix("--aim=")
	var pr: Dictionary = AIM_PROFILES[aim_profile]
	aim_error_base_deg = pr.base
	aim_error_per_100m_deg = pr.per100
	suppression_aim_mult = pr.supp
	weapon_aim = pr.weapon_aim
	aim_first_mult = float(pr.get("first", 2.0))
	for a in args:
		if a.begins_with("--aim-base="):
			aim_error_base_deg = float(a.trim_prefix("--aim-base="))
		elif a.begins_with("--aim-per100="):
			aim_error_per_100m_deg = float(a.trim_prefix("--aim-per100="))
		elif a.begins_with("--aim-supp="):
			suppression_aim_mult = float(a.trim_prefix("--aim-supp="))


## Hearing, hits and deaths feed the soldiers' awareness; membership changes rebuild the
## perception queue.
func connect_signals() -> void:
	sim.state.shot_fired.connect(_on_shot)
	sim.state.explosive_launched.connect(_on_explosive)
	sim.state.unit_damaged.connect(_on_damaged)
	sim.state.unit_died.connect(_on_died)
	sim.state.unit_added.connect(func(_u: UnitState) -> void: _queue_dirty = true)
	sim.state.unit_removed.connect(func(id: int) -> void:
		_queue_dirty = true
		_searches.erase(id))
	sim.state.restored.connect(func() -> void:
		_queue_dirty = true
		_searches.clear())


func reset_stats() -> void:
	sight_checks = 0
	sight_usec = 0
	perception_updates = 0
	update_usec = 0
	update_usec_max = 0
	frames = 0
	ai_shots = 0
	friendly_holds = 0
	own_cover_holds = 0
	acquisitions = 0
	target_switches = 0
	dropped_targets = 0
	cover_searches = 0
	cover_evals = 0
	cover_found = 0
	cover_none = 0
	cover_unreachable = 0
	warm_cells = 0
	warm_waits = 0
	budget_waits = 0
	for k in prof:
		prof[k] = 0
	for k in prof_max:
		prof_max[k] = 0


func update(delta: float) -> void:
	if not enabled:
		return
	var t0 := Time.get_ticks_usec()
	var checks0 := sight_checks
	if _queue_dirty or Engine.get_physics_frames() % 120 == 0:
		_rebuild_queue()
	_ensure_grid()
	var tw := Time.get_ticks_usec()
	_warm_step()
	var tq := Time.get_ticks_usec()
	prof.warm += tq - tw
	prof_max.warm = maxi(prof_max.warm, tq - tw)
	_prune_recent_shots()
	_grenade_reactions(sim.state.time)
	# Perception (and the tactical decision): each soldier perception_hz times per
	# second, spread over the frames.
	_accum = minf(_accum + delta * perception_hz * _queue.size(), float(_queue.size()))
	var budget := los_budget
	while _accum >= 1.0 and budget > 0 and not _queue.is_empty():
		_accum -= 1.0
		_qi = _qi % _queue.size()
		var u := sim.state.get_unit(_queue[_qi])
		_qi += 1
		if u == null or u.vehicle_id >= 0:
			continue
		# Far from the observer, every other turn is skipped: half the perception rate
		# for distant battles (they still fight; reactions are a little slower).
		if distance_lod and _is_far(u):
			_lod_skip[u.id] = not _lod_skip.get(u.id, false)
			if _lod_skip[u.id]:
				continue
		budget -= _perceive(u, budget)
		if tactics_enabled:
			_tactics(u)
		if posture_ai and u.alive and not u.player_controlled:
			_choose_posture(u)
	var tp := Time.get_ticks_usec()
	prof.perceive += tp - tq
	prof_max.perceive = maxi(prof_max.perceive, tp - tq)
	if tactics_enabled:
		_search_step()
	var tc := Time.get_ticks_usec()
	prof.cover += tc - tp
	prof_max.cover = maxi(prof_max.cover, tc - tp)
	# Engagement: every frame for soldiers with something to do. The start rotates so
	# the shot budget does not always favour the same soldiers.
	var now := sim.state.time
	_shots_left = ai_shot_budget
	var nq := _queue.size()
	_ei = (_ei + 1) % maxi(nq, 1)
	for j in nq:
		var id := _queue[(_ei + j) % nq]
		var u := sim.state.get_unit(id)
		if u == null or u.vehicle_id >= 0:
			continue
		if u.target_id < 0 and not u.is_reloading() and u.watch_until < now and not u.player_controlled \
				and not (u.fire_at.is_finite() and now < u.fire_until) \
					and (u.mag * 2 >= _mag_size(u) or u.reserve <= 0):
			if u.ai_state != UnitState.AiState.IDLE:
				u.ai_state = UnitState.AiState.IDLE
				u.ai_reason = "no target"
				u.watch_yaw = NAN
			continue
		_engage(u)
	prof.engage += Time.get_ticks_usec() - tc
	prof_max.engage = maxi(prof_max.engage, Time.get_ticks_usec() - tc)
	last_frame_checks = sight_checks - checks0
	last_frame_usec = Time.get_ticks_usec() - t0
	update_usec += last_frame_usec
	update_usec_max = maxi(update_usec_max, last_frame_usec)
	frames += 1


func _mag_size(u: UnitState) -> int:
	var def := sim.combat.weapon(u.weapon_id)
	return def.magazine_size if def else 0


# --- Perception ------------------------------------------------------------------------

## One perception update of one soldier. Returns the sight checks it used.
func _perceive(u: UnitState, budget: int) -> int:
	if not u.alive:
		u.ai_state = UnitState.AiState.DEAD
		return 0
	if u.player_controlled:
		return 0
	perception_updates += 1
	var now := sim.state.time
	var eye := CombatSim.eye_of(u)
	# Hearing: the nearest recent enemy shot within hearing_m turns an idle soldier.
	if u.target_id < 0 and u.watch_until < now:
		var heard := Vector3.INF
		var hd := hearing_m
		for r: Array in _recent_shots:
			if r[1] != u.faction:
				var d := _flat(u.position, r[0])
				if d < hd:
					hd = d
					heard = r[0]
		if heard.is_finite():
			# AI-COMBAT-02: a bearing, not the shooter's point.
			var side := Vector3(-(heard.z - u.position.z), 0.0, heard.x - u.position.x).normalized()
			_watch(u, heard + side * (_rand(u, 29) * 2.0 - 1.0) * heard_blur * hd, 5.0)
			# AI-INTEL-01: the faction hears it too, without learning who or exactly where.
			if sim.war != null and sim.war.enabled:
				sim.war.intel.report_heard(u, heard, hd)
	var used := 0
	var cur := sim.state.get_unit(u.target_id)
	if cur and (not cur.alive or cur.faction == u.faction):
		_drop_target(u, "target down")
		cur = null
	var cur_visible := false
	# COMBAT-01: whether the sight line was really checked this update. While vegetation cells along it still fill, the last
	# answer is kept - but then the target's position is not refreshed (that would follow a hidden enemy).
	var cur_checked := false
	var cur_dist := INF
	var sight := sight_of(u)
	if cur:
		cur_dist = _flat(u.position, cur.position)
		if cur_dist <= sight and _line_warm(eye, cur.position):
			var s := _see(eye, cur, u.target_aim_y)
			used += s.checks
			cur_visible = s.visible
			cur_checked = true
			if cur_visible:
				u.target_aim_y = s.aim_y
		elif cur_dist <= sight:
			cur_visible = u.target_visible  # cells still filling: keep the last answer
	# Look for a (closer) enemy: always when the target is hidden or missing, otherwise
	# only among enemies clearly closer than the current one.
	var best: UnitState = null
	var best_aim := 1.0
	var crowded: UnitState = null
	var crowded_aim := 1.0
	var tried := 0
	var max_d := cur_dist * switch_ratio if cur_visible else sight
	if cur_visible and _lof_blocked_on(u, cur.id, now):
		max_d = sight  # COMBAT-COVER-03: seen but not shootable: any other enemy in sight may take its place
	for c: UnitState in _candidates(u, max_d, max_candidates + 1):
		if used >= budget or tried >= max_candidates:
			break
		if c == cur:
			continue
		if crowded != null and _flat(u.position, c.position) > _flat(u.position, crowded.position) * crowd_ratio:
			break
		if not _line_warm(eye, c.position):
			warm_waits += 1
			continue
		tried += 1
		var s := _see(eye, c, 1.55)
		used += s.checks
		if s.visible and _noticed(u, c, now, int(s.foliage)):
			if crowded == null and not cur_visible and c.target_id != u.id and int(_aimers.get(c.id, 0)) >= crowd_n:
				crowded = c
				crowded_aim = s.aim_y
				continue
			if crowded != null:
				crowd_skips += 1
			best = c
			best_aim = s.aim_y
			break
	if best == null and crowded != null:
		best = crowded
		best_aim = crowded_aim
	if best:
		_acquire(u, best, best_aim)
	elif cur and cur_visible and not cur_checked:
		u.target_visible = true
	elif cur and cur_visible:
		u.target_seen_at = now
		u.target_last_pos = cur.position
		u.target_visible = true
		_remember_seen(u, cur.id, now, cur.position)
		_report_seen(u, cur)
	elif cur:
		u.target_visible = false
		if now - u.target_seen_at > target_memory_s:
			_drop_target(u, "lost contact")
	else:
		u.target_visible = false
	return used


## Up to k living enemies within max_d, nearest first, that the soldier can notice (in
## its field of view, or within awareness_m). Per-faction 128 m grid; no full sort.
func _candidates(u: UnitState, max_d: float, k: int) -> Array:
	var out := []
	var dists := PackedFloat32Array()
	var p := u.position
	var look := look_yaw(u)
	var fx := -sin(look)
	var fz := -cos(look)
	var cos_half := cos(deg_to_rad(fov_deg * 0.5))
	var r2 := max_d * max_d
	var aw2 := awareness_m * awareness_m
	var c0 := Vector2i(floori((p.x - max_d) / FGRID), floori((p.z - max_d) / FGRID))
	var c1 := Vector2i(floori((p.x + max_d) / FGRID), floori((p.z + max_d) / FGRID))
	for f: int in _fgrid:
		if f == u.faction:
			continue
		var cells: Dictionary = _fgrid[f]
		for x in range(c0.x, c1.x + 1):
			for z in range(c0.y, c1.y + 1):
				var arr: Array = cells.get(Vector2i(x, z), [])
				for c: UnitState in arr:
					var dx := c.position.x - p.x
					var dz := c.position.z - p.z
					var d2 := dx * dx + dz * dz
					if d2 > r2:
						continue
					if d2 > aw2 and (dx * fx + dz * fz) < cos_half * sqrt(d2):
						continue
					if out.size() >= k and d2 >= dists[k - 1]:
						continue
					var i := dists.bsearch(d2)
					dists.insert(i, d2)
					out.insert(i, c)
					if out.size() > k:
						out.pop_back()
						dists.remove_at(k)
	return out


## Sight from an eye to a soldier: first the height that was visible last time, then
## the other one (head 1.55 m / torso 1.1 m). {visible, aim_y, checks, blocker}
## COMBAT-01: aim_y stays the marker (1.55 head, 1.1 torso); the points are the target's posture's (Posture.aim_point).
func _see(eye: Vector3, t: UnitState, first_y: float) -> Dictionary:
	var ys: Array[float] = [1.55, 1.1]
	if first_y <= 1.3:
		ys = [1.1, 1.55]
	var checks := 0
	var blocker := ""
	for y in ys:
		var t0 := Time.get_ticks_usec()
		var r := sim.combat.line.sight(eye, Posture.aim_point(t, y > 1.3))
		sight_usec += Time.get_ticks_usec() - t0
		sight_checks += 1
		checks += 1
		if r.visible:
			# Seen at the head: the torso may still be visible (better target).
			if y > 1.3:
				var t1 := Time.get_ticks_usec()
				var r2 := sim.combat.line.sight(eye, Posture.aim_point(t, false))
				sight_usec += Time.get_ticks_usec() - t1
				sight_checks += 1
				checks += 1
				return {"visible": true, "aim_y": 1.1 if r2.visible else 1.55, "checks": checks, "blocker": "",
					"foliage": mini(int(r.foliage), int(r2.foliage)) if r2.visible else int(r.foliage)}
			return {"visible": true, "aim_y": y, "checks": checks, "blocker": "", "foliage": int(r.foliage)}
		blocker = r.blocker
		if r.blocker == "terrain" and y > 1.3:
			break  # the head is under the horizon: the torso is too
	return {"visible": false, "aim_y": first_y, "checks": checks, "blocker": blocker, "foliage": 0}


## COMBAT-01: a candidate the soldier can see is noticed once it has been in view for acquire_delay in total: every
## perception update that sees it adds the time since the last look (at most notice_glimpse_s), so glimpses add up while the
## soldier's attention sweeps; out of view for notice_forget_s the count starts again.
var notice_glimpse_s := 0.5
var notice_forget_s := 6.0


func _noticed(u: UnitState, t: UnitState, now: float, foliage := 0) -> bool:
	var seen: Dictionary = _spot.get(u.id, {})
	var e: Array = seen.get(t.id, [0.0, now, -INF, Vector3.INF])
	var gap := now - float(e[1])
	if gap > notice_forget_s:
		e[0] = 0.0
	e[0] = float(e[0]) + minf(gap, notice_glimpse_s)
	e[1] = now
	seen[t.id] = e
	_spot[u.id] = seen
	# AI-COMBAT-02: picked up again at once only near where it was last seen, within the (difficulty's) recall time.
	var since := now - float(e[2])
	var last: Vector3 = e[3]
	if since <= notice_recall_s / _diff(u, "regain") and (not last.is_finite() or _flat(t.position, last) <= recall_slack_m + recall_speed_ms * since):
		return true
	var need := acquire_delay(u, t, now, foliage)
	if float(e[0]) >= need:
		return true
	notice_waits += 1
	# Suspicion: something there - the soldier turns to look (not at the man: at a blurred place) before he has seen anyone.
	if u.target_id < 0 and float(e[0]) >= need * suspect_frac and (u.watch_until < now or is_nan(u.watch_yaw)):
		var d := _flat(u.position, t.position)
		var side := Vector3(-(t.position.z - u.position.z), 0.0, t.position.x - u.position.x).normalized()
		_watch(u, t.position + side * (_rand(u, 23 + t.id % 7) * 2.0 - 1.0) * suspect_blur * d, 4.0)
		suspicions += 1
		_event(u, "suspects movement at %.0f m" % d)
	return false


## How long a soldier needs to notice t, which it can see (s): grass at t against t's height, the distance, t's posture,
## movement and fire. Concealment.grass_height is a cached map lookup; no sight line is added.
## AI-COMBAT-02: also the target's shape at a distance (posture_notice_s), where it stands in the observer's field of view, the
## tree crowns the sight line passes (`foliage`, from the sight check already made), the observer's own movement and
## suppression, and the difficulty (Difficulty "spot", for soldiers hostile to the player).
func acquire_delay(u: UnitState, t: UnitState, now: float, foliage := 0) -> float:
	if not conceal_on:
		return 0.0
	var d := _flat(u.position, t.position)
	if d <= notice_close_m:
		return 0.0
	var top := Posture.top(t, now)
	var hidden := smoothstep(0.08, 0.75, concealment.grass_height(t.position) / maxf(top, 0.1))
	var delay := hidden * (conceal_base_s + conceal_per_150m_s * minf(d / 150.0, 1.5)) + posture_notice_s[Posture.current(t, now)] * d / 100.0
	delay *= clampf((d - notice_close_m) / 15.0, 0.0, 1.0)
	delay *= 1.0 + notice_foliage_mult * foliage
	# Where it is in the observer's field of view: in the centre of his attention at once, at the edge much later.
	var bearing := atan2(-(t.position.x - u.position.x), -(t.position.z - u.position.z))
	if d > awareness_m:
		var off := rad_to_deg(absf(angle_difference(look_yaw(u), bearing)))
		delay *= lerpf(1.0, notice_edge_mult, clampf((off - notice_centre_deg) / maxf(fov_deg * 0.5 - notice_centre_deg, 1.0), 0.0, 1.0))
	var speed := Vector2(t.velocity.x, t.velocity.z).length()
	delay *= lerpf(1.0, notice_moving_mult, clampf(speed / 4.5, 0.0, 1.0))
	if now - t.last_shot_at < 2.5:
		delay *= lerpf(notice_firing_mult, notice_firing_far_mult, clampf((d - notice_fire_near_m) / (notice_fire_far_m - notice_fire_near_m), 0.0, 1.0))
	elif u.watch_until >= now and not is_nan(u.watch_yaw) and rad_to_deg(absf(angle_difference(u.watch_yaw, bearing))) <= notice_told_deg:
		delay *= notice_told_mult
	if Vector2(u.velocity.x, u.velocity.z).length() > 1.0:
		delay *= notice_moving_obs_mult
	delay *= 1.0 + (notice_supp_mult - 1.0) * u.suppression_at(now)
	return delay * _diff(u, "spot")


## AI-COMBAT-02: the difficulty multiplier `key` for soldier u (Difficulty: full for soldiers hostile to the player).
func _diff(u: UnitState, key: String) -> float:
	return Difficulty.mult(key, u.faction, sim.state.war.player_faction if sim.state.war else 0)


func _acquire(u: UnitState, t: UnitState, aim_y: float) -> void:
	var now := sim.state.time
	_remember_seen(u, t.id, now, t.position)
	if t.id != u.target_id:
		if u.target_id > 0:
			target_switches += 1
		acquisitions += 1
		u.target_id = t.id
		var d := _flat(u.position, t.position)
		u.aim_ready_at = now + (reaction_s + reaction_per_100m_s * d / 100.0) * _diff(u, "react") + suppression_acquire_s * u.suppression_at(now)
		u.aim_since = now
		u.burst_left = 0
		_event(u, "sees %s at %.0f m" % [t.unit_name, d])
		_share_contact(u, t)
		# Shots that miss fly on: fill the vegetation cells beyond the target too.
		var eye := CombatSim.eye_of(u)
		var far := eye + (t.position - u.position).normalized() * 600.0
		_line_warm(eye, far)
	u.target_aim_y = aim_y
	u.target_seen_at = now
	u.target_last_pos = t.position
	u.target_visible = true
	_report_seen(u, t)


func _remember_seen(u: UnitState, tid: int, now: float, at := Vector3.INF) -> void:
	var seen: Dictionary = _spot.get(u.id, {})
	seen[tid] = [0.0, now, now, at]
	_spot[u.id] = seen


## AI-INTEL-01: a soldier that really sees an enemy (the line of sight was just checked)
## reports it to its faction; IntelSim throttles and merges. This is the only way sightings
## reach the faction - the contact picture is built from what CombatBrain perceives.
func _report_seen(u: UnitState, t: UnitState) -> void:
	if sim.war != null and sim.war.enabled and sim.war.intel.seen_due(u):
		var t0 := Time.get_ticks_usec()
		var group := _group_near(t, 25.0)
		sim.war.intel.group_usec += Time.get_ticks_usec() - t0
		sim.war.intel.report_seen(u, t, group)


## Enemy soldiers (of t's faction) within r of t, t included: the size of the group a sighted
## soldier belongs to. Uses the faction grid of this frame; no sight checks.
func _group_near(t: UnitState, r: float) -> int:
	var cells: Dictionary = _fgrid.get(t.faction, {})
	var c0 := Vector2i(floori((t.position.x - r) / FGRID), floori((t.position.z - r) / FGRID))
	var c1 := Vector2i(floori((t.position.x + r) / FGRID), floori((t.position.z + r) / FGRID))
	var n := 0
	var r2 := r * r
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			for o: UnitState in cells.get(Vector2i(x, z), []):
				var dx := o.position.x - t.position.x
				var dz := o.position.z - t.position.z
				if dx * dx + dz * dz <= r2:
					n += 1
	return maxi(n, 1)


func _drop_target(u: UnitState, why: String) -> void:
	if u.target_id < 0:
		return
	dropped_targets += 1
	_event(u, "drops target (%s)" % why)
	if u.target_last_pos.is_finite():
		_watch(u, u.target_last_pos, watch_after_lost_s)
	u.target_id = -1
	u.target_visible = false
	u.burst_left = 0


## Squad mates nearby turn towards a contact one of them reported (they still need to
## see it themselves before they shoot).
func _share_contact(u: UnitState, t: UnitState) -> void:
	var sq := sim.state.squad_of(u.id)
	if sq == null:
		return
	for id in sq.members:
		var m := sim.state.get_unit(id)
		if m and m != u and m.target_id < 0 and not m.player_controlled and _flat(m.position, u.position) <= contact_share_m:
			# AI-COMBAT-02: told roughly where ("by the barn"), not shown the man - they still have to find him themselves.
			var side := Vector3(-(t.position.z - m.position.z), 0.0, t.position.x - m.position.x).normalized()
			_watch(m, t.position + side * (_rand(m, 31) * 2.0 - 1.0) * suspect_blur * _flat(m.position, t.position), 6.0)


func _watch(u: UnitState, at: Vector3, seconds: float) -> void:
	var d := Vector3(at.x - u.position.x, 0.0, at.z - u.position.z)
	if d.length() < 0.5:
		return
	u.watch_yaw = atan2(-d.x, -d.z)
	u.watch_until = sim.state.time + seconds


## Every shot: enemies of the shooter within hearing_m look towards it; enemies it
## passed within near_miss_m (or hit) come under fire.
func _on_shot(shot: Dictionary) -> void:
	if not enabled:
		return
	var t0 := Time.get_ticks_usec()
	var s := sim.state.get_unit(shot.shooter)
	if s == null:
		return
	var origin: Vector3 = shot.origin
	var end: Vector3 = shot.end
	_ensure_grid()
	_recent_shots.append([origin, s.faction, sim.state.time])
	if tactics_enabled:
		# GAMEPLAY-02B: the weapon decides how close a round must pass and how much it suppresses (a machine gun's stream
		# of rounds); the damage is never scaled for it.
		var wdef := sim.combat.weapon(s.weapon_id)
		var miss_m := wdef.near_miss_m if wdef else near_miss_m
		var per_shot := suppression_per_shot * (wdef.suppression_mult if wdef else 1.0)
		var a := Vector2(origin.x, origin.z)
		var b := Vector2(end.x, end.z)
		if a.distance_to(b) > 450.0:
			b = a + (b - a).normalized() * 450.0
		for u: UnitState in units_near_segment(a, b, miss_m):
			if u.faction != s.faction and u.alive:
				# Vertical check too: a shot far overhead does not count.
				var ax := Posture.span(u)
				var pts := Geometry3D.get_closest_points_between_segments(origin, end, ax[0], ax[1])
				var miss: float = pts[0].distance_to(pts[1])
				if miss <= miss_m and u.player_controlled:
					# GAMEPLAY-02D: the possessed soldier's record keeps its suppression too - only the HUD reads it (the
					# player's aim is the player's), so first person feels the fire the AI feels.
					u.add_suppression(per_shot * (1.0 - 0.7 * miss / miss_m), sim.state.time)
				if miss <= miss_m and not u.player_controlled:
					_under_fire(u, origin)
					# AI-SQUAD-01: the closer it passes, the more it suppresses; a hit is
					# counted by _on_damaged. AI-COMBAT-02: x the difficulty's suppression weight.
					u.add_suppression(per_shot * (1.0 - 0.7 * miss / miss_m) * _diff(u, "supp"), sim.state.time)
					suppression_events += 1
	prof.shot_events += Time.get_ticks_usec() - t0


## A soldier died: everyone tracking it lets go at once (not at their next update); its
## cover search and reservation go.
func _on_died(t: UnitState) -> void:
	_searches.erase(t.id)
	t.clear_reaction()
	for u: UnitState in sim.state.units.values():
		if u.target_id == t.id:
			_drop_target(u, "target down")


func _on_damaged(t: UnitState, _amount: float, _zone: int, source_id: int) -> void:
	var s := sim.state.get_unit(source_id)
	if not enabled or s == null or not t.alive or t.player_controlled:
		return
	if tactics_enabled and s.faction != t.faction:
		t.hit_at = sim.state.time
		t.add_suppression(suppression_per_hit * _diff(t, "supp"), sim.state.time)
		_under_fire(t, CombatSim.eye_of(s))
	# AI-COMBAT-02: towards where the fire came from as he can tell (the blurred threat), not the shooter's exact position.
	if t.target_id < 0 or not t.target_visible:
		_watch(t, t.threat_pos if t.threat_pos.is_finite() else s.position, 5.0)


## Under fire: the soldier knows roughly where from (the shooter's position, blurred by a
## seeded error of up to 8 % of the distance sideways), not who or exactly where.
func _under_fire(u: UnitState, from: Vector3, alert_squad := true) -> void:
	var now := sim.state.time
	var first := u.under_fire_until < now
	u.under_fire_until = now + under_fire_s
	u.threat_at = now
	if first or not u.threat_pos.is_finite() or _flat(u.threat_pos, from) > 30.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([sim.state.world_seed, u.id, int(now * 4.0), 31])
		var d := _flat(u.position, from)
		var side := Vector3(-(from.z - u.position.z), 0.0, from.x - u.position.x).normalized()
		u.threat_pos = Vector3(from.x, from.y - CombatSim.EYE_HEIGHT, from.z) + side * rng.randf_range(-0.08, 0.08) * d
	if u.target_id < 0:
		_watch(u, u.threat_pos, 5.0)
	if first:
		_event(u, "under fire from %.0f m" % _flat(u.position, from))
		if sim.war != null and sim.war.enabled:
			sim.war.intel.report_fire(u, u.threat_pos)
		if alert_squad:
			var sq := sim.state.squad_of(u.id)
			if sq:
				for id in sq.members:
					var m := sim.state.get_unit(id)
					if m and m != u and not m.player_controlled and m.under_fire_until < now and _flat(m.position, u.position) <= squad_alert_m:
						_under_fire(m, from, false)
						m.under_fire_until = now + under_fire_s * 0.6


# --- Spatial index ---------------------------------------------------------------------

func _prune_recent_shots() -> void:
	var now := sim.state.time
	var keep := []
	for r: Array in _recent_shots:
		if now - r[2] <= 1.0:
			keep.append(r)
	_recent_shots = keep.slice(-96) if keep.size() > 96 else keep


func _is_far(u: UnitState) -> bool:
	if sim.detail == null:
		return false
	return _flat(u.position, sim.detail.observer) > far_m


## GAMEPLAY-02C: soldiers within r of p (the grid is refreshed first); for bursts and other bounded queries.
func units_near(p: Vector3, r: float) -> Array:
	_ensure_grid()
	return _near(p, r)


## GAMEPLAY-02C: a burst near u - it knows roughly where it came from, as from a shot.
func under_fire_from(u: UnitState, from: Vector3) -> void:
	if enabled and tactics_enabled and u.alive and not u.player_controlled:
		_under_fire(u, from + Vector3.UP * CombatSim.EYE_HEIGHT)


func _near(p: Vector3, r: float) -> Array:
	var out := []
	var c0 := Vector2i(floori((p.x - r) / GRID), floori((p.z - r) / GRID))
	var c1 := Vector2i(floori((p.x + r) / GRID), floori((p.z + r) / GRID))
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			for u: UnitState in _grid.get(Vector2i(x, z), []):
				if _flat(u.position, p) <= r:
					out.append(u)
	return out


## Living soldiers whose position lies within r of the 2D segment a-b (r up to a few
## metres): the cells the segment crosses plus their neighbours. Used by LineOfFire for
## shots (instead of scanning every unit) and for near misses.
func units_near_segment(a: Vector2, b: Vector2, r: float) -> Array:
	_ensure_grid()
	var cells := {}
	var seg := b - a
	# Samples at most one cell apart, each with its 3 x 3 neighbourhood: any point within
	# r (a few metres) of the segment lies in one of these cells.
	var n := maxi(1, ceili(seg.length() / GRID))
	for k in n + 1:
		var q := a + seg * (float(k) / n)
		var c := Vector2i(floori(q.x / GRID), floori(q.y / GRID))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				cells[c + Vector2i(dx, dz)] = true
	var out := []
	for c: Vector2i in cells:
		for u: UnitState in _grid.get(c, []):
			if LineOfFire._point_segment_dist2d(Vector2(u.position.x, u.position.z), a, b) <= r:
				out.append(u)
	return out


func _ensure_grid() -> void:
	var f := Engine.get_physics_frames()
	if f == _grid_frame:
		return
	var tg := Time.get_ticks_usec()
	_grid_frame = f
	_grid.clear()
	_fgrid.clear()
	_covers.clear()
	_aimers.clear()
	for u: UnitState in sim.state.units.values():
		if u.alive and u.kind == UnitState.Kind.SOLDIER and u.vehicle_id < 0:
			if u.target_id > 0 and u.target_visible:
				_aimers[u.target_id] = int(_aimers.get(u.target_id, 0)) + 1
			if u.cover_pos.is_finite():
				_covers.append([u.cover_pos, u])
			if u.post_pos.is_finite():
				_covers.append([u.post_pos, u])
			var k := Vector2i(floori(u.position.x / GRID), floori(u.position.z / GRID))
			if not _grid.has(k):
				_grid[k] = []
			_grid[k].append(u)
			if not _fgrid.has(u.faction):
				_fgrid[u.faction] = {}
			var fk := Vector2i(floori(u.position.x / FGRID), floori(u.position.z / FGRID))
			var cells: Dictionary = _fgrid[u.faction]
			if not cells.has(fk):
				cells[fk] = []
			cells[fk].append(u)
	prof.grid += Time.get_ticks_usec() - tg


## Where the soldier is looking: at its target, else where it was told / heard to look,
## else scanning around its heading (COMBAT-02: idle soldiers sweep idle_scan_deg to
## each side over idle_scan_s, so one that ended up facing the wrong way is not blind
## behind it for good; the body does not turn for this).
func look_yaw(u: UnitState) -> float:
	if u.target_id > 0 and u.target_last_pos.is_finite():
		var d := u.target_last_pos - u.position
		if Vector2(d.x, d.z).length() > 0.5:
			return atan2(-d.x, -d.z)
	if not is_nan(u.watch_yaw) and u.watch_until >= sim.state.time:
		return u.watch_yaw
	return u.yaw + deg_to_rad(idle_scan_deg) * sin(TAU * sim.state.time / idle_scan_s + u.id * 1.7)


func _rebuild_queue() -> void:
	_queue.clear()
	for u: UnitState in sim.state.all_units():
		if u.alive and u.kind == UnitState.Kind.SOLDIER and u.vehicle_id < 0:
			_queue.append(u.id)
	_qi = _qi % maxi(_queue.size(), 1)
	_queue_dirty = false


# --- Vegetation warm-up ------------------------------------------------------------------

## True when every vegetation cell along the line is filled; otherwise queues the missing
## ones (filled warm_cells_per_frame per frame) and returns false.
func _line_warm(a: Vector3, b: Vector3) -> bool:
	var line := sim.combat.line
	if line.vegetation == null:
		return true
	var ready := true
	var cs: float = line.vegetation.cell_size_m
	var n := maxi(1, ceili(_flat(a, b) / (cs * 0.5)))
	for k in n + 1:
		var q := a.lerp(b, float(k) / n)
		var c := Vector2i(floori(q.x / cs), floori(q.z / cs))
		for d: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var cc := c + d
			if not line.cell_ready(cc):
				ready = false
				if not _warm_set.has(cc):
					_warm_set[cc] = true
					_warm_queue.append(cc)
	return ready


func _warm_step() -> void:
	var n := 0
	while n < warm_cells_per_frame and not _warm_queue.is_empty():
		var c: Vector2i = _warm_queue.pop_front()
		_warm_set.erase(c)
		if not sim.combat.line.cell_ready(c):
			sim.combat.line.warm(c)
			warm_cells += 1
			n += 1


# --- Tactical reactions (COMBAT-02) ------------------------------------------------------

## What the soldier's order allows: "hold" (an area, no time limit), "move", "follow",
## "regroup" (brief reactions near where it is), "player" (none).
func order_mode(u: UnitState) -> String:
	if u.player_controlled:
		return "player"
	# GAMEPLAY-01C: a soldier standing in a fortification slot fights from it: the structure is his cover.
	if u.fort_pos.is_finite():
		return "fort"
	var sq := sim.state.squad_of(u.id)
	if sq and not sq.is_detached(u.id):
		# AI-SQUAD-01: inside a squad tactic a soldier either dashes to its assigned post
		# (reacts only when pinned) or holds it (reacts within a few metres of it).
		if sq.tactic != SquadState.Tactic.NONE:
			if u.order == UnitState.Order.MOVE:
				return "dash"
			if u.post_pos.is_finite():
				return "post"
			return "hold"
		match sq.order:
			SquadState.Order.FOLLOW:
				return "follow"
			SquadState.Order.REGROUP:
				return "regroup" if u.order == UnitState.Order.MOVE else "hold"
			SquadState.Order.MOVE:
				return "move" if u.order == UnitState.Order.MOVE else "hold"
	return "move" if u.order == UnitState.Order.MOVE else "hold"


func _tactics(u: UnitState) -> void:
	if not u.alive:
		return
	var now := sim.state.time
	var mode := order_mode(u)
	if mode == "player" or mode == "fort":
		if u.tactic != UnitState.Tactic.NONE or u.is_reacting():
			u.clear_reaction()
		_searches.erase(u.id)
		return
	var supp := u.suppression_at(now)
	var threatened := (u.under_fire_until >= now or supp >= suppressed_at) and u.threat_pos.is_finite()
	# A soldier dashing between posts of a squad tactic keeps going unless pinned down.
	if mode == "dash" and supp < pinned_at and u.tactic == UnitState.Tactic.NONE:
		return
	match u.tactic:
		UnitState.Tactic.NONE:
			if u.is_reacting():
				u.clear_reaction()
			if threatened and now >= u.tactic_cooldown_until and not _searches.has(u.id):
				_start_search(u, mode)
			elif _lof_move_ok(u, mode, now):
				_lof_move(u, mode, now)
			elif (mode == "hold" or mode == "post") and not threatened and now - u.threat_at > calm_s and u.anchor_pos.is_finite() \
					and _flat(u.position, u.anchor_pos) > 2.5 and now >= u.tactic_cooldown_until and not _fighting(u, now):
				# A reaction that ended away from the held spot (cover not reached, cover no
				# longer useful): walk back once it is calm.
				u.tactic = UnitState.Tactic.RETURNING
				u.tactic_since = now
				u.react_target = u.anchor_pos
				u.react_state = UnitState.ReactState.MOVING
				Posture.for_move(u, _flat(u.position, u.anchor_pos), now)
				u.cover_note = "calm: back to the held position"
		UnitState.Tactic.SEEK_COVER:
			if _searches.has(u.id):
				return
			if u.react_state == UnitState.ReactState.ARRIVED:
				u.tactic = UnitState.Tactic.IN_COVER
				u.tactic_since = now
				u.cover_checked_at = now
				_event(u, "in cover")
			elif u.react_state == UnitState.ReactState.FAILED or now - u.tactic_since > 20.0:
				_mark_bad(u, u.cover_pos)
				cover_unreachable += 1
				u.cover_note = "could not reach cover: rejected for %.0f s" % bad_cover_s
				_end_reaction(u, 1.0)
			elif now > u.react_until:
				u.cover_note = "reaction time over: order resumes"
				_end_reaction(u, move_react_cooldown_s)
		UnitState.Tactic.IN_COVER:
			if now > u.react_until:
				u.cover_note = "reaction time over: order resumes"
				_end_reaction(u, move_react_cooldown_s)
			elif now - u.threat_at > calm_s and not _fighting(u, now):
				var anchor := u.anchor_pos
				if (mode == "hold" or mode == "post") and anchor.is_finite() and _flat(u.position, anchor) > 2.0:
					u.tactic = UnitState.Tactic.RETURNING
					u.tactic_since = now
					u.react_target = anchor
					u.react_state = UnitState.ReactState.MOVING
					Posture.for_move(u, _flat(u.position, anchor), now)
					u.cover_pos = Vector3.INF
					u.cover_note = "calm: back to the held position"
				else:
					u.cover_note = "calm"
					_end_reaction(u, 2.0)
			elif now - u.cover_checked_at >= recheck_s and u.threat_pos.is_finite() and not _searches.has(u.id):
				u.cover_checked_at = now
				var ev := _evaluate_spot(u, u.position, u.threat_pos)
				if not ev.protected and now - u.tactic_since >= min_dwell_s:
					u.cover_note = "cover no longer protects: looking again"
					_end_reaction(u, 0.0)
				elif _lof_move_ok(u, mode, now):
					_lof_move(u, mode, now)
				elif ev.protected and not ev.can_fire and _wants_firing_spot(u, now):
					# AI-COMBAT-02: safe but useless - full cover with no line to the enemy, nobody in sight for a while: a short
					# move to nearby cover he can fire from (he keeps this cover when there is none).
					_fire_retry[u.id] = now + fire_retry_s
					_start_search(u, mode, true)
		UnitState.Tactic.RETURNING:
			if not u.is_reacting() or u.react_state != UnitState.ReactState.MOVING:
				u.clear_reaction()
			elif threatened and now >= u.tactic_cooldown_until:
				u.clear_reaction()


## COMBAT-01: the posture an AI soldier fights in, from what it already knows (its order, reaction, target, suppression):
## standing when idle or in a fortification slot, crouched when alert or in cover, prone when pinned in the open or when a
## machine gun / marksman rifle engages a distant target - never while moving (Posture.for_move decided that when the move
## began), never where the ground does not suit it, never just before its squad moves on. A choice holds posture_hold_s
## (prone prone_hold_s) before the next one; getting down / up takes its own time (Posture.TRANSITION_S).
func _choose_posture(u: UnitState) -> void:
	var now := sim.state.time
	var moving := (u.order == UnitState.Order.MOVE and u.move_state == UnitState.MoveState.MOVING) \
		or (u.is_reacting() and u.react_state == UnitState.ReactState.MOVING)
	if Posture.busy(u, now):
		return
	# QOL-01: the squad's behaviour mode (what it acts on now) and how near the threat it believes in is.
	var sq := sim.state.squad_of(u.id)
	var beh := sim.tactics.behaviour_now(sq) if sq else SquadBehaviour.AWARE
	var near := sq != null and SquadBehaviour.LOW_M[beh] > 0.0 and sim.tactics.threat_dist(sq) <= SquadBehaviour.LOW_M[beh]
	# COMBAT-POLISH-01: an AI faction's soldier at the post his squad settled into at the end of a move (SquadTactics._settle,
	# which places AI squads as COMBAT) keeps low against the believed threat like a COMBAT squad of the player's.
	if sq != null and not near and sq.tactic == SquadState.Tactic.NONE and u.post_pos.is_finite() and _flat(u.position, u.post_pos) < 2.0 \
			and not sim.tactics._player_squad(sq) and sim.tactics.threat_dist(sq) <= SquadBehaviour.LOW_M[SquadBehaviour.COMBAT]:
		near = true
	if moving:
		# STEALTH close to a believed enemy walks crouched (concealment delays noticing); upright again further off, and always
		# upright when it sprints across open ground or dashes for cover (QOL-01.1: no crouch-walking the whole approach).
		if beh == SquadBehaviour.STEALTH and not u.is_reacting():
			var close := sq != null and sim.tactics.threat_dist(sq) <= SquadBehaviour.STEALTH_CROUCH_MOVE_M
			var mw := Posture.CROUCH if close and sim.pace_of(u) == UnitState.Pace.WALK else Posture.STAND
			if mw != u.posture and u.posture != Posture.PRONE and Posture.request(u, mw, now):
				posture_changes += 1
				u.posture_hold_until = now + posture_hold_s
		return
	var want := Posture.STAND
	var mode := order_mode(u)
	if now < u.down_until:
		want = Posture.PRONE
	elif mode != "fort":
		var supp := u.suppression_at(now)
		var engaged := u.target_id > 0 and now - u.target_seen_at < 4.0
		var alert := engaged or now < u.under_fire_until or now < u.watch_until or supp >= suppressed_at \
			or (u.fire_at.is_finite() and now < u.fire_until)
		if beh == SquadBehaviour.SAFE:
			# SAFE (nothing seen, nobody shooting): upright; only fire taken brings it down.
			alert = now < u.under_fire_until or supp >= suppressed_at
		if u.tactic == UnitState.Tactic.IN_COVER or alert or near:
			want = Posture.CROUCH
		if beh == SquadBehaviour.STEALTH and near and not alert and (mode == "hold" or mode == "post") and not _moves_soon(u, mode) \
				and sq.status != SquadState.Status.MOVING and not sim.squads.marching(sq) \
				and sim.tactics.threat_dist(sq) <= SquadBehaviour.STEALTH_PRONE_M and prone_ground_ok(u):
			want = Posture.PRONE
		# WORLD-COVER-01.1: where only lying down protects (a hollow, a low bank or log: the spot is "low" against the believed
		# threat) a soldier taking cover, under fire or waiting goes prone; one fighting a target he sees keeps his crouch to shoot.
		if want == Posture.CROUCH and (u.tactic == UnitState.Tactic.IN_COVER or supp >= suppressed_at or not engaged) \
				and not _moves_soon(u, mode) and _low_cover(u, now) and prone_ground_ok(u):
			want = Posture.PRONE
		# WORLD-COVER-01.1: behind cover taller than a crouching man's eye (a boulder, a root plate, the crest of a fold) a soldier
		# fighting a target he sees stands to fire over it; the next choice brings him down again when the fight eases.
		if want == Posture.CROUCH and engaged and supp < suppressed_at and not _moves_soon(u, mode) and _stand_to_fire(u, now):
			want = Posture.STAND
		if alert and u.tactic != UnitState.Tactic.IN_COVER:
			var wdef := sim.combat.weapon(u.weapon_id)
			var steady_weapon := wdef != null and (wdef.role == &"lmg" or wdef.role == &"dmr")
			var far := engaged and u.target_last_pos.is_finite() and _flat(u.position, u.target_last_pos) >= prone_engage_m
			# Down when pinned in the open; a gun / marksman down for a distant target; once down, up again only when
			# the fire has eased (hysteresis).
			var keep := u.posture == Posture.PRONE and (supp >= 0.3 or (far and steady_weapon))
			if (supp >= pinned_at or (far and steady_weapon) or keep) and not _moves_soon(u, mode) and prone_ground_ok(u):
				want = Posture.PRONE
	if want == u.posture or (now < u.posture_hold_until and now >= u.down_until):
		return
	if Posture.request(u, want, now):
		posture_changes += 1
		u.posture_hold_until = now + (prone_hold_s if want == Posture.PRONE else posture_hold_s)
		_event(u, Posture.NAMES[want])


## QOL-01: a STEALTH squad that has not been found holds fire at a target beyond STEALTH_FIRE_M (a shot is heard and gives
## the squad away); a soldier just hit, or a target that close, is fired at. Fired on (compromised) the squad fights as COMBAT.
func _stealth_holds(u: UnitState, sq: SquadState, dist: float, now: float) -> bool:
	if sq == null or sq.behaviour != SquadBehaviour.STEALTH or sim.tactics.behaviour_now(sq) != SquadBehaviour.STEALTH:
		return false
	# QOL-01.1: a fight the player ordered (assault, suppress, flank, defend) is fought: the order outranks the mode.
	if sq.tactic_owner == SquadState.Owner.PLAYER and sq.tactic in [SquadState.Tactic.ASSAULT, SquadState.Tactic.SUPPRESS, SquadState.Tactic.FLANK, SquadState.Tactic.DEFEND]:
		return false
	return dist > SquadBehaviour.STEALTH_FIRE_M and now - u.hit_at > self_defence_s


## WORLD-COVER-01.1: the soldier's spot protects him only lying down against the threat he believes in (judged at most every
## 4 s per spot and threat; derived, never saved).
var _low := {}


func _low_cover(u: UnitState, now: float) -> bool:
	var threat := u.threat_pos if u.threat_pos.is_finite() else u.target_last_pos
	if not threat.is_finite():
		# The squad's belief (a reported enemy the soldier has not seen himself).
		var sq := sim.state.squad_of(u.id)
		threat = sim.tactics.threat_pos(sq) if sq else Vector3.INF
	if not threat.is_finite() or _flat(u.position, threat) > 400.0:
		return false
	var e: Array = _low.get(u.id, [])
	if not e.is_empty() and now - float(e[0]) < 4.0 and _flat(e[1], u.position) < 1.0 and _flat(e[2], threat) < 10.0:
		return e[3]
	var low := bool(_evaluate_spot(u, u.position, threat).get("low", false))
	_low[u.id] = [now, u.position, threat, low]
	return low


## WORLD-COVER-01.1: the soldier's crouched eye line to his target meets cover within 4 m while his standing one is clear (judged
## at most every 2 s per spot and target; derived, never saved).
var _stand := {}


func _stand_to_fire(u: UnitState, now: float) -> bool:
	var t := u.target_last_pos
	if not t.is_finite():
		return false
	var e: Array = _stand.get(u.id, [])
	if not e.is_empty() and now - float(e[0]) < 2.0 and _flat(e[1], u.position) < 1.0 and _flat(e[2], t) < 5.0:
		return e[3]
	var line := sim.combat.line
	var aim := t + Vector3.UP * 1.0
	var ce := u.position + Vector3.UP * Posture.EYE[Posture.CROUCH].y
	var se := u.position + Vector3.UP * Posture.EYE[Posture.STAND].y
	var d := _flat(u.position, t) - 1.0
	var ok := false
	if d > 4.0:
		var rc := line.trace(ce, ce + (aim - ce).normalized() * d, u.id, false)
		if rc.blocker != "range" and float(rc.distance) <= 4.0:
			ok = line.trace(se, se + (aim - se).normalized() * d, u.id, false).blocker == "range"
	_stand[u.id] = [now, u.position, t, ok]
	return ok


## The squad is about to move this soldier (an assault, flank, bound or withdrawal it is not holding a post in).
func _moves_soon(u: UnitState, mode: String) -> bool:
	if mode == "dash":
		return true
	var sq := sim.state.squad_of(u.id)
	if sq == null or mode == "post":
		return false
	return sq.tactic in [SquadState.Tactic.ASSAULT, SquadState.Tactic.FLANK, SquadState.Tactic.BOUND, SquadState.Tactic.WITHDRAW, SquadState.Tactic.REGROUP]


## Ground a soldier can lie on where it stands, facing as it does: not too steep, not wet, not on a bridge deck, no
## structure under the head or the legs (the prone body reaches ~0.8 m forward and ~1 m back; Posture.span).
func prone_ground_ok(u: UnitState) -> bool:
	if sim.terrain:
		var n: Vector3 = sim.terrain.data.get_normal(u.position)
		if n.is_finite() and n.y < 0.9:
			return false
	if sim.state.roads and not is_nan(sim.state.roads.deck_height(u.position)):
		return false
	if sim.structures:
		for p: Vector3 in Posture.span(u) + [u.position]:
			if sim.structures.blocks_point(Vector2(p.x, p.z), 0.25) or sim.structures._wet(p.x, p.z, u.position.y - 0.1):
				return false
	return true


func _end_reaction(u: UnitState, cooldown: float) -> void:
	_searches.erase(u.id)
	u.clear_reaction()
	u.tactic_cooldown_until = sim.state.time + cooldown


func _mark_bad(u: UnitState, p: Vector3) -> void:
	if not p.is_finite():
		return
	if not _bad_cover.has(u.id):
		_bad_cover[u.id] = []
	_bad_cover[u.id].append([p, sim.state.time + bad_cover_s])


func _is_bad(u: UnitState, p: Vector3) -> bool:
	var now := sim.state.time
	var keep := []
	var bad := false
	for e: Array in _bad_cover.get(u.id, []):
		if e[1] > now:
			keep.append(e)
			if _flat(e[0], p) < 1.5:
				bad = true
	if _bad_cover.has(u.id):
		_bad_cover[u.id] = keep
	return bad


## AI-COMBAT-02: a soldier in full cover without a line of fire looks for cover he can fire from after fire_retry_s in cover
## with no enemy in sight for fire_blind_s, not suppressed, at most once per fire_retry_s; the search excludes his own spot.
var fire_retry_s := 25.0
var fire_blind_s := 10.0
var fire_moves := 0
var _fire_retry := {}
## `--no-stalemate`: no such moves (and no squad stalemate shifts, SquadTactics.stalemate_on) - comparison runs.
var firing_moves := true


func _wants_firing_spot(u: UnitState, now: float) -> bool:
	if not firing_moves or now < float(_fire_retry.get(u.id, 0.0)) or now - u.tactic_since < min_dwell_s * 2.0 or u.suppression_at(now) >= suppressed_at:
		return false
	if u.target_id > 0 and now - u.target_seen_at < fire_blind_s:
		return false
	var sq := sim.state.squad_of(u.id)
	return sq == null or sq.roe != SquadState.Roe.HOLD_FIRE


## COMBAT-COVER-03: nobody shooting at him is not calm while he fights - a target seen within 4 s, or a fire mission he has a line
## for (he moved to a firing position for it): he stays where he can fire instead of walking back behind the wall.
func _fighting(u: UnitState, now: float) -> bool:
	if u.target_id > 0 and now - u.target_seen_at < 4.0:
		return true
	return u.fire_at.is_finite() and now < u.fire_until and not lof_stuck(u, now)


## COMBAT-COVER-03: a soldier whose line of fire keeps being blocked (lof_stuck) moves to a nearby firing position: not while
## dashing, suppressed or holding fire, at most every lof_retry_s.
func _lof_move_ok(u: UnitState, mode: String, now: float) -> bool:
	if not firing_moves or mode == "dash" or _searches.has(u.id) or not lof_stuck(u, now):
		return false
	if now < float(_fire_retry.get(u.id, 0.0)) or u.suppression_at(now) >= suppressed_at:
		return false
	var sq := sim.state.squad_of(u.id)
	return sq == null or sq.roe != SquadState.Roe.HOLD_FIRE


func _lof_move(u: UnitState, mode: String, now: float) -> void:
	_fire_retry[u.id] = now + lof_retry_s
	var e: Array = _lof_block.get(u.id, [])
	var tgt := sim.state.get_unit(int(e[4])) if not e.is_empty() else null
	var threat := u.target_last_pos if tgt != null and u.target_last_pos.is_finite() else (u.fire_at if u.fire_at.is_finite() else u.threat_pos)
	_lof_block.erase(u.id)
	lof_moves += 1
	_start_search(u, mode, true, threat)


func _start_search(u: UnitState, mode: String, need_fire := false, threat := Vector3.INF) -> void:
	var th := threat if threat.is_finite() else u.threat_pos
	var center := u.position
	var radius := cover_radius_hold
	var limit := INF
	match mode:
		"post":
			# A squad-assigned firing post: look for cover only next to it.
			center = u.post_pos
			radius = cover_radius_post
			if not u.anchor_pos.is_finite():
				u.anchor_pos = u.post_pos
		"dash":
			radius = cover_radius_regroup
			limit = react_s_regroup
		"hold":
			if not u.anchor_pos.is_finite():
				u.anchor_pos = u.position
			center = u.anchor_pos
		"move":
			# QOL-01: how far a soldier on the move goes for cover and how long he stays, by the squad's behaviour (COMBAT and a
			# compromised STEALTH squad dash farther and stay longer, SAFE takes the nearest and moves on).
			var b := sim.tactics.behaviour_now(sim.state.squad_of(u.id))
			radius = cover_radius_move * SquadBehaviour.REACT_RADIUS[b]
			limit = react_s_move * SquadBehaviour.REACT_TIME[b]
		"follow":
			radius = cover_radius_follow
			limit = react_s_follow
		"regroup":
			radius = cover_radius_regroup
			limit = react_s_regroup
	if not th.is_finite():
		return
	var cands := _cover_candidates(u, center, radius, th)
	if cands.is_empty():
		u.cover_note = "waiting for vegetation data"
		return
	var open_ok := false
	if need_fire:
		# Somewhere else: his own spot and the ones within a metre of it are what he is leaving.
		cands = cands.filter(func(c: Dictionary) -> bool: return c.kind != "here" and _flat(c.p, u.position) > 1.5)
		# COMBAT-COVER-03: a step or two sideways (past a corner, past a friend in the way) before anything farther.
		var tdir := Vector3(th.x - u.position.x, 0.0, th.z - u.position.z).normalized()
		var lat := Vector3(-tdir.z, 0.0, tdir.x)
		var steps: Array = []
		for s: float in [2.0, -2.0, 3.5, -3.5]:
			_add_candidate(steps, u.position, center, radius, u.position + lat * s, "step")
		cands = steps + cands
		# COMBAT-COVER-03: a firing spot without protection against this threat (past a corner, a step out from behind a wall) is
		# taken when nothing protected can fire - the soldier fights from the corner; under fire his reaction takes him back into
		# cover (protected spots score higher, _cover_score).
		open_ok = true
		if cands.is_empty():
			u.cover_note = "no other cover near: stays (no line of fire)"
			return
	cover_searches += 1
	_searches[u.id] = {"cands": cands, "i": 0, "accepted": [],
		"mode": mode, "limit": limit, "threat": th, "rejects": {}, "need_fire": need_fire, "open_ok": open_ok}
	if need_fire:
		u.cover_note = "no line of fire: looking for a firing position (%s, %.0f m)" % [mode, radius]
		return  # keeps his cover (IN_COVER) until a better spot is found
	u.tactic = UnitState.Tactic.SEEK_COVER
	u.tactic_since = sim.state.time
	u.cover_note = "looking for cover (%s, %.0f m)" % [mode, radius]


## Evaluates pending cover candidates, cover_budget per frame for everyone together,
## and finishes searches whose candidates are all evaluated.
func _search_step() -> void:
	var budget := cover_budget
	for id: int in _searches.keys():
		if budget <= 0:
			return
		var u := sim.state.get_unit(id)
		if u == null or not u.alive:
			_searches.erase(id)
			continue
		var s: Dictionary = _searches[id]
		var cands: Array = s.cands
		while s.i < cands.size() and budget > 0:
			var c: Dictionary = cands[s.i]
			s.i += 1
			budget -= eval_cost
			cover_evals += 1
			var why := _reject(u, c.p)
			if why != "":
				s.rejects[why] = s.rejects.get(why, 0) + 1
				continue
			var ev := _evaluate_spot(u, c.p, s.threat)
			if not ev.protected and not (bool(s.get("open_ok", false)) and ev.can_fire):
				s.rejects["no protection from the threat"] = s.rejects.get("no protection from the threat", 0) + 1
				continue
			if bool(s.get("need_fire", false)) and not ev.can_fire:
				s.rejects["no line of fire either"] = s.rejects.get("no line of fire either", 0) + 1
				continue
			c["can_fire"] = ev.can_fire
			c["score"] = _cover_score(u, c, ev)
			s.accepted.append(c)
		if s.i >= cands.size():
			_finish_search(u, s)


func _finish_search(u: UnitState, s: Dictionary) -> void:
	_searches.erase(u.id)
	var accepted: Array = s.accepted
	accepted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var now := sim.state.time
	for c: Dictionary in accepted:
		# Another soldier may have taken the spot since it was evaluated.
		if c.kind != "here" and _reject(u, c.p) != "":
			continue
		if c.kind != "here" and not _reachable(u, c.p):
			_mark_bad(u, c.p)
			cover_unreachable += 1
			continue
		cover_found += 1
		u.cover_pos = c.p
		_covers.append([c.p, u])
		u.react_target = u.position if c.kind == "here" else c.p
		u.react_state = UnitState.ReactState.ARRIVED if c.kind == "here" else UnitState.ReactState.MOVING
		if c.kind != "here":
			Posture.for_move(u, _flat(u.position, c.p), now)
		u.react_until = now + s.limit if s.limit < INF else INF
		u.tactic = UnitState.Tactic.IN_COVER if c.kind == "here" else UnitState.Tactic.SEEK_COVER
		u.tactic_since = now
		u.cover_checked_at = now
		u.cover_note = "%s: %s %.0f m (%s)" % ["staying" if c.kind == "here" else "cover", c.kind, c.d,
			"can fire" if c.can_fire else "full cover"]
		_event(u, u.cover_note)
		if bool(s.get("need_fire", false)):
			fire_moves += 1
			u.cover_note = "moves to a firing position %.0f m (%s): no line of fire from his cover" % [c.d, c.kind]
		return
	cover_none += 1
	var rej: Dictionary = s.rejects
	var top := ""
	var most := 0
	for k: String in rej:
		if rej[k] > most:
			most = rej[k]
			top = k
	if bool(s.get("need_fire", false)):
		u.cover_note = "no firing position with cover near (%s): stays in cover" % (top if top != "" else "no candidates")
		return
	u.cover_note = "no usable cover within %s (%s)" % [s.mode, top if top != "" else "no candidates"]
	u.tactic = UnitState.Tactic.NONE
	u.tactic_cooldown_until = now + 4.0


## Candidate spots, cheapest first: where the soldier stands; behind structure modules,
## rocks and trunks (relative to the threat); terrain spots with a rise towards the
## threat. Only within radius of center, on usable ground; at most max_cover_candidates.
func _cover_candidates(u: UnitState, center: Vector3, radius: float, threat: Vector3) -> Array:
	var out := [{"p": u.position, "kind": "here", "d": 0.0}]
	var spots := cover_spots(center, radius, threat, u.position)
	if spots.is_empty() and sim.combat.line.vegetation and _veg_missing(center, radius):
		return []  # vegetation not filled yet: search again next update
	return out + spots


## Cover spots around `center` (structures, rocks, trunks, terrain rises relative to the
## threat), cheapest first, at most max_cover_candidates; `origin` is where distances are
## measured from. Shared by the soldiers own reaction and the squad tactics post search
## (AI-SQUAD-01). Empty while vegetation cells are still being filled.
func cover_spots(center: Vector3, radius: float, threat: Vector3, origin: Vector3, limit := -1) -> Array:
	var tdir := Vector3(threat.x - origin.x, 0.0, threat.z - origin.z)
	tdir = tdir.normalized() if tdir.length() > 0.1 else Vector3.FORWARD
	var out := []
	var st := sim.structures
	if st and st.state:
		var cs := StructureManager.CELL
		var c0 := Vector2i(floori((center.x - radius - 10.0) / cs), floori((center.z - radius - 10.0) / cs))
		var c1 := Vector2i(floori((center.x + radius + 10.0) / cs), floori((center.z + radius + 10.0) / cs))
		for x in range(c0.x, c1.x + 1):
			for z in range(c0.y, c1.y + 1):
				for e: Vector2i in st._index.get(Vector2i(x, z), []):
					var s := st.state.get_structure(e.x)
					if s == null or (s.is_line() and s.is_removed(e.y)) or e.y >= s.instances.size():
						continue
					var xf: Transform3D = s.instances[e.y]
					if _flat(xf.origin, center) > radius + _half_extent(s.type_id) + 2.0:
						continue
					# COMBAT-COVER-03: spots along every collision box of the structure (a fighting position, a HESCO line, a
					# bunker: several soldiers along its lee face and at its corners), not one spot behind its middle.
					var def := StructureCatalog.get_def(s.type_id)
					if def == null:
						continue
					for box: AABB in def.get_collision_boxes():
						var bc := xf * Vector3(box.get_center().x, box.position.y, box.get_center().z)
						for q: Vector3 in CoverEval.box_spots(bc, xf.basis.orthonormalized(), box.size.x * 0.5, box.size.z * 0.5, box.size.y, tdir, 0.6):
							_add_candidate(out, origin, center, radius, q, "structure")
	var line := sim.combat.line
	if line.vegetation:
		var b0 := Vector2i(floori((center.x - radius - 2.0) / LineOfFire.BUCKET), floori((center.z - radius - 2.0) / LineOfFire.BUCKET))
		var b1 := Vector2i(floori((center.x + radius + 2.0) / LineOfFire.BUCKET), floori((center.z + radius + 2.0) / LineOfFire.BUCKET))
		var vc0 := Vector2i(floori(b0.x * LineOfFire.BUCKET / line.vegetation.cell_size_m), floori(b0.y * LineOfFire.BUCKET / line.vegetation.cell_size_m))
		var vc1 := Vector2i(floori(b1.x * LineOfFire.BUCKET / line.vegetation.cell_size_m), floori(b1.y * LineOfFire.BUCKET / line.vegetation.cell_size_m))
		var missing := false
		for x in range(vc0.x, vc1.x + 1):
			for z in range(vc0.y, vc1.y + 1):
				var cc := Vector2i(x, z)
				if not line.cell_ready(cc):
					missing = true
					if not _warm_set.has(cc):
						_warm_set[cc] = true
						_warm_queue.append(cc)
		if missing:
			return []
		var seen := {}
		for bx in range(b0.x, b1.x + 1):
			for bz in range(b0.y, b1.y + 1):
				var data: PackedFloat32Array = line._buckets.get(Vector2i(bx, bz), PackedFloat32Array())
				for i in range(0, data.size(), LineOfFire.STRIDE):
					var r: float = data[i + 3]
					var c := Vector3(data[i], data[i + 2], data[i + 1])
					if data[i + 5] > 1.5:
						# COMBAT-COVER-03: a large box (a house) is filed in several buckets: once.
						if LineOfFire.copy_of(data, i, Vector2i(bx, bz)):
							var key := Vector4(data[i], data[i + 1], data[i + 6], data[i + 7])
							if seen.has(key):
								continue
							seen[key] = true
						_box_candidates(out, origin, center, radius, data, i, tdir)
						continue
					var rock := data[i + 5] > 0.5
					if (rock and r < 0.5) or (not rock and r < 0.25):
						continue
					_add_candidate(out, origin, center, radius, c - tdir * (r + COVER_GAP), "rock" if rock else "tree")
					if rock and r >= 1.0:
						# WORLD-COVER-01: a large boulder hides more than one soldier: spots to either side behind it too.
						var lat := Vector3(-tdir.z, 0.0, tdir.x) * r * 0.75
						_add_candidate(out, origin, center, radius, c - tdir * (r * 0.75 + COVER_GAP) + lat, "rock")
						_add_candidate(out, origin, center, radius, c - tdir * (r * 0.75 + COVER_GAP) - lat, "rock")
	# WORLD-COVER-01.1: the terrain microrelief near the centre - the bottom of a hollow or a ditch, the back of a fold or a bank
	# (seen from the threat) - from its feature list: precise spots without sampling the ground.
	if sim.terrain:
		_relief_candidates(out, origin, center, radius, tdir)
	# Terrain: spots with ground rising at least 0.55 m within 8 m towards the threat (prone cover; crouched needs more,
	# _evaluate_spot decides).
	if sim.terrain:
		for ring: float in [3.0, 6.0, 9.0, 12.0]:
			if ring > radius:
				break
			for k in 8:
				var a := k * TAU / 8.0
				var p := center + Vector3(cos(a), 0.0, sin(a)) * ring
				var h: float = sim.terrain.data.get_height(p)
				if is_nan(h):
					continue
				var rise := -INF
				for step: float in [1.5, 3.0, 5.0, 8.0]:
					var hh: float = sim.terrain.data.get_height(p + tdir * step)
					if not is_nan(hh):
						rise = maxf(rise, hh - h)
				if rise >= 0.55:
					_add_candidate(out, origin, center, radius, p, "terrain")
	var rank := {"structure": 1, "building": 1, "rock": 2, "box": 2, "terrain": 3, "tree": 4, "step": 0}
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.d + rank[a.kind] * 3.0 < b.d + rank[b.kind] * 3.0)
	return out.slice(0, max_cover_candidates if limit < 0 else limit)


## WORLD-COVER-01.1: cover spots on the terrain microrelief within radius of center (TerrainRelief features), for a threat in
## direction tdir: a hollow's bottom and its threat-side half (nearer the rim that shields it); along a fold, step or bank the
## back slope at 0.55 of its width from the crest (crouched behind the crest, the eye over it) and at 0.75 (lower: covered,
## not firing); along a ditch its bottom.
func _relief_candidates(out: Array, origin: Vector3, center: Vector3, radius: float, tdir: Vector3) -> void:
	for fi: int in TerrainRelief.features_near(center, radius):
		var f: Dictionary = TerrainRelief.feats[fi]
		match int(f.type):
			TerrainRelief.HOLLOW:
				if float(f.d) < 0.3:
					continue
				var c := Vector3(float(f.x), 0.0, float(f.z))
				_add_candidate(out, origin, center, radius, c, "terrain")
				_add_candidate(out, origin, center, radius, c + tdir * minf(float(f.rx), float(f.rz)) * 0.35, "terrain")
			TerrainRelief.RIDGE:
				var along := Vector3(float(f.cs), 0.0, float(f.sn))
				var across := Vector3(-float(f.sn), 0.0, float(f.cs))
				var away := -1.0 if across.dot(tdir) > 0.0 else 1.0
				var w := float(f.wb) if away > 0.0 else float(f.wf)
				for k: float in [-0.45, 0.0, 0.45]:
					var s := k * float(f.hl)
					var crest := Vector3(float(f.x), 0.0, float(f.z)) + along * s + across * float(f.get("bend", 0.0)) * (1.0 - k * k)
					_add_candidate(out, origin, center, radius, crest + across * away * w * 0.55, "terrain")
					_add_candidate(out, origin, center, radius, crest + across * away * w * 0.75, "terrain")
			TerrainRelief.LINE:
				var pts: PackedVector2Array = f.p2
				var q := Vector2(center.x, center.z)
				for i in pts.size() - 1:
					var ab := pts[i + 1] - pts[i]
					var l2 := maxf(ab.length_squared(), 1e-6)
					var foot := pts[i] + ab * clampf((q - pts[i]).dot(ab) / l2, 0.0, 1.0)
					if foot.distance_to(q) > radius:
						continue
					if float(f.a) < 0.0:
						_add_candidate(out, origin, center, radius, Vector3(foot.x, 0.0, foot.y), "terrain")
					else:
						var n := Vector2(-ab.y, ab.x).normalized()
						var nn := Vector3(n.x, 0.0, n.y)
						var side := -1.0 if nn.dot(tdir) > 0.0 else 1.0
						_add_candidate(out, origin, center, radius, Vector3(foot.x, 0.0, foot.y) + nn * side * float(f.w) * 0.6, "terrain")


## WORLD-COVER-01: how far behind the surface of a trunk, rock or box solid a cover spot lies (m). The local navmesh keeps
## agents tree_margin + agent radius (~0.95 m) off such solids: a spot nearer than that cannot be reached, the soldier stopped
## a metre short and often out of its shadow. 1.0 m behind a 0.85 m wall still hides a crouched soldier from a level shooter.
const COVER_GAP := 1.0


## WORLD-COVER-01: cover spots behind a box solid (log, wall, timber stack, root plate, rock group) at data[i] from a threat in
## direction tdir: along its long side away from the threat every 1.4 m (several soldiers behind one wall), or, when the
## threat lies along its length, behind its far end.
func _box_candidates(out: Array, origin: Vector3, center: Vector3, radius: float, data: PackedFloat32Array, i: int, tdir: Vector3) -> void:
	var c := Vector3(data[i], data[i + 2], data[i + 1])
	var hx: float = data[i + 7]
	var hz: float = data[i + 8]
	if _flat(c, center) > radius + Vector2(hx, hz).length() + COVER_GAP + 0.5:
		return
	# COMBAT-COVER-03: every lee face, corners of tall solids (CoverEval.box_spots); a building's walls are "building" spots.
	var kind := "building" if data[i + 4] >= 2.5 and maxf(hx, hz) >= 1.5 else "box"
	for q: Vector3 in CoverEval.box_spots(c, Basis(Vector3.UP, data[i + 6]), hx, hz, data[i + 4], tdir, COVER_GAP, 1.4):
		_add_candidate(out, origin, center, radius, q, kind)


## True while vegetation cells within radius of center are missing (queued for filling).
func _veg_missing(center: Vector3, radius: float) -> bool:
	var line := sim.combat.line
	var b0 := Vector2i(floori((center.x - radius - 2.0) / LineOfFire.BUCKET), floori((center.z - radius - 2.0) / LineOfFire.BUCKET))
	var b1 := Vector2i(floori((center.x + radius + 2.0) / LineOfFire.BUCKET), floori((center.z + radius + 2.0) / LineOfFire.BUCKET))
	var vc0 := Vector2i(floori(b0.x * LineOfFire.BUCKET / line.vegetation.cell_size_m), floori(b0.y * LineOfFire.BUCKET / line.vegetation.cell_size_m))
	var vc1 := Vector2i(floori(b1.x * LineOfFire.BUCKET / line.vegetation.cell_size_m), floori(b1.y * LineOfFire.BUCKET / line.vegetation.cell_size_m))
	for x in range(vc0.x, vc1.x + 1):
		for z in range(vc0.y, vc1.y + 1):
			if not line.cell_ready(Vector2i(x, z)):
				return true
	return false


func _add_candidate(out: Array, origin: Vector3, center: Vector3, radius: float, p: Vector3, kind: String) -> void:
	if _flat(p, center) > radius:
		return
	var h: float = sim.terrain.data.get_height(p) if sim.terrain else NAN
	var g := Vector3(p.x, (p.y if is_nan(h) else h), p.z)
	for c: Dictionary in out:
		if _flat(c.p, g) < 1.0:
			return
	if not sim.squads._usable(g + Vector3.UP * 0.25):
		return
	# COMBAT-COVER-03: a spot behind one part of a solid can lie inside another (a house's roof box, the next module of a wall).
	if sim.structures and sim.structures.blocks_trunk(Vector2(g.x, g.z), 0.45):
		return
	out.append({"p": g, "kind": kind, "d": _flat(origin, g)})


func _half_extent(type_id: StringName) -> float:
	if _extent.has(type_id):
		return _extent[type_id]
	var def := StructureCatalog.get_def(type_id)
	var r := 0.6
	if def:
		for box: AABB in def.get_collision_boxes():
			r = maxf(r, maxf(absf(box.position.x), absf(box.end.x)))
			r = maxf(r, maxf(absf(box.position.z), absf(box.end.z)))
	_extent[type_id] = minf(r, 8.0)
	return _extent[type_id]


## Why a spot cannot be used, or "".
func _reject(u: UnitState, p: Vector3) -> String:
	if _is_bad(u, p):
		return "could not be reached before"
	for e: Array in _covers:
		var o: UnitState = e[1]
		if o != u and o.alive and o.cover_pos.is_finite() and _flat(o.cover_pos, p) < cover_spacing_m:
			return "taken by %s" % o.unit_name
	for o: UnitState in _near(p, 1.6):
		if o == u:
			continue
		if not o.is_reacting() and o.move_state != UnitState.MoveState.MOVING and _flat(o.position, p) < 1.0:
			return "occupied by %s" % o.unit_name
	return ""


## Protection of a spot against a threat (COMBAT-COVER-03: CoverEval.judge, the same judgement the player's placement preview
## shows): {protected, low, can_fire, level, fire, partial, concealed, stand, blocker}.
func _evaluate_spot(_u: UnitState, p: Vector3, threat: Vector3, low_ok := true) -> Dictionary:
	return cover_eval.judge(p, threat, low_ok)


func _cover_score(u: UnitState, c: Dictionary, ev: Dictionary) -> float:
	var sq := sim.state.squad_of(u.id)
	var hold_fire := sq != null and sq.roe == SquadState.Roe.HOLD_FIRE
	var score := 10.0 if ev.can_fire else 7.0
	if hold_fire:
		score = 9.0 if ev.can_fire else 10.0
	# COMBAT-COVER-03: heavy cover beats light (a corner, a trunk, low cover); a suppressed soldier values it over a line of fire.
	var supp := u.suppression_at(sim.state.time) >= suppressed_at
	if int(ev.get("level", CoverEval.Level.LIGHT)) == CoverEval.Level.HEAVY:
		score += 2.5 if supp else 1.5
	if supp and ev.can_fire:
		score -= 1.5
	if not bool(ev.get("protected", true)):
		score -= 3.0
	score -= 0.35 * c.d
	match c.kind:
		"here":
			score += 2.0
		"structure", "building":
			score += 1.0
		"rock", "box":
			score += 0.5
	return score


## Can the soldier get there? With a body: a navigation path that ends at the spot and
## is not much longer than the straight line. Without: no structure footprint on the
## straight line (the abstract tier walks straight).
func _reachable(u: UnitState, p: Vector3) -> bool:
	var body := sim.body_of(u.id) as SoldierBody
	if body and body.nav:
		var map := body.nav.get_navigation_map()
		if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
			var path := NavigationServer3D.map_get_path(map, body.global_position, p, true)
			if path.is_empty() or _flat(path[path.size() - 1], p) > 1.0:
				return false
			var length := 0.0
			for i in range(1, path.size()):
				length += path[i - 1].distance_to(path[i])
			return length <= _flat(u.position, p) * 2.5 + 4.0
	if sim.structures:
		var a := Vector2(u.position.x, u.position.z)
		var b := Vector2(p.x, p.z)
		var n := maxi(1, int(a.distance_to(b)))
		for k in range(1, n):
			if sim.structures.blocks_point(a.lerp(b, float(k) / n), 0.3):
				return false
	return true


# --- Engagement ----------------------------------------------------------------------

func _engage(u: UnitState) -> void:
	if not u.alive:
		u.ai_state = UnitState.AiState.DEAD
		u.ai_reason = "dead"
		return
	if u.player_controlled:
		u.ai_state = UnitState.AiState.PLAYER
		u.ai_reason = "player in control"
		return
	var now := sim.state.time
	var def := sim.combat.weapon(u.weapon_id)
	var t := sim.state.get_unit(u.target_id)
	if t and not t.alive:
		_drop_target(u, "target down")
		t = null
	# Facing: towards the target (or its last position), else the watch direction.
	if t:
		_watch(u, t.position if u.target_visible else u.target_last_pos, 1.0)
	elif u.watch_until < now:
		u.watch_yaw = NAN
	if def == null:
		u.ai_state = UnitState.AiState.IDLE
		u.ai_reason = "unarmed"
		return
	if u.is_reloading():
		u.ai_state = UnitState.AiState.RELOADING
		u.ai_reason = "reloading"
		return
	if _support_weapons(u, t, now):
		return
	# COMBAT-01: aimed fire only at a target confirmed in sight lately (a kept "visible" answer while vegetation data fills
	# is not a sighting: the true position of an enemy nobody checked is never aimed at; 1.2 s covers the half-rate far tier).
	if t == null or not u.target_visible or now - u.target_seen_at > 1.2:
		# AI-SQUAD-01: no visible target - a fire mission (suppressive fire at a reported
		# position a squad tactic gave this soldier) may still apply.
		if u.fire_at.is_finite() and now < u.fire_until and _fire_mission(u, def, now):
			return
		if t == null:
			u.ai_state = UnitState.AiState.OBSERVING if u.watch_until >= now else UnitState.AiState.IDLE
			u.ai_reason = "no target"
			if u.mag < def.magazine_size * tactical_reload_fraction and u.reserve > 0:
				sim.combat.request_reload(u.id)
		else:
			u.ai_state = UnitState.AiState.LOST_TARGET
			u.ai_reason = "target hidden"
		return
	var dist := _flat(u.position, t.position)
	var sq := sim.state.squad_of(u.id)
	var supp := u.suppression_at(now)
	if sq and sq.roe == SquadState.Roe.HOLD_FIRE:
		# Hold fire still defends: a soldier that was just hit returns fire at a close enemy.
		if not (now - u.hit_at <= self_defence_s and dist <= self_defence_m):
			u.ai_state = UnitState.AiState.OBSERVING
			u.ai_reason = "hold fire"
			u.burst_left = 0
			return
		u.ai_reason = "self-defence"
	elif _stealth_holds(u, sq, dist, now):
		u.ai_state = UnitState.AiState.OBSERVING
		u.ai_reason = "stealth: not giving the position away"
		u.burst_left = 0
		return
	u.ai_state = UnitState.AiState.ENGAGING
	if dist > engage_reach(def):
		u.ai_reason = "out of range"
		return
	if dist > move_fire_m and Vector2(u.velocity.x, u.velocity.z).length() > 1.0 and now - u.hit_at > self_defence_s:
		move_holds += 1
		u.ai_reason = "moving: holds fire at range"
		return
	if now < u.aim_ready_at:
		u.ai_reason = "aiming"
		return
	if u.mag <= 0 and u.reserve <= 0:
		u.ai_reason = "no ammunition"
		return
	if now < u.next_shot_at:
		return
	if u.burst_left <= 0:
		if now < u.next_burst_at:
			u.ai_reason = "between bursts"
			return
		# AI-SQUAD-01: a suppressed soldier in cover keeps its head down for some bursts
		# (more likely the more suppressed, never against a target within 30 m).
		if supp > suppressed_at and u.tactic == UnitState.Tactic.IN_COVER and dist > 30.0 and _rand(u, 17) < (supp - suppressed_at) * 1.2:
			u.ai_reason = "suppressed: head down"
			u.next_burst_at = now + 0.8 + 1.2 * supp
			return
		u.burst_left = maxi(1, roundi(_burst_size(u, dist) * def.burst_mult))
	var lag := Vector3(t.velocity.x, 0.0, t.velocity.z) * track_lag_s
	var aim := Posture.aim_point(t, u.target_aim_y > 1.3) - lag
	# COMBAT-COVER-03: seen is not shootable - the weapon's line to the aim point must be free (the target's cover, a crest, the
	# ground in front of a prone soldier). The other aim point (head / torso), then standing up, else no round is wasted.
	var eye := CombatSim.eye_of(u)
	var lof := _lof(u, eye, aim, lof_slack_m)
	if not lof.clear:
		var alt := Posture.aim_point(t, not (u.target_aim_y > 1.3)) - lag
		if _lof(u, eye, alt, lof_slack_m).clear:
			aim = alt
		elif _stand_for_line(u, aim, now):
			return
		else:
			_lof_blocked(u, now, String(lof.blocker), t.id)
			return
	_lof_free(u)
	_try_fire(u, aim, dist, now, false)


## AI-SQUAD-01: suppressive fire at a position a squad tactic assigned (u.fire_at - a
## reported contact or a position the player chose, never the true position of a hidden
## enemy). The same weapon, ammunition, spread and friendly-fire rules as a normal shot.
## Returns true when it handled the soldier this frame (fired, waited or held).
func _fire_mission(u: UnitState, def: WeaponDef, now: float) -> bool:
	var sq := sim.state.squad_of(u.id)
	# QOL-01: a STEALTH squad that has not been found fires no missions either.
	if _stealth_holds(u, sq, _flat(u.position, u.fire_at), now):
		u.ai_reason = "stealth: no fire mission"
		return false
	if sq and sq.roe == SquadState.Roe.HOLD_FIRE:
		return false
	var full := float(def.magazine_size + def.reserve_start)
	var have := float(u.mag + u.reserve)
	# One magazine is always kept for self-defence; below mission_slow_ammo the fire thins out.
	if have <= def.magazine_size or have / full < mission_stop_ammo:
		u.ai_state = UnitState.AiState.OBSERVING
		u.ai_reason = "mission: ammunition kept in reserve"
		mission_holds += 1
		return true
	var dist := _flat(u.position, u.fire_at)
	if dist > engage_reach(def) or dist < 12.0:
		return false
	u.ai_state = UnitState.AiState.ENGAGING
	_watch(u, u.fire_at, 1.0)
	if now < u.next_shot_at:
		return true
	if u.burst_left <= 0:
		if now < u.next_burst_at:
			u.ai_reason = "mission: between bursts"
			return true
		var mb := rifle_mission_burst if def.role == &"rifle" else def.mission_burst
		u.burst_left = maxi(1, mb - (1 if have / full < mission_slow_ammo else 0))
	# Scatter over the area the report covers (deterministic: world seed, soldier, shot).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.state.world_seed, u.id, u.shot_counter + 1, 4177])
	var scatter := Vector3(rng.randfn(0.0, 2.5), 0.0, rng.randfn(0.0, 2.5))
	var aim := u.fire_at + scatter + Vector3.UP * 0.9
	# COMBAT-COVER-03: area fire may strike the cover round the report (that is what suppresses), never a wall, a house or a
	# hillside well short of it: the scatter point, else the report itself, else standing up, else the round is kept.
	var eye := CombatSim.eye_of(u)
	var lof := _lof(u, eye, aim, lof_mission_slack_m)
	if not lof.clear:
		var centre := u.fire_at + Vector3.UP * 0.9
		if _lof(u, eye, centre, lof_mission_slack_m).clear:
			aim = centre
		elif _stand_for_line(u, centre, now):
			return true
		else:
			_lof_blocked(u, now, String(lof.blocker), -1)
			u.ai_reason = "mission: no line of fire (%s in the way)" % _blocker_name(String(lof.blocker))
			u.burst_left = 0
			u.next_burst_at = now + 0.8
			return true
	_lof_free(u)
	if _try_fire(u, aim, dist, now, true):
		mission_shots += 1
	return true


## The part of a shot every engagement shares: aim error, the soldier's own cover, friends
## in the line of fire, the frame's shot budget, the weapon. Returns true when a round left.
func _try_fire(u: UnitState, aim: Vector3, dist: float, now: float, mission: bool) -> bool:
	var origin := CombatSim.eye_of(u)
	var ideal := (aim - origin).normalized()
	var dir := _aim_error(u, ideal, dist)
	# COMBAT-COVER-03: the aim error never puts the round into the ground right in front of the muzzle (a prone soldier's 0.36 m
	# eye, a crouched one on a slope): the ideal line clears the first metres, so the error's downward part is dropped there.
	if dir.y < ideal.y and minf(dist, ground_check_m) > 2.0:
		var near := minf(dist, ground_check_m)
		if sim.combat.line._terrain_hit(origin, origin + dir * near, near) < near and sim.combat.line._terrain_hit(origin, origin + ideal * near, near) >= near:
			dir = Vector3(dir.x, ideal.y, dir.z).normalized()
			ground_saves += 1
	# COMBAT-02: from cover, the actual shot (with its aim error) must clear the soldier's
	# own cover; otherwise wait for the next one instead of firing into the wall.
	if u.tactic != UnitState.Tactic.NONE:
		var own := sim.combat.line.trace(origin, origin + dir * 3.0, u.id, false)
		if own.blocker != "range":
			own_cover_holds += 1
			u.ai_reason = "own cover in the way"
			u.burst_left = 0
			u.next_burst_at = now + 0.3
			return false
	var tf := Time.get_ticks_usec()
	var friend_near := _friendly_near_line(u, origin, aim)
	prof.friendly += Time.get_ticks_usec() - tf
	if friend_near:
		# The shot preview (same world data and hit shapes as the real shot, without the
		# weapon spread) and a 0.5 m margin around friends for that spread.
		var p := sim.combat.preview_shot(u.id, origin, dir, u.shot_counter + 1, 0.0)
		var hit := sim.state.get_unit(p.get("hit_unit", -1))
		if (hit and hit.faction == u.faction) or _friend_on_ray(u, origin, dir, minf(dist, p.get("distance", dist))):
			friendly_holds += 1
			_lof_blocked(u, now, "friend", u.target_id)
			u.ai_reason = "friendly in line of fire"
			u.burst_left = 0
			u.next_burst_at = now + 0.4
			return false
	if _shots_left <= 0:
		budget_waits += 1
		u.ai_reason = "waiting (shot budget)"
		return false
	_shots_left -= 1
	var tfire := Time.get_ticks_usec()
	var shot := sim.combat.request_fire(u.id, origin, dir, CombatSim.Source.AI)
	prof.fire += Time.get_ticks_usec() - tfire
	if shot.get("fired", false):
		ai_shots += 1
		u.ai_reason = "mission" if mission else ""
		u.burst_left -= 1
		if u.burst_left <= 0:
			var mp := rifle_mission_pause_s if mission and sim.combat.weapon(u.weapon_id) != null and sim.combat.weapon(u.weapon_id).role == &"rifle" else mission_pause_s
			u.next_burst_at = now + (mp * (0.8 + 0.4 * _rand(u, 19)) if mission else _burst_pause(u, dist))
		return true
	u.ai_reason = shot.get("reason", "")
	u.burst_left = 0
	return false


## COMBAT-COVER-03 line-of-fire discipline. A line counts as free when nothing solid stops it more than `slack` short of the aim
## point (aimed fire: lof_slack_m - the target's own cover right in front of him; area fire: lof_mission_slack_m - the cover round
## the report is what area fire strikes). Repeated holds within lof_window_s (lof_moves_after of them) send the soldier to a nearby
## firing position (_tactics -> _start_search need_fire, sidesteps included); while his current target stays blocked, any other
## enemy he sees may replace it (_perceive).
var lof_slack_m := 1.5
var lof_mission_slack_m := 6.0
var lof_window_s := 5.0
var lof_moves_after := 3
var lof_retry_s := 12.0
var lof_holds := 0
var lof_stands := 0
## Rounds whose aim error would have struck the ground within ground_check_m of the muzzle (levelled, _try_fire).
var ground_check_m := 30.0
var ground_saves := 0
var lof_moves := 0
## unit id -> [first hold, holds, last hold, blocker, target id]
var _lof_block := {}


func _lof(u: UnitState, from: Vector3, to: Vector3, slack: float) -> Dictionary:
	var d := from.distance_to(to)
	var r := sim.combat.line.trace(from, to, u.id, false)
	return {"clear": r.blocker == "range" or float(r.distance) >= d - slack, "blocker": r.blocker, "d": r.distance}


func _lof_blocked(u: UnitState, now: float, blocker: String, target_id: int) -> void:
	lof_holds += 1
	var e: Array = _lof_block.get(u.id, [])
	if e.is_empty() or now - float(e[2]) > lof_window_s:
		e = [now, 0, now, blocker, target_id]
	e[1] = int(e[1]) + 1
	e[2] = now
	e[3] = blocker
	e[4] = target_id
	_lof_block[u.id] = e
	u.burst_left = 0
	u.next_burst_at = maxf(u.next_burst_at, now + 0.5)
	u.ai_reason = "no line of fire (%s in the way)" % _blocker_name(blocker)


func _lof_free(u: UnitState) -> void:
	if _lof_block.has(u.id):
		_lof_block.erase(u.id)


## The soldier has been holding fire for a blocked line long enough to move for it.
func lof_stuck(u: UnitState, now: float) -> bool:
	var e: Array = _lof_block.get(u.id, [])
	return not e.is_empty() and int(e[1]) >= lof_moves_after and now - float(e[2]) < 2.0 and now - float(e[0]) >= 1.0


## His current target is the one his line keeps being blocked to.
func _lof_blocked_on(u: UnitState, target_id: int, now: float) -> bool:
	var e: Array = _lof_block.get(u.id, [])
	return not e.is_empty() and int(e[4]) == target_id and int(e[1]) >= 2 and now - float(e[2]) < lof_window_s


static func _blocker_name(b: String) -> String:
	match b:
		"structure":
			return "a structure"
		"terrain":
			return "the ground"
		"tree":
			return "a solid"
		"friend":
			return "a friend"
	return b


## Crouched or prone behind something his standing eye clears: he stands to fire (held longer than a normal choice, so he does not
## bob up and down every burst). Not while suppressed, not while the posture is changing anyway.
func _stand_for_line(u: UnitState, aim: Vector3, now: float) -> bool:
	if u.posture == Posture.STAND or Posture.busy(u, now) or u.suppression_at(now) >= suppressed_at:
		return false
	var se := u.position + Vector3.UP * Posture.EYE[Posture.STAND].y
	if not _lof(u, se, aim, lof_slack_m).clear:
		return false
	if Posture.request(u, Posture.STAND, now):
		lof_stands += 1
		posture_changes += 1
		u.posture_hold_until = now + posture_hold_s * 2.0
		u.ai_reason = "stands to fire over cover"
		return true
	return false


## Bursts: long at close range, short at medium range, single aimed shots far away.
func _burst_size(u: UnitState, dist: float) -> int:
	var r := _rand(u, 11)
	if dist < 40.0:
		return 4 + int(r * 3.0)
	if dist < 120.0:
		return 2 + int(r * 3.0)
	if dist < 250.0:
		return 1 + int(r * 2.0)
	return 1


func _burst_pause(u: UnitState, dist: float) -> float:
	return (0.25 + dist / 250.0 + _rand(u, 13) * 0.35) * (1.0 + 1.5 * u.suppression_at(sim.state.time))


## GAMEPLAY-04C: how rough the aim still is (aim_first_mult on a fresh target, 1 when settled): time on the target since it
## was acquired or the soldier last moved, against the weapon's aim time scaled by proficiency. Computed when a shot is aimed;
## no per-frame state beyond UnitState.aim_since / moved_at.
func aim_settle_mult(u: UnitState, wdef: WeaponDef) -> float:
	if not aim_model:
		return 1.0
	var t_aim := (wdef.aim_time_s if wdef and wdef.aim_time_s > 0.0 else aim_time_default_s) * lerpf(1.4, 0.6, clampf(u.proficiency, 0.0, 1.0))
	var since := maxf(u.aim_since, u.moved_at)
	var k := clampf((sim.state.time - since) / maxf(t_aim, 0.05), 0.0, 1.0)
	return lerpf(aim_first_mult, aim_settled_mult, k) * (float(weapon_aim.get(wdef.id, wdef.aim_mult)) if wdef else 1.0)


## GAMEPLAY-04C: aim error of a soldier against a trained one (proficiency 0.5 -> 1.0; a recruit 0 -> 1.35, a veteran 1 -> 0.65).
func proficiency_mult(u: UnitState) -> float:
	return 1.35 - 0.7 * clampf(u.proficiency, 0.0, 1.0) if aim_model else 1.0


## The distance a soldier engages at with its weapon (WeaponDef.ai_engage_m, else engage_range).
func engage_reach(def: WeaponDef) -> float:
	return def.ai_engage_m if aim_model and def and def.ai_engage_m > 0.0 else engage_range


## How far a soldier notices enemies: a magnified optic (WeaponDef.optic_sight_m) beyond the plain sight range.
func sight_of(u: UnitState) -> float:
	var def := sim.combat.weapon(u.weapon_id)
	return maxf(sight_range, def.optic_sight_m) if def and aim_model else sight_range


## The direction the soldier actually holds: the ideal one plus a seeded aim error that
## grows with distance and while walking (the weapon's spread is added by CombatSim).
func _aim_error(u: UnitState, dir: Vector3, dist: float) -> Vector3:
	var speed := Vector2(u.velocity.x, u.velocity.z).length()
	# GAMEPLAY-02B: the weapon's handling - a braced machine gun holds tighter, the same gun on the move much worse.
	var wdef := sim.combat.weapon(u.weapon_id)
	var settle := sim.combat.settle_factor(u, wdef) if wdef else 1.0
	var sigma := (aim_error_base_deg + aim_error_per_100m_deg * dist / 100.0) * lerpf(1.0, settle, 0.5) \
			+ aim_error_moving_deg * clampf(speed / 4.5, 0.0, 1.0) * (wdef.moving_aim_mult if wdef else 1.0)
	# GAMEPLAY-04C: a fresh aim is rougher and settles with time on the target; a better soldier aims tighter and settles sooner.
	sigma *= aim_settle_mult(u, wdef) * proficiency_mult(u) * _diff(u, "aim")
	sigma *= 1.0 + suppression_aim_mult * u.suppression_at(sim.state.time)
	# COMBAT-01: crouched a little steadier, prone much steadier.
	sigma *= Posture.steady(u)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.state.world_seed, u.id, u.shot_counter + 1, 977])
	var ex := deg_to_rad(rng.randfn(0.0, sigma))
	var ey := deg_to_rad(rng.randfn(0.0, sigma))
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		return dir
	side = side.normalized()
	var up := side.cross(dir).normalized()
	return (dir + side * tan(ex) + up * tan(ey)).normalized()


# --- Grenades and the anti-structure launcher (GAMEPLAY-02C) ---------------------------------------------------------------
# The same individual layer as the rifle: what this soldier knows (its target, the last place it saw it, the squad's fire
# mission point), never where a hidden enemy really is. A few cheap conditions, a rate limit per soldier and per squad.

var grenade_min_m := 11.0
var grenade_max_m := 30.0
var grenade_squad_gap_s := 7.0
var grenade_soldier_gap_s := 14.0
var launcher_min_m := 35.0
var launcher_max_m := 260.0
var launcher_squad_gap_s := 12.0
## GAMEPLAY-03D: shouldering the launcher before the shot, holding it after (the rifle is away meanwhile).
var launcher_raise_s := 0.8
var launcher_lower_s := 2.5
## GAMEPLAY-03D: "grenade!" takes a moment to notice (seeded per soldier and grenade, longer when suppressed); a soldier
## who cannot get clear before the burst (or is pinned) gets down where he is instead of running into the open.
var grenade_notice_s := Vector2(0.5, 1.5)
var grenade_told_s := Vector2(0.2, 0.5)
var grenade_downs := 0
var _nade_react: Array = []
var grenades_thrown := 0
var grenade_dodges := 0
var grenade_holds := 0
var rockets_fired := 0
var _squad_nade_at := {}
var _squad_rocket_at := {}
var _rocket_check := {}
var _nade_check := {}
## Why a launcher was not fired (reason -> count), for tests and the report.
var rocket_holds := {}


func _rocket_hold(why: String) -> void:
	rocket_holds[why] = int(rocket_holds.get(why, 0)) + 1


## Throws a grenade or fires the launcher when the situation calls for it; true when it did (this update is spent).
func _support_weapons(u: UnitState, t: UnitState, now: float) -> bool:
	if u.grenades <= 0 and (u.sec_id == &"" or u.sec_ammo <= 0):
		return false
	var sq := sim.state.squad_of(u.id)
	if sq and sq.roe == SquadState.Roe.HOLD_FIRE:
		return false
	if t and _stealth_holds(u, sq, _flat(u.position, t.position), now):
		return false
	if u.suppression_at(now) >= 0.85:
		return false
	# What the soldier knows of the enemy: the target it sees, or where it saw it last (a few seconds ago).
	var known := Vector3.INF
	var seen := false
	if t and t.alive:
		if u.target_visible and now - u.target_seen_at <= 1.2:
			known = u.target_last_pos   # COMBAT-01: where it was seen (written at the sighting)
			seen = true
		elif u.target_last_pos.is_finite() and now - u.target_seen_at < 8.0:
			known = u.target_last_pos
	if u.grenades > 0 and known.is_finite() and now - u.nade_at >= grenade_soldier_gap_s and now >= float(_squad_nade_at.get(sq.id if sq else -1, -INF)) \
			and now >= float(_nade_check.get(u.id, -INF)):
		_nade_check[u.id] = now + 1.0  # considered at most once a second per soldier
		var d := _flat(u.position, known)
		# Into cover: an enemy that went out of sight, one in a position or behind cover, or two together.
		var worth := not seen or (t.tactic == UnitState.Tactic.IN_COVER) or t.fort_slot != "" or _group_near(t, 6.0) >= 2
		if d >= grenade_min_m and d <= grenade_max_m and worth:
			# No friend in the blast, nor one that could walk into it before it bursts (the fuse) or is on its way there.
			if _friend_near(u, known, 14.0) or _friend_heading(u, known, 11.0):
				grenade_holds += 1
			else:
				var res := sim.combat.throw_grenade(u.id, known)
				if res.ok:
					grenades_thrown += 1
					_squad_nade_at[sq.id if sq else -1] = now + grenade_squad_gap_s
					_event(u, "grenade at %.0f m" % d)
					return true
	var sdef := sim.combat.weapon(u.sec_id) if u.sec_id != &"" else null
	if sdef and sdef.role == &"gl":
		return _grenade_launcher(u, t, sdef, known, seen, sq, now)
	if u.sec_id != &"" and u.sec_ammo > 0 and now >= u.sec_ready_at and now >= float(_squad_rocket_at.get(sq.id if sq else -1, -INF)) \
			and now >= float(_rocket_check.get(u.id, -INF)):
		_rocket_check[u.id] = now + 2.0  # the structure query at most every two seconds per soldier
		var aim_at := known
		if not aim_at.is_finite() and u.fire_at.is_finite() and now < u.fire_until:
			aim_at = u.fire_at  # the squad's fire mission: a reported position
		if aim_at.is_finite():
			# The position the seen enemy fights from, else an enemy structure at the point it knows.
			var st: StructureState = null
			if t and t.alive and t.fort_slot != "" and (seen or now - u.target_seen_at < 8.0):
				st = sim.state.construction.get_structure(int(t.fort_slot.split(":")[0]))
				if st and (st.faction == u.faction or st.health() <= 0.0):
					st = null
			if st == null:
				st = _enemy_structure_at(u, aim_at)
			if st == null:
				_rocket_hold("no enemy structure where the enemy is")
			elif now - u.moved_at < 1.0:
				_rocket_hold("moving")
			# A shoulder-fired rocket is fired standing still (a moving soldier waits), at the middle of the structure's body.
			if st and now - u.moved_at >= 1.0:
				var origin := CombatSim.eye_of(u)
				var aim := _structure_aim(st)
				var d := _flat(u.position, aim)
				if d < launcher_min_m or d > maxf(launcher_max_m, sdef.effective_range if sdef else 0.0):
					_rocket_hold("range")
				elif _friendly_near_line(u, origin, aim):
					_rocket_hold("friend in the line")
				else:
					# A clear line to it, with room to the sides for the launcher's spread (a trunk that just misses the line of
					# sight catches a rocket that strays).
					var look := sim.combat.line.trace(origin, aim, u.id, false)
					# (structure_id stays set when something nearer - a tree - blocks: the blocker decides.)
					var clear: bool = look.blocker == "structure" and int(look.structure_id) == st.id
					var side := Vector3(-(aim - origin).z, 0.0, (aim - origin).x).normalized() * 0.4
					for off: Vector3 in [side, -side]:
						if not clear:
							break
						var edge := sim.combat.line.trace(origin, aim + off, u.id, false)
						clear = (edge.blocker == "structure" and int(edge.structure_id) == st.id) or edge.blocker == "range"
					if not clear:
						_rocket_hold("no clear line")
					elif u.sec_raised_at < 0.0 or now - u.sec_raised_at > launcher_raise_s + 4.0:
						# GAMEPLAY-03D: the rifle goes away and the launcher comes up first (the update is spent on it).
						u.sec_raised_at = now
						_rocket_hold("raising the launcher")
						return true
					elif now - u.sec_raised_at < launcher_raise_s:
						_rocket_hold("raising the launcher")
						return true
					else:
						# Aimed and braced: the launcher's own spread (WeaponDef) is the error, as for the player.
						var res := sim.combat.fire_secondary(u.id, origin, (aim - origin).normalized(), CombatSim.Source.AI)
						if res.get("fired", false):
							u.sec_raised_at = -1.0
							u.sec_shown_until = now + launcher_lower_s
							rockets_fired += 1
							_squad_rocket_at[sq.id if sq else -1] = now + launcher_squad_gap_s
							_event(u, "launcher at %s %.0f m" % [st.type_id, d])
							return true
	return false


## GAMEPLAY-04C: the 40 mm grenade launcher - explosive rounds at enemies the soldier saw or saw a moment ago, gl_min_m to
## gl_max_m away, where they are worth a round: in cover or a position, or two together; never with a friend within
## gl_friend_m of the impact or near the line; one round per squad per gl_squad_gap_s, the last rounds kept for positions and
## groups. The round comes down at the aimed distance (CombatSim.fire_secondary). True when it fired (the update is spent).
var gl_min_m := 40.0
var gl_max_m := 300.0
var gl_friend_m := 18.0
var gl_squad_gap_s := 6.0
var gl_fired := 0
var gl_holds := {}
var _squad_gl_at := {}


func _grenade_launcher(u: UnitState, t: UnitState, sdef: WeaponDef, known: Vector3, seen: bool, sq: SquadState, now: float) -> bool:
	if u.sec_ammo <= 0 or now < u.sec_ready_at or not known.is_finite() or now < float(_squad_gl_at.get(sq.id if sq else -1, -INF)):
		return false
	if now < float(_rocket_check.get(u.id, -INF)):
		return false
	_rocket_check[u.id] = now + 1.0
	var d := _flat(u.position, known)
	var hold := ""
	var group := _group_near(t, 6.0) if t and t.alive else 1
	var worth := not seen or (t and (t.tactic == UnitState.Tactic.IN_COVER or t.fort_slot != "")) or group >= 2
	if u.sec_ammo <= 2 and not (group >= 2 or (t and t.fort_slot != "")):
		hold = "last rounds kept"
	elif d < gl_min_m or d > minf(gl_max_m, sdef.effective_range):
		hold = "range"
	elif not worth:
		hold = "a lone enemy in the open"
	elif _friend_near(u, known, gl_friend_m) or _friend_heading(u, known, gl_friend_m * 0.7):
		hold = "friend near the impact"
	elif now - u.moved_at < 0.8:
		hold = "moving"
	var origin := CombatSim.eye_of(u)
	var aim := known + Vector3.UP * 0.6
	if hold == "" and _friendly_near_line(u, origin, aim):
		hold = "friend in the line"
	if hold != "":
		gl_holds[hold] = int(gl_holds.get(hold, 0)) + 1
		return false
	var res := sim.combat.fire_secondary(u.id, origin, (aim - origin).normalized(), CombatSim.Source.AI, origin.distance_to(aim))
	if res.get("fired", false):
		gl_fired += 1
		_squad_gl_at[sq.id if sq else -1] = now + gl_squad_gap_s
		u.sec_shown_until = now + launcher_lower_s
		_event(u, "40 mm at %.0f m" % d)
		return true
	return false


## Where a rocket is aimed: inside the largest collision box standing on the ground (a parapet or a wall, not a roof - a
## point between them is a firing slit the rocket would fly through), at most 1 m up.
func _structure_aim(st: StructureState) -> Vector3:
	var def := StructureCatalog.get_def(st.type_id)
	var xf: Transform3D = st.instances[0] if not st.instances.is_empty() else Transform3D(Basis(), st.position)
	var best := AABB()
	if def:
		for b: AABB in def.get_collision_boxes():
			if b.position.y < 0.4 and b.get_volume() > best.get_volume():
				best = b
	if best.get_volume() <= 0.0:
		return st.position + Vector3.UP * 0.8
	var c := best.get_center()
	c.y = best.position.y + minf(best.size.y * 0.7, 1.0)
	return xf * c


## GAMEPLAY-02D: "grenade!" - soldiers near where a grenade lands get away from it before it bursts: the thrower's own
## friends (they were told), and anybody who sees it land (within 20 m with a clear line) or has it at their feet. A soldier
## in a fortification slot stays down in it (the walls shield it). The run is an ordinary reaction (react_target), so the
## squad's order resumes afterwards.
func _on_explosive(e: Dictionary) -> void:
	if not enabled or not tactics_enabled or String(e.def) != "grenade":
		return
	var def := sim.combat.weapon(&"grenade")
	var at: Vector3 = e.at
	var r := def.blast_radius if def else 9.0
	var now := sim.state.time
	for u: UnitState in units_near(at, r + 1.0):
		if not u.alive or u.player_controlled or u.kind != UnitState.Kind.SOLDIER or u.fort_slot != "" or u.vehicle_id >= 0:
			continue
		var d := _flat(u.position, at)
		var told := u.faction == int(e.f)
		var knows := told or d <= 4.0
		if not knows and d <= 20.0:
			knows = sim.combat.line.trace(CombatSim.eye_of(u), at + Vector3.UP * 0.2, u.id, false).blocker == "range"
		if not knows:
			continue
		# GAMEPLAY-03D: noticing takes a moment (the thrower's friends were told, the others see it land), more under fire.
		var span := grenade_told_s if told else grenade_notice_s
		var h := fposmod(sin(float(u.id) * 12.9898 + float(e.id) * 78.233) * 43758.5453, 1.0)
		var delay := lerpf(span.x, span.y, h) * (1.0 + u.suppression_at(now))
		_nade_react.append({"u": u.id, "at": at, "t": now + delay, "burst": float(e.t)})


## The delayed "grenade!" reactions whose moment has come: get clear if there is time, else get down where he is.
func _grenade_reactions(now: float) -> void:
	if _nade_react.is_empty():
		return
	var def := sim.combat.weapon(&"grenade")
	var r := def.blast_radius if def else 9.0
	var keep: Array = []
	for q: Dictionary in _nade_react:
		if now < float(q.t):
			keep.append(q)
			continue
		var u := sim.state.get_unit(int(q.u))
		if u == null or not u.alive or u.player_controlled or u.fort_slot != "" or u.vehicle_id >= 0 or now >= float(q.burst):
			continue
		var at: Vector3 = q.at
		var d := _flat(u.position, at)
		if d > r + 1.0:
			continue
		# Pinned, or no time to run out of the blast (a soldier covers about 80 % of his speed from a standstill): down.
		var reach := u.speed * 0.8 * (float(q.burst) - now)
		if u.suppression_at(now) >= pinned_at or reach < r + 1.0 - d:
			# Down where he is (the "staying here" reaction): no walking on along his order until the burst has passed.
			u.react_target = u.position
			u.react_state = UnitState.ReactState.ARRIVED
			u.react_until = float(q.burst) + 1.5
			u.down_until = float(q.burst) + 0.5
			# COMBAT-01: down is the prone posture (the burst finds him lower).
			Posture.request(u, Posture.PRONE, now)
			u.posture_hold_until = u.down_until + 1.0
			u.tactic = UnitState.Tactic.IN_COVER
			u.tactic_since = now
			u.cover_note = "grenade! %.0f m away: no time to get clear, down" % d if u.suppression_at(now) < pinned_at else "grenade! pinned: stays down"
			grenade_downs += 1
			_event(u, u.cover_note)
			continue
		var away := Vector3(u.position.x - at.x, 0.0, u.position.z - at.z)
		away = away.normalized() if away.length() > 0.2 else Vector3(1, 0, 0).rotated(Vector3.UP, float(u.id))
		var to := sim.tactics.pos.nearest_valid(at + away * (r + 3.0), 5.0) if sim.tactics else Vector3.INF
		if not to.is_finite():
			continue
		u.react_target = to
		u.react_state = UnitState.ReactState.MOVING
		Posture.for_move(u, _flat(u.position, to), now)
		u.react_until = now + 5.0
		u.tactic = UnitState.Tactic.SEEK_COVER
		u.tactic_since = now
		u.cover_note = "grenade! %.0f m away: getting clear" % d
		grenade_dodges += 1
		_event(u, u.cover_note)
	_nade_react = keep


## A living friend (not u) walking to a point within r of p (an assault moving onto the landing spot).
func _friend_heading(u: UnitState, p: Vector3, r: float) -> bool:
	for f: UnitState in units_near(p, 40.0):
		if f != u and f.alive and f.faction == u.faction and f.order == UnitState.Order.MOVE and f.move_state == UnitState.MoveState.MOVING \
				and _flat(f.order_target, p) <= r:
			return true
	return false


## A living friend (not u) within r of p.
func _friend_near(u: UnitState, p: Vector3, r: float) -> bool:
	for f: UnitState in units_near(p, r):
		if f != u and f.alive and f.faction == u.faction:
			return true
	return false


## A standing enemy (owned by another faction) structure the enemy u knows of uses: within 6 m of the point.
func _enemy_structure_at(u: UnitState, p: Vector3) -> StructureState:
	var best: StructureState = null
	var best_d := INF
	for hit: Dictionary in sim.combat.line.structures_near(p, 6.0):
		var st := sim.state.construction.get_structure(int(hit.id))
		if st == null or st.faction < 0 or st.faction == u.faction or st.is_site() or st.health() <= 0.0:
			continue
		# Fortifications (firing positions) first, then the nearest.
		var d := float(hit.d) - (10.0 if DefenceDefs.has(st.type_id) else 0.0)
		if d < best_d:
			best_d = d
			best = st
	return best


## Cheap pre-check before the shot preview: a living friend close to the line in front.
func _friendly_near_line(u: UnitState, origin: Vector3, aim: Vector3) -> bool:
	for f: UnitState in units_near_segment(Vector2(origin.x, origin.z), Vector2(aim.x, aim.z), 1.5):
		if f != u and f.faction == u.faction:
			return true
	return false


## A living friend whose body axis passes within friendly_margin_m of the ray before
## max_d (the spread can still carry a shot that the preview passed by a hair).
func _friend_on_ray(u: UnitState, origin: Vector3, dir: Vector3, max_d: float) -> bool:
	var end := origin + dir * max_d
	for f: UnitState in units_near_segment(Vector2(origin.x, origin.z), Vector2(end.x, end.z), friendly_margin_m + LineOfFire.TORSO_R + 0.1):
		if f == u or f.faction != u.faction:
			continue
		var ax := Posture.span(f)
		var pts := Geometry3D.get_closest_points_between_segments(origin, end, ax[0], ax[1])
		if pts[0].distance_to(pts[1]) < friendly_margin_m + LineOfFire.TORSO_R:
			return true
	return false


func _rand(u: UnitState, salt: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.state.world_seed, u.id, u.shot_counter, salt])
	return rng.randf()


func _event(u: UnitState, text: String) -> void:
	var e := {"t": snappedf(sim.state.time, 0.01), "unit": u.unit_name, "text": text}
	events.append(e)
	if events.size() > MAX_EVENTS:
		events.pop_front()
	if log_events:
		print("BRAIN %.2f %s %s" % [e.t, u.unit_name, text])


## Summary for the HUD and tests.
func summary() -> Dictionary:
	var states := {}
	var tactics := {}
	for u: UnitState in sim.state.units.values():
		if u.kind == UnitState.Kind.SOLDIER:
			var k := u.ai_state_name()
			states[k] = states.get(k, 0) + 1
			if u.alive and u.tactic != UnitState.Tactic.NONE:
				tactics[u.tactic_name()] = tactics.get(u.tactic_name(), 0) + 1
	return {"states": states, "tactics": tactics, "sight_checks": sight_checks, "ai_shots": ai_shots, "acquisitions": acquisitions,
		"switches": target_switches, "dropped": dropped_targets, "friendly_holds": friendly_holds, "own_cover_holds": own_cover_holds,
		"cover": {"searches": cover_searches, "evaluations": cover_evals, "found": cover_found, "none": cover_none, "unreachable": cover_unreachable},
		"warm": {"cells": warm_cells, "waits": warm_waits, "queued": _warm_queue.size()}, "shot_budget_waits": budget_waits,
		"update_us_avg": snappedf(float(update_usec) / maxi(frames, 1), 0.1), "update_us_max": update_usec_max,
		"sight_us_avg": snappedf(float(sight_usec) / maxi(sight_checks, 1), 0.1),
		"sight_checks_per_frame": snappedf(float(sight_checks) / maxi(frames, 1), 0.01),
		"prof_us_per_frame": _prof_per_frame(), "prof_us_max": prof_max.duplicate(),
		"line_cells": {"loads": sim.combat.line.cell_loads, "load_us_max": sim.combat.line.cell_load_usec_max,
			"load_us_avg": snappedf(float(sim.combat.line.cell_load_usec) / maxi(sim.combat.line.cell_loads, 1), 0.1)}}


func _prof_per_frame() -> Dictionary:
	var out := {}
	for k in prof:
		out[k] = snappedf(float(prof[k]) / maxi(frames, 1), 0.1)
	return out


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
