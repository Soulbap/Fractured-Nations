## Tactical input: selecting units and issuing orders from the RTS camera.
##
## Selection is screen-space (nearest projected unit within a few pixels, or a drag
## box), which works at any zoom. Orders go to WorldState only; nothing here moves a
## unit.
##
## UNIT-01A squads: a squad counts as selected when all its members are (Ctrl+click on a
## soldier or the squad panel selects them). Orders go to selected squads as squad
## orders (formation slots, see SquadControl) and to the other selected soldiers as
## individual orders, which detach them from their squad order. Keys: RMB move, H hold,
## F then click a unit = follow it (or its squad), G regroup on the leader, Shift+G
## regroup at the cursor, V line / column, [ ] spacing, Y weapons free / hold fire
## (COMBAT-01b rules of engagement). The ground point of a move order comes from a physics ray against the terrain
## collision, with Terrain3D's height-map ray march as fallback.
class_name RTSController
extends Node

signal selection_changed(ids: Array)
signal possess_requested(unit_id: int)
## LOGISTICS-01: the player wants the wheel of a selected vehicle (P / Enter with no soldier selected).
signal drive_requested(unit_id: int)
signal order_issued(count: int, target: Vector3)
## AI-SQUAD-01: a tactical order was given or refused ({ok, n, text, ...}); the panel shows the text.
signal tactical_order(result: Dictionary)

@export var rig: RTSCamera
@export var sim: WorldSim:
	set(v):
		sim = v
		if v and not v.view_added.is_connected(_on_view_added):
			v.view_added.connect(_on_view_added)
@export var terrain: Terrain3D
## LOGISTICS-01: clicking a building selects it (its facility panel shows in the HUD).
@export var structures: StructureManager
## Where the move-order marker lives.
@export var marker_parent: Node3D
@export var pick_radius_px := 22.0
@export var drag_threshold_px := 6.0
@export var formation_spacing := 2.5
## Allow ordering and possessing units of any faction (no combat yet, useful for testing).
@export var command_any_faction := true
@export var player_faction := 0

var selected: Array[int] = []
## Selected facility (structure id, -1 none): a building clicked in the tactical view.
var selected_structure := -1
var active := false
var drag_start := Vector2.INF
var drag_current := Vector2.ZERO
var dragging := false
var last_order_target := Vector3.INF
## Waiting for a click on the unit to follow (F).
var follow_pick := false
## AI-SQUAD-01: a tactical order (SquadState.Tactic) armed from the panel, waiting for the click that
## gives its target (-1 = none). The hotkeys give the order at the cursor at once.
var armed_tactic := -1
## The last tactical order's result text (accepted / why it cannot be executed), for the panel.
var tactic_feedback := ""
var tactic_feedback_ok := true
## Short feedback line for the HUD.
var message := ""
var _message_until := 0.0

var _marker: MeshInstance3D
var _marker_until := 0.0


func _ready() -> void:
	GameController.ensure_input_actions()
	_ensure_squad_actions()
	set_process_unhandled_input(false)
	_marker = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.7
	cyl.height = 0.08
	_marker.mesh = cyl
	var m := UnitVisuals.make_ring_material()
	m.albedo_color = Color(0.4, 1.0, 0.4, 0.8)
	_marker.material_override = m
	_marker.visible = false
	(marker_parent if marker_parent else self).add_child.call_deferred(_marker)


func set_active(on: bool) -> void:
	active = on
	set_process_unhandled_input(on)
	if not on:
		_end_drag()
		follow_pick = false
		armed_tactic = -1


