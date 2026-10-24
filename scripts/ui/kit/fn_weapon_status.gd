## Kit weapon status (first person): weapon name, the rounds in the magazine as the largest figure,
## the reserve beside it, the fire mode as a chip and one tick per round of the magazine. Low
## magazine turns amber, empty red; while reloading the ticks become a progress bar.
class_name FNWeaponStatus
extends Control

var weapon_name := ""
var mag := 0
var mag_size := 30
var reserve := 0
var mode := "AUTO"
## 0..1 while reloading, < 0 otherwise.
var reload := -1.0

const W := 184.0
const H := 68.0


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(p_name: String, p_mag: int, p_size: int, p_reserve: int, p_mode: String, p_reload: float) -> void:
	if p_name == weapon_name and p_mag == mag and p_size == mag_size and p_reserve == reserve and p_mode == mode and is_equal_approx(p_reload, reload):
		return
	weapon_name = p_name
	mag = p_mag
	mag_size = maxi(p_size, 1)
	reserve = p_reserve
	mode = p_mode
	reload = p_reload
	queue_redraw()


func _draw() -> void:
	var nf := FNUI.font("semibold")
	var cf := FNUI.caps_font()
	var frac := float(mag) / mag_size
	var col := FNUI.INK if frac > 0.25 else (FNUI.WARN if mag > 0 else FNUI.DANGER)
	# Soft backing so the figures read on bright ground, no hard box.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(FNUI.BG, 0.55)
	bg.set_corner_radius_all(FNUI.RADIUS)
	bg.border_color = Color(FNUI.LINE_STRONG, 0.5)
	bg.border_width_right = 2
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	# Weapon line.
	var icon := FNIcons.texture(&"rifle", FNUI.ICON_M)
	draw_texture_rect(icon, Rect2(8, 5, 18, 18), false, Color(FNUI.INK_2, 0.9))
	draw_string(cf, Vector2(30, 17), weapon_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 80, FNUI.CAPTION, FNUI.INK_2)
	# Fire mode chip, top right.
	var mw := cf.get_string_size(mode, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION - 1).x + 8.0
	var chip := Rect2(size.x - mw - 8, 6, mw, 12)
	draw_rect(chip, Color(FNUI.INK_3, 0.25), true)
	draw_rect(chip, Color(FNUI.INK_2, 0.7), false, 1.0)
	draw_string(cf, chip.position + Vector2(4, 9.5), mode, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION - 1, FNUI.INK)
	# Magazine (large) and reserve.
	var big := str(mag)
	var bw := nf.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
	draw_string(nf, Vector2(8, 55), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, col)
	draw_string(nf, Vector2(8 + bw + 5, 55), "/ %d" % reserve, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.TITLE, FNUI.INK_2 if reserve > 0 else FNUI.DANGER)
	# Rounds: one tick each (or the reload progress).
	var x0 := 8.0
	var x1 := size.x - 8.0
	var y := size.y - 7.0
	if reload >= 0.0:
		draw_rect(Rect2(x0, y - 1, x1 - x0, 3), Color(FNUI.LINE_STRONG, 0.6), true)
		draw_rect(Rect2(x0, y - 1, (x1 - x0) * clampf(reload, 0.0, 1.0), 3), FNUI.INFO, true)
		draw_string(cf, Vector2(x1 - 58, 54), "RELOADING", HORIZONTAL_ALIGNMENT_RIGHT, 58, FNUI.CAPTION, FNUI.INFO)
	else:
		var step := (x1 - x0) / mag_size
		for i in mag_size:
			draw_rect(Rect2(x0 + i * step, y - 2, maxf(step - 1.0, 1.0), 4), col if i < mag else Color(FNUI.LINE_STRONG, 0.5), true)
