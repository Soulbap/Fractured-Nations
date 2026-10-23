## Kit build card: a structure the player can place - thumbnail (rendered from the real model by
## tools/ui/make_structure_thumbs.gd, else the category icon), name, what it does and an optional note
## (why it is unavailable). States: hover, selected (being placed), disabled (rules forbid it now).
class_name FNBuildCard
extends Button

var thumb: TextureRect
var name_label: Label
var info_label: Label
var note_label: Label
var selected := false:
	set(v):
		if v != selected:
			selected = v
			_restyle()

const THUMB := Vector2(52, 39)


func _init(title: String, info: String, thumb_tex: Texture2D, fallback_icon: StringName) -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(0, THUMB.y + 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", FNUI.S3)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 4
	h.offset_top = 4
	h.offset_right = -6
	h.offset_bottom = -4
	add_child(h)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = THUMB
	frame.add_theme_stylebox_override("panel", FNUI.box(Color(0.16, 0.19, 0.17, 1.0), Color(FNUI.LINE, 0.9), 1, 2, 0))
	h.add_child(frame)
	if thumb_tex:
		thumb = TextureRect.new()
		thumb.texture = thumb_tex
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		thumb = FNIcons.rect(fallback_icon, FNUI.ICON_L, FNUI.INK_2)
	frame.add_child(thumb)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	name_label = FNUI.label(title, FNUI.BODY + 1, FNUI.INK, "title")
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(name_label)
	info_label = FNUI.label(info, FNUI.CAPTION, FNUI.INK_2, "body")
	info_label.clip_text = true
	info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(info_label)
	note_label = FNUI.label("", FNUI.CAPTION - 1, FNUI.WARN, "caps")
	note_label.visible = false
	v.add_child(note_label)
	mouse_entered.connect(_restyle)
	mouse_exited.connect(_restyle)
	_restyle()


## Available or not, with the reason shown on the card when not.
func set_available(on: bool, why := "") -> void:
	disabled = not on
	note_label.text = why
	note_label.visible = not on and why != ""
	_restyle()


func _restyle() -> void:
	var st := &"normal"
	if disabled:
		st = &"disabled"
	elif selected:
		st = &"selected_hover" if is_hovered() else &"selected"
	elif is_hovered():
		st = &"hover"
	var sb := FNUI.state_style(st, 0)
	if st == &"normal":
		sb.bg_color = Color(FNUI.BG_RAISED, 0.55)
		sb.border_color = Color(FNUI.LINE, 0.7)
	add_theme_stylebox_override("normal", sb)
	add_theme_stylebox_override("hover", sb)
	add_theme_stylebox_override("disabled", sb)
	add_theme_stylebox_override("pressed", FNUI.state_style(&"pressed", 0))
	thumb.modulate.a = 0.4 if disabled else 1.0
	name_label.add_theme_color_override("font_color", FNUI.INK_3 if disabled else FNUI.INK)
	queue_redraw()


func _draw() -> void:
	if selected:
		draw_rect(Rect2(0, 0, 2, size.y), FNUI.ACCENT)