func _process(_delta: float) -> void:
	if _marker.visible and Time.get_ticks_msec() / 1000.0 > _marker_until:
		_marker.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and follow_pick:
			if event.pressed:
				order_follow_at(event.position)
			return
		if event.button_index == MOUSE_BUTTON_LEFT and armed_tactic >= 0:
			if event.pressed:
				var t := armed_tactic
				armed_tactic = -1
				order_tactic(t, tactic_target_at(event.position))
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag_start = event.position
				drag_current = event.position
				dragging = false
				if event.double_click:
					var id := _unit_at(event.position)
					if id > 0 and _can_command(id):
						select([id])
						possess_requested.emit(id)
			else:
				if dragging:
					_box_select(Rect2(drag_start, drag_current - drag_start).abs(), event.shift_pressed)
				elif drag_start != Vector2.INF:
					if event.ctrl_pressed:
						_click_select_squad(event.position, event.shift_pressed)
					else:
						_click_select(event.position, event.shift_pressed)
				_end_drag()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if armed_tactic >= 0:
				armed_tactic = -1
				_say("Tactical order cancelled")
			elif event.shift_pressed and not selected_squads().is_empty():
				# Shift + right click: move by bounds (one fire team covers while the other moves).
				order_tactic(SquadState.Tactic.BOUND, tactic_target_at(event.position))
			else:
				order_move_at(event.position)
	elif event is InputEventMouseMotion and drag_start != Vector2.INF and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		drag_current = event.position
		if drag_current.distance_to(drag_start) > drag_threshold_px:
			dragging = true
	elif event.is_action_pressed("possess"):
		var id := first_selected_soldier()
		if id > 0:
			possess_requested.emit(id)
		else:
			var vid := first_selected_vehicle()
			if vid > 0:
				drive_requested.emit(vid)
	elif event.is_action_pressed("squad_assault"):
		tactic_hotkey(SquadState.Tactic.ASSAULT)
	elif event.is_action_pressed("squad_suppress"):
		tactic_hotkey(SquadState.Tactic.SUPPRESS)
	elif event.is_action_pressed("squad_flank"):
		tactic_hotkey(SquadState.Tactic.FLANK)
	elif event.is_action_pressed("squad_defend"):
		tactic_hotkey(SquadState.Tactic.DEFEND)
	elif event.is_action_pressed("squad_withdraw"):
		tactic_hotkey(SquadState.Tactic.WITHDRAW)
	elif event.is_action_pressed("halt"):
		order_hold()
	elif event.is_action_pressed("squad_follow"):
		if selected_squads().is_empty():
			_say("Follow: select a squad first")
		else:
			follow_pick = true
			_say("Follow: click the soldier or squad to follow (Esc cancels)")
	elif event.is_action_pressed("squad_regroup"):
		var at := ground_point(get_viewport().get_mouse_position()) if Input.is_key_pressed(KEY_SHIFT) else Vector3.INF
		order_regroup(at)
	elif event.is_action_pressed("squad_formation"):
		toggle_formation()
	elif event.is_action_pressed("squad_spacing_down"):
		change_spacing(-0.5)
	elif event.is_action_pressed("squad_spacing_up"):
		change_spacing(0.5)
	elif event.is_action_pressed("squad_roe"):
		toggle_roe()
	elif event.is_action_pressed("vehicle_board"):
		order_board()
	elif event.is_action_pressed("vehicle_unload"):
		order_unload()
	elif event.is_action_pressed("select_all"):
		var ids := []
		for u in sim.state.soldiers():
			if _can_command(u.id) and u.alive:
				ids.append(u.id)
		select(ids)
	elif event.is_action_pressed("ui_cancel"):
		if follow_pick:
			follow_pick = false
			_say("Follow cancelled")
		elif armed_tactic >= 0:
			armed_tactic = -1
			_say("Tactical order cancelled")
		else:
			select([])


func select(p_ids: Array) -> void:
	# Callers build the new list from Array(selected), which is the same array, not a
	# copy: take a copy before clearing (UNIT-01A; Shift+click add selected nothing).
	var ids := p_ids.duplicate()
	selected_structure = -1
	for id in selected:
		var v := sim.view_of(id)
		if v and "selected" in v:
			v.selected = false
	selected.clear()
	for id in ids:
		var su := sim.state.get_unit(id)
		if su == null or not su.alive or selected.has(id):
			continue
		selected.append(id)
		var v := sim.view_of(id)
		if v and "selected" in v:
			v.selected = true
	selection_changed.emit(selected)


## A unit changed tier (body <-> proxy): the new node must show the selection too.
func _on_view_added(id: int, view: Node3D) -> void:
	if selected.has(id) and "selected" in view:
		view.selected = true


## COMBAT-01a: casualties leave the selection.
func on_unit_died(u: UnitState) -> void:
	if selected.has(u.id):
		var ids := Array(selected)
		ids.erase(u.id)
		select(ids)


func first_selected_vehicle() -> int:
	for id in selected:
		var u := sim.state.get_unit(id)
		if u and u.kind == UnitState.Kind.VEHICLE and u.alive and _can_command(id):
			return id
	return -1


