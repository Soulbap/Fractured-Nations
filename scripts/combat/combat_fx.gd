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
var _boom_stream: AudioStreamWAV
var _launch_stream: AudioStreamWAV
## GAMEPLAY-02C: thrown grenades / rockets on their way (node -> explosive entry) and the burst effects.
var _flying := {}
var _grenade_scene: PackedScene
var _bursts: Array[Node3D] = []
var explosions_shown := 0
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
	sim.state.explosive_launched.connect(_on_launched)
	sim.state.exploded.connect(_on_exploded)
	_boom_stream = CombatAudio.explosion()
	_launch_stream = CombatAudio.launch()
	if ResourceLoader.exists("res://assets/characters/infantry/weapons/grenade.glb"):
		_grenade_scene = load("res://assets/characters/infantry/weapons/grenade.glb")
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
	_move_flying()
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
		_flash(from, 2.5)
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
	if cam.distance_to(at) < sound_radius:
		_play3d(_boom_stream, at, 6.0)
	if cam.distance_to(at) > fx_radius:
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
	var dust := _particles(28, 1.4, Color(0.42, 0.37, 0.3), 9.0, 0.4, 1.0, false)
	dust.spread = 80.0
	dust.gravity = Vector3(0, -7, 0)
	b.add_child(dust)
	var smoke := _particles(16, 5.0, Color(0.28, 0.27, 0.26, 0.85), 2.0, 1.2, 3.2, false)
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


func _particles(amount: int, life: float, col: Color, speed: float, s0: float, s1: float, glow: bool) -> CPUParticles3D:
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
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	p.mesh = sm
	var m := StandardMaterial3D.new()
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


func _play3d(stream: AudioStream, at: Vector3, db: float) -> void:
	if not at.is_finite():
		return
	var ap: AudioStreamPlayer3D = _take("player", _players)
	ap.stream = stream
	ap.volume_db = db
	ap.global_position = at
	ap.pitch_scale = randf_range(0.95, 1.05)
	ap.play()
