## GAMEPLAY-01B early-game feedback on the UI-01C kit, part of GameHUD (tactical view and first person):
##   * the supply strip, top centre: supplies, ammunition, fuel (pool + every base), income per minute, personnel;
##   * one unobtrusive hint about a sensible next step (find supplies, Command Post, depot, barracks, recruit, fortify,
##     capture ground) - a suggestion, not an objective; the × hides the hints for this game (WarState.guide, saved);
##   * markers in the world for the supply caches the faction knows (state, securing progress) and for the player's
##     construction sites (progress, workers, why they wait).
## Reads the records only; shown while the scenario uses the economy (rule build_costs or player_income).
class_name EconomyHud
extends Control

var hud: GameHUD
var _strip: FNPanel
var _strip_label: Label
var _hint: FNPanel
var _hint_label: Label
var _timer := 0.0
## The current hint (tests read it): id and text.
var hint_id := ""
var hint_text := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = FNUI.theme()
	_strip = FNPanel.new(FNUI.OK, FNUI.S3)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	var sh := HBoxContainer.new()
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_theme_constant_override("separation", FNUI.S3)
	_strip.add_child(sh)
	sh.add_child(FNIcons.rect(&"cargo", FNUI.ICON_S, FNUI.OK))
	_strip_label = FNUI.label("", FNUI.LABEL, FNUI.INK, "caps")
	sh.add_child(_strip_label)
	_hint = FNPanel.new(FNUI.ARMED, FNUI.S3)
	add_child(_hint)
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", FNUI.S3)
	_hint.add_child(hh)
	var tag := FNUI.label("Next", FNUI.CAPTION, FNUI.ARMED, "caps")
	hh.add_child(tag)
	_hint_label = FNUI.label("", FNUI.LABEL, FNUI.INK, "body")
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(300, 0)
	hh.add_child(_hint_label)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Hide the hints for this game"
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(func() -> void:
		if _war():
			_war().guide["off"] = true
		_hint.visible = false)
	hh.add_child(close)
	_strip.visible = false
	_hint.visible = false


func _war() -> WarState:
	return hud.sim.state.war if hud and hud.sim else null


func active() -> bool:
	var w := _war()
	return w != null and w.active and hud.war_sim != null and hud.war_sim.enabled and (bool(w.rule("build_costs", false)) or bool(w.rule("player_income", false)))


func _process(delta: float) -> void:
	var on := active() and hud.game != null and hud.game.mode != GameController.Mode.DRIVE
	_strip.visible = on
	if not on:
		_hint.visible = false
		return
	queue_redraw()
	var vp := get_viewport_rect().size
	_strip.position = Vector2(roundf((vp.x - _strip.size.x) * 0.5), FNUI.EDGE)
	_hint.position = Vector2(roundf((vp.x - _hint.size.x) * 0.5), _strip.position.y + _strip.size.y + 6.0)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var w := _war()
	var f := w.faction(w.player_faction)
	var bs := hud.sim.logistics.bases
	var st := bs.faction_stock(f.id)
	var rate: Dictionary = hud.war_sim.econ.rate_per_min(f)
	_strip_label.text = "Supplies %d kg%s   ·   Ammunition %d kg   ·   Fuel %d l   ·   Personnel %d" % [roundi(st.supplies),
		("  (+%d/min)" % roundi(rate.supplies)) if float(rate.supplies) > 0.0 else "", roundi(st.ammo), roundi(st.fuel), f.reserves]
	_strip.size = Vector2.ZERO
	# GAMEPLAY-04A: during the introduction the objective tracker guides; the hints take over after it.
	var intro_on := hud.war_sim.intro.active() and not hud.war_sim.intro.complete()
	var h := next_hint() if bool(w.rule("guide", false)) and not w.guide.get("off", false) and not intro_on else {}
	hint_id = h.get("id", "")
	hint_text = h.get("text", "")
	_hint.visible = hint_text != "" and hud.game.mode == GameController.Mode.RTS
	if _hint_label.text != hint_text:
		_hint_label.text = hint_text
		_hint.size = Vector2.ZERO