## Selected vehicles the player may command, in id order.
func selected_vehicles() -> Array:
	var out := []
	for id in selected:
		var u := sim.state.get_unit(id)
		if u and u.kind == UnitState.Kind.VEHICLE and u.alive and _can_command(id):
			out.append(id)
	out.sort()
	return out


func first_selected_soldier() -> int:
	for id in selected:
		var u := sim.state.get_unit(id)
		if u and u.kind == UnitState.Kind.SOLDIER:
			return id
	return -1


## Issues a move order toward the ground under a screen position: squad orders for the
## selected squads, individual orders for the other selected soldiers. Returns the
## number of soldiers ordered.
func order_move_at(screen_pos: Vector2) -> int:
	# LOGISTICS-01: right-click on a friendly vehicle with squads selected = board it.
	var over := _unit_at(screen_pos)
	if over > 0 and not selected.has(over):
		var ou := sim.state.get_unit(over)
		if ou and ou.kind == UnitState.Kind.VEHICLE and _can_command(over) and not selected_squads().is_empty():
			return order_board_vehicle(over)
	var hit := ground_point(screen_pos)
	if not hit.is_finite():
		return 0
	return order_move(hit)


func order_move(hit: Vector3) -> int:
	# Squads and vehicles selected together: a combined transport order (the squads board
	# the vehicles and are driven to the point).
	if not selected_vehicles().is_empty() and not selected_squads().is_empty():
		var tn := order_transport_group(hit)
		if tn > 0:
			last_order_target = hit
			_marker.global_position = hit + Vector3.UP * 0.1
			_marker.visible = true
			_marker_until = Time.get_ticks_msec() / 1000.0 + 2.5
			order_issued.emit(tn, hit)
			return tn
	var sqs := selected_squads()
	_player_takes(sqs)
	var n := sim.squads.order_move(sqs, hit) if not sqs.is_empty() else 0
	var loose := loose_selected()
	if not loose.is_empty():
		var at := hit if sqs.is_empty() else hit + _beside_squads(sqs)
		n += sim.state.issue_individual_moves(loose, at, formation_spacing)
	n += order_vehicles(hit)
	if n > 0:
		last_order_target = hit
		_marker.global_position = hit + Vector3.UP * 0.1
		_marker.visible = true
		_marker_until = Time.get_ticks_msec() / 1000.0 + 2.5
		order_issued.emit(n, hit)
	return n


## Squads of the selection board vehicles of the selection (in order, while seats last);
## dest finite: they are driven there and set down. Returns the soldiers boarding.
func order_transport_group(dest: Vector3) -> int:
	var sqs := selected_squads()
	var r := sim.vehicles.transport.order_group(selected_vehicles(), sqs, dest)
	_player_takes(sqs)
	_say(" · ".join(r.texts))
	return r.n


## T: the selected squads board the selected vehicle(s) and wait for orders.
func order_board() -> int:
	if selected_vehicles().is_empty() or selected_squads().is_empty():
		_say("Board: select a squad and a vehicle (T)")
		return 0
	return order_transport_group(Vector3.INF)


## Right-click on a vehicle: the selected squads board it.
func order_board_vehicle(vid: int) -> int:
	var sqs := selected_squads()
	var n := 0
	var u := sim.state.get_unit(vid)
	var texts: Array[String] = []
	for sid in sqs:
		var res := sim.vehicles.transport.order_transport(vid, sid)
		if res.ok:
			n += res.boarding
			texts.append("%s boards %s (%d)" % [sim.state.get_squad(sid).squad_name, u.unit_name, res.boarding])
		else:
			texts.append("%s: %s" % [u.unit_name, res.reason])
			break
	_player_takes(sqs)
	_say(" · ".join(texts))
	return n


## U: selected vehicles stop and set their passengers down.
func order_unload() -> void:
	var vids := selected_vehicles()
	if vids.is_empty():
		_say("Unload: select a vehicle (U)")
		return
	for vid in vids:
		sim.vehicles.transport.unload(vid)
	_say("Disembarking")


## LOGISTICS-01: the selected vehicles drive to the point (a line abreast when several go to
## one place, so they do not fight for the same square metre). Feedback in the HUD message.
func order_vehicles(hit: Vector3) -> int:
	var vids := selected_vehicles()
	if vids.is_empty():
		return 0
	var r := sim.vehicles.order_group(vids, hit)
	_say(" · ".join(r.texts))
	return r.n


# --- Tactical orders (AI-SQUAD-01) ---------------------------------------------------------------

