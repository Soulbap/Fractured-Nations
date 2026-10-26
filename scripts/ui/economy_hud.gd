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
## UI-UX-03: the strip's top (GameHUD moves it below the navigation when the top row is too narrow).
var top_y := float(FNUI.EDGE)


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
	_strip.position = Vector2(roundf((vp.x - _strip.size.x) * 0.5), top_y)
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
	var fortified := false
	for s: StructureState in cs.all():
		if s.faction == pf and (FacilityDefs.kind_of(s.type_id) == &"guard" or s.type_id in [&"sandbag_fighting_position", &"hesco", &"hesco_tall", &"mg_nest", &"dfp_sandbag_ring", &"bunker_fighting", &"fighting_position", &"mg_emplacement"]):
			fortified = true
			break
	if not fortified:
		return {"id": "fortify", "text": "Fortify the base before South answers: a Guard Tower (%d kg) and fighting positions (%d kg) cover the approaches; garrison it with O." % [roundi(BuildCosts.COST[&"guard_tower_steel"]), roundi(BuildCosts.COST[&"fighting_position"])]}
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
	if hud.game == null or hud.game.mode != GameController.Mode.RTS:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_draw_captures(cam)
	_draw_order_preview(cam)
	if not active():
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
		var s := FNUI.project(cam, p + Vector3.UP * 3.0)
		if not s.is_finite():
			continue
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
	# GAMEPLAY-05: stashes close together on screen are one marker with a summary (a fight leaves many); weapon types the
	# faction has not registered are named and drawn in the find colour; the mouse over a marker lists what lies there.
	var mouse := get_local_mouse_position()
	for g: Dictionary in stash_groups(cam, pf):
		var ss: Vector2 = g.screen
		var fresh: Array = g.new_types
		var col := FNUI.ARMED if not fresh.is_empty() else FNUI.OK
		draw_rect(Rect2(ss - Vector2(6, 6), Vector2(12, 12)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(ss - Vector2(4, 4), Vector2(8, 8)), col)
		var lines: Array[String] = [String(g.title)]
		if ss.distance_to(mouse) <= 18.0:
			lines.append_array(g.details)
		elif not fresh.is_empty():
			lines.append("NEW: " + ", ".join(fresh))
		for i in lines.size():
			_text(font, ss + Vector2(10, 4 + i * 15), lines[i], col if i == 1 and not fresh.is_empty() else FNUI.INK)
	for st: StructureState in hud.sim.state.construction.all():
		if not st.is_site() or st.faction != pf:
			continue
		var p := st.site_center()
		if cp.distance_to(p) > 1500.0:
			continue
		var s := FNUI.project(cam, p + Vector3.UP * 6.0)
		if not s.is_finite():
			continue
		var def := StructureCatalog.get_def(st.type_id)
		var workers := int(st.site.get("workers", 0))
		var why := String(st.site.get("why", ""))
		var line2 := ("%d working" % workers) if workers > 0 else (why if why != "" else "waiting for workers")
		_text(font, s + Vector2(-60, -4), "%s · %d%%" % [(def.display_name if def else String(st.type_id)).to_upper(), roundi(st.site_progress() * 100.0)], FNUI.INK)
		_bar(s + Vector2(-60, 1), 120.0, st.site_progress(), FNUI.OK if workers > 0 else FNUI.WARN)
		_text(font, s + Vector2(-60, 16), line2.to_upper(), FNUI.OK if workers > 0 else FNUI.WARN)


## GAMEPLAY-05B: objectives the player's faction is capturing, has paused, contests or is losing: the capture radius on the
## ground, the state and progress, and what keeps the capture going ("Keep 2+ soldiers within 70 m" - the objective's own
## radius and WarSim.capture_min). Reads WarSim.capture_state; nothing is stored.
func _draw_captures(cam: Camera3D) -> void:
	var ws := hud.war_sim
	if ws == null or not ws.enabled or hud.sim.terrain == null:
		return
	var pf := ws.war.player_faction
	var font := FNUI.caps_font()
	for o: ObjectiveState in ws.war.all_objectives():
		var cs := ws.capture_state(o, pf)
		var st := String(cs.state)
		if st == "" or cam.global_position.distance_to(o.position) > 2500.0:
			continue
		var col: Color = {"capturing": FNUI.OK, "paused": FNUI.WARN, "contested": FNUI.ALERT, "losing": FNUI.ALERT}[st]
		# The ring in visible pieces (a large radius at a close zoom has points behind the camera).
		var ring := PackedVector2Array()
		for i in 97:
			var a := TAU * i / 96.0
			var x := o.position.x + cos(a) * o.radius
			var z := o.position.z + sin(a) * o.radius
			var gp := Vector3(x, hud.sim.terrain.data.get_height(Vector3(x, 0.0, z)) + 0.5, z)
			if cam.is_position_behind(gp) or i == 96:
				if not cam.is_position_behind(gp):
					ring.append(cam.unproject_position(gp))
				if ring.size() > 1:
					draw_polyline(ring, Color(0, 0, 0, 0.45), 4.0)
					draw_polyline(ring, Color(col, 0.85), 2.0)
				ring.clear()
				continue
			ring.append(cam.unproject_position(gp))
		var sp := FNUI.project(cam, o.position + Vector3.UP * 12.0)
		if not sp.is_finite():
			continue
		var pct := roundi(float(cs.progress) * 100.0)
		var need := int(cs.need)
		var r := roundi(o.radius)
		var head: String = {"capturing": "CAPTURING — %d%%" % pct, "paused": "CAPTURE PAUSED — %d%%" % pct, "contested": "CONTESTED — %d%%" % pct,
			"losing": "BEING TAKEN BY %s — %d%%" % [WorldState.faction_name(o.capture_faction).to_upper(), pct]}[st]
		var hint: String = {"capturing": "Keep %d+ soldiers within %d m to complete the capture" % [need, r],
			"paused": "%d of %d soldiers inside: bring them back within %d m (progress fades)" % [int(cs.have), need, r],
			"contested": "Enemy soldiers inside %d m: the capture waits until they are cleared" % r,
			"losing": "Bring %d+ soldiers within %d m to stop it" % [need, r]}[st]
		var title := "%s · %s" % [o.obj_name.to_upper(), head]
		var w := maxf(font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.LABEL).x, 160.0)
		_text(font, sp + Vector2(-w * 0.5, -18), title, col)
		_bar(sp + Vector2(-w * 0.5, -12), w, float(cs.progress), col)
		var bf := FNUI.font("regular", false)
		var hw := bf.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION).x
		draw_string_outline(bf, sp + Vector2(-hw * 0.5, 6), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION, 3, Color(0, 0, 0, 0.75))
		draw_string(bf, sp + Vector2(-hw * 0.5, 6), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION, FNUI.INK)


