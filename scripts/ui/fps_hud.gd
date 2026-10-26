## First-person HUD (COMBAT-01a readout, UI-01C): the possessed soldier's weapon bottom right (rounds in
## the magazine largest, reserve, fire mode, a tick per round, reload progress), health and combat
## state bottom left with a few quiet keys, the squad card top right (side, callsign, soldiers, what
## the squad is doing, whether the player leads it) and a contextual prompt under the crosshair
## (reload when the magazine runs low or empty, no ammunition). Everything is read from the unit and
## squad records each frame; nothing here changes them.
class_name FPSHud
extends Control

var _weapon: FNWeaponStatus
var _health_box: PanelContainer
var _name: Label
var _health: FNHealthBar
var _state: FNStatusIndicator
var _squad: FNPanel
var _sq_emblem: FNUnitEmblem
var _sq_title: Label
var _sq_count: Label
var _sq_status: FNStatusIndicator
var _sq_lead: Label
var _prompt: FNPrompt
## GAMEPLAY-02D: darkened screen edges while the possessed soldier is suppressed (its record's suppression).
var _vignette: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = FNUI.theme()
	_vignette = TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.03, 0.02, 0.0))
	g.set_color(1, Color(0.05, 0.03, 0.02, 1.0))
	g.add_point(0.42, Color(0.05, 0.03, 0.02, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	_vignette.texture = gt
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	add_child(_vignette)
	_weapon = FNWeaponStatus.new()
	add_child(_weapon)
	# Health block: no frame, a faint backing.
	_health_box = PanelContainer.new()
	_health_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_box.add_theme_stylebox_override("panel", FNUI.box(Color(FNUI.BG, 0.62), Color.TRANSPARENT, 0, FNUI.RADIUS, FNUI.S3))
	add_child(_health_box)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", FNUI.S2)
	_health_box.add_child(v)
	_name = FNUI.label("", FNUI.LABEL, FNUI.INK, "caps")
	v.add_child(_name)
	_health = FNHealthBar.new()
	v.add_child(_health)
	_state = FNStatusIndicator.new(FNUI.ICON_S, FNUI.LABEL)
	v.add_child(_state)
	var keys := HBoxContainer.new()
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys.add_theme_constant_override("separation", FNUI.S4)
	for k: Array in [["Tab", "Tactical"], ["M", "Map"], ["F1", "Controls"]]:
		keys.add_child(FNKeyHint.new(k[0], k[1]))
	v.add_child(keys)
	# Squad card.
	_squad = FNPanel.new(Color.TRANSPARENT, FNUI.S3)
	_squad.custom_minimum_size = Vector2(170, 0)
	add_child(_squad)
	var sv := VBoxContainer.new()
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_theme_constant_override("separation", FNUI.S2)
	_squad.add_child(sv)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", FNUI.S3)
	sv.add_child(head)
	_sq_emblem = FNUnitEmblem.new(Vector2(20, 13))
	head.add_child(_sq_emblem)
	_sq_title = FNUI.label("", FNUI.TITLE, FNUI.INK, "title")
	_sq_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_sq_title)
	head.add_child(FNIcons.rect(&"soldiers", FNUI.ICON_S, FNUI.INK_2))
	_sq_count = FNUI.label("", FNUI.BODY, FNUI.INK, "number")
	head.add_child(_sq_count)
	_sq_status = FNStatusIndicator.new(FNUI.ICON_S, FNUI.LABEL)
	sv.add_child(_sq_status)
	_sq_lead = FNUI.label("You lead this squad", FNUI.CAPTION, FNUI.ACCENT, "caps")
	sv.add_child(_sq_lead)
	_prompt = FNPrompt.new()
	_prompt.visible = false
	add_child(_prompt)


## Called by GameHUD every frame while a soldier is possessed.
func update(sim: WorldSim, u: UnitState) -> void:
	var vp := get_viewport_rect().size
	var now := sim.state.time
	# Weapon.
	var def: WeaponDef = sim.combat.weapon(u.weapon_id) if u.weapon_id != &"" else null
	_weapon.visible = def != null
	var reload := -1.0
	# GAMEPLAY-02C: the grenades carried, and the secondary weapon while it is raised (X).
	var nades := ("   G x%d" % u.grenades) if u.grenades > 0 else ""
	var sec: WeaponDef = sim.combat.weapon(u.sec_id) if u.sec_active and u.sec_id != &"" else null
	if sec:
		if now < u.sec_ready_at:
			reload = clampf(1.0 - (u.sec_ready_at - now) / maxf(sec.reload_time, 0.1), 0.0, 1.0)
		_weapon.set_state(sec.display_name + nades, mini(u.sec_ammo, 1), 1, maxi(u.sec_ammo - 1, 0), "X", reload)
	elif def:
		if u.is_reloading():
			reload = clampf(1.0 - (u.reload_until - now) / def.reload_time, 0.0, 1.0)
		_weapon.set_state(def.display_name + nades, u.mag, def.magazine_size, u.reserve, "AUTO" if u.fire_auto else "SEMI", reload)
		_weapon.position = Vector2(vp.x - _weapon.size.x - FNUI.EDGE - 4, vp.y - _weapon.size.y - FNUI.EDGE - 4)
	# Health and combat state.
	# COMBAT-01: the posture beside the name (C crouch, Z prone); "getting down / up" while it changes.
	var pst := "" if u.posture == Posture.STAND and Posture.settled(u, now) else ("  ·  " + (("getting down" if u.posture == Posture.PRONE else "getting up") if Posture.busy(u, now) else Posture.NAMES[u.posture].capitalize()))
	_name.text = u.unit_name + pst
	_health.set_health(u.health, u.max_health)
	var supp := u.suppression_at(now)
	# COMBAT-01: a restrained cue (the edges only, never most of the screen): sound and impacts carry the danger.
	_vignette.modulate.a = clampf((supp - 0.1) * 0.7, 0.0, 0.45)
	if supp > 0.3:
		_state.set_status(&"suppression", "Suppressed", FNUI.ALERT)
	elif u.under_fire_until >= now:
		_state.set_status(&"under_fire", "Under fire", FNUI.ALERT)
	_state.visible = supp > 0.3 or u.under_fire_until >= now
	_health_box.size = Vector2.ZERO
	_health_box.position = Vector2(FNUI.EDGE + 4, vp.y - _health_box.size.y - FNUI.EDGE - 4)
	# Squad.
	var sq := sim.state.squad_of(u.id)
	_squad.visible = sq != null
	if sq:
		var st := SquadPanel.squad_status(sim, sq)
		_sq_emblem.color = WorldState.faction_color(sq.faction)
		_squad.accent = WorldState.faction_color(sq.faction)
		_sq_title.text = "%s  ·  %s" % [WorldState.faction_name(sq.faction).to_upper(), sq.squad_name.to_upper()]
		var sn := SquadPanel.strength(sq)
		_sq_count.text = "%d/%d" % [sn.x, sn.y]
		_sq_status.set_status(st.icon, "Order: " + st.text, st.color)
		# QOL-01: the squad's behaviour mode under the order (the leader line keeps its own row).
		_sq_lead.text = ("You lead · " if sq.leader_id == u.id else "") + sq.behaviour_name().to_upper()
		_sq_lead.add_theme_color_override("font_color", FNUI.ACCENT if sq.leader_id == u.id else FNUI.INK_2)
		_sq_lead.visible = true
		_squad.size = Vector2.ZERO
		_squad.position = Vector2(vp.x - _squad.size.x - FNUI.EDGE, FNUI.EDGE)
	# Contextual prompt under the crosshair.
	_prompt.visible = false
	if def and reload < 0.0:
		if u.mag == 0 and u.reserve > 0:
			_prompt.show_prompt("R", "Reload", FNUI.WARN)
		elif u.mag == 0:
			_prompt.show_prompt("", "No ammunition", FNUI.DANGER)
		elif float(u.mag) / def.magazine_size <= 0.2 and u.reserve > 0:
			_prompt.show_prompt("R", "Reload", FNUI.INK_2)
	if _prompt.visible:
		_prompt.position = Vector2(roundf((vp.x - _prompt.size.x) * 0.5), roundf(vp.y * 0.5 + 40.0))
