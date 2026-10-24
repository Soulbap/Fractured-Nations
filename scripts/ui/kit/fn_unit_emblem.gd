## Kit unit emblem: the NATO-style friendly frame of a unit, filled with the side's colour, with
## the unit-type mark drawn inside (infantry: the cross). frame_color shows the unit's state
## (e.g. red while engaged).
class_name FNUnitEmblem
extends Control

var color := FNUI.ACCENT:
	set(v):
		color = v
		queue_redraw()
var frame_color := Color.TRANSPARENT:
	set(v):
		frame_color = v
		queue_redraw()
var kind := &"infantry"


func _init(p_size := Vector2(30, 20)) -> void:
	custom_minimum_size = p_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	draw_rect(r, Color(color, 0.30), true)
	var edge := frame_color if frame_color.a > 0.0 else color.lightened(0.35)
	draw_rect(r, edge, false, 1.5)
	if kind == &"infantry":
		var ink := Color(color.lightened(0.6), 0.95)
		draw_line(r.position, r.end, ink, 1.5, true)
		draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), ink, 1.5, true)
