## Shot presentation (COMBAT-01a): muzzle flash, tracer, impact, sound. No authority -
## it only listens to WorldState.shot_fired / reload_started and draws what the active
## camera can see. Shots farther than fx_radius from the camera produce nothing, so
## distant and abstract fights cost no effects. All nodes come from small pools.
##
## COMBAT-01: recorded-style sounds (assets/audio/combat, tools/audio/make_combat_sounds.py) chosen by weapon and by the
## listener's distance - the close report with its action and echoes, the distant "pop and roll" beyond it - and heard
## after the light (sound travels SOUND_MS). A round passing the first-person camera cracks (and whizzes very close) where
## it passed, so the player hears where the fire comes from; impacts look and sound like what they hit (earth, wood,
## metal, stone, flesh). Muzzle flashes are star-shaped, brief, and grow with the camera distance so a distant firefight
## reads as flickers (flash_radius) without drawing every round; a little smoke lingers at close range. Hits make the
## soldier flinch (InfantryCharacter.flinch). Nothing here touches the camera or the player's aim.
class_name CombatFX
extends Node3D

@export var fx_radius := 450.0
@export var sound_radius := 1400.0
@export var pool_size := 24
## Distant muzzle flashes (no tracer, impact or light) out to this far from the camera.
@export var flash_radius := 1300.0
## The close report up to close_m, the distant one from far_m (both between); the action is heard within mech_m.
@export var close_m := 160.0
@export var far_m := 90.0
## A round passing the first-person camera within crack_m cracks (supersonic, from shooters farther than 25 m); within
## whiz_m it also whizzes.
@export var crack_m := 6.0
@export var whiz_m := 1.4
const SOUND_MS := 343.0
const AUDIO_DIR := "res://assets/audio/combat/"

var sim: WorldSim
var game: GameController

var _reload_stream: AudioStream
var _tick_stream: AudioStream
var _kill_stream: AudioStream
var _launch_stream: AudioStream
## name -> Array of streams (variants)
var _snd := {}
## GAMEPLAY-02C: thrown grenades / rockets on their way (node -> explosive entry) and the burst effects.
var _flying := {}
var _grenade_scene: PackedScene
var _bursts: Array[Node3D] = []
var explosions_shown := 0
var _tracers: Array[MeshInstance3D] = []
var _flashes: Array[Node3D] = []
var _impacts: Array[Node3D] = []
var _smokes: Array[CPUParticles3D] = []
var _players: Array[AudioStreamPlayer3D] = []
var _near_players: Array[AudioStreamPlayer3D] = []
var _ui_player: AudioStreamPlayer
var _ui_reload: AudioStreamPlayer
var _next := {"tracer": 0, "flash": 0, "impact": 0, "player": 0, "near": 0, "smoke": 0}
var _life := {}
## Sounds waiting for their travel time: [play_at_msec, stream, position, db, pitch].
var _delayed: Array = []
var _smoke_at := {}
## Counters for tests and the HUD.
var shown := 0
var skipped_far := 0
var far_flashes := 0
var cracks := 0
var flinches := 0


func setup(p_sim: WorldSim, p_game: GameController) -> void:
	sim = p_sim
	game = p_game
	sim.state.shot_fired.connect(_on_shot)
	sim.state.reload_started.connect(_on_reload)
	sim.state.explosive_launched.connect(_on_launched)
	sim.state.exploded.connect(_on_exploded)
	sim.state.unit_damaged.connect(_on_damaged)
	_launch_stream = CombatAudio.launch()
	if ResourceLoader.exists("res://assets/characters/infantry/weapons/grenade.glb"):
		_grenade_scene = load("res://assets/characters/infantry/weapons/grenade.glb")
	_reload_stream = CombatAudio.reload_sound()
	_tick_stream = CombatAudio.hit_tick(false)
	_kill_stream = CombatAudio.hit_tick(true)
	_load_sounds()
	_build_pools()