## The first early-game step the player has not taken: {id, text}, or {} when there is nothing to suggest.
func next_hint() -> Dictionary:
	var w := _war()
	var pf := w.player_faction
	var f := w.faction(pf)
	var bs := hud.sim.logistics.bases
	var cs := hud.sim.state.construction
	var supplies := float(bs.faction_stock(pf).supplies)
	var has := func(kind: StringName) -> bool:
		for s: StructureState in cs.all():
			if s.faction == pf and FacilityDefs.kind_of(s.type_id) == kind:
				return true
		return false
	var site_of := func(kind: StringName) -> StructureState:
		for s: StructureState in cs.all():
			if s.faction == pf and s.is_site() and FacilityDefs.kind_of(s.type_id) == kind:
				return s
		return null
	var taken := 0
	var cache_known: Dictionary = {}
	for c: Dictionary in w.caches:
		if int(c.taken_by) == pf:
			taken += 1
		elif c.state != "depleted" and (c.known as Array).has(pf) and cache_known.is_empty():
			cache_known = c
	var cp_site: StructureState = site_of.call(&"hq")
	if bs.bases_of(pf).is_empty():
		if cp_site:
			return {"id": "cp_building", "text": "Your soldiers are building the Command Post (%d%%). The base opens when it is finished." % roundi(cp_site.site_progress() * 100.0)}
		if taken == 0 and not cache_known.is_empty():
			return {"id": "cache", "text": "Find supplies: move your squad onto the %s (diamond marker, also on the map - M) and hold it for about 30 s." % cache_known.name}
		if supplies >= BuildCosts.COST[&"command_post"]:
			return {"id": "cp", "text": "Establish a Command Post: B, then Command Post, on open level ground. Idle soldiers nearby build it."}
		return {"id": "cp_supplies", "text": "A Command Post needs %d kg of supplies: secure a cache or capture an objective." % roundi(BuildCosts.COST[&"command_post"])}
	var depot_site: StructureState = site_of.call(&"supply")
	if not has.call(&"supply") or (depot_site and not _complete_of(pf, &"supply")):
		if depot_site:
			return {"id": "depot_building", "text": "The Supply Depot is under construction (%d%%). What you carry is stored there when it is done." % roundi(depot_site.site_progress() * 100.0)}
		return {"id": "depot", "text": "Build a Supply Depot inside the base (%d kg): the supplies you carry are stored there." % roundi(BuildCosts.COST[&"supply_depot"])}
	if not has.call(&"barracks"):
		var need := BuildCosts.COST[&"barracks_block"]
		# GAMEPLAY-04B: the barracks has to be developed first.
		var dev := hud.war_sim.dev
		if dev.structure_lock(pf, &"barracks_block") != "":
			var st := dev.status(pf, &"personnel_facilities")
			if st.state == "active":
				return {"id": "dev_barracks_running", "text": "Barracks & Personnel is in development (%d%%). Meanwhile: capture ground, fortify, or develop something else later." % roundi(float(st.progress) * 100.0)}
			return {"id": "dev_barracks", "text": "Develop Barracks & Personnel (F2) to build a Barracks and recruit squads."}
		return {"id": "barracks", "text": "Construct a Barracks (%d kg): it trains new squads.%s" % [roundi(need),
			"" if supplies >= need else " You have %d kg - secure caches or capture Verket for income." % roundi(supplies)]}
	if int(f.ledger.squads_recruited) == 0 and bs.queued_recruits(pf) == 0:
		if not _complete_of(pf, &"barracks"):
			return {"id": "barracks_building", "text": "The Barracks is under construction. When it is finished, click it and recruit a squad."}
		return {"id": "recruit", "text": "Recruit a squad: click the Barracks, then Recruit (%s)." % bs.cost_text(BaseSim.RECRUIT_COST)}
	var fortified := false
	for s: StructureState in cs.all():
		if s.faction == pf and (FacilityDefs.kind_of(s.type_id) == &"guard" or s.type_id in [&"sandbag_fighting_position", &"hesco", &"hesco_tall", &"mg_nest", &"dfp_sandbag_ring", &"bunker_fighting"]):
			fortified = true
			break
	if not fortified:
		return {"id": "fortify", "text": "Fortify the base: a Guard Post or sandbag positions cover the approaches."}
	if w.owned_by(pf).is_empty():
		return {"id": "capture", "text": "Capture ground: objectives such as Verket pay supplies every minute (map - M - select a squad, Attack)."}
	return {}