## The position a tactical order aims at for a screen point: the ground under the cursor (an
## enemy soldier under the cursor is a position the player can see on screen, so it counts).
func tactic_target_at(screen_pos: Vector2) -> Vector3:
	var over := _unit_at(screen_pos)
	if over > 0:
		var ou := sim.state.get_unit(over)
		if ou and ou.alive and ou.faction != player_faction and ou.kind == UnitState.Kind.SOLDIER:
			return ou.position
	return ground_point(screen_pos)


## Hotkey: the tactical order at the cursor, at once.
func tactic_hotkey(tactic: int) -> void:
	if selected_squads().is_empty():
		_say("%s: select a squad first" % SquadState.TACTIC_NAMES[tactic])
		return
	order_tactic(tactic, tactic_target_at(get_viewport().get_mouse_position()))


## Panel button: wait for the click that gives the target (Esc / right click cancels).
func arm_tactic(tactic: int) -> void:
	if selected_squads().is_empty():
		_say("%s: select a squad first" % SquadState.TACTIC_NAMES[tactic])
		return
	armed_tactic = tactic
	_say("%s: click the target (Esc cancels)" % SquadState.TACTIC_NAMES[tactic].to_upper())


## A tactical order for the selected squads: {ok, n, results, text}. The result text says what was
## accepted and, for a refused squad, why it cannot be done.
func order_tactic(tactic: int, at := Vector3.INF) -> Dictionary:
	var sqs := selected_squads()
	if sqs.is_empty():
		_say("%s: select a squad first" % SquadState.TACTIC_NAMES[tactic])
		return {"ok": false, "n": 0, "text": "no squad selected", "results": []}
	if tactic != SquadState.Tactic.DEFEND and tactic != SquadState.Tactic.WITHDRAW and not at.is_finite():
		var msg := "%s needs a target: no ground under the cursor" % SquadState.TACTIC_NAMES[tactic]
		tactic_feedback = msg
		tactic_feedback_ok = false
		_say(msg)
		return {"ok": false, "n": 0, "text": msg, "results": []}
	# A defence faces the way the squad is looking at the spot.
	if tactic == SquadState.Tactic.DEFEND and at.is_finite():
		for sid in sqs:
			var sq := sim.state.get_squad(sid)
			var c := sim.squads._centroid(sq)
			if Vector2(at.x - c.x, at.z - c.z).length() > 8.0:
				sq.order_yaw = SquadControl._yaw_towards(c, at, sq.order_yaw)
	_player_takes(sqs)
	var res := sim.tactics.order_tactic(sqs, tactic, at, SquadState.Owner.PLAYER)
	tactic_feedback = res.text
	tactic_feedback_ok = res.ok
	_say(res.text)
	if res.n > 0 and at.is_finite():
		last_order_target = at
		_marker.global_position = at + Vector3.UP * 0.1
		_marker.visible = true
		_marker_until = Time.get_ticks_msec() / 1000.0 + 2.5
		order_issued.emit(res.n, at)
	tactical_order.emit(res)
	return res


## H: selected squads hold; other selected soldiers stop.
func order_hold() -> void:
	for id in selected_vehicles():
		sim.vehicles.halt(id)
	_player_takes(selected_squads())
	sim.squads.order_hold(selected_squads())
	for id in loose_selected():
		sim.state.detach(id)
		sim.state.halt(id)
	_say("Hold" if not selected.is_empty() else "Nothing selected")


## F + click: the selected squads follow the clicked soldier (its squad if it has one).
func order_follow_at(screen_pos: Vector2) -> int:
	follow_pick = false
	var id := _unit_at(screen_pos)
	return order_follow(id)


func order_follow(id: int) -> int:
	var u := sim.state.get_unit(id)
	if u == null or u.kind != UnitState.Kind.SOLDIER:
		_say("Follow: no soldier there")
		return 0
	_player_takes(selected_squads())
	var n := sim.squads.order_follow(selected_squads(), id)
	var sq := sim.state.squad_of(id)
	_say(("Following %s" % (sq.squad_name if sq else u.unit_name)) if n > 0 else "Follow: a squad cannot follow itself")
	return n


func order_regroup(at := Vector3.INF) -> int:
	var sqs := selected_squads()
	if sqs.is_empty():
		_say("Regroup: select a squad first")
		return 0
	_player_takes(sqs)
	var n := sim.squads.order_regroup(sqs, at)
	_say("Regroup %s" % ("at the cursor" if at.is_finite() else "on the leader"))
	return n