## The sound files (variants name_0, name_1 ...); a missing set falls back to the COMBAT-01a synthesised placeholder.
func _load_sounds() -> void:
	var names := ["report_rifle", "report_dmr", "report_lmg", "report_gpmg", "far_light", "far_heavy", "crack", "whiz",
		"impact_dirt", "impact_wood", "impact_metal", "impact_stone", "impact_flesh"]
	for n in names:
		var list: Array = []
		for v in 6:
			var p: String = "%s%s_%d.wav" % [AUDIO_DIR, n, v]
			if ResourceLoader.exists(p):
				list.append(load(p))
		_snd[n] = list
	for n in ["boom_close", "boom_far"]:
		var p: String = AUDIO_DIR + String(n) + ".wav"
		_snd[n] = [load(p)] if ResourceLoader.exists(p) else [CombatAudio.explosion()]
	for n in ["report_rifle", "report_dmr", "report_lmg", "report_gpmg", "far_light", "far_heavy"]:
		if (_snd[n] as Array).is_empty():
			_snd[n] = [CombatAudio.gunshot()]


func _pick(name: String) -> AudioStream:
	var list: Array = _snd.get(name, [])
	return list[randi() % list.size()] if not list.is_empty() else null


func _build_pools() -> void:
	var tracer_mat := StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.albedo_color = Color(1.0, 0.85, 0.45)
	tracer_mat.emission_enabled = true
	tracer_mat.emission = Color(1.0, 0.7, 0.3) * 3.0
	tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var star := StandardMaterial3D.new()
	star.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star.albedo_texture = _flash_texture(false)
	star.albedo_color = Color(1.0, 0.82, 0.5)
	star.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	star.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star.cull_mode = BaseMaterial3D.CULL_DISABLED
	star.no_depth_test = false
	var flame := star.duplicate() as StandardMaterial3D
	flame.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	flame.albedo_texture = _flash_texture(true)
	for i in pool_size:
		var t := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, 1.0)
		t.mesh = bm
		t.material_override = tracer_mat
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		t.top_level = true
		add_child(t)
		_tracers.append(t)
		# Muzzle flash: a star facing the camera, two crossed flame quads along the bore, a light only up close.
		var f := Node3D.new()
		f.top_level = true
		f.visible = false
		var s := MeshInstance3D.new()
		s.name = "Star"
		var q := QuadMesh.new()
		q.size = Vector2(0.42, 0.42)
		s.mesh = q
		s.material_override = star
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_child(s)
		for k in 2:
			var fl := MeshInstance3D.new()
			fl.name = "Flame%d" % k
			var fq := QuadMesh.new()
			fq.size = Vector2(0.16, 0.42)
			fq.center_offset = Vector3(0, 0.18, 0)
			fl.mesh = fq
			fl.material_override = flame
			fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fl.rotation = Vector3(-PI * 0.5, 0.0, k * PI * 0.5)
			f.add_child(fl)
		var light := OmniLight3D.new()
		light.name = "Light"
		light.light_color = Color(1.0, 0.75, 0.4)
		light.light_energy = 2.5
		light.omni_range = 4.0
		light.shadow_enabled = false
		f.add_child(light)
		add_child(f)
		_flashes.append(f)
		_impacts.append(_impact_node())
	for i in 10:
		var sm := _particles(5, 1.6, Color(0.72, 0.7, 0.66, 0.28), 0.5, 0.25, 0.9, false, true)
		sm.gravity = Vector3(0, 0.25, 0)
		sm.explosiveness = 0.9
		sm.spread = 25.0
		sm.top_level = true
		add_child(sm)
		_smokes.append(sm)
	for i in 28:
		var ap := AudioStreamPlayer3D.new()
		ap.max_distance = sound_radius
		ap.unit_size = 14.0
		ap.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		ap.attenuation_filter_cutoff_hz = 6000.0
		ap.attenuation_filter_db = -18.0
		ap.top_level = true
		add_child(ap)
		_players.append(ap)
	for i in 8:
		var ap := AudioStreamPlayer3D.new()
		ap.max_distance = 60.0
		ap.unit_size = 4.0
		ap.top_level = true
		add_child(ap)
		_near_players.append(ap)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.volume_db = -4.0
	_ui_player.max_polyphony = 6
	add_child(_ui_player)
	_ui_reload = AudioStreamPlayer.new()
	add_child(_ui_reload)


