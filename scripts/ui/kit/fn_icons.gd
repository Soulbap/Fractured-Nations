## The UI kit's icon set (UI-01C): small military line icons as SVG on a 24 x 24 grid, 2 px square
## strokes, white (tinted by the control). They are rasterised at the size asked for, so they stay
## sharp at 16, 20 or 26 px. Only the icons the RTS HUD uses: unit type, orders, tactics, statuses.
## To add one: draw it on the 24 grid with the same stroke and append it to SHAPES.
class_name FNIcons
extends RefCounted

const SHAPES := {
	# Unit type: NATO friendly infantry frame.
	&"infantry": "<rect x='2' y='5' width='20' height='14'/><path d='M2 5L22 19M22 5L2 19'/>",
	# Movement orders.
	&"move": "<path d='M4 20L19 5M10 5H19V14'/>",
	&"bound": "<path d='M3 8H12M9 5L12 8L9 11M10 16H20M17 13L20 16L17 19'/>",
	&"follow": "<circle cx='18' cy='6' r='3'/><path d='M3 21L5.5 18.5M8 16L10.5 13.5M13 11L15 9'/>",
	&"hold": "<path d='M8 3H16L21 8V16L16 21H8L3 16V8Z M8 12H16'/>",
	&"regroup": "<path d='M3 3L9 9M9 4V9H4M21 3L15 9M15 4V9H20M3 21L9 15M9 20V15H4M21 21L15 15M15 20V15H20'/>",
	# Combat.
	&"assault": "<circle cx='17' cy='12' r='4'/><path d='M2 12H14M10 8L14 12L10 16'/>",
	&"suppress": "<path d='M3 12L19 5M3 12H19M3 12L19 19M21 4V7M21 10.5V13.5M21 17V20'/>",
	&"flank": "<rect x='15' y='10' width='6' height='6'/><path d='M3 21C3 9 7 5 13 5H20M17 2L20 5L17 8'/>",
	# Defence.
	&"defend": "<path d='M12 3L20 6V12C20 16.5 16.5 19.5 12 21C7.5 19.5 4 16.5 4 12V6Z'/>",
	&"withdraw": "<path d='M20 21V12A7 7 0 0 0 13 5H4M8 1L4 5L8 9'/>",
	# Squad settings.
	&"formation": "<circle cx='12' cy='5' r='2'/><circle cx='7' cy='12' r='2'/><circle cx='17' cy='12' r='2'/><circle cx='3' cy='19' r='2'/><circle cx='21' cy='19' r='2'/>",
	&"roe_free": "<circle cx='12' cy='12' r='6'/><path d='M12 2V8M12 16V22M2 12H8M16 12H22'/>",
	&"roe_hold": "<circle cx='12' cy='12' r='6'/><path d='M12 2V8M12 16V22M2 12H8M16 12H22M4 4L20 20'/>",
	# Statuses.
	&"idle": "<circle cx='12' cy='12' r='5'/>",
	&"moving": "<path d='M3 12H19M13 6L19 12L13 18'/>",
	&"engaged": "<path d='M12 2V8M12 16V22M2 12H8M16 12H22M5 5L9 9M19 5L15 9M5 19L9 15M19 19L15 15'/>",
	&"under_fire": "<path d='M12 3L22 20H2Z M12 9V14M12 16.5V17.5'/>",
	&"blocked": "<circle cx='12' cy='12' r='8'/><path d='M6.5 6.5L17.5 17.5'/>",
	&"tactic": "<path d='M12 3L21 12L12 21L3 12Z'/>",
	# Readouts.
	&"health": "<path d='M12 4V20M4 12H20'/>",
	&"ammo": "<path d='M9 21V9L12 3L15 9V21ZM9 15H15'/>",
	&"suppression": "<path d='M3 15C6 9 9 9 12 15C15 21 18 21 21 15'/>",
	&"soldiers": "<circle cx='12' cy='6' r='3'/><path d='M6 21V14A6 5 0 0 1 18 14V21'/>",
	# Construction (UI-01C phase 2): categories and tools.
	&"build": "<path d='M14 3L21 10L18 13L11 6Z M12.5 7.5L3 17L7 21L16.5 11.5'/>",
	&"base": "<path d='M6 21V3M6 4H18L15 8L18 12H6'/>",
	&"building": "<path d='M3 11L12 4L21 11M5 10V20H19V10M10 20V14H14V20'/>",
	&"training": "<circle cx='12' cy='12' r='9'/><circle cx='12' cy='12' r='4.5'/><path d='M12 11V13'/>",
	&"logistics": "<path d='M3 8L12 3L21 8V17L12 22L3 17Z M3 8L12 13L21 8M12 13V22'/>",
	&"wall": "<path d='M3 20V8H21V20Z M3 14H21M9 8V14M15 8V14M6 14V20M12 14V20M18 14V20'/>",
	&"infrastructure": "<path d='M12 21V10M8 21L12 10L16 21M6 6A8 8 0 0 1 18 6M9 8.5A4 4 0 0 1 15 8.5'/>",
	&"road": "<path d='M8 21L10 3M16 21L14 3M12 6V8M12 11V13M12 16V18'/>",
	&"demolish": "<path d='M4 6H20M9 6V3H15V6M6 6L7 21H17L18 6M10 10V17M14 10V17'/>",
	&"clearing": "<path d='M12 2L18 11H6Z M12 8L19 18H5Z M12 18V22'/>",
	&"save": "<path d='M4 4H17L20 7V20H4Z M8 4V9H15V4M7 20V14H17V20'/>",
	&"load": "<path d='M3 6H9L11 8H21V19H3Z'/>",
	&"rotate": "<path d='M20 12A8 8 0 1 1 17 5.6M20 3V8H15'/>",
	# FPS.
	&"rifle": "<path d='M2 10H15L17 8H22V11H18L16.5 13H12.5L11 17H8L9 13H2Z'/>",
	&"interact": "<path d='M8 13V5.5A1.5 1.5 0 0 1 11 5.5V11M11 10V4A1.5 1.5 0 0 1 14 4V10M14 10V6A1.5 1.5 0 0 1 17 6V14A7 7 0 0 1 10 21C7 21 5 19 4 16L3.5 13A1.5 1.5 0 0 1 6.5 12.5L8 15'/>",
	# Map and logistics.
	&"layers": "<path d='M12 3L22 8L12 13L2 8Z M2 12L12 17L22 12M2 16L12 21L22 16'/>",
	&"objective": "<circle cx='12' cy='12' r='8'/><circle cx='12' cy='12' r='3'/>",
	&"hq": "<path d='M12 2L14.9 8.6L22 9.3L16.6 14L18.2 21L12 17.3L5.8 21L7.4 14L2 9.3L9.1 8.6Z'/>",
	&"operation": "<path d='M3 19C9 19 9 7 16 7H21M18 4L21 7L18 10'/><circle cx='3.5' cy='19' r='1'/>",
	&"territory": "<path d='M12 2L21 7V17L12 22L3 17V7Z'/>",
	&"contact": "<path d='M12 3L21 12L12 21L3 12Z M12 8V13M12 15.5V16.5'/>",
	&"bridge": "<path d='M2 10H22M2 16H22M5 10V16M19 10V16M5 10A7 5 0 0 1 19 10'/>",
	&"vehicle": "<path d='M2 16V7H14V16M14 10H19L22 13V16H2'/><circle cx='6.5' cy='17.5' r='2'/><circle cx='17.5' cy='17.5' r='2'/>",
	&"fuel": "<path d='M12 3C15 8 18 11 18 15A6 6 0 0 1 6 15C6 11 9 8 12 3Z'/>",
	&"repair": "<path d='M4 20L13 11M14.5 4A5 5 0 0 0 20 9.5L16.5 9.5L14.5 7.5Z'/>",
	&"cargo": "<path d='M3 7H21V20H3Z M3 11H21M10 11V14H14V11'/>",
	&"route": "<circle cx='5' cy='18' r='2'/><circle cx='19' cy='6' r='2'/><path d='M7 18H15A3 3 0 0 0 15 12H9A3 3 0 0 1 9 6H17'/>",
	&"recruit": "<circle cx='9' cy='7' r='3'/><path d='M3 21V15A6 5 0 0 1 15 15V21M19 8V14M16 11H22'/>",
	&"stop": "<rect x='5' y='5' width='14' height='14'/>",
	&"unload": "<path d='M12 3V15M7 10L12 15L17 10M4 20H20'/>",
	&"drive": "<circle cx='12' cy='12' r='9'/><circle cx='12' cy='12' r='2'/><path d='M3.5 10H10M14 10H20.5M12 14V21'/>",
	&"clock": "<circle cx='12' cy='12' r='9'/><path d='M12 7V12L15 14'/>",
	&"check": "<path d='M4 12.5L9.5 18L20 6'/>",
	# GAMEPLAY-04
	&"development": "<circle cx='12' cy='12' r='3'/><path d='M12 2V5M12 19V22M2 12H5M19 12H22M4.9 4.9L7 7M17 17L19.1 19.1M4.9 19.1L7 17M17 7L19.1 4.9'/>",
	&"locked": "<rect x='5' y='11' width='14' height='10'/><path d='M8 11V7A4 4 0 0 1 16 7V11'/>",
	&"mission": "<path d='M5 21V3M5 4H19L16 8L19 12H5'/><circle cx='12' cy='8' r='1'/>",
	&"equipment": "<path d='M3 9H14L16 7H21V10H17L15.5 12H11L10 16H7L8 12H3Z M5 19H19'/>",
	# QOL-01 behaviour modes and camera focus.
	&"beh_safe": "<circle cx='12' cy='4' r='2'/><path d='M12 7V14M12 14L8 21M12 14L16 21M8 10H16'/>",
	&"beh_aware": "<path d='M2 12C6 5 18 5 22 12C18 19 6 19 2 12Z'/><circle cx='12' cy='12' r='3'/>",
	&"beh_combat": "<path d='M12 2L14 9L21 7L16 12L21 17L14 15L12 22L10 15L3 17L8 12L3 7L10 9Z'/>",
	&"beh_stealth": "<path d='M3 8C7 12 17 12 21 8M6 11L4.5 13M12 12V14.5M18 11L19.5 13M3 21H21M7 21L8 17M12 21V17M17 21L16 17'/>",
	&"garrison": "<path d='M4 21V11L12 6L20 11V21Z M12 6V2H16L15 3.5L16 5H12 M10 21V16H14V21'/>",
	&"rearm": "<rect x='3' y='11' width='18' height='10'/><path d='M7 11V5L8 3L9 5V11M11 11V5L12 3L13 5V11M15 11V5L16 3L17 5V11'/>",
	&"focus": "<path d='M3 8V3H8M16 3H21V8M21 16V21H16M8 21H3V16'/><circle cx='12' cy='12' r='3'/>",
	# UI-UX-03: dropdowns, the main navigation and time controls.
	&"chevron_down": "<path d='M6 9L12 15L18 9'/>",
	&"chevron_up": "<path d='M6 15L12 9L18 15'/>",
	&"more": "<path d='M5 12H6M11.5 12H12.5M18 12H19'/>",
	&"map": "<path d='M3 6L9 3L15 6L21 3V18L15 21L9 18L3 21Z M9 3V18M15 6V21'/>",
	&"menu": "<path d='M4 6H20M4 12H20M4 18H20'/>",
	&"pause": "<path d='M8 5V19M16 5V19'/>",
	&"play": "<path d='M7 4L19 12L7 20Z'/>",
	&"armoury": "<path d='M3 15H15L18 12H21M6 15V18H9V15M12 12V15M3 12H12'/>",
	&"close": "<path d='M6 6L18 18M18 6L6 18'/>",
	&"filter": "<path d='M3 5H21L14 13V20L10 18V13Z'/>",
	&"info": "<circle cx='12' cy='12' r='9'/><path d='M12 11V17M12 7V8'/>",
	&"relief":"<path d='M2 19C6 19 7 9 12 9C17 9 18 19 22 19M6 19C8 19 9 13 12 13C15 13 16 19 18 19'/>",
}

