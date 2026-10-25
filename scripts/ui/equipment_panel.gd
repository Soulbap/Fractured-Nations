## GAMEPLAY-04D/04F squad equipment screen, part of GameHUD (the EQUIP button of the command panel): the selected squad's
## soldiers with role, weapon and ammunition, where the squad stands (at a base: armoury and procurement; in the field: only
## its cargo), its cargo, the faction's armoury and registered discoveries; per soldier a choice of role, each choice saying
## how it would be met - ready (cargo / armoury), procured (price), locked (what unlocks it) or unavailable (why). Every
## change goes through SquadEquipment.equip; the screen keeps only the open squad.
class_name EquipmentPanel
extends Control

const W := 780.0

var hud: GameHUD
var squad_id := -1
var _panel: FNPanel
var _title: Label
var _where: Label
var _stores: Label
var _rows: VBoxContainer
var _say: Label
var _sig := ""
var _timer := 0.0
var _say_until := 0.0
## Tests read these: unit id -> OptionButton and its option dicts.
var pickers := {}
var choices := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = FNUI.theme()
	visible = false
	_panel = FNPanel.new(FNUI.OK, FNUI.S5)
	_panel.custom_minimum_size = Vector2(W, 0)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", FNUI.S4)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", FNUI.S3)
	v.add_child(head)
	head.add_child(FNIcons.rect(&"equipment", FNUI.ICON_M, FNUI.OK))
	_title = FNUI.label("Equipment", FNUI.HEADLINE, FNUI.INK, "caps")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := FNUI.action_button(&"blocked", "Close", "Close the equipment screen (Esc)")
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	_where = FNUI.label("", FNUI.LABEL, FNUI.INK, "body")
	_where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_where)
	_stores = FNUI.label("", FNUI.CAPTION + 1, FNUI.INK_2, "body")
	_stores.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stores.custom_minimum_size = Vector2(W - 30.0, 0)
	v.add_child(_stores)
	v.add_child(FNSectionHeader.new("Soldiers", "role · weapon · ammunition"))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", FNUI.S2)
	v.add_child(_rows)
	_say = FNUI.label("", FNUI.LABEL, FNUI.WARN, "body")
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_say)


func _eq() -> SquadEquipment:
	return hud.war_sim.equip if hud and hud.war_sim else null


func open_for(sid: int) -> void:
	if _eq() == null or sid < 0:
		return
	squad_id = sid
	_sig = ""
	visible = true
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	var sq := hud.sim.state.get_squad(squad_id) if hud else null
	if sq == null or sq.members.is_empty() or hud.game == null or hud.game.mode != GameController.Mode.RTS:
		visible = false
		return
	var vp := get_viewport_rect().size
	_panel.position = Vector2(roundf((vp.x - _panel.size.x) * 0.5), roundf(maxf((vp.y - _panel.size.y) * 0.5 - 40.0, FNUI.EDGE + 40.0)))
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.5
		_refresh()
	if Time.get_ticks_msec() / 1000.0 > _say_until:
		_say.text = ""


func _refresh() -> void:
	var eq := _eq()
	var sq := hud.sim.state.get_squad(squad_id)
	if eq == null or sq == null:
		return
	var f := hud.war_sim.war.faction(sq.faction)
	_title.text = "Equipment · %s" % sq.squad_name
	var base := eq.at_base(sq)
	if base >= 0:
		_where.text = "At %s: weapons from the squad's cargo, the armoury, or procured here (supplies and ammunition)." % hud.sim.state.construction.bases[base].name
		_where.add_theme_color_override("font_color", FNUI.OK)
	else:
		_where.text = "In the field: only weapons the squad carries can be issued. Armoury and procurement are at a base with a Supply Depot."
		_where.add_theme_color_override("font_color", FNUI.WARN)
	_stores.text = "Cargo (%d/%d): %s\nArmoury: %s\nRegistered types: %s" % [SquadEquipment.cargo_count(sq), SquadEquipment.cargo_cap(sq), _items(sq.cargo),
		_items(f.armory if f else {}), ", ".join((f.discovered if f else []).map(func(w: String) -> String: return _wname(StringName(w))))]
	# Rows are rebuilt only when something they show changed (an open drop-down is not torn down).
	var sig := str(base) + str(sq.cargo) + str(f.armory if f else {}) + str(f.discovered if f else [])
	for uid in sq.members:
		var u := hud.sim.state.get_unit(uid)
		if u:
			sig += "%d:%s:%s:%d|" % [uid, u.role, u.weapon_id, u.alive]
	sig += str(hud.sim.logistics.bases.faction_stock(sq.faction))
	if sig == _sig:
		return
	for p: OptionButton in pickers.values():
		if p.get_popup().visible:
			return
	_sig = sig
	for c in _rows.get_children():
		c.queue_free()
	pickers.clear()
	choices.clear()
	for uid in sq.members:
		var u := hud.sim.state.get_unit(uid)
		if u == null or not u.alive:
			continue
		_rows.add_child(_row(sq, u))