## One pooled impact: chunks (earth, splinters, chips, sparks, blood) and a soft puff.
func _impact_node() -> Node3D:
	var n := Node3D.new()
	n.top_level = true
	var chunks := CPUParticles3D.new()
	chunks.name = "Chunks"
	chunks.emitting = false
	chunks.one_shot = true
	chunks.amount = 10
	chunks.lifetime = 0.45
	chunks.explosiveness = 1.0
	chunks.direction = Vector3.UP
	chunks.spread = 50.0
	chunks.initial_velocity_min = 1.0
	chunks.initial_velocity_max = 3.0
	chunks.gravity = Vector3(0, -6, 0)
	chunks.scale_amount_min = 0.05
	chunks.scale_amount_max = 0.12
	var pm := SphereMesh.new()
	pm.radius = 0.5
	pm.height = 1.0
	pm.radial_segments = 6
	pm.rings = 3
	chunks.mesh = pm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.45, 0.4, 0.33)
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chunks.material_override = cm
	n.add_child(chunks)
	var puff := _particles(4, 0.7, Color(0.55, 0.5, 0.42, 0.5), 1.2, 0.25, 0.7, false, true)
	puff.name = "Puff"
	puff.gravity = Vector3(0, 0.2, 0)
	n.add_child(puff)
	add_child(n)
	return n


func _process(delta: float) -> void:
	_move_flying()
	for n in _life.keys():
		_life[n] -= delta
		if _life[n] <= 0.0:
			(n as Node3D).visible = false
			_life.erase(n)
	if not _delayed.is_empty():
		var now := Time.get_ticks_msec()
		var keep: Array = []
		for d: Array in _delayed:
			if now >= int(d[0]):
				_play3d(d[1], d[2], d[3], d[4])
			else:
				keep.append(d)
		_delayed = keep


func _camera_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.INF


## Which sound set a weapon fires with.
func _profile(def: WeaponDef) -> String:
	if def == null:
		return "rifle"
	match def.id:
		&"dmr":
			return "dmr"
		&"gpmg":
			return "gpmg"
		&"lmg":
			return "lmg"
	return "gpmg" if def.role == &"lmg" and def.damage >= 40.0 else ("lmg" if def.role == &"lmg" else "rifle")


