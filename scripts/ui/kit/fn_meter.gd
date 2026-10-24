## Kit meter: caption, a segmented bar and the value ("HEALTH ▮▮▮▮▮▮▮▯ 92%"). value is 0..1;
## a negative value draws an empty, dimmed bar with value_text (e.g. "—" when unknown).
class_name FNMeter
extends Control

const SEGMENTS := 12

var caption := ""
var value := 1.0
var value_text := ""
var color := FNUI.OK
## A value that needs attention now (low health, heavy suppression): the bar pulses and is framed.
var critical := false:
	set(v):
		critical = v
		set_process(v)
		queue_redraw()
var caption_w := 58.0
var value_w := 28.0


func _init(p_caption := "", p_color := FNUI.OK) -> void:
	caption = p_caption
	color = p_color
	custom_minimum_size = Vector2(140, 11)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func _process(_delta: float) -> void:
	queue_redraw()


func set_value(v: float, text: String, c := Color.TRANSPARENT) -> void:
	if is_equal_approx(v, value) and text == value_text and (c.a == 0.0 or c == color):
		return
	value = v
	value_text = text
	if c.a > 0.0:
		color = c
	queue_redraw()


func _draw() -> void:
	var f := FNUI.caps_font()
	var nf := FNUI.font("semibold")
	var base := size.y * 0.5 + 3.0
	draw_string(f, Vector2(0, base), caption.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, caption_w, FNUI.CAPTION, FNUI.INK_2)
	var bx := caption_w
	var bw := size.x - caption_w - value_w - 6.0
	var gap := 1.5
	var sw := (bw - gap * (SEGMENTS - 1)) / SEGMENTS
	var filled := roundi(clampf(value, 0.0, 1.0) * SEGMENTS) if value >= 0.0 else 0
	if value > 0.0:
		filled = maxi(filled, 1)
	var on := color
	if critical:
		on = color.lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)))
		draw_rect(Rect2(bx - 2.0, size.y * 0.5 - 4.0, bw + 4.0, 8.0), Color(color, 0.8), false, 1.0)
	for i in SEGMENTS:
		var r := Rect2(bx + i * (sw + gap), size.y * 0.5 - 2.0, sw, 4.0)
		draw_rect(r, on if i < filled else Color(FNUI.LINE_STRONG, 0.45), true)
	draw_string(nf, Vector2(size.x - value_w, base), value_text, HORIZONTAL_ALIGNMENT_RIGHT, value_w, FNUI.LABEL,
		(color if critical else FNUI.INK) if value >= 0.0 else FNUI.INK_3)