func _items(d: Dictionary) -> String:
	if d.is_empty():
		return "-"
	var parts: Array[String] = []
	for k in d:
		parts.append("%d x %s" % [int(d[k]), _wname(StringName(k))])
	return ", ".join(parts)


func _wname(id: StringName) -> String:
	var wd := hud.sim.combat.weapon(id)
	return wd.display_name if wd else String(id)


func _row(sq: SquadState, u: UnitState) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", FNUI.S4)
	var name := FNUI.label(u.unit_name, FNUI.BODY, FNUI.INK, "title")
	name.custom_minimum_size = Vector2(70, 0)
	h.add_child(name)
	var role := InfantryRole.by_id(u.role)
	var def := hud.sim.combat.weapon(u.weapon_id)
	var full := (def.magazine_size + def.reserve_start) if def else 1
	var now := FNUI.label("%s · %s · %d%%%s" % [role.short if role and role.short != "" else "RF", def.display_name if def else "unarmed",
		roundi(100.0 * float(u.mag + u.reserve) / maxf(full, 1)), (" · %s %d" % [_wname(u.sec_id), u.sec_ammo]) if u.sec_id != &"" else ""], FNUI.CAPTION + 1, FNUI.INK_2, "body")
	now.custom_minimum_size = Vector2(300, 0)
	now.clip_text = true
	h.add_child(now)
	var pick := OptionButton.new()
	pick.focus_mode = Control.FOCUS_NONE
	pick.custom_minimum_size = Vector2(300, 0)
	pick.fit_to_longest_item = false
	pick.clip_text = true
	pick.add_theme_font_size_override("font_size", FNUI.CAPTION + 1)
	var opts: Array = _eq().options(sq, u)
	var shown := []
	for o: Dictionary in opts:
		var txt := String(o.name)
		match o.state:
			"current":
				txt += "  - current"
			"ready":
				txt += "  - ready (%s)" % ", ".join((o.sources as Dictionary).values().filter(func(s: String) -> bool: return s != "carried"))
			"procure":
				txt += "  - procure %d kg supplies, %d kg ammunition" % [roundi(float(o.cost.get(&"supplies", 0.0))), roundi(float(o.cost.get(&"ammo", 0.0)))]
			"locked":
				txt += "  - " + String(o.reason)
			_:
				txt += "  - " + String(o.reason)
		pick.add_item(txt)
		var idx := pick.item_count - 1
		pick.set_item_disabled(idx, not o.state in ["current", "ready", "procure"])
		pick.set_item_tooltip(idx, txt)
		if o.state == "current":
			pick.select(idx)
		shown.append(o)
	pickers[u.id] = pick
	choices[u.id] = shown
	h.add_child(pick)
	var apply := FNUI.action_button(&"check", "Apply", "Give this soldier the chosen role")
	var uid := u.id
	apply.pressed.connect(func() -> void: apply_choice(uid))
	h.add_child(apply)
	return h


## Gives soldier `uid` the role chosen in its row (the button; tests call it too). Returns SquadEquipment.equip's result.
func apply_choice(uid: int, role_id := &"") -> Dictionary:
	var sq := hud.sim.state.get_squad(squad_id)
	var u := hud.sim.state.get_unit(uid)
	if sq == null or u == null:
		return {"ok": false, "reason": "gone"}
	if role_id == &"":
		var pick: OptionButton = pickers.get(uid)
		if pick == null or pick.selected < 0:
			return {"ok": false, "reason": "nothing chosen"}
		role_id = StringName((choices[uid] as Array)[pick.selected].role)
	var r := _eq().equip(sq, u, role_id)
	_say.text = String(r.get("text", "")) if r.ok else "Cannot: %s" % r.reason
	_say.add_theme_color_override("font_color", FNUI.OK if r.ok else FNUI.WARN)
	_say_until = Time.get_ticks_msec() / 1000.0 + 6.0
	_sig = ""
	_refresh()
	return r