func _on_shot(shot: Dictionary) -> void:
	var cam := _camera_pos()
	var origin: Vector3 = shot.origin
	var end: Vector3 = shot.end
	var own: bool = game != null and game.mode == GameController.Mode.FPS and shot.shooter == game.possessed_id
	var su := sim.state.get_unit(shot.shooter)
	var wdef := sim.combat.weapon(su.weapon_id) if su else null
	var prof := _profile(wdef)
	var heavy := prof == "gpmg" or prof == "dmr"
	var d_cam := cam.distance_to(origin) if cam.is_finite() else INF
	if not own:
		_report(origin, d_cam, prof, heavy)
		_near_miss(shot, cam)
	var near := own or (cam.is_finite() and (d_cam < fx_radius or cam.distance_to(end) < fx_radius))
	if not near:
		skipped_far += 1
		if d_cam < flash_radius:
			# A distant firefight reads as muzzle flickers (no tracer, impact or light).
			far_flashes += 1
			_flash(origin, d_cam, (1.5 if prof == "lmg" or prof == "gpmg" else 1.0), Vector3.ZERO)
		return
	shown += 1
	var muzzle := _muzzle_of(shot.shooter, origin)
	var mg := prof == "lmg" or prof == "gpmg"
	_flash(muzzle, cam.distance_to(muzzle) if cam.is_finite() else 0.0, (0.6 if own else 1.0) * (1.4 if mg else (1.15 if heavy else 1.0)),
		shot.dir if shot.has("dir") else Vector3.ZERO)
	if not own:
		_smoke(muzzle, shot.shooter, d_cam, mg)
	# Every round leaves a faint streak; a machine gun's every third is a bright tracer.
	_tracer(muzzle, end, mg and int(shot.get("counter", 0)) % 3 == 0)
	# (no strike drawn on the possessed soldier himself: the camera is inside him; the HUD says he was hit)
	var on_me: bool = game != null and game.mode == GameController.Mode.FPS and int(shot.get("hit_unit", -1)) == game.possessed_id
	if shot.blocker != "range" and not on_me:
		var mat := _material(shot)
		var close_to_cam := cam.is_finite() and cam.distance_to(end) < 12.0
		_impact(end, mat, close_to_cam, shot.dir if shot.has("dir") else Vector3.DOWN)
		if cam.is_finite() and cam.distance_to(end) < 120.0:
			_play3d(_pick("impact_" + mat), end, -4.0 if mat != "flesh" else -8.0, randf_range(0.9, 1.1))
	if own:
		_ui_player.stream = _pick("report_" + prof)
		_ui_player.pitch_scale = randf_range(0.97, 1.03)
		_ui_player.play()
		if shot.hit_unit > 0:
			_play3d(_kill_stream if shot.killed else _tick_stream, cam, 0.0)


## The report heard at the camera: the close one (with its action and echoes) near, the distant pop-and-roll far, both
## between, after the time the sound takes to arrive.
func _report(origin: Vector3, d: float, prof: String, heavy: bool) -> void:
	if not is_finite(d) or d > sound_radius:
		return
	var delay := int(d / SOUND_MS * 1000.0)
	var at := Time.get_ticks_msec() + delay
	var pitch := randf_range(0.96, 1.04)
	if d < close_m:
		var k := clampf((d - far_m) / maxf(close_m - far_m, 1.0), 0.0, 1.0)
		_queue(at, _pick("report_" + prof), origin, 2.0 - 10.0 * k, pitch)
	if d > far_m:
		var k2 := clampf((d - far_m) / maxf(close_m - far_m, 1.0), 0.0, 1.0)
		_queue(at, _pick("far_heavy" if heavy else "far_light"), origin, 4.0 - 8.0 * (1.0 - k2), pitch)


func _queue(at_ms: int, stream: AudioStream, pos: Vector3, db: float, pitch: float) -> void:
	if stream == null:
		return
	if at_ms <= Time.get_ticks_msec() + 8:
		_play3d(stream, pos, db, pitch)
	elif _delayed.size() < 64:
		_delayed.append([at_ms, stream, pos, db, pitch])


## COMBAT-01: a round passing the first-person camera close: the crack where it passed (the direction it came from) and,
## very close, the whiz. Sound only - the player's view and aim are never moved.
func _near_miss(shot: Dictionary, cam: Vector3) -> void:
	if game == null or game.mode != GameController.Mode.FPS or not cam.is_finite():
		return
	var origin: Vector3 = shot.origin
	var end: Vector3 = shot.end
	if origin.distance_to(cam) < 3.0 or int(shot.get("hit_unit", -1)) == game.possessed_id:
		return
	var p := Geometry3D.get_closest_point_to_segment(cam, origin, end)
	var miss := p.distance_to(cam)
	if miss > crack_m:
		return
	cracks += 1
	var k := 1.0 - miss / crack_m
	if origin.distance_to(cam) > 25.0:
		_play_near(_pick("crack"), p, -10.0 + 14.0 * k)
	if miss < whiz_m:
		_play_near(_pick("whiz"), p, -6.0 + 6.0 * k)


