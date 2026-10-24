## The logistics panel of the tactical view (LOGISTICS-01 / BASE-02, UI-01C kit): what the player sees and
## does with a selected vehicle or facility. Not a management screen: one panel, top right, shown only
## while a vehicle or a facility (click a building) is selected.
##
##   vehicle   type, status, fuel / condition / cargo meters, passengers, current job, convoy, nearest
##             depot; actions: take the wheel, stop, unload passengers, cancel the job, load / refuel at
##             the nearest depot, deliver / unload / repair at a chosen depot, repeat a delivery
##   facility  base (stock, facilities, vehicles, soldiers), this store, queue; barracks: recruit a squad;
##             vehicle depot: acquire a truck or APC; stores: load / unload / refuel a selected vehicle,
##             resupply selected squads
##
## Every button calls the same functions the tests and the automation use (LogisticsSim, BaseSim,
## VehicleSim); the panel keeps no state of its own besides which item / quantity / destination is
## chosen for the next order.
class_name LogisticsPanel
extends FNPanel

const FRACTIONS := [0.25, 0.5, 1.0]
const ITEM_ICONS := {Inventory.AMMO: &"ammo", Inventory.FUEL: &"fuel", Inventory.SUPPLIES: &"cargo"}
const WIDTH := 262.0

var rts: RTSController
var sim: WorldSim
var game: GameController
## GAMEPLAY-01B: cancelling a construction site goes through the construction controller (refund rule).
var construction: ConstructionController
var enabled := true

var _icon: TextureRect
var _title: Label
var _subtitle: Label
var _state: FNStatusIndicator
var _meters: VBoxContainer
var _fields: VBoxContainer
var _actions: VBoxContainer
var _status: Label
var _sig := ""
var _data_sig := ""
var _timer := 0.0
var _item := Inventory.AMMO
var _frac := 2
var _dest := -1
var _repeat := false
var _status_until := 0.0
var _dest_box: OptionButton


func _init() -> void:
	super(FNUI.INFO, FNUI.S4)


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", FNUI.S3)
	add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", FNUI.S3)
	box.add_child(head)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(32, 28)
	frame.add_theme_stylebox_override("panel", FNUI.box(Color(FNUI.INFO, 0.14), Color(FNUI.INFO, 0.7), 1, 2, 0))
	head.add_child(frame)
	_icon = FNIcons.rect(&"vehicle", FNUI.ICON_L, FNUI.INFO.lightened(0.3))
	frame.add_child(_icon)
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", -1)
	head.add_child(names)
	_title = FNUI.label("", FNUI.TITLE, FNUI.INK, "title")
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(_title)
	_subtitle = FNUI.label("", FNUI.CAPTION, FNUI.INK_2, "caps")
	_subtitle.clip_text = true
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(_subtitle)
	_state = FNStatusIndicator.new(FNUI.ICON_S, FNUI.LABEL)
	box.add_child(_state)
	_meters = VBoxContainer.new()
	_meters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meters.add_theme_constant_override("separation", 1)
	box.add_child(_meters)
	_fields = VBoxContainer.new()
	_fields.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fields.add_theme_constant_override("separation", 1)
	box.add_child(_fields)
	var rule := ColorRect.new()
	rule.color = Color(FNUI.LINE, 0.9)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", FNUI.S2)
	box.add_child(_actions)
	_status = FNUI.label("", FNUI.CAPTION + 1, FNUI.ARMED, "caps")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(WIDTH - 2 * FNUI.S4, 0)
	box.add_child(_status)
	visible = false


func _process(delta: float) -> void:
	if sim == null or rts == null:
		return
	var in_rts := game != null and game.mode == GameController.Mode.RTS and enabled
	var vid := rts.first_selected_vehicle() if in_rts else -1
	var sid: int = rts.selected_structure if in_rts else -1
	visible = vid > 0 or (sid > 0 and sim.logistics.structure(sid) != null)
	if not visible:
		return
	position = Vector2(get_viewport_rect().size.x - size.x - FNUI.EDGE, FNUI.EDGE)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.3
	_refresh(vid, sid)
	_status.visible = Time.get_ticks_msec() / 1000.0 < _status_until and _status.text != ""
	size = Vector2.ZERO


func _say(text: String) -> void:
	_status.text = text
	_status_until = Time.get_ticks_msec() / 1000.0 + 6.0
	_sig = ""


