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
	&"bound": "<path d='M4 6L10 12L4 18M12 6L18 12L12 18'/>",
	&"follow": "<circle cx='17' cy='7' r='3'/><path d='M3 21L12 12M7 12H12V17'/>",
	&"hold": "<rect x='5' y='5' width='14' height='14'/><path d='M10 9V15M14 9V15'/>",
	&"regroup": "<path d='M3 3L9 9M9 4V9H4M21 3L15 9M15 4V9H20M3 21L9 15M9 20V15H4M21 21L15 15M15 20V15H20'/>",
	# Combat.
	&"assault": "<path d='M3 12H16M11 7L16 12L11 17M20 4V20'/>",
	&"suppress": "<path d='M3 7H8M11 7H14M17 7H21M3 12H10M13 12H21M3 17H8M11 17H14M17 17H21'/>",
	&"flank": "<path d='M5 21V13A8 8 0 0 1 13 5H20M16 1L20 5L16 9'/>",
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