func _play_near(stream: AudioStream, at: Vector3, db: float) -> void:
	if stream == null:
		return
	var ap: AudioStreamPlayer3D = _take("near", _near_players)
	ap.stream = stream
	ap.volume_db = db
	ap.global_position = at
	ap.pitch_scale = randf_range(0.92, 1.08)
	ap.play()


## What a shot struck: earth (terrain), wood (trunks, timber), metal, stone (rocks, concrete), flesh.
func _material(shot: Dictionary) -> String:
	match String(shot.blocker):
		"unit":
			return "flesh"
		"tree":
			return "wood"
		"terrain":
			return "dirt"
		"structure":
			var st := sim.state.construction.get_structure(int(shot.get("structure_id", -1)))
			var t := String(st.type_id).to_lower() if st else ""
			for w in ["sandbag", "hesco", "berm", "earth", "trench", "dirt"]:
				if t.contains(w):
					return "dirt"
			for w in ["wood", "log", "timber", "plank", "fence", "house", "barn", "shed", "tower"]:
				if t.contains(w):
					return "wood"
			for w in ["metal", "container", "steel", "truck", "tank", "fuel", "gate", "wire"]:
				if t.contains(w):
					return "metal"
			return "stone"
	return "stone"


func _on_reload(u: UnitState) -> void:
	if game and game.mode == GameController.Mode.FPS and u.id == game.possessed_id:
		_ui_reload.stream = _reload_stream
		_ui_reload.play()
	else:
		var cam := _camera_pos()
		if cam.is_finite() and cam.distance_to(u.position) < 60.0:
			_play3d(_reload_stream, u.position + Vector3.UP, -6.0)


## COMBAT-01: a hit makes the soldier flinch away from it (presentation only; the record decides the damage).
func _on_damaged(t: UnitState, amount: float, _zone: int, source_id: int) -> void:
	if not t.alive or amount <= 0.0:
		return
	var b := sim.body_of(t.id) as SoldierBody
	if b == null or b.character == null or b.player_controlled:
		return
	var s := sim.state.get_unit(source_id)
	var from := (s.position - t.position) if s else Vector3.FORWARD
	b.character.flinch(from, clampf(amount / 40.0, 0.4, 1.0))
	flinches += 1


## Visible start of a shot: the body's muzzle if there is one, else the record's eye.
func _muzzle_of(shooter_id: int, origin: Vector3) -> Vector3:
	var b := sim.body_of(shooter_id) as SoldierBody
	if b:
		return b.muzzle_position()
	return origin


func _take(kind: String, pool: Array) -> Variant:
	var i: int = _next[kind]
	_next[kind] = (i + 1) % pool.size()
	return pool[i]


## A muzzle flash: brief, star-shaped, a little different each time; it grows with the camera distance (at 300 m a few
## pixels, as a flicker reads); the light only near the camera. dir: the bore (flame quads along it), ZERO = star only.
func _flash(at: Vector3, cam_d: float, size := 1.0, dir := Vector3.ZERO) -> void:
	var f: Node3D = _take("flash", _flashes)
	var grow := clampf(cam_d * 0.012, 1.0, 9.0)
	f.global_position = at
	if dir.length_squared() > 0.01:
		f.global_basis = Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	f.scale = Vector3.ONE * size * grow * randf_range(0.8, 1.2)
	(f.get_node("Star") as MeshInstance3D).rotation.z = randf() * TAU
	for k in 2:
		(f.get_node("Flame%d" % k) as Node3D).visible = dir.length_squared() > 0.01 and cam_d < 200.0
	var light := f.get_node("Light") as OmniLight3D
	light.visible = cam_d < 80.0
	f.visible = true
	_life[f] = 0.045