func _meter(caption: String, v: float, text: String, col: Color) -> void:
	var m := FNMeter.new(caption, col)
	m.custom_minimum_size = Vector2(WIDTH - 2 * FNUI.S4, 11)
	m.value_w = 52.0
	m.set_value(v, text, col)
	_meters.add_child(m)


func _field(caption: String, value: String, icon_name := &"", col := FNUI.INK) -> void:
	var f := FNField.new(caption, value, icon_name, 58.0)
	f.set_value(value, col)
	_fields.add_child(f)


func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _refresh(vid: int, sid: int) -> void:
	var lg := sim.logistics
	# A facility clicked last wins: its panel offers the orders for the selected vehicle / squads.
	if vid > 0 and sid < 0:
		var u := sim.state.get_unit(vid)
		if u == null or u.veh == null:
			return
		var v := u.veh
		var d := v.def()
		accent = FNUI.INFO
		_icon.texture = FNIcons.texture(&"vehicle", FNUI.ICON_L)
		_title.text = u.unit_name
		_subtitle.text = d.display_name
		var col := FNUI.OK if v.reason == "" else FNUI.ALERT
		_state.set_status(&"moving" if u.order == UnitState.Order.MOVE else &"idle", v.status_name() + ((" · " + v.reason) if v.reason != "" else ""), col)
		var near := lg.nearest_store(u.position, u.faction)
		if near and Vector2(near.position.x - u.position.x, near.position.z - u.position.z).length() >= 400.0:
			near = null
		var dsig := "%d|%d|%d|%s|%s|%s|%s" % [roundi(v.fuel), roundi(u.health), roundi(v.cargo.total()), v.status_name(), str(v.job.get("stage", "")),
			str(v.occupants.size()), str(near.id if near else -1)]
		if dsig != _data_sig:
			_data_sig = dsig
			_clear(_meters)
			_clear(_fields)
			var ff := v.fuel / maxf(d.fuel_capacity, 1.0)
			_meter("Fuel", ff, "%d l" % roundi(v.fuel), FNUI.INFO if ff >= 0.25 else FNUI.WARN)
			var hf := u.health / maxf(u.max_health, 1.0)
			_meter("Condition", hf, "%d %%" % roundi(hf * 100.0), FNUI.OK if hf >= 0.5 else FNUI.DANGER)
			_meter("Cargo", v.cargo.total() / maxf(v.cargo.capacity, 1.0), "%d / %d" % [roundi(v.cargo.total()), roundi(v.cargo.capacity)], FNUI.NEUTRAL)
			if v.cargo.total() > 0.0:
				_field("Carrying", v.cargo.summary(), &"cargo")
			if not v.occupants.is_empty() or v.phase != VehicleState.Phase.NONE:
				_field("Aboard", sim.vehicles.transport.describe(u), &"soldiers")
			if not v.job.is_empty():
				_field("Job", lg.describe_job(u), &"route", FNUI.ARMED)
			elif u.order == UnitState.Order.MOVE:
				_field("Route", "%.1f km to go" % (v.route_remaining_m() / 1000.0), &"route")
			if v.convoy_id >= 0:
				_field("Convoy", sim.vehicles.convoy.describe(v.convoy_id), &"vehicle")
			if near:
				_field("Depot", "%s · %s" % [lg.store_name(near), near.inventory.summary()], &"logistics")
		var sig := "v%d|%s|%s|%d|%s|%s|%d|%s" % [vid, str(v.job.get("stage", "")), v.status_name(), _frac, _item, str(_repeat), _dest, str(near.id if near else -1)]
		if sig != _sig:
			_sig = sig
			_build_vehicle_actions(u, near)
		return
	var s := lg.structure(sid)
	if s == null:
		return
	if s.is_site():
		_refresh_site(s)
		return
	accent = FNUI.OK
	var kind := FacilityDefs.kind_of(s.type_id)
	_icon.texture = FNIcons.texture({&"barracks": &"building", &"vehicle": &"vehicle", &"hq": &"base", &"fuel": &"fuel", &"ammo": &"ammo"}.get(kind, &"logistics"), FNUI.ICON_L)
	_title.text = FacilityDefs.display_name(s.type_id)
	var b := lg.bases.summary(s.base_id) if s.base_id >= 0 else {}
	_subtitle.text = ("%s · %s" % [b.name, b.kind]) if not b.is_empty() else "Facility #%d" % s.id
	var queue: Array = s.facility.get("queue", [])
	if queue.is_empty():
		_state.set_status(&"check", "Operational", FNUI.OK)
	else:
		_state.set_status(&"clock", "%s · %d s left" % [queue[0].get("what", "queued"), maxi(0, roundi(float(queue[0].done) - sim.state.time))], FNUI.ARMED)
	var dsig2 := "%d|%s|%s|%d" % [sid, str(b.get("stock", {})), str(s.inventory.total() if s.inventory else -1), queue.size()]
	if dsig2 != _data_sig:
		_data_sig = dsig2
		_clear(_meters)
		_clear(_fields)
		if s.inventory:
			_meter("This store", s.inventory.total() / maxf(s.inventory.capacity, 1.0), "%d / %d" % [roundi(s.inventory.total()), roundi(s.inventory.capacity)], FNUI.NEUTRAL)
		if not b.is_empty():
			_field("Ammo", "%d kg" % roundi(b.stock.ammo), &"ammo")
			_field("Fuel", "%d l" % roundi(b.stock.fuel), &"fuel")
			_field("Supplies", "%d kg" % roundi(b.stock.supplies), &"cargo")
			_field("Base", "%d facilities · %d vehicles · %d soldiers near" % [b.facilities.size(), b.vehicles.size(), b.soldiers], &"base")
		for q: Dictionary in queue.slice(1):
			_field("Queued", "%s · %d s" % [q.get("what", "queued"), maxi(0, roundi(float(q.done) - sim.state.time))], &"clock", FNUI.ARMED)
		if kind == &"vehicle":
			var st: Dictionary = s.facility.get("stock", {})
			var parts := []
			for t in st:
				parts.append("%s x%d" % [VehicleDefs.get_def(StringName(t)).short_name, int(st[t])])
			_field("Available", ", ".join(parts), &"vehicle")
	var sig2 := "s%d|%d|%d|%s|%s|%d" % [sid, queue.size(), rts.selected.size(), str(rts.first_selected_vehicle()), _item, _frac]
	if sig2 != _sig:
		_sig = sig2
		_build_facility_actions(s)


