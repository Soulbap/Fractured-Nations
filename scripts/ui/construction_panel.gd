## Construction HUD (BASE-01, UI-01C): the build menu on the right and one context panel at the bottom.
##
## Menu: the player's base (or how to found one), category tiles (BASE = the five base buildings in
## build order, then the StructureCatalog categories), build cards for the chosen category (thumbnail
## rendered from the model, name, what it does, why it is unavailable) in a scroll area, and the tools
## (demolish X, vegetation clearing C, save F5, load F9). Built from StructureCatalog, so a new type
## shows up without touching the UI. Until the player has a base only the command post (and anything
## that is not a base facility) can be chosen.
##
## Context panel: only while placing or demolishing - the selected structure, VALID PLACEMENT or the
## reason it cannot be built, rotation / groundwork / line or road figures, and the keys for this tool.
## Everything comes from ConstructionController (its check, def, yaw, tool); the panel keeps no state
## besides the open category.
class_name ConstructionPanel
extends Control

## Short name and function of the base menu entries.
const BASE_ENTRIES := {
	&"command_post": ["Command Post", "Establishes a base (150 m area)"],
	&"barracks_block": ["Barracks", "+32 soldier capacity"],
	&"supply_depot": ["Supply Depot", "Base stores"],
	&"vehicle_parking_pad": ["Vehicle Parking", "6 vehicle bays"],
	&"guard_tower_steel": ["Guard Post", "Defensive position"],
}
const BASE := "Base"
const CATEGORY_ICONS := {
	"Base": &"base", "Buildings": &"building", "Training": &"training", "Logistics": &"logistics",
	"Defences": &"wall", "Infrastructure": &"infrastructure", "Roads": &"road",
}
const MENU_W := 250.0

var controller: ConstructionController
## BASE-01 tests read these: the base cards (id -> FNBuildCard, a Button) and the base line.
var _base_buttons := {}
var _base_info: Label
var _buttons := {}
var _tiles := {}
var _cards := {}
var _category := BASE
var _menu: FNPanel
var _scroll: ScrollContainer
var _list: VBoxContainer
var _base_title: Label
var _base_fields: GridContainer
var _tools := {}
var _poll := 0.0
# Context panel.
var _context: FNPanel
var _ctx_thumb: TextureRect
var _ctx_title: Label
var _ctx_status: FNStatusIndicator
var _ctx_detail: Label
var _ctx_reason: Label
var _ctx_info: Label
var _ctx_keys: VBoxContainer
var _ctx_sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = FNUI.theme()
	_build_menu()
	_build_context()
	_show_category(BASE)
	refresh()


# --- Menu ---------------------------------------------------------------------------------------------

