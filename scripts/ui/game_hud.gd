## Minimal HUD: mode, controls, selection, unit summary, crosshair and drag box.
class_name GameHUD
extends CanvasLayer

@export var game: GameController
@export var rts: RTSController
@export var sim: WorldSim

var _label: Label
var _overlay: Overlay


class Overlay extends Control:
	var hud: GameHUD

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if hud.game and hud.game.mode == GameController.Mode.FPS:
			var c := size * 0.5
			draw_line(c + Vector2(-10, 0), c + Vector2(-3, 0), Color.WHITE, 1.5)
			draw_line(c + Vector2(3, 0), c + Vector2(10, 0), Color.WHITE, 1.5)
			draw_line(c + Vector2(0, -10), c + Vector2(0, -3), Color.WHITE, 1.5)
			draw_line(c + Vector2(0, 3), c + Vector2(0, 10), Color.WHITE, 1.5)
		elif hud.rts and hud.rts.dragging:
			var r := Rect2(hud.rts.drag_start, hud.rts.drag_current - hud.rts.drag_start).abs()
			draw_rect(r, Color(1, 1, 1, 0.12), true)
			draw_rect(r, Color(1, 1, 1, 0.85), false, 1.5)


func _ready() -> void:
	layer = 40
	_overlay = Overlay.new()
	_overlay.hud = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_label.position = Vector2(12, 0)
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_label.add_theme_stylebox_override("normal", sb)
	add_child(_label)


func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 6 == 0:
		_label.text = _text()
		_label.position = Vector2(12, get_viewport().get_visible_rect().size.y - _label.size.y - 12)


func _text() -> String:
	if game == null or sim == null:
		return ""
	var st := sim.stats()
	var lines: Array[String] = []
	if game.mode == GameController.Mode.FPS:
		var u := sim.state.get_unit(game.possessed_id)
		var who := "%s (%s)" % [u.unit_name, WorldState.faction_name(u.faction)] if u else "-"
		lines.append("FIRST PERSON  controlling %s" % who)
		if u and u.has_order():
			lines.append("Order: move to %s  (suspended while possessed, resumes on release)" % _fmt(u.order_target))
		lines.append("Tab tactical view | WASD move, Shift sprint, Space jump, Esc release mouse, F fly, F3 stats")
	else:
		var back := sim.state.get_unit(game.possessed_id)
		lines.append("TACTICAL  WASD pan, Q/E rotate, wheel zoom, middle-drag rotate")
		lines.append("LMB select / drag box, Shift add, Ctrl+A all, RMB move order, H halt, P or double-click possess, Tab back to %s" % (back.unit_name if back else "soldier"))
		var sel: Array[String] = []
		var moving := 0
		for id in rts.selected:
			var s := sim.state.get_unit(id)
			if s:
				sel.append(s.unit_name)
				if s.move_state == UnitState.MoveState.MOVING:
					moving += 1
		lines.append("Selected: %s%s" % [", ".join(sel) if not sel.is_empty() else "none", "  (%d moving)" % moving if moving > 0 else ""])
	lines.append("Units %d (%d soldiers, %d vehicles)  moving %d  bodies %d  sim time %.0f s" % [
		st.units, sim.state.count_of(UnitState.Kind.SOLDIER), sim.state.count_of(UnitState.Kind.VEHICLE), st.moving, st.bodies, st.time])
	return "\n".join(lines)


static func _fmt(p: Vector3) -> String:
	return "(%.0f, %.0f)" % [p.x, p.z]
