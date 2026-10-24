## Kit health bar (first person): the cross icon, a bar and the value. Below LOW the bar and the
## number turn red and pulse, so a wounded soldier reads at a glance without a new damage system.
class_name FNHealthBar
extends Control

const LOW := 0.35

var value := 100.0
var max_value := 100.0


func _init() -> void:
	custom_minimum_size = Vector2(170, 18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_health(v: float, m: float) -> void:
	value = v
	max_value = maxf(m, 1.0)
	queue_redraw()


func _process(_delta: float) -> void:
	if value / max_value < LOW:
		queue_redraw()


func _draw() -> void:
	var f := clampf(value / max_value, 0.0, 1.0)
	var low := f < LOW
	var col := FNUI.OK if f >= 0.6 else (FNUI.WARN if not low else FNUI.DANGER)
	if low:
		col = col.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)))
	draw_texture_rect(FNIcons.texture(&"health", FNUI.ICON_S), Rect2(0, size.y * 0.5 - 6, 12, 12), false, col)
	var x0 := 18.0
	var x1 := size.x - 30.0
	var r := Rect2(x0, size.y * 0.5 - 4, x1 - x0, 8)
	draw_rect(r, Color(FNUI.BG, 0.6), true)
	draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), col, true)
	draw_rect(r, Color(FNUI.LINE_STRONG, 0.7), false, 1.0)
	draw_string(FNUI.font("semibold"), Vector2(x1 + 4, size.y * 0.5 + 5), str(ceili(value)), HORIZONTAL_ALIGNMENT_RIGHT, 26, FNUI.TITLE,
		FNUI.DANGER if low else FNUI.INK)
