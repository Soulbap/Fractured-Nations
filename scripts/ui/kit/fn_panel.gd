## Kit panel: the HUD surface (FNUI.panel_style) with the kit theme, and an optional accent edge
## along the top (e.g. the faction colour of the Task Force).
class_name FNPanel
extends PanelContainer

var accent := Color.TRANSPARENT:
	set(v):
		accent = v
		queue_redraw()


func _init(p_accent := Color.TRANSPARENT, pad := FNUI.S4) -> void:
	accent = p_accent
	theme = FNUI.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", FNUI.panel_style(pad))


func _draw() -> void:
	if accent.a > 0.0:
		draw_rect(Rect2(1, 0, size.x - 2, 2), accent)