## GAMEPLAY-05B: an order armed on the command bar, before its click: a line from the (first) selected squad to the ground under
## the cursor, the order, the distance, and what the click will do there (REARM: what it would search; GARRISON: the base).
const ORDER_PREVIEW := {
	SquadState.Tactic.BOUND: "bound forward to here, one team covering",
	SquadState.Tactic.ASSAULT: "assault this position",
	SquadState.Tactic.SUPPRESS: "pin this area with fire",
	SquadState.Tactic.FLANK: "flank this position by a covered route",
	SquadState.Tactic.DEFEND: "defend this spot from firing posts",
	SquadState.Tactic.WITHDRAW: "break contact towards here",
}


func _draw_order_preview(cam: Camera3D) -> void:
	var rts := hud.rts
	if rts == null or rts.armed_tactic < 0 or hud.war_sim == null:
		return
	var sqs := rts.selected_squads()
	if sqs.is_empty():
		return
	var g := rts.ground_point(get_viewport().get_mouse_position())
	var sq := hud.sim.state.get_squad(sqs[0])
	if not g.is_finite() or sq == null or cam.is_position_behind(g):
		return
	var c := hud.war_sim.squad_center(sq)
	var gs := cam.unproject_position(g + Vector3.UP * 0.3)
	var col := FNUI.ARMED
	if not cam.is_position_behind(c):
		var cs := cam.unproject_position(c + Vector3.UP * 0.3)
		var n := maxi(int(cs.distance_to(gs) / 12.0), 1)
		for i in n:
			if i % 2 == 0:
				draw_line(cs.lerp(gs, float(i) / n), cs.lerp(gs, float(i + 1) / n), Color(col, 0.8), 2.0)
	draw_arc(gs, 12.0, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 4.0)
	draw_arc(gs, 12.0, 0.0, TAU, 24, col, 2.0)
	var t := rts.armed_tactic
	var what := String(ORDER_PREVIEW.get(t, ""))
	if t == RTSController.REARM:
		what = "rearm " + hud.war_sim.equip.describe_sources(g, sq.faction)
	elif t == RTSController.GARRISON:
		var bid := hud.sim.logistics.bases.base_area_at(g, sq.faction)
		what = ("garrison " + String(hud.sim.state.construction.bases[bid].name)) if bid >= 0 else "no base of yours here - click one of your bases"
	var font := FNUI.caps_font()
	_text(font, gs + Vector2(18, -4), "%s · %d M%s" % [RTSController._armed_name(t).to_upper(), roundi(WarSim._flat(c, g)), (" · %d SQUADS" % sqs.size()) if sqs.size() > 1 else ""], col)
	var bf := FNUI.font("regular", false)
	var line := "Click: %s   (Esc cancels)" % what
	draw_string_outline(bf, gs + Vector2(18, 12), line, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION, 3, Color(0, 0, 0, 0.75))
	draw_string(bf, gs + Vector2(18, 12), line, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION, FNUI.INK)


