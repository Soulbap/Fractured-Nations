## ASSET-INTEGRATION-01 development armoury: the WEAPON-ASSETS-01 weapons and VEHICLE-ASSETS-01 vehicles at hand for
## testing, in the Development Scenario only (scenario rule "dev_armoury"; New Game never shows it). F10 opens it in the
## tactical view.
##  * Weapons: the button gives the selected soldier (or the possessed one) the weapon's development role (InfantryRole
##    dev_<id>: weapon, look, secondary launcher) through CombatSim.give_role - the same record fields the economy's
##    equipment changes write, so FPS / RTS / save / load all see it. In first person [ and ] step through the list.
##  * Vehicles: a button parks one of the type for the player's faction at the camera's focus (WorldState.add_vehicle).
##  * Parts: doors, turret sweep and rotor of the selected (else the last spawned) vehicle - VehicleVisual's presentation
##    inputs - and Drive (GameController.drive).
## Nothing here changes rules, stock or progression.
class_name DevArmoury
extends Control

const WEAPONS: Array[StringName] = [&"hk416", &"hk417", &"fn_minimi", &"fn_mag", &"glock_17", &"axmc", &"carl_gustaf_m4",
	&"m72_law", &"ak12", &"ak74m", &"rpk74m", &"svd", &"pkp_pecheneg", &"mp443", &"rpg7", &"rpg26"]

var demo: CoreDemo
var last_vehicle := -1
var sweep := false
var _panel: FNPanel
var _say: Label
var _doors: Button
var _sweep: Button
var _rotor: Button
var _t := 0.0