func _build_menu() -> void:
	_menu = FNPanel.new(FNUI.OK, FNUI.S4)
	_menu.custom_minimum_size = Vector2(MENU_W, 0)
	add_child(_menu)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", FNUI.S3)
	_menu.add_child(box)
	# Header: BUILD, the close key.
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", FNUI.S3)
	box.add_child(head)
	head.add_child(FNIcons.rect(&"build", FNUI.ICON_M, FNUI.OK))
	var t := FNUI.label("Construction", FNUI.TITLE, FNUI.INK, "caps")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(FNKeyHint.new("B", "Close"))
	# The player's base.
	var base_box := PanelContainer.new()
	base_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base_box.add_theme_stylebox_override("panel", FNUI.box(Color(0, 0, 0, 0.22), Color(FNUI.LINE, 0.8), 1, 2, FNUI.S3))
	box.add_child(base_box)
	var bv := VBoxContainer.new()
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_theme_constant_override("separation", FNUI.S2 - 1)
	base_box.add_child(bv)
	_base_title = FNUI.label("", FNUI.LABEL, FNUI.INK, "caps")
	bv.add_child(_base_title)
	_base_fields = GridContainer.new()
	_base_fields.columns = 2
	_base_fields.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base_fields.add_theme_constant_override("h_separation", FNUI.S4)
	_base_fields.add_theme_constant_override("v_separation", 0)
	bv.add_child(_base_fields)
	_base_info = FNUI.label("", FNUI.CAPTION, FNUI.INK_2, "body")
	_base_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_base_info.custom_minimum_size = Vector2(MENU_W - 40.0, 0)
	bv.add_child(_base_info)
	# Categories.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", FNUI.S2)
	grid.add_theme_constant_override("v_separation", FNUI.S2)
	box.add_child(grid)
	var cats: Array[String] = [BASE]
	for cat in StructureCatalog.CATEGORIES:
		if not StructureCatalog.in_category(cat).is_empty():
			cats.append(cat)
	for cat in cats:
		var n := ConstructionController.BASE_TYPES.size() if cat == BASE else StructureCatalog.in_category(cat).size()
		var tile := FNCategoryTile.new(CATEGORY_ICONS.get(cat, &"building"), cat, str(n))
		tile.pressed.connect(func() -> void: _show_category(cat))
		grid.add_child(tile)
		_tiles[cat] = tile
	# Build cards (one list per category, built once; only the chosen one is shown).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", FNUI.S2 - 1)
	_scroll.add_child(_list)
	for cat in cats:
		var defs: Array[StructureDef] = []
		if cat == BASE:
			for id in ConstructionController.BASE_TYPES:
				var d := StructureCatalog.get_def(id)
				if d:
					defs.append(d)
		else:
			defs = StructureCatalog.in_category(cat)
		var cards: Array = []
		for d in defs:
			var card := _make_card(d, cat)
			cards.append(card)
			if cat == BASE:
				_base_buttons[d.id] = card
			else:
				_buttons[d.id] = card
		_cards[cat] = cards
	# Tools.
	var rule := ColorRect.new()
	rule.color = Color(FNUI.LINE, 0.9)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	var tools := HBoxContainer.new()
	tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tools.add_theme_constant_override("separation", FNUI.S2)
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(tools)
	for e: Array in [[&"demolish", &"demolish", "Demolish", "X", "Remove a building or a line module (Shift+click: the whole line)"],
			[&"clearing", &"clearing", "Clearing", "C", "Cut trees and undergrowth inside new footprints (off: trees block placement)"],
			[&"save", &"save", "Save", "F5", "Save structures, units and squads"],
			[&"load", &"load", "Load", "F9", "Load the last save"]]:
		var b := FNCommandButton.new(e[1], e[2], e[3], e[4])
		b.custom_minimum_size = Vector2(52, 44)
		b.pressed.connect(_on_tool.bind(e[0]))
		tools.add_child(b)
		_tools[e[0]] = b


func _make_card(d: StructureDef, cat: String) -> FNBuildCard:
	var path := "res://assets/ui/thumbs/%s.png" % d.id
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	var e: Array = BASE_ENTRIES.get(d.id, [d.display_name, ""]) if cat == BASE else [d.display_name, ""]
	var info: String = e[1]
	if info == "":
		info = _short(d)
	var card := FNBuildCard.new(e[0], info, tex, CATEGORY_ICONS.get(d.category, &"building"))
	card.tooltip_text = "%s\n%s" % [d.display_name, d.description]
	var id := d.id
	card.pressed.connect(func() -> void:
		controller.select_type(id)
		refresh())
	return card


## One line on what a type is: line / road / area tools say how they are drawn, buildings the first
## clause of their description.
static func _short(d: StructureDef) -> String:
	if d.surface == StructureDef.Surface.ROAD:
		return "Road · click control points"
	if d.surface == StructureDef.Surface.AREA:
		return "Paved area · click the corners"
	var s := d.description
	for sep in [":", ".", ";", ",", " ("]:
		var i := s.find(sep)
		if i > 8:
			s = s.left(i)
	return ("Line · " if d.linear else "") + s


func _on_tool(which: StringName) -> void:
	match which:
		&"demolish":
			if controller.tool == ConstructionController.Tool.DELETE:
				controller.clear_tool()
			else:
				controller.select_delete()
		&"clearing":
			controller.toggle_clearing()
		&"save":
			controller.save()
		&"load":
			controller.load_saved()
	refresh()


