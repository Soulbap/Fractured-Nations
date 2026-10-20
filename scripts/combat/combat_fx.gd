## Shot presentation (COMBAT-01a): muzzle flash, tracer, impact, sound. No authority -
## it only listens to WorldState.shot_fired / reload_started and draws what the active
## camera can see. Shots farther than fx_radius from the camera produce nothing, so
## distant and abstract fights cost no effects. All nodes come from small pools.
class_name CombatFX
extends Node3D

@export var fx_radius := 450.0
@export var sound_radius := 900.0
@export var pool_size := 24

var sim: WorldSim
var game: GameController

var _shot_stream: AudioStreamWAV
var _reload_stream: AudioStreamWAV
var _tick_stream: AudioStreamWAV
var _kill_stream: AudioStreamWAV
var _tracers: Array[MeshInstance3D] = []
var _flashes: Array[Node3D] = []
var _impacts: Array[CPUParticles3D] = []
var _players: Array[AudioStreamPlayer3D] = []
var _ui_player: AudioStreamPlayer
var _ui_reload: AudioStreamPlayer
var _next := {"tracer": 0, "flash": 0, "impact": 0, "player": 0}
var _life := {}
## Counters for tests and the HUD.
var shown := 0
var skipped_far := 0


func setup(p_sim: WorldSim, p_game: GameController) -> void:
	sim = p_sim
	game = p_game
	sim.state.shot_fired.connect(_on_shot)
	sim.state.reload_started.connect(_on_reload)
	_shot_stream = CombatAudio.gunshot()
	_reload_stream = CombatAudio.reload_sound()
	_tick_stream = CombatAudio.hit_tick(false)
	_kill_stream = CombatAudio.hit_tick(true)
	_build_pools()


func _build_pools() -> void:
	var tracer_mat := StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.albedo_color = Color(1.0, 0.85, 0.45)
	tracer_mat.emission_enabled = true
	tracer_mat.emission = Color(1.0, 0.7, 0.3) * 3.0
	tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var flash_mat := tracer_mat.duplicate() as StandardMaterial3D
	flash_mat.albedo_color = Color(1.0, 0.8, 0.4, 0.9)
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
		var f := Node3D.new()
		f.top_level = true
		f.visible = false
		var fm := MeshInstance3D.new()
		var qm := SphereMesh.new()
		qm.radius = 0.09
		qm.height = 0.18
		qm.radial_segments = 8
		qm.rings = 4
		fm.mesh = qm
		fm.material_override = flash_mat
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_child(fm)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.75, 0.4)
		light.light_energy = 2.5
		light.omni_range = 4.0
		light.shadow_enabled = false
		f.add_child(light)
		add_child(f)
		_flashes.append(f)
		var p := CPUParticles3D.new()
		p.top_level = true
		p.emitting = false
		p.one_shot = true
		p.amount = 10
		p.lifetime = 0.45
		p.explosiveness = 1.0
		p.direction = Vector3.UP
		p.spread = 50.0
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 3.0
		p.gravity = Vector3(0, -6, 0)
		p.scale_amount_min = 0.06
		p.scale_amount_max = 0.14
		var pm := SphereMesh.new()
		pm.radius = 0.5
		pm.height = 1.0
		pm.radial_segments = 6
		pm.rings = 3
		p.mesh = pm
		var dust := StandardMaterial3D.new()
		dust.albedo_color = Color(0.45, 0.4, 0.33)
		dust.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		p.material_override = dust
		add_child(p)
		_impacts.append(p)
	for i in 12:
		var ap := AudioStreamPlayer3D.new()
		ap.max_distance = sound_radius
		ap.unit_size = 12.0
		ap.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		ap.top_level = true
		add_child(ap)
		_players.append(ap)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.volume_db = -4.0
	add_child(_ui_player)
	_ui_reload = AudioStreamPlayer.new()
	add_child(_ui_reload)


func _process(delta: float) -> void:
	for n in _life.keys():
		_life[n] -= delta
		if _life[n] <= 0.0:
			(n as Node3D).visible = false
			_life.erase(n)


func _camera_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.INF


func _on_shot(shot: Dictionary) -> void:
	var cam := _camera_pos()
	var origin: Vector3 = shot.origin
	var end: Vector3 = shot.end
	var own: bool = game != null and game.mode == GameController.Mode.FPS and shot.shooter == game.possessed_id
	var near := own or (cam.is_finite() and (cam.distance_to(origin) < fx_radius or cam.distance_to(end) < fx_radius))
	if not near:
		skipped_far += 1
		if cam.is_finite() and cam.distance_to(origin) < sound_radius:
			_play3d(_shot_stream, origin, -6.0)
		return
	shown += 1
	var muzzle := _muzzle_of(shot.shooter, origin)
	_flash(muzzle, 0.3 if own else 1.0)
	_tracer(muzzle, end)
	if shot.blocker != "range":
		_impact(end, shot.blocker == "unit")
	if own:
		_ui_player.stream = _shot_stream
		_ui_player.pitch_scale = randf_range(0.96, 1.04)
		_ui_player.play()
		if shot.hit_unit > 0:
			_play3d(_kill_stream if shot.killed else _tick_stream, cam, 0.0)
	else:
		_play3d(_shot_stream, origin, 0.0)


func _on_reload(u: UnitState) -> void:
	if game and game.mode == GameController.Mode.FPS and u.id == game.possessed_id:
		_ui_reload.stream = _reload_stream
		_ui_reload.play()
	else:
		var cam := _camera_pos()
		if cam.is_finite() and cam.distance_to(u.position) < 60.0:
			_play3d(_reload_stream, u.position + Vector3.UP, -6.0)


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


func _flash(at: Vector3, size := 1.0) -> void:
	var f: Node3D = _take("flash", _flashes)
	f.global_position = at
	f.scale = Vector3.ONE * size
	f.visible = true
	_life[f] = 0.05


func _tracer(from: Vector3, to: Vector3) -> void:
	var d := from.distance_to(to)
	if d < 1.0:
		return
	var t: MeshInstance3D = _take("tracer", _tracers)
	# A short streak 35 % of the way along the path reads as a passing bullet.
	var len := minf(d * 0.6, 22.0)
	var mid := from.lerp(to, 0.35) if d > 30.0 else from.lerp(to, 0.5)
	var dir := (to - from).normalized()
	# Local Z scale (Basis.scaled() would scale world axes and shear the streak).
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT) * Basis.from_scale(Vector3(1, 1, len))
	t.global_transform = Transform3D(basis, mid)
	t.visible = true
	_life[t] = 0.06


func _impact(at: Vector3, flesh: bool) -> void:
	var p: CPUParticles3D = _take("impact", _impacts)
	p.global_position = at
	(p.material_override as StandardMaterial3D).albedo_color = Color(0.55, 0.05, 0.04) if flesh else Color(0.45, 0.4, 0.33)
	p.restart()
	p.emitting = true


func _play3d(stream: AudioStream, at: Vector3, db: float) -> void:
	if not at.is_finite():
		return
	var ap: AudioStreamPlayer3D = _take("player", _players)
	ap.stream = stream
	ap.volume_db = db
	ap.global_position = at
	ap.pitch_scale = randf_range(0.95, 1.05)
	ap.play()