## Lingering muzzle smoke near the camera (a puff per shooter every quarter second at most).
func _smoke(at: Vector3, shooter: int, cam_d: float, mg: bool) -> void:
	if cam_d > 120.0:
		return
	var now := Time.get_ticks_msec()
	if now - int(_smoke_at.get(shooter, -10000)) < (180 if mg else 250):
		return
	_smoke_at[shooter] = now
	var p: CPUParticles3D = _take("smoke", _smokes)
	p.global_position = at
	p.restart()
	p.emitting = true


func _tracer(from: Vector3, to: Vector3, bright := false) -> void:
	var d := from.distance_to(to)
	if d < 1.0:
		return
	var t: MeshInstance3D = _take("tracer", _tracers)
	# A short streak 35 % of the way along the path reads as a passing bullet.
	var len := minf(d * 0.6, 30.0 if bright else 22.0)
	var mid := from.lerp(to, 0.35) if d > 30.0 else from.lerp(to, 0.5)
	var dir := (to - from).normalized()
	# Local Z scale (Basis.scaled() would scale world axes and shear the streak).
	# GAMEPLAY-02D: thicker the farther the camera is, so a firefight reads from the tactical view too (2.5 cm up close).
	var cam := _camera_pos()
	var w := clampf(cam.distance_to(mid) * 0.0016 / 0.025, 1.0, 8.0) if cam.is_finite() else 1.0
	if bright:
		w *= 1.8
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT) * Basis.from_scale(Vector3(w, w, len))
	t.global_transform = Transform3D(basis, mid)
	t.transparency = 0.0 if bright else 0.55
	t.visible = true
	_life[t] = 0.08 if bright else 0.06


const IMPACT_LOOK := {
	"dirt": [Color(0.42, 0.34, 0.24), Color(0.55, 0.48, 0.38, 0.55), 10, 3.0],
	"wood": [Color(0.55, 0.4, 0.24), Color(0.62, 0.55, 0.45, 0.35), 8, 4.0],
	"metal": [Color(1.0, 0.82, 0.45), Color(0.6, 0.6, 0.6, 0.2), 9, 7.0],
	"stone": [Color(0.62, 0.6, 0.57), Color(0.72, 0.7, 0.67, 0.5), 9, 4.0],
	"flesh": [Color(0.42, 0.05, 0.04), Color(0.38, 0.06, 0.05, 0.35), 6, 1.5],
}


## The strike: chunks of what was hit (earth, splinters, chips, sparks, blood) and a puff; bigger right next to the camera
## (incoming fire landing close is seen as well as heard). back: the shot's direction (debris flies back out of the hole).
func _impact(at: Vector3, mat: String, near_cam: bool, back: Vector3) -> void:
	var n: Node3D = _take("impact", _impacts)
	n.global_position = at
	var look: Array = IMPACT_LOOK.get(mat, IMPACT_LOOK.stone)
	var chunks := n.get_node("Chunks") as CPUParticles3D
	var cm := chunks.material_override as StandardMaterial3D
	cm.albedo_color = look[0]
	cm.emission_enabled = mat == "metal"
	cm.emission = Color(1.0, 0.7, 0.3) * 4.0
	chunks.amount = int(look[2])
	chunks.visible = mat != "flesh"   # blood: only the small soft puff
	chunks.initial_velocity_max = float(look[3])
	chunks.scale_amount_max = 0.05 if mat == "metal" else 0.12
	chunks.direction = (-back + Vector3.UP).normalized() if back.length_squared() > 0.01 else Vector3.UP
	n.scale = Vector3.ONE * ((1.7 if near_cam else 1.0) if mat != "flesh" else 0.6)
	chunks.restart()
	chunks.emitting = true
	var puff := n.get_node("Puff") as CPUParticles3D
	(puff.material_override as StandardMaterial3D).albedo_color = look[1]
	puff.restart()
	puff.emitting = true