## Icons are rasterised larger than drawn and shrunk with mipmaps: the canvas is scaled up to the
## window (x1.67 at 1080p), so a texture of the logical size would be blurred.
const OVERSAMPLE := 3

static var _cache := {}


## The icon as a white texture of (px * OVERSAMPLE)^2 (Godot's SVG rasteriser, mipmapped, cached);
## draw it at px x px (rect() does).
static func texture(icon: StringName, px := FNUI.ICON_M) -> Texture2D:
	var key := "%s@%d" % [icon, px]
	if _cache.has(key):
		return _cache[key]
	var shape: String = SHAPES.get(icon, SHAPES[&"idle"])
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24'>" \
		+ "<g fill='none' stroke='#ffffff' stroke-width='2' stroke-linecap='square' stroke-linejoin='miter'>%s</g></svg>" % shape
	var img := Image.new()
	if img.load_svg_from_string(svg, px * OVERSAMPLE / 24.0) != OK:
		push_warning("FNIcons: icon %s did not rasterise" % icon)
		img = Image.create(px * OVERSAMPLE, px * OVERSAMPLE, false, Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## A TextureRect showing the icon, tinted.
static func rect(icon: StringName, px := FNUI.ICON_M, tint := FNUI.INK) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture(icon, px)
	r.modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return r
