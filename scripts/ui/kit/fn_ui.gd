## FRACTURED NATIONS UI kit (UI-01C): the design tokens (colour, type, spacing, icon sizes), the
## fonts, the style boxes for every interaction state and the shared Theme. The components in
## scripts/ui/kit/ and the HUD panels build on it; a panel sets `theme = FNUI.theme()` and only
## overrides what differs. Nothing here knows about squads or the war.
class_name FNUI
extends RefCounted

# --- Colour ---------------------------------------------------------------------------------------
## Surfaces, darkest to lightest.
const BG := Color("0b0f0c")
const BG_PANEL := Color(0.051, 0.067, 0.055, 0.90)
const BG_RAISED := Color(0.090, 0.114, 0.098, 0.92)
const BG_HOVER := Color(0.145, 0.180, 0.157, 0.96)
const BG_PRESSED := Color(0.075, 0.094, 0.082, 1.0)
## Hairlines and frames.
const LINE := Color(0.200, 0.239, 0.212, 1.0)
const LINE_STRONG := Color(0.329, 0.380, 0.345, 1.0)
## Text: primary, secondary, tertiary (captions, disabled).
const INK := Color("e8ebe3")
const INK_2 := Color("a9b1a5")
const INK_3 := Color("687264")
## Interaction accent (selection, focus) and the armed / attention accent.
const ACCENT := Color("5fa9e8")
const ARMED := Color("e3b04f")
## Status colours. Always paired with an icon or a word, never colour alone.
const OK := Color("86c46c")
const WARN := Color("e3b04f")
const ALERT := Color("e8853f")
const DANGER := Color("e25a4a")
const INFO := Color("8cc2ec")
const NEUTRAL := Color("d9ddd3")

# --- Type -----------------------------------------------------------------------------------------
## All sizes are in the project's logical canvas (1152 x 648, stretch mode canvas_items): x1.67 at
## 1080p, x1.11 at 720p. Caption, label, body, title, headline.
const CAPTION := 9
const LABEL := 10
const BODY := 11
const TITLE := 13
const HEADLINE := 16

# --- Spacing and sizes ------------------------------------------------------------------------------
const S1 := 1
const S2 := 3
const S3 := 6
const S4 := 8
const S5 := 12
const RADIUS := 2
const ICON_S := 11
const ICON_M := 14
const ICON_L := 18
## Gap between the HUD and the screen edge.
const EDGE := 10

static var _theme: Theme
static var _fonts := {}


## Barlow Condensed (headers, labels, numbers) and Barlow (body); SIL OFL, assets/ui/fonts/.
## weight: "regular", "medium", "semibold", "bold"; condensed false = Barlow (body text).
static func font(weight := "medium", condensed := true, tracking := 0) -> Font:
	var key := "%s/%s/%d" % [weight, condensed, tracking]
	if _fonts.has(key):
		return _fonts[key]
	var file: String = {"regular": "Regular", "medium": "Medium", "semibold": "SemiBold", "bold": "Bold"}.get(weight, "Medium")
	if not condensed and file == "Bold":
		file = "SemiBold"
	var path := "res://assets/ui/fonts/%s-%s.ttf" % ["BarlowCondensed" if condensed else "Barlow", file]
	var base: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	var f: Font = base
	if tracking != 0:
		var v := FontVariation.new()
		v.base_font = base
		v.spacing_glyph = tracking
		f = v
	_fonts[key] = f
	return f


## Uppercase caption style: condensed semibold with a little tracking.
static func caps_font() -> Font:
	return font("semibold", true, 1)


# --- Style boxes ------------------------------------------------------------------------------------