## GAMEPLAY-01B: a construction site - progress, who works on it or why nobody does, what it cost; actions: the selected
## squads build it, cancel it (full refund).
func _refresh_site(s: StructureState) -> void:
	accent = FNUI.ARMED
	var def := StructureCatalog.get_def(s.type_id)
	var what := def.display_name if def else String(s.type_id)
	_icon.texture = FNIcons.texture(&"build", FNUI.ICON_L)
	_title.text = what
	_subtitle.text = "Construction site"
	var workers := int(s.site.get("workers", 0))
	var why := String(s.site.get("why", ""))
	if workers > 0:
		_state.set_status(&"build", "%d soldiers working" % workers, FNUI.OK)
	else:
		_state.set_status(&"clock", why if why != "" else "Waiting for workers", FNUI.WARN)
	var builders: Array[String] = []
	for sq: SquadState in sim.state.all_squads():
		if sq.tactic == SquadState.Tactic.BUILD and sq.tactic_site == s.id:
			builders.append(sq.squad_name)
	var left := (float(s.site.need) - float(s.site.work)) / maxf(float(workers), 1.0)
	var dsig := "site%d|%d|%d|%s|%s" % [s.id, roundi(s.site_progress() * 100.0), workers, why, str(builders)]
	if dsig != _data_sig:
		_data_sig = dsig
		_clear(_meters)
		_clear(_fields)
		_meter("Progress", s.site_progress(), "%d %%" % roundi(s.site_progress() * 100.0), FNUI.OK if workers > 0 else FNUI.WARN)
		_field("Builders", ", ".join(builders) if not builders.is_empty() else "none", &"soldiers")
		_field("Time left", ("about %d s with %d soldiers" % [roundi(left), workers]) if workers > 0 else "%d soldier-seconds of work" % roundi(float(s.site.need) - float(s.site.work)), &"clock")
		var cost := BuildCosts.cost_of(def, s.built_count() if s.is_line() else 1)
		if not (s.site.get("paid", {}) as Dictionary).is_empty():
			_field("Paid", "%d kg supplies (refunded if cancelled)" % roundi(cost), &"cargo")
	var sig := "site%d|%d" % [s.id, rts.selected_squads().size()]
	if sig != _sig:
		_sig = sig
		_clear(_actions)
		var sid := s.id
		if not rts.selected_squads().is_empty():
			_row([_button(&"build", "Build with selected squads", func() -> void:
				var r := sim.tactics.order_build(rts.selected_squads(), sid)
				_say(r.text))])
		else:
			_caption("Select a squad and right-click the site to build it")
		if construction:
			_row([_button(&"demolish", "Cancel construction (refund)", func() -> void:
				var back := construction.cancel_site(sid)
				_say(construction.message if back >= 0.0 else "Cannot cancel")
				rts.selected_structure = -1)])