static func enabled_for(d: CoreDemo) -> bool:
	return d.sandbox and d.sim.state.war != null and bool(d.sim.state.war.rule("dev_armoury", false))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = FNUI.theme()
	visible = false
	_panel = FNPanel.new(FNUI.WARN, FNUI.S5)
	_panel.position = Vector2(16, 64)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", FNUI.S3)
	_panel.add_child(v)
	v.add_child(FNUI.label("Development armoury", FNUI.HEADLINE, FNUI.INK, "caps"))
	v.add_child(FNSectionHeader.new("Weapons", "to the selected / possessed soldier · FPS: [ ]"))
	var g := GridContainer.new()
	g.columns = 4
	v.add_child(g)
	for wid in WEAPONS:
		var def := demo.sim.combat.weapon(wid)
		var b := FNUI.action_button(&"", def.display_name if def else String(wid), String(wid))
		b.pressed.connect(func() -> void: _say_text(give(wid)))
		g.add_child(b)
	v.add_child(FNSectionHeader.new("Vehicles", "parked at the camera focus"))
	var gv := GridContainer.new()
	gv.columns = 3
	v.add_child(gv)
	for tid in VehicleDefs.pack_ids():
		var d := VehicleDefs.get_def(tid)
		var b := FNUI.action_button(&"", d.display_name, d.role_note)
		b.pressed.connect(func() -> void: _say_text(spawn(tid)))
		gv.add_child(b)
	v.add_child(FNSectionHeader.new("Vehicle parts", "selected or last spawned vehicle"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FNUI.S3)
	v.add_child(row)
	_doors = FNUI.action_button(&"", "Doors", "open / follow the transport", true)
	_doors.toggled.connect(func(on: bool) -> void: _parts(func(vv: VehicleVisual) -> void: vv.doors_open = 1.0 if on else -1.0))
	row.add_child(_doors)
	_sweep = FNUI.action_button(&"", "Turret sweep", "turret, gun and RWS traverse", true)
	_sweep.toggled.connect(func(on: bool) -> void: sweep = on)
	row.add_child(_sweep)
	_rotor = FNUI.action_button(&"", "Rotor", "rotors at flight speed", true)
	_rotor.toggled.connect(func(on: bool) -> void: _parts(func(vv: VehicleVisual) -> void: vv.rotor_rate = 28.0 if on else NAN))
	row.add_child(_rotor)
	var drive := FNUI.action_button(&"", "Drive", "take the wheel (Tab leaves)")
	drive.pressed.connect(func() -> void:
		var id := target_vehicle()
		_say_text("" if id >= 0 and demo.game.drive(id) else "No vehicle to drive"))
	row.add_child(drive)
	_say = FNUI.label("", FNUI.LABEL, FNUI.WARN, "body")
	v.add_child(_say)


func _say_text(t: String) -> void:
	if _say:
		_say.text = t


## The soldier the armoury equips: the possessed one in first person, else the first selected soldier.
func target_soldier() -> UnitState:
	var id := demo.game.possessed_id if demo.game.mode == GameController.Mode.FPS else (demo.rts.first_selected_soldier() if demo.rts else -1)
	return demo.sim.state.get_unit(id) if id >= 0 else null


## Gives the target soldier the weapon's development role. Returns what happened (shown on the panel).
func give(wid: StringName, u: UnitState = null) -> String:
	if u == null:
		u = target_soldier()
	if u == null:
		return "Select a soldier first"
	if not demo.sim.combat.give_role(u, StringName("dev_" + String(wid))):
		return "No development role for %s" % wid
	var def := demo.sim.combat.weapon(wid)
	return "%s: %s" % [u.unit_name, def.display_name if def else String(wid)]


## Parks a vehicle of the type for the player's faction at p (default: the tactical camera's focus). Returns the text shown.
func spawn(type_id: StringName, p := Vector3.INF, yaw := NAN) -> String:
	var u := spawn_unit(type_id, p, yaw)
	return "%s parked" % u.unit_name if u else "No room there"


func spawn_unit(type_id: StringName, p := Vector3.INF, yaw := NAN) -> UnitState:
	var f := demo.sim.state.war.player_faction if demo.sim.state.war else 0
	if not p.is_finite():
		p = demo.rts_camera.focus
	if is_nan(yaw):
		yaw = demo.rts_camera.yaw
	p.y = demo.sim.vehicles.ground_at(p)
	var u := demo.sim.state.add_vehicle(type_id, f, p, yaw)
	if demo.sim.detail:
		demo.sim.detail.create_missing_proxies()
	last_vehicle = u.id
	return u


## The vehicle the part controls act on: the selected one, else the last spawned.
func target_vehicle() -> int:
	var sel: Array = demo.rts.selected_vehicles() if demo.rts else []
	if not sel.is_empty():
		return int(sel[0])
	return last_vehicle if demo.sim.state.get_unit(last_vehicle) else -1


func _parts(fn: Callable) -> void:
	var b := demo.sim.body_of(target_vehicle()) as VehicleBody
	if b and b.visual:
		fn.call(b.visual)
	else:
		_say_text("No vehicle in view")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = (event as InputEventKey).physical_keycode
	if k == KEY_F10 and demo.game.mode == GameController.Mode.RTS:
		visible = not visible
		get_viewport().set_input_as_handled()
	elif visible and k == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
	elif (k == KEY_BRACKETLEFT or k == KEY_BRACKETRIGHT) and demo.game.mode == GameController.Mode.FPS:
		var u := target_soldier()
		if u:
			var i := WEAPONS.find(StringName(String(u.role).trim_prefix("dev_")))
			i = posmod(i + (1 if k == KEY_BRACKETRIGHT else -1), WEAPONS.size()) if i >= 0 else 0
			# the first-person HUD's weapon readout shows the new weapon
			print("DevArmoury: ", give(WEAPONS[i], u))
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if demo.game.mode != GameController.Mode.RTS:
		visible = false
	if not sweep:
		return
	_t += delta
	var b := demo.sim.body_of(target_vehicle()) as VehicleBody
	if b and b.visual:
		b.visual.turret_yaw = sin(_t * 0.5) * 1.6
		b.visual.gun_pitch = 0.06 + sin(_t * 0.8) * 0.1
		b.visual.rws_yaw = sin(_t * 0.7 + 1.0) * 2.2
		b.visual.rws_pitch = 0.1 + sin(_t * 1.1) * 0.25