func toggle_formation() -> void:
	var sqs := selected_squads()
	if sqs.is_empty():
		return
	# V toggles Line <-> Column as before (a squad on auto formation goes to Line); Shift+V cycles
	# Line -> Column -> Wedge -> Staggered -> Dispersed -> Auto (terrain and situation) -> Line.
	var first := sim.state.get_squad(sqs[0])
	if not Input.is_key_pressed(KEY_SHIFT):
		for sid in sqs:
			sim.state.get_squad(sid).formation_auto = false
		var f := SquadState.Formation.COLUMN if first.formation == SquadState.Formation.LINE else SquadState.Formation.LINE
		sim.squads.set_formation(sqs, f)
		_say("Formation: %s" % SquadState.FORMATION_NAMES[f])
		return
	if first.formation_auto:
		for sid in sqs:
			sim.state.get_squad(sid).formation_auto = false
		sim.squads.set_formation(sqs, SquadState.Formation.LINE)
		_say("Formation: Line")
		return
	var next: int = first.formation + 1
	if next >= SquadState.FORMATION_NAMES.size():
		for sid in sqs:
			sim.state.get_squad(sid).formation_auto = true
		sim.squads.set_formation(sqs, SquadState.Formation.WEDGE)
		_say("Formation: Auto (column on roads and in woods, wedge in the open, dispersed under fire)")
		return
	sim.squads.set_formation(sqs, next)
	_say("Formation: %s" % SquadState.FORMATION_NAMES[next])


## Y: weapons free <-> hold fire for the selected squads (the first one decides).
func toggle_roe() -> void:
	var sqs := selected_squads()
	if sqs.is_empty():
		_say("Rules of engagement: select a squad first")
		return
	var first := sim.state.get_squad(sqs[0])
	var roe := SquadState.Roe.HOLD_FIRE if first.roe == SquadState.Roe.WEAPONS_FREE else SquadState.Roe.WEAPONS_FREE
	set_roe(sqs, roe)


func set_roe(squad_ids: Array, roe: SquadState.Roe) -> void:
	var n := sim.squads.set_roe(squad_ids, roe)
	if n > 0:
		_say("%s: %s" % [", ".join(squad_ids.map(func(id: int) -> String: return sim.state.get_squad(id).squad_name)), SquadState.ROE_NAMES[roe]])


func change_spacing(delta: float) -> void:
	var sqs := selected_squads()
	if sqs.is_empty():
		return
	var first := sim.state.get_squad(sqs[0])
	sim.squads.set_spacing(sqs, first.spacing + delta)
	_say("Spacing %.1f m" % sim.state.get_squad(sqs[0]).spacing)


## Squads whose members are all selected (commandable), in id order.
func selected_squads() -> Array:
	var out := []
	for sq: SquadState in sim.state.all_squads():
		if not _can_command(sq.leader_id):
			continue
		var all := true
		for id in sq.members:
			if not selected.has(id):
				all = false
				break
		if all:
			out.append(sq.id)
	return out


## Selected commandable soldiers that are not part of a fully selected squad.
func loose_selected() -> Array:
	var in_sq := {}
	for sid in selected_squads():
		for id in sim.state.get_squad(sid).members:
			in_sq[id] = true
	var out := []
	for id in selected:
		var u := sim.state.get_unit(id)
		if u and u.kind == UnitState.Kind.SOLDIER and not in_sq.has(id) and _can_command(id):
			out.append(id)
	return out


## Selects whole squads (add: keep the current selection).
func select_squads(squad_ids: Array, add := false) -> void:
	var ids := Array(selected) if add else []
	for sid in squad_ids:
		var sq := sim.state.get_squad(sid)
		if sq == null:
			continue
		for id in sq.members:
			if not ids.has(id):
				ids.append(id)
	select(ids)


func _click_select_squad(screen_pos: Vector2, add: bool) -> void:
	var sq := sim.state.squad_of(_unit_at(screen_pos))
	if sq:
		select_squads([sq.id], add)
	else:
		_click_select(screen_pos, add)