func _button(icon_name: StringName, text: String, fn: Callable, tip := "") -> Button:
	var bt := FNUI.action_button(icon_name, text, tip)
	bt.pressed.connect(fn)
	return bt


func _row(buttons: Array) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", FNUI.S2)
	for b in buttons:
		if b is Button:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	_actions.add_child(h)


func _caption(text: String) -> void:
	_actions.add_child(FNUI.label(text, FNUI.CAPTION - 1, FNUI.INK_3, "caps"))


## Ammo / fuel / supplies and the share of the capacity, as a segmented choice.
func _item_buttons() -> Array:
	var out := []
	for it in Inventory.ITEMS:
		var bt := FNUI.action_button(ITEM_ICONS.get(it, &"cargo"), Inventory.NAMES[it], "Cargo to move", true)
		bt.set_pressed_no_signal(it == _item)
		bt.pressed.connect(func() -> void:
			_item = it
			_sig = "")
		out.append(bt)
	var fr := FNUI.action_button(&"", "%d %%" % roundi(FRACTIONS[_frac] * 100.0), "Click to change how much of the cargo capacity to move")
	fr.alignment = HORIZONTAL_ALIGNMENT_CENTER
	fr.pressed.connect(func() -> void:
		_frac = (_frac + 1) % FRACTIONS.size()
		_sig = "")
	out.append(fr)
	return out


func _build_vehicle_actions(u: UnitState, near: StructureState) -> void:
	_clear(_actions)
	_dest_box = null
	var lg := sim.logistics
	var v := u.veh
	var cmd := HBoxContainer.new()
	cmd.add_theme_constant_override("separation", FNUI.S2)
	for e: Array in [[&"drive", "Drive", "P", "Take the wheel", func() -> void: rts.drive_requested.emit(u.id)],
			[&"stop", "Stop", "H", "Stop and cancel the job", func() -> void:
				sim.vehicles.halt(u.id)
				sim.logistics.cancel_job(u.id)
				_say("Stopped")],
			[&"unload", "Unload", "U", "Passengers out", func() -> void: sim.vehicles.transport.unload(u.id)]]:
		var b := FNCommandButton.new(e[0], e[1], e[2], e[3])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(e[4])
		cmd.add_child(b)
	_actions.add_child(cmd)
	if not v.job.is_empty():
		_row([_button(&"blocked", "Cancel job", func() -> void:
			lg.cancel_job(u.id)
			_say("Job cancelled; cargo stays aboard"))])
	_caption("Cargo order")
	_row(_item_buttons())
	var stores := lg.stores(u.faction)
	var qty: float = v.cargo.capacity * float(FRACTIONS[_frac])
	if near:
		_row([_button(&"cargo", "Load here", func() -> void:
				var r := lg.order_load(u.id, near.id, _item, qty)
				_say("Loading %s at %s" % [Inventory.NAMES[_item], lg.store_name(near)] if r.ok else r.reason),
			"Load at the nearest depot (%s)" % lg.store_name(near)),
			_button(&"fuel", "Refuel here", func() -> void:
				var r := lg.order_refuel(u.id, near.id)
				_say("Refuelling" if r.ok else r.reason))])
	if not stores.is_empty():
		_dest_box = OptionButton.new()
		_dest_box.focus_mode = Control.FOCUS_NONE
		_dest_box.add_theme_font_size_override("font_size", FNUI.CAPTION + 1)
		for st in ["normal", "hover", "pressed"]:
			_dest_box.add_theme_stylebox_override(st, FNUI.state_style(StringName(st), FNUI.S2))
		var chosen := 0
		for i in stores.size():
			_dest_box.add_item(lg.store_name(stores[i]), stores[i].id)
			if stores[i].id == _dest:
				chosen = i
		_dest_box.select(chosen)
		_dest = _dest_box.get_item_id(chosen)
		_dest_box.item_selected.connect(func(i: int) -> void:
			_dest = _dest_box.get_item_id(i)
			_sig = "")
		_dest_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var dl := FNUI.label("Depot", FNUI.CAPTION, FNUI.INK_3, "caps")
		dl.custom_minimum_size = Vector2(40, 0)
		_row([dl, _dest_box])
	var dest_id := _dest
	if dest_id > 0:
		_row([_button(&"route", "Deliver", func() -> void:
				var src := near.id if near else -1
				var r := lg.order_delivery(u.id, src, dest_id, _item, qty, _repeat) if src > 0 else {"ok": false, "reason": "No depot nearby to load from"}
				_say("Delivering %s" % Inventory.NAMES[_item] if r.ok else r.reason),
				"Load at the nearest depot, drive to the chosen depot and unload"),
			_button(&"unload", "Unload", func() -> void:
				var r := lg.order_unload(u.id, dest_id)
				_say("Unloading at the chosen depot" if r.ok else r.reason), "Unload at the chosen depot"),
			_button(&"repair", "Repair", func() -> void:
				var r := lg.order_repair(u.id, dest_id)
				_say("Repairing" if r.ok else r.reason), "Repair at the chosen depot")])
		var cb := FNUI.action_button(&"rotate", "Repeat the delivery", "Keep running the delivery", true)
		cb.set_pressed_no_signal(_repeat)
		cb.toggled.connect(func(on: bool) -> void: _repeat = on)
		_actions.add_child(cb)


