## The logistics panel of the tactical view (LOGISTICS-01 / BASE-02): what the player sees and
## does with a selected vehicle or facility. Not a management screen: one panel, shown only
## while a vehicle or a facility (click a building) is selected.
##
##   vehicle   status, fuel, health, passengers, cargo, current job; buttons: take the wheel,
##             stop, unload passengers, load / unload / deliver / refuel / repair at depots,
##             repeat a delivery, cancel the job
##   facility  base, inventory, queue; barracks: recruit a squad; vehicle depot: acquire a
##             truck or APC; stores: load a selected vehicle, resupply a selected squad
##
## Every button calls the same functions the tests and the automation use (LogisticsSim,
## BaseSim, VehicleSim); the panel keeps no state of its own besides which item / quantity /
## destination is chosen for the next order.
class_name LogisticsPanel
extends PanelContainer

const FRACTIONS := [0.25, 0.5, 1.0]

var rts: RTSController
var sim: WorldSim
var game: GameController
var enabled := true

var _title: Label
var _body: RichTextLabel
var _actions: VBoxContainer
var _status: Label
var _sig := ""
var _timer := 0.0
var _item := Inventory.AMMO
var _frac := 2
var _dest := -1
var _repeat := false
var _status_until := 0.0
var _dest_box: OptionButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(380, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.62)
	sb.border_width_left = 3
	sb.border_color = Color(0.45, 0.7, 1.0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	_title.modulate = Color(0.75, 0.9, 1.0)
	box.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.add_theme_font_size_override("normal_font_size", 13)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_body)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 3)
	box.add_child(_actions)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.modulate = Color(1.0, 0.9, 0.5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	position = Vector2(get_viewport().get_visible_rect().size.x - size.x - 12.0, 84.0)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.3
	_refresh(vid, sid)
	_status.text = _status.text if Time.get_ticks_msec() / 1000.0 < _status_until else ""


func _say(text: String) -> void:
	_status.text = text
	_status_until = Time.get_ticks_msec() / 1000.0 + 6.0
	_sig = ""


func _refresh(vid: int, sid: int) -> void:
	var lg := sim.logistics
	if vid > 0:
		var u := sim.state.get_unit(vid)
		if u == null or u.veh == null:
			return
		_title.text = "VEHICLE  %s" % u.unit_name
		var v := u.veh
		var d := v.def()
		var lines: Array[String] = []
		lines.append("[b]%s[/b] · %s%s" % [d.display_name, v.status_name(), (" - " + v.reason) if v.reason != "" else ""])
		lines.append("Fuel %d / %d l · condition %d / %d" % [roundi(v.fuel), roundi(d.fuel_capacity), roundi(u.health), roundi(u.max_health)])
		lines.append("Cargo: %s (%d / %d)" % [v.cargo.summary(), roundi(v.cargo.total()), roundi(v.cargo.capacity)])
		if not v.occupants.is_empty() or v.phase != VehicleState.Phase.NONE:
			lines.append("Passengers: " + sim.vehicles.transport.describe(u))
		if not v.job.is_empty():
			lines.append("[color=#ffe070]Job: %s[/color]" % lg.describe_job(u))
		elif u.order == UnitState.Order.MOVE:
			lines.append("Driving %.1f km to go" % (v.route_remaining_m() / 1000.0))
		if v.convoy_id >= 0:
			lines.append(sim.vehicles.convoy.describe(v.convoy_id))
		var near := lg.nearest_store(u.position, u.faction)
		var near_txt := ""
		if near and Vector2(near.position.x - u.position.x, near.position.z - u.position.z).length() < 400.0:
			near_txt = "Nearest depot: %s (%s)" % [lg.store_name(near), near.inventory.summary()]
			lines.append(near_txt)
		_body.text = "\n".join(lines)
		var sig := "v%d|%s|%s|%d|%d|%s|%d|%s" % [vid, str(v.job.get("stage", "")), v.status_name(), _frac, _item.hash(), str(_repeat), _dest, str(near.id if near else -1)]
		if sig != _sig:
			_sig = sig
			_build_vehicle_actions(u, near)
		return
	var s := lg.structure(sid)
	_title.text = "%s  #%d" % [FacilityDefs.display_name(s.type_id).to_upper(), s.id]
	var b := lg.bases.summary(s.base_id) if s.base_id >= 0 else {}
	var lines2: Array[String] = []
	if not b.is_empty():
		lines2.append("[b]%s[/b] (%s)" % [b.name, b.kind])
		lines2.append("Base stock: ammo %d kg · fuel %d l · supplies %d kg" % [roundi(b.stock.ammo), roundi(b.stock.fuel), roundi(b.stock.supplies)])
		lines2.append("%d facilities · %d vehicles · %d soldiers near" % [b.facilities.size(), b.vehicles.size(), b.soldiers])
	if s.inventory:
		lines2.append("This store: %s (%d / %d)" % [s.inventory.summary(), roundi(s.inventory.total()), roundi(s.inventory.capacity)])
	for q: Dictionary in s.facility.get("queue", []):
		lines2.append("[color=#ffe070]%s - %d s left[/color]" % [q.get("what", "queued"), maxi(0, roundi(float(q.done) - sim.state.time))])
	if FacilityDefs.kind_of(s.type_id) == &"vehicle":
		var st: Dictionary = s.facility.get("stock", {})
		var parts := []
		for t in st:
			parts.append("%s x%d" % [VehicleDefs.get_def(StringName(t)).short_name, int(st[t])])
		lines2.append("Vehicles available: %s" % ", ".join(parts))
	_body.text = "\n".join(lines2)
	var sig2 := "s%d|%d|%d|%s|%s|%d" % [sid, s.facility.get("queue", []).size(), rts.selected.size(), str(rts.first_selected_vehicle()), _item, _frac]
	if sig2 != _sig:
		_sig = sig2
		_build_facility_actions(s)


func _clear_actions() -> void:
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	_dest_box = null


func _button(text: String, fn: Callable, tip := "") -> Button:
	var bt := Button.new()
	bt.text = text
	bt.tooltip_text = tip
	bt.add_theme_font_size_override("font_size", 12)
	bt.pressed.connect(fn)
	return bt


func _row(buttons: Array) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	for b in buttons:
		h.add_child(b)
	_actions.add_child(h)


func _item_buttons() -> Array:
	var out := []
	for it in Inventory.ITEMS:
		var bt := _button(("[%s]" if it == _item else "%s") % Inventory.NAMES[it], func() -> void:
			_item = it
			_sig = "")
		out.append(bt)
	var fr := _button("%d %%" % roundi(FRACTIONS[_frac] * 100.0), func() -> void:
		_frac = (_frac + 1) % FRACTIONS.size()
		_sig = "", "Click to change how much of the cargo capacity to move")
	out.append(fr)
	return out


func _build_vehicle_actions(u: UnitState, near: StructureState) -> void:
	_clear_actions()
	var lg := sim.logistics
	var v := u.veh
	_row([_button("Take the wheel (P)", func() -> void: rts.drive_requested.emit(u.id)),
		_button("Stop (H)", func() -> void:
			sim.vehicles.halt(u.id)
			sim.logistics.cancel_job(u.id)
			_say("Stopped")),
		_button("Passengers out (U)", func() -> void: sim.vehicles.transport.unload(u.id))])
	if not v.job.is_empty():
		_row([_button("Cancel job", func() -> void:
			lg.cancel_job(u.id)
			_say("Job cancelled; cargo stays aboard"))])
	_row(_item_buttons())
	var stores := lg.stores(u.faction)
	if not stores.is_empty():
		_dest_box = OptionButton.new()
		_dest_box.add_theme_font_size_override("font_size", 12)
		var idx := 0
		var chosen := 0
		for i in stores.size():
			_dest_box.add_item(lg.store_name(stores[i]), stores[i].id)
			if stores[i].id == _dest:
				chosen = i
			idx += 1
		_dest_box.select(chosen)
		_dest = _dest_box.get_item_id(chosen)
		_dest_box.item_selected.connect(func(i: int) -> void:
			_dest = _dest_box.get_item_id(i)
			_sig = "")
		_row([Label.new(), _dest_box])
		(_actions.get_child(_actions.get_child_count() - 1).get_child(0) as Label).text = "Depot:"
	var dest_id := _dest
	var qty: float = v.cargo.capacity * float(FRACTIONS[_frac])
	if near:
		_row([_button("Load %s here" % Inventory.NAMES[_item], func() -> void:
				var r := lg.order_load(u.id, near.id, _item, qty)
				_say("Loading %s at %s" % [Inventory.NAMES[_item], lg.store_name(near)] if r.ok else r.reason),
			"Load at the nearest depot (%s)" % lg.store_name(near)),
			_button("Refuel here", func() -> void:
				var r := lg.order_refuel(u.id, near.id)
				_say("Refuelling" if r.ok else r.reason))])
	if dest_id > 0:
		_row([_button("Deliver there", func() -> void:
				var src := near.id if near else -1
				var r := lg.order_delivery(u.id, src, dest_id, _item, qty, _repeat) if src > 0 else {"ok": false, "reason": "No depot nearby to load from"}
				_say("Delivering %s" % Inventory.NAMES[_item] if r.ok else r.reason),
				"Load at the nearest depot, drive to the chosen depot and unload"),
			_button("Unload there", func() -> void:
				var r := lg.order_unload(u.id, dest_id)
				_say("Unloading at the chosen depot" if r.ok else r.reason)),
			_button("Repair there", func() -> void:
				var r := lg.order_repair(u.id, dest_id)
				_say("Repairing" if r.ok else r.reason))])
		var cb := CheckButton.new()
		cb.text = "Repeat the delivery"
		cb.button_pressed = _repeat
		cb.add_theme_font_size_override("font_size", 12)
		cb.toggled.connect(func(on: bool) -> void: _repeat = on)
		_actions.add_child(cb)


func _build_facility_actions(s: StructureState) -> void:
	_clear_actions()
	var lg := sim.logistics
	var kind := FacilityDefs.kind_of(s.type_id)
	if kind == &"barracks":
		_row([_button("Recruit a squad (%s)" % lg.bases.cost_text(BaseSim.RECRUIT_COST), func() -> void:
			var r := lg.bases.recruit(s.id)
			_say("Training a squad" if r.ok else r.reason))])
	if kind == &"vehicle":
		for t in BaseSim.VEHICLES:
			var tid: StringName = t
			var dn := VehicleDefs.get_def(tid).display_name
			_row([_button("Acquire %s (%s)" % [dn, lg.bases.cost_text(BaseSim.VEHICLES[tid].cost)], func() -> void:
				var r := lg.bases.acquire_vehicle(s.id, tid)
				_say("Preparing a %s" % dn if r.ok else r.reason))])
	if not s.facility.get("queue", []).is_empty():
		_row([_button("Cancel the first in the queue (refund)", func() -> void:
			lg.bases.cancel_queue(s.id, 0)
			_say("Cancelled"))])
	if s.inventory:
		var vid := rts.first_selected_vehicle()
		if vid > 0:
			var u := sim.state.get_unit(vid)
			_row(_item_buttons())
			var qty: float = u.veh.cargo.capacity * float(FRACTIONS[_frac])
			_row([_button("Load the vehicle here", func() -> void:
					var r := lg.order_load(vid, s.id, _item, qty)
					_say("%s drives here to load %s" % [u.unit_name, Inventory.NAMES[_item]] if r.ok else r.reason)),
				_button("Unload it here", func() -> void:
					var r := lg.order_unload(vid, s.id)
					_say("%s drives here to unload" % u.unit_name if r.ok else r.reason)),
				_button("Refuel it here", func() -> void:
					var r := lg.order_refuel(vid, s.id)
					_say("Refuelling" if r.ok else r.reason))])
		var squads := rts.selected_squads()
		if not squads.is_empty():
			_row([_button("Resupply the selected squads here", func() -> void:
				var r := lg.order_resupply(squads, "s%d" % s.id)
				_say("The squads go to resupply" if r.ok else r.reason))])