# --- Explosives (GAMEPLAY-02C) ----------------------------------------------------------------------------------------------

## A grenade or rocket left a hand / a tube: a grenade model flying a short arc, or a rocket streak, while near the camera.
func _on_launched(e: Dictionary) -> void:
	var cam := _camera_pos()
	var from: Vector3 = e.from
	var at: Vector3 = e.at
	if not cam.is_finite() or (cam.distance_to(from) > fx_radius and cam.distance_to(at) > fx_radius):
		return
	var n: Node3D
	if String(e.def) == "grenade" and _grenade_scene:
		n = _grenade_scene.instantiate()
		for c in n.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			if not String(mi.name).ends_with("_LOD0"):
				mi.visible = false
			else:
				for s in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(s)
					if m:
						mi.set_surface_override_material(s, InfantryMaterials.get_material(m.resource_name, int(e.f)))
		n.scale = Vector3.ONE * 1.6  # readable from the tactical camera
	else:
		var streak := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.12, 1.4)
		streak.mesh = bm
		streak.material_override = (_tracers[0].material_override as Material)
		n = streak
		_play3d(_launch_stream, from, 2.0)
		_flash(from, cam.distance_to(from), 2.5)
	n.top_level = true
	add_child(n)
	n.global_position = from
	_flying[n] = e


func _move_flying() -> void:
	if _flying.is_empty():
		return
	var now := sim.state.time
	for n: Node3D in _flying.keys():
		var e: Dictionary = _flying[n]
		var from: Vector3 = e.from
		var at: Vector3 = e.at
		if now >= float(e.t) or not sim.state.explosives.has(e):
			_flying.erase(n)
			n.queue_free()
			continue
		if String(e.def) == "grenade":
			# Flies about a second, then lies where it landed until the fuse burns down.
			var k := clampf((now - float(e.t0)) / 1.0, 0.0, 1.0)
			var p := from.lerp(at + Vector3.UP * 0.07, k)
			p.y += sin(k * PI) * maxf(2.0, from.distance_to(at) * 0.25)
			n.global_position = p
			n.rotation = Vector3(k * 9.0, k * 5.0, 0.0)
		else:
			var k := clampf((now - float(e.t0)) / maxf(float(e.t) - float(e.t0), 0.01), 0.0, 1.0)
			var dir := (at - from).normalized()
			n.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT), from.lerp(at, k))


## A burst: a fireball and light, a fast dust ring and a slow smoke column, and the sound (heard farther than seen).
func _on_exploded(e: Dictionary) -> void:
	var at: Vector3 = e.at
	var cam := _camera_pos()
	if not cam.is_finite():
		return
	var d := cam.distance_to(at)
	if d < sound_radius:
		_queue(Time.get_ticks_msec() + int(d / SOUND_MS * 1000.0), _pick("boom_close" if d < 250.0 else "boom_far"), at, 6.0, randf_range(0.95, 1.05))
	if d > fx_radius:
		return
	explosions_shown += 1
	var big := String(e.def) != "grenade"
	var b := _burst_node()
	b.global_position = at + Vector3.UP * 0.3
	b.visible = true
	for c in b.get_children():
		if c is CPUParticles3D:
			(c as CPUParticles3D).restart()
			(c as CPUParticles3D).emitting = true
		elif c is OmniLight3D:
			(c as OmniLight3D).light_energy = 9.0 if big else 6.0
	b.scale = Vector3.ONE * (1.3 if big else 1.0)
	_life[b] = 6.0
	var light: OmniLight3D = b.get_node("Light")
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35)