## Loose soldiers ordered together with squads stand next to them, not on top.
func _beside_squads(sqs: Array) -> Vector3:
	var sq := sim.state.get_squad(sqs[-1])
	var right := SquadControl._right(sq.order_yaw)
	var width := 0.0
	for sid in sqs:
		width += sim.squads._width(sim.state.get_squad(sid)) + sim.squads.squad_gap
	return right * (width * 0.5 + formation_spacing * 2.0)


## WORLD-SANDBOX-01: a direct order from the player takes the squads out of whatever
## operation they served (the player's command always wins; the operation continues with
## its other squads or ends).
func _player_takes(squad_ids: Array) -> void:
	if sim.war:
		sim.war.release_squads(squad_ids, "player order")


func _say(text: String) -> void:
	message = text
	_message_until = Time.get_ticks_msec() / 1000.0 + 3.0


func current_message() -> String:
	return message if Time.get_ticks_msec() / 1000.0 < _message_until else ""


static func _ensure_squad_actions() -> void:
	var binds := {"vehicle_board": KEY_T, "vehicle_unload": KEY_U, "squad_follow": KEY_F, "squad_regroup": KEY_G, "squad_formation": KEY_V,
		"squad_spacing_down": KEY_BRACKETLEFT, "squad_spacing_up": KEY_BRACKETRIGHT, "squad_roe": KEY_Y,
		"squad_assault": KEY_Z, "squad_suppress": KEY_K, "squad_flank": KEY_L, "squad_defend": KEY_J, "squad_withdraw": KEY_BACKSPACE}
	for action in binds:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = binds[action]
		InputMap.action_add_event(action, ev)


## World position of the terrain under a screen point, or Vector3.INF.
func ground_point(screen_pos: Vector2) -> Vector3:
	var cam := rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 20000.0)
	q.collide_with_areas = false
	var exclude: Array[RID] = []
	for b in sim.bodies.values():
		if b is CollisionObject3D:
			exclude.append(b.get_rid())
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit.position
	if terrain:
		var p: Vector3 = terrain.get_intersection(from, dir, false)
		if p.is_finite() and not is_nan(p.x):
			return p
	return Vector3.INF


func _can_command(id: int) -> bool:
	var u := sim.state.get_unit(id)
	return u != null and (command_any_faction or u.faction == player_faction)


func _unit_at(screen_pos: Vector2) -> int:
	var cam := rig.camera
	var best := -1
	var best_d := INF
	# Positions come from the records, so units in either tier are pickable.
	for u: UnitState in sim.state.units.values():
		if not u.alive:
			continue
		var id := u.id
		var p := u.position + Vector3.UP * (1.0 if u.kind == UnitState.Kind.SOLDIER else 1.3)
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		var radius := pick_radius_px * (1.0 if u.kind == UnitState.Kind.SOLDIER else 2.2)
		var d := sp.distance_to(screen_pos)
		if d <= radius and d < best_d:
			best_d = d
			best = id
	return best


func _click_select(screen_pos: Vector2, add: bool) -> void:
	var id := _unit_at(screen_pos)
	if id < 0:
		# A facility under the cursor is selected without dropping the selected units (a
		# selected truck / squad is then ordered from the facility's panel).
		if _pick_structure(screen_pos):
			return
		if not add:
			select([])
		return
	if add:
		var ids := Array(selected)
		if ids.has(id):
			ids.erase(id)
		else:
			ids.append(id)
		select(ids)
	else:
		select([id])


## A click on a facility selects it (vehicles and squads stay selected, so a selected truck
## can be sent to the depot from its panel).
func _pick_structure(screen_pos: Vector2) -> bool:
	if structures == null or rig == null:
		return false
	var cam := rig.camera
	var hit := structures.pick(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos), 6000.0)
	if hit.is_empty():
		return false
	var s := structures.state.get_structure(hit.id)
	if s != null and FacilityDefs.has(s.type_id) and s.faction == player_faction:
		selected_structure = s.id
		_say("%s selected" % FacilityDefs.display_name(s.type_id))
		selection_changed.emit(selected)
		return true
	return false


func _box_select(rect: Rect2, add: bool) -> void:
	var cam := rig.camera
	var ids := Array(selected) if add else []
	for u: UnitState in sim.state.units.values():
		if not u.alive:
			continue
		var p := u.position + Vector3.UP
		if cam.is_position_behind(p):
			continue
		if rect.has_point(cam.unproject_position(p)) and not ids.has(u.id):
			ids.append(u.id)
	select(ids)


func _end_drag() -> void:
	drag_start = Vector2.INF
	dragging = false