func _show_category(cat: String) -> void:
	_category = cat
	for c in _tiles:
		_tiles[c].selected = c == cat
	for child in _list.get_children():
		_list.remove_child(child)
	for card in _cards.get(cat, []):
		_list.add_child(card)
	_scroll.scroll_vertical = 0
	_fit.call_deferred()


func _process(delta: float) -> void:
	if controller == null:
		return
	_layout()
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.2
		_refresh_base()
		_refresh_cards()
	_refresh_context()


func _layout() -> void:
	var vp := get_viewport_rect().size
	_menu.position = Vector2(vp.x - _menu.size.x - FNUI.EDGE, FNUI.EDGE)
	if _context.visible:
		_context.position = Vector2(roundf((vp.x - MENU_W - _context.size.x) * 0.5), vp.y - _context.size.y - FNUI.EDGE)


## The card list is as tall as its content, up to what fits on the screen.
func _fit() -> void:
	if _scroll == null:
		return
	var others := _menu.get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	var room := get_viewport_rect().size.y - 2.0 * FNUI.EDGE - others
	_scroll.custom_minimum_size = Vector2(MENU_W - 2.0 * FNUI.S4, clampf(_list.get_combined_minimum_size().y, 60.0, maxf(room, 120.0)))
	_menu.size = Vector2.ZERO


## The base strip: the player's base and what it holds, or how to found one.
func _refresh_base() -> void:
	var bs := controller._bases()
	var mine: Array = bs.bases_of(controller.player_faction()) if bs else []
	for c in _base_fields.get_children():
		c.queue_free()
	if mine.is_empty():
		_base_title.text = "No base"
		_base_title.add_theme_color_override("font_color", FNUI.WARN)
		_base_info.text = "Place a Command Post on open, level ground: it opens a 150 m base area for the other buildings."
		_base_info.visible = true
		return
	var sm := bs.summary(mine[0].id)
	var buildings := 0
	for k in sm.facilities:
		buildings += int(sm.facilities[k])
	_base_title.text = "%s%s" % [sm.name, ("  ·  +%d more" % (mine.size() - 1)) if mine.size() > 1 else ""]
	_base_title.add_theme_color_override("font_color", FNUI.OK)
	_base_info.text = "%d buildings, %d beds, %d parking bays, %d guard posts" % [buildings, sm.capacity, sm.parking, sm.guard_posts]
	_base_info.visible = false
	for f: Array in [["Buildings", str(buildings)], ["Soldiers", "%d / %d beds" % [sm.soldiers, sm.capacity]],
			["Parking", "%d bays" % sm.parking], ["Guard posts", str(sm.guard_posts)]]:
		var fld := FNField.new(f[0], f[1], &"", 52.0)
		fld.value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_base_fields.add_child(fld)


## Card states: selected while being placed, unavailable while the base rules forbid the type.
func _refresh_cards() -> void:
	var bs := controller._bases()
	var has_base := not controller.base_rules or (bs != null and not bs.bases_of(controller.player_faction()).is_empty())
	var placing := controller.tool == ConstructionController.Tool.PLACE and controller.def != null
	for dict in [_base_buttons, _buttons]:
		for id in dict:
			var card: FNBuildCard = dict[id]
			card.selected = placing and controller.def.id == id
			var needs_base: bool = FacilityDefs.has(id) and not FacilityDefs.founds_base(id) and not has_base
			card.set_available(not needs_base, "Needs a Command Post" if needs_base else "")
	(_tools[&"demolish"] as FNCommandButton).armed = controller.tool == ConstructionController.Tool.DELETE
	(_tools[&"clearing"] as FNCommandButton).set_face(&"clearing", "Clearing" if controller.clear_trees else "No clear")
	(_tools[&"clearing"] as FNCommandButton).current = controller.clear_trees