func _burst_node() -> Node3D:
	for b in _bursts:
		if not b.visible:
			return b
	if _bursts.size() >= 6:
		return _bursts[explosions_shown % _bursts.size()]
	var b := Node3D.new()
	b.top_level = true
	b.visible = false
	add_child(b)
	var fire := _particles(18, 0.35, Color(1.0, 0.62, 0.22), 7.0, 0.5, 1.1, true)
	fire.name = "Fire"
	b.add_child(fire)
	var dust := _particles(28, 1.4, Color(0.48, 0.42, 0.34, 0.9), 9.0, 0.8, 2.0, false, true)
	dust.spread = 80.0
	dust.gravity = Vector3(0, -7, 0)
	b.add_child(dust)
	var smoke := _particles(18, 5.5, Color(0.3, 0.29, 0.28, 0.7), 2.0, 2.4, 6.0, false, true)
	smoke.gravity = Vector3(0, 0.6, 0)
	smoke.explosiveness = 0.85
	b.add_child(smoke)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.65, 0.3)
	light.omni_range = 14.0
	light.shadow_enabled = false
	b.add_child(light)
	_bursts.append(b)
	return b


## soft: camera-facing quads with a soft round edge (smoke, dust) instead of solid spheres.
func _particles(amount: int, life: float, col: Color, speed: float, s0: float, s1: float, glow: bool, soft := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = s0
	p.scale_amount_max = s1
	var m := StandardMaterial3D.new()
	if soft:
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE
		p.mesh = qm
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = _puff_texture()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 8
		sm.rings = 4
		p.mesh = sm
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		m.emission_enabled = true
		m.emission = col * 4.0
	p.material_override = m
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0 if glow else 0.7))
	p.scale_amount_curve = curve
	return p


static var _puff: GradientTexture2D
static var _flash_tex := {}


## A soft round puff (alpha falling off from the centre), shared by smoke and dust.
static func _puff_texture() -> GradientTexture2D:
	if _puff == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.75))
		_puff = GradientTexture2D.new()
		_puff.gradient = g
		_puff.fill = GradientTexture2D.FILL_RADIAL
		_puff.fill_from = Vector2(0.5, 0.5)
		_puff.fill_to = Vector2(1.0, 0.5)
		_puff.width = 64
		_puff.height = 64
	return _puff


## COMBAT-01 muzzle flash textures, drawn once: a hot core with four to six uneven spikes (star), or a flame tongue
## along +Y (the side view of the flash).
static func _flash_texture(tongue: bool) -> ImageTexture:
	if _flash_tex.has(tongue):
		return _flash_tex[tongue]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var spikes: Array = []
	for k in 6:
		spikes.append([k * TAU / 6.0 + rng.randf_range(-0.25, 0.25), rng.randf_range(0.55, 1.0)])
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var a := 0.0
			if tongue:
				var along := 1.0 - (v + 1.0) * 0.5          # 1 at the muzzle (bottom), 0 at the tip
				var width := 0.55 * along + 0.05
				a = clampf(1.0 - absf(u) / width, 0.0, 1.0) * along
			else:
				var r := sqrt(u * u + v * v)
				a = clampf(1.0 - r / 0.32, 0.0, 1.0)
				var ang := atan2(v, u)
				for s: Array in spikes:
					var da := absf(wrapf(ang - float(s[0]), -PI, PI))
					a = maxf(a, clampf(1.0 - da / 0.16, 0.0, 1.0) * clampf(1.0 - r / float(s[1]), 0.0, 1.0))
			a = a * a
			# additive: the shape is in the colour (black adds nothing)
			img.set_pixel(x, y, Color(a, (0.85 + 0.15 * a) * a, (0.6 + 0.4 * a) * a, a))
	var tex := ImageTexture.create_from_image(img)
	_flash_tex[tongue] = tex
	return tex


func _play3d(stream: AudioStream, at: Vector3, db: float, pitch := -1.0) -> void:
	if not at.is_finite() or stream == null:
		return
	var ap: AudioStreamPlayer3D = _take("player", _players)
	ap.stream = stream
	ap.volume_db = db
	ap.global_position = at
	ap.pitch_scale = pitch if pitch > 0.0 else randf_range(0.95, 1.05)
	ap.play()