## GAMEPLAY-05: the known stashes in view, grouped when their labels would overlap on screen (markers closer than STASH_GROUP_W
## sideways and STASH_GROUP_H up or down). Each group: screen (the marker), title (one line), details (a line per weapon type
## and the ammunition), new_types (display names of weapon types the faction has not registered), stashes (how many). The
## records are untouched.
const STASH_GROUP_W := 240.0
const STASH_GROUP_H := 44.0


func stash_groups(cam: Camera3D, pf: int) -> Array:
	var groups: Array = []
	var fs := _war().faction(pf)
	var cp := cam.global_position
	for s: Dictionary in hud.war_sim.equip.known_stashes(pf):
		var sp: Vector3 = s.pos
		if cp.distance_to(sp) > 1500.0:
			continue
		var ss := FNUI.project(cam, sp + Vector3.UP * 2.0)
		if not ss.is_finite():
			continue
		var into: Dictionary = {}
		for g: Dictionary in groups:
			var dd: Vector2 = (g.screen as Vector2) - ss
			if absf(dd.x) <= STASH_GROUP_W and absf(dd.y) <= STASH_GROUP_H:
				into = g
				break
		if into.is_empty():
			into = {"screen": ss, "members": []}
			groups.append(into)
		(into.members as Array).append(s)
	for g: Dictionary in groups:
		var items := {}
		var ammo := 0.0
		var names: Array[String] = []
		var sum := Vector2.ZERO
		for s: Dictionary in g.members:
			for k in s.items:
				items[k] = int(items.get(k, 0)) + int(s.items[k])
			ammo += float(s.ammo)
			sum += cam.unproject_position((s.pos as Vector3) + Vector3.UP * 2.0)
			if s.kind != "fallen" and not names.has(String(s.name)):
				names.append(String(s.name))
		var n := (g.members as Array).size()
		g.screen = sum / n
		var weapons := 0
		var details: Array[String] = []
		var fresh: Array[String] = []
		for k in items:
			if int(items[k]) <= 0:
				continue
			weapons += int(items[k])
			var def := hud.sim.combat.weapon(StringName(k))
			var wname := (def.display_name if def else String(k)).to_upper()
			var unknown := fs != null and not fs.discovered.has(String(k))
			details.append("%d × %s%s" % [int(items[k]), wname, "  (NEW)" if unknown else ""])
			if unknown:
				fresh.append(wname)
		if ammo >= 1.0:
			details.append("%d KG AMMUNITION" % roundi(ammo))
		var what := "FALLEN EQUIPMENT" if names.is_empty() else names[0].to_upper()
		if n > 1:
			what += " +%d" % (n - 1) if not names.is_empty() else " ×%d" % n
		var parts: Array[String] = [what]
		if weapons > 0:
			parts.append("%d WPN" % weapons)
		if ammo >= 1.0:
			parts.append("%d KG" % roundi(ammo))
		g.title = " · ".join(parts)
		g.details = details
		g.new_types = fresh
		g.stashes = n
	return groups


func _text(font: Font, at: Vector2, txt: String, col: Color) -> void:
	draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.LABEL, 3, Color(0, 0, 0, 0.75))
	draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.LABEL, col)


func _bar(at: Vector2, w: float, v: float, col: Color) -> void:
	draw_rect(Rect2(at, Vector2(w, 4)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at, Vector2(w * clampf(v, 0.0, 1.0), 4)), col)