static func box(fill: Color, border := Color.TRANSPARENT, width := 1, radius := RADIUS, pad := S3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(width if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


## A HUD panel: dark, slightly translucent, a hairline frame and a soft shadow that lifts it off
## the terrain (FNPanel adds the optional accent edge).
static func panel_style(pad := S4) -> StyleBoxFlat:
	var s := box(BG_PANEL, Color(LINE_STRONG, 0.75), 1, RADIUS, pad)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 2)
	return s


## Interactive surface in one of the states: normal, hover, pressed, selected, armed, disabled.
static func state_style(state: StringName, pad := S3) -> StyleBoxFlat:
	match state:
		&"hover":
			return box(BG_HOVER, Color(INK_2, 0.55), 1, RADIUS, pad)
		&"pressed":
			return box(BG_PRESSED, ACCENT, 1, RADIUS, pad)
		&"selected":
			var s := box(Color(ACCENT, 0.17), ACCENT, 1, RADIUS, pad)
			return s
		&"selected_hover":
			return box(Color(ACCENT, 0.24), ACCENT.lightened(0.2), 1, RADIUS, pad)
		&"armed":
			return box(Color(ARMED, 0.20), ARMED, 1, RADIUS, pad)
		&"disabled":
			return box(Color(BG_RAISED, 0.55), Color(LINE, 0.6), 1, RADIUS, pad)
		_:
			return box(BG_RAISED, LINE, 1, RADIUS, pad)


## A keycap: the hotkey hint shown on buttons and in the hint bar.
static func keycap_style() -> StyleBoxFlat:
	var s := box(Color(0, 0, 0, 0.25), Color(INK_3, 0.8), 1, 2, 0)
	s.content_margin_left = 3
	s.content_margin_right = 3
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	return s


# --- Theme ------------------------------------------------------------------------------------------

## The shared Theme: fonts, label colours, button states, scroll bars and tooltips.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("medium", false)
	t.default_font_size = BODY
	t.set_color("font_color", "Label", INK)
	t.set_constant("line_spacing", "Label", 0)
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "Button", state_style(StringName(st)))
	t.set_stylebox("hover_pressed", "Button", state_style(&"pressed"))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", caps_font())
	t.set_font_size("font_size", "Button", LABEL)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_hover_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", INK_3)
	t.set_color("icon_normal_color", "Button", INK)
	t.set_color("icon_disabled_color", "Button", INK_3)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	# Thin scroll bar: a 3 px grabber on a hairline track.
	var track := box(Color(LINE, 0.5), Color.TRANSPARENT, 0, 1, 0)
	track.content_margin_left = 2
	var grab := box(LINE_STRONG, Color.TRANSPARENT, 0, 1, 0)
	grab.content_margin_left = 2
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", box(INK_2, Color.TRANSPARENT, 0, 2, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT, Color.TRANSPARENT, 0, 2, 0))
	var tip := box(Color(BG, 0.97), LINE_STRONG, 1, RADIUS, S3)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_font("font", "TooltipLabel", font("regular", false))
	t.set_font_size("font_size", "TooltipLabel", LABEL)
	t.set_color("font_color", "TooltipLabel", INK)
	_theme = t
	return t


## A Label in the kit's type scale. kind: "caps" (uppercase caption), "title", "body", "number".
static func label(text := "", size := LABEL, color := INK, kind := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	match kind:
		"caps":
			l.add_theme_font_override("font", caps_font())
			l.uppercase = true
		"title":
			l.add_theme_font_override("font", font("semibold"))
		"number":
			l.add_theme_font_override("font", font("semibold"))
		_:
			l.add_theme_font_override("font", font("regular", false))
	return l


## A compact action button: icon + uppercase text on the kit surfaces (secondary actions in inspectors,
## where a large FNCommandButton would be too much). toggle: shows the selected surface while pressed.
static func action_button(icon_name: StringName, text: String, tip := "", toggle := false) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = toggle
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 20)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", CAPTION)
	b.add_theme_constant_override("icon_max_width", ICON_S)
	b.add_theme_constant_override("h_separation", S3 - 1)
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var sb := state_style(&"selected" if st in ["pressed", "hover_pressed"] and toggle else StringName(st), 0)
		sb.content_margin_left = 6
		sb.content_margin_right = 7
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		b.add_theme_stylebox_override(st, sb)
	if icon_name != &"":
		b.icon = FNIcons.texture(icon_name, ICON_S)
	return b


## A keycap hint ("Z", "RMB", "F1").
static func keycap(key: String, size := CAPTION) -> Label:
	var l := label(key, size, INK_2, "caps")
	l.add_theme_stylebox_override("normal", keycap_style())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## UI-UX-03: the screen point of a world position for a HUD marker, or Vector2.INF when it is not drawable: behind the camera,
## or so far off the viewport that it is no marker the player can see. A point just in front of the camera plane projects to
## coordinates near 1e9, where a 9 px diamond loses its size in float precision and the canvas cannot triangulate it.
static func project(cam: Camera3D, p: Vector3, margin := 200.0) -> Vector2:
	if cam == null or not p.is_finite() or cam.is_position_behind(p):
		return Vector2.INF
	var s := cam.unproject_position(p)
	var r := cam.get_viewport().get_visible_rect().grow(margin)
	return s if s.is_finite() and r.has_point(s) else Vector2.INF