func _complete_of(pf: int, kind: StringName) -> bool:
	for s: StructureState in hud.sim.state.construction.all():
		if s.faction == pf and not s.is_site() and FacilityDefs.kind_of(s.type_id) == kind:
			return true
	return false


# --- World markers -----------------------------------------------------------------------------------------------

func _draw() -> void:
	if not active() or hud.game == null or hud.game.mode != GameController.Mode.RTS:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var w := _war()
	var pf := w.player_faction
	var font := FNUI.caps_font()
	var cp := cam.global_position
	for c: Dictionary in w.caches:
		if c.state == "depleted" or not (c.known as Array).has(pf):
			continue
		var p: Vector3 = c.pos
		if cp.distance_to(p) > 2500.0:
			continue
		var at := p + Vector3.UP * 3.0
		if cam.is_position_behind(at):
			continue
		var s := cam.unproject_position(at)
		var col := FNUI.ARMED
		var d := 7.0
		draw_colored_polygon(PackedVector2Array([s + Vector2(0, -d - 2), s + Vector2(d + 2, 0), s + Vector2(0, d + 2), s + Vector2(-d - 2, 0)]), Color(0, 0, 0, 0.6))
		draw_colored_polygon(PackedVector2Array([s + Vector2(0, -d), s + Vector2(d, 0), s + Vector2(0, d), s + Vector2(-d, 0)]), col)
		var txt := "%s · %d kg" % [String(c.name).to_upper(), roundi(float(c.supplies))]
		if c.state == "securing" and int(c.faction) == pf:
			txt = "%s · SECURING %d%%" % [String(c.name).to_upper(), roundi(float(c.progress) * 100.0)]
		elif c.state == "securing":
			txt = "%s · CONTESTED" % String(c.name).to_upper()
		_text(font, s + Vector2(12, 4), txt, FNUI.INK)
		if c.state == "securing":
			_bar(s + Vector2(12, 9), 90.0, float(c.progress), col)
	# GAMEPLAY-04D: equipment the faction knows of (finds, cache equipment, the fallen's weapons): a square marker.
	for s: Dictionary in hud.war_sim.equip.known_stashes(pf):
		var sp: Vector3 = s.pos
		if cp.distance_to(sp) > 1500.0:
			continue
		var sat := sp + Vector3.UP * 2.0
		if cam.is_position_behind(sat):
			continue
		var ss := cam.unproject_position(sat)
		draw_rect(Rect2(ss - Vector2(6, 6), Vector2(12, 12)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(ss - Vector2(4, 4), Vector2(8, 8)), FNUI.OK)
		var n := 0
		for k in s.items:
			n += int(s.items[k])
		_text(font, ss + Vector2(10, 4), "%s · %s%s" % [String(s.name).to_upper(), ("%d WEAPONS" % n) if n > 0 else "", (" · %d KG AMMO" % roundi(float(s.ammo))) if float(s.ammo) >= 1.0 else ""], FNUI.INK)
	for st: StructureState in hud.sim.state.construction.all():
		if not st.is_site() or st.faction != pf:
			continue
		var p := st.site_center()
		if cp.distance_to(p) > 1500.0:
			continue
		var at := p + Vector3.UP * 6.0
		if cam.is_position_behind(at):
			continue
		var s := cam.unproject_position(at)
		var def := StructureCatalog.get_def(st.type_id)
		var workers := int(st.site.get("workers", 0))
		var why := String(st.site.get("why", ""))
		var line2 := ("%d working" % workers) if workers > 0 else (why if why != "" else "waiting for workers")
		_text(font, s + Vector2(-60, -4), "%s · %d%%" % [(def.display_name if def else String(st.type_id)).to_upper(), roundi(st.site_progress() * 100.0)], FNUI.INK)
		_bar(s + Vector2(-60, 1), 120.0, st.site_progress(), FNUI.OK if workers > 0 else FNUI.WARN)
		_text(font, s + Vector2(-60, 16), line2.to_upper(), FNUI.OK if workers > 0 else FNUI.WARN)


func _text(font: Font, at: Vector2, txt: String, col: Color) -> void:
	draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.LABEL, 3, Color(0, 0, 0, 0.75))
	draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.LABEL, col)


func _bar(at: Vector2, w: float, v: float, col: Color) -> void:
	draw_rect(Rect2(at, Vector2(w, 4)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at, Vector2(w * clampf(v, 0.0, 1.0), 4)), col)