func _build_facility_actions(s: StructureState) -> void:
	_clear(_actions)
	_dest_box = null
	var lg := sim.logistics
	var kind := FacilityDefs.kind_of(s.type_id)
	if kind == &"barracks":
		_row([_button(&"recruit", "Recruit a squad (%s)" % lg.bases.cost_text(BaseSim.RECRUIT_COST), func() -> void:
			var r := lg.bases.recruit(s.id)
			_say("Training a squad" if r.ok else r.reason))])
	if kind == &"vehicle":
		for t in BaseSim.VEHICLES:
			var tid: StringName = t
			var dn := VehicleDefs.get_def(tid).display_name
			_row([_button(&"vehicle", "Acquire %s (%s)" % [dn, lg.bases.cost_text(BaseSim.VEHICLES[tid].cost)], func() -> void:
				var r := lg.bases.acquire_vehicle(s.id, tid)
				_say("Preparing a %s" % dn if r.ok else r.reason))])
	if not s.facility.get("queue", []).is_empty():
		_row([_button(&"blocked", "Cancel first in queue (refund)", func() -> void:
			lg.bases.cancel_queue(s.id, 0)
			_say("Cancelled"))])
	if s.inventory:
		var vid := rts.first_selected_vehicle()
		if vid > 0:
			var u := sim.state.get_unit(vid)
			_caption("Selected vehicle: %s" % u.unit_name)
			_row(_item_buttons())
			var qty: float = u.veh.cargo.capacity * float(FRACTIONS[_frac])
			_row([_button(&"cargo", "Load", func() -> void:
					var r := lg.order_load(vid, s.id, _item, qty)
					_say("%s drives here to load %s" % [u.unit_name, Inventory.NAMES[_item]] if r.ok else r.reason), "Load the vehicle here"),
				_button(&"unload", "Unload", func() -> void:
					var r := lg.order_unload(vid, s.id)
					_say("%s drives here to unload" % u.unit_name if r.ok else r.reason), "Unload it here"),
				_button(&"fuel", "Refuel", func() -> void:
					var r := lg.order_refuel(vid, s.id)
					_say("Refuelling" if r.ok else r.reason), "Refuel it here")])
		var squads := rts.selected_squads()
		if not squads.is_empty():
			_row([_button(&"ammo", "Resupply the selected squads", func() -> void:
				var r := lg.order_resupply(squads, "s%d" % s.id)
				_say("The squads go to resupply" if r.ok else r.reason))])
	if _actions.get_child_count() == 0:
		_caption("No orders for this facility")