func refresh() -> void:
	if controller == null or _menu == null:
		return
	var placing := controller.tool == ConstructionController.Tool.PLACE and controller.def != null
	# Picking a type elsewhere (tests, hotkeys) opens its category, unless it is shown under BASE.
	if placing and not (_category == BASE and _base_buttons.has(controller.def.id)) and _tiles.has(controller.def.category) \
			and _category != controller.def.category:
		_show_category(BASE if _base_buttons.has(controller.def.id) else controller.def.category)
	_refresh_base()
	_refresh_cards()
	_ctx_sig = ""
	_refresh_context()
	_fit.call_deferred()


# --- Context panel -----------------------------------------------------------------------------------

func _build_context() -> void:
	_context = FNPanel.new(Color.TRANSPARENT, FNUI.S4)
	_context.custom_minimum_size = Vector2(430, 0)
	_context.visible = false
	add_child(_context)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", FNUI.S4)
	_context.add_child(h)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(76, 57)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.add_theme_stylebox_override("panel", FNUI.box(Color(0.16, 0.19, 0.17, 1.0), Color(FNUI.LINE, 0.9), 1, 2, 0))
	h.add_child(frame)
	_ctx_thumb = TextureRect.new()
	_ctx_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ctx_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ctx_thumb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_ctx_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_ctx_thumb)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 1)
	h.add_child(v)
	_ctx_title = FNUI.label("", FNUI.TITLE + 1, FNUI.INK, "caps")
	v.add_child(_ctx_title)
	_ctx_status = FNStatusIndicator.new(FNUI.ICON_M, FNUI.BODY)
	v.add_child(_ctx_status)
	_ctx_reason = FNUI.label("", FNUI.CAPTION + 1, FNUI.DANGER, "caps")
	_ctx_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ctx_reason.custom_minimum_size = Vector2(190, 0)
	v.add_child(_ctx_reason)
	_ctx_detail = FNUI.label("", FNUI.CAPTION, FNUI.INK_2, "caps")
	_ctx_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ctx_detail.custom_minimum_size = Vector2(190, 0)
	v.add_child(_ctx_detail)
	_ctx_info = FNUI.label("", FNUI.CAPTION, FNUI.INK_3, "body")
	_ctx_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ctx_info.custom_minimum_size = Vector2(190, 0)
	v.add_child(_ctx_info)
	var rule := ColorRect.new()
	rule.color = Color(FNUI.LINE_STRONG, 0.6)
	rule.custom_minimum_size = Vector2(1, 0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(rule)
	_ctx_keys = VBoxContainer.new()
	_ctx_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ctx_keys.alignment = BoxContainer.ALIGNMENT_CENTER
	_ctx_keys.add_theme_constant_override("separation", FNUI.S2)
	h.add_child(_ctx_keys)


func _refresh_context() -> void:
	if controller == null or _context == null:
		return
	var placing := controller.tool == ConstructionController.Tool.PLACE and controller.def != null
	var deleting := controller.tool == ConstructionController.Tool.DELETE
	_context.visible = controller.active and (placing or deleting)
	if not _context.visible:
		return
	var keys: Array = []
	_ctx_reason.text = ""
	_ctx_reason.visible = false
	if deleting:
		_set_thumb(null, &"demolish")
		_ctx_title.text = "Demolish"
		var what := "Point at a building or a line module"
		var hv := controller.hover
		if not hv.is_empty():
			var s := controller.structures.state.get_structure(hv.id)
			if s:
				what = StructureCatalog.get_def(s.type_id).display_name + (" · module %d" % hv.index if s.is_line() and not hv.get("surface", false) else "")
		_ctx_status.set_status(&"demolish", what, FNUI.ALERT if not hv.is_empty() else FNUI.INK_2)
		_ctx_detail.text = ""
		_ctx_info.text = ""
		keys = [["LMB", "Remove"], ["Shift+LMB", "Whole line"], ["RMB / Esc", "Stop"]]
	else:
		var d := controller.def
		var path := "res://assets/ui/thumbs/%s.png" % d.id
		_set_thumb(load(path) if ResourceLoader.exists(path) else null, CATEGORY_ICONS.get(d.category, &"building"))
		_ctx_title.text = d.display_name
		var e: Array = BASE_ENTRIES.get(d.id, [d.display_name, _short(d)])
		_ctx_info.text = e[1]
		var chk := controller.check
		var clearing := "Clearing on" if controller.clear_trees else "Clearing off"
		if d.is_surface():
			var road := d.surface == StructureDef.Surface.ROAD
			if chk.has("ok"):
				_status(chk.ok, chk.get("reason", ""))
				_ctx_detail.text = ("%.0f m · steepest %.0f %% (max %.0f %%) · cut / fill %.1f m" % [chk.length_m, chk.grade * 100.0, d.max_grade * 100.0, chk.max_cut_m]) if road \
					else ("%.0f m² · slope %.1f %% · cut / fill %.1f m" % [chk.area_m2, chk.grade * 100.0, chk.max_cut_m])
			else:
				_ctx_status.set_status(&"route" if road else &"territory", "Click the first point" if controller.line_points.is_empty() else "Add the next point", FNUI.INK_2)
				_ctx_detail.text = ""
			keys = [["LMB", "Add point"], ["Enter / RMB", "Finish" if road else "Close"], ["Bksp", "Undo point"], ["Esc", "Cancel"]]
		elif d.linear:
			if chk.has("modules"):
				var n: int = chk.modules.size()
				var bad: int = n - chk.ok_count
				_status(bad == 0, controller._first_reason(), "%d of %d modules blocked" % [bad, n] if bad > 0 else "")
				_ctx_detail.text = "%d modules · %.0f m%s · %s" % [n, chk.length_m, "  ·  snapped" if not controller.snap.is_empty() else "", clearing]
			else:
				_ctx_status.set_status(&"route", "Click the start of the line", FNUI.INK_2)
				_ctx_detail.text = clearing
			keys = [["LMB", "Start" if controller.line_points.is_empty() else "Add corner"], ["Enter / RMB", "Finish"], ["Bksp", "Undo corner"], ["Esc", "Cancel"]]
		else:
			if chk.is_empty():
				_ctx_status.set_status(&"build", "Point at the ground", FNUI.INK_2)
			else:
				_status(bool(chk.get("ok", false)), chk.get("reason", "point at the ground"))
			var lvl: float = chk.get("level_m", 0.0)
			_ctx_detail.text = "Rotation %.0f°%s · %s" % [fposmod(rad_to_deg(controller.yaw), 360.0), ("  ·  groundwork levels %.1f m" % lvl) if lvl >= 0.1 else "", clearing]
			keys = [["LMB", "Place"], ["R", "Rotate"], ["RMB / Esc", "Cancel"]]
	var sig := str(keys)
	if sig != _ctx_sig:
		_ctx_sig = sig
		for c in _ctx_keys.get_children():
			c.queue_free()
		for k: Array in keys:
			_ctx_keys.add_child(FNKeyHint.new(k[0], k[1]))
	_context.size = Vector2.ZERO


## VALID PLACEMENT, or "Cannot build" (or extra, e.g. blocked modules) with the reason on its own line.
func _status(ok: bool, reason: String, extra := "") -> void:
	if ok:
		_ctx_status.set_status(&"check", "Valid placement", FNUI.OK)
	else:
		_ctx_status.set_status(&"blocked", extra if extra != "" else "Cannot build here", FNUI.DANGER)
		_ctx_reason.text = reason
		_ctx_reason.visible = reason != ""


func _set_thumb(tex: Texture2D, icon_name: StringName) -> void:
	if tex:
		_ctx_thumb.texture = tex
		_ctx_thumb.modulate = Color.WHITE
		_ctx_thumb.custom_minimum_size = Vector2.ZERO
	else:
		_ctx_thumb.texture = FNIcons.texture(icon_name, FNUI.ICON_L)
		_ctx_thumb.modulate = FNUI.INK_2
