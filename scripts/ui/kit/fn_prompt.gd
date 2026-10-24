## Kit contextual prompt: keycap + action ("[R] RELOAD"), centred under the crosshair, only while it
## applies. tone: the status colour of the action (amber attention, red blocked).
class_name FNPrompt
extends PanelContainer

var key: Label
var action: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := FNUI.box(Color(FNUI.BG, 0.72), Color(FNUI.LINE_STRONG, 0.7), 1, FNUI.RADIUS, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	add_child(h)
	key = FNUI.keycap("", FNUI.LABEL)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(key)
	action = FNUI.label("", FNUI.LABEL, FNUI.INK, "caps")
	h.add_child(action)


func show_prompt(p_key: String, p_action: String, tone := FNUI.INK) -> void:
	key.text = p_key
	key.visible = p_key != ""
	action.text = p_action
	action.add_theme_color_override("font_color", tone)
	visible = true
	size = Vector2.ZERO
