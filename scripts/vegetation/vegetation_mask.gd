## World-aligned exclusion mask for ground vegetation (grass): 1 where no grass may
## grow (road surfaces and their margins, base pads), 0 elsewhere, with a short soft
## edge. One texel is a few meters; the GPU grass samples it bilinearly and the CPU
## side can query it for tests or future placement rules (buildings, trenches ...).
##
## Built deterministically from world data by WorldBuilder and stored as
## worlds/<name>/vegetation/mask.res.
class_name VegetationMask
extends Resource

## World XZ of the corner of texel (0, 0).
@export var origin := Vector2(-1024, -1024)
@export var texel_m := 2.0
@export var image: Image


func size_m() -> float:
	return image.get_width() * texel_m if image else 0.0


## Mask value 0..1 at a world position (nearest texel).
func value(x: float, z: float) -> float:
	if image == null:
		return 0.0
	var px := int((x - origin.x) / texel_m)
	var pz := int((z - origin.y) / texel_m)
	if px < 0 or pz < 0 or px >= image.get_width() or pz >= image.get_height():
		return 0.0
	return image.get_pixel(px, pz).r


func is_excluded(x: float, z: float) -> bool:
	return value(x, z) >= 0.5


func make_texture() -> ImageTexture:
	return ImageTexture.create_from_image(image)


## Builds the mask. polylines: Array of PackedVector3Array (world XZ in x/z),
## widths: full road width per polyline, discs: Array of [Vector2 center, radius].
## margin_m is added around roads; edge_m is the soft falloff beyond the hard edge.
static func build(half_size_m: float, p_texel_m: float, polylines: Array, widths: PackedFloat32Array,
		discs: Array, margin_m: float, edge_m: float) -> VegetationMask:
	var mask := VegetationMask.new()
	mask.texel_m = p_texel_m
	mask.origin = Vector2(-half_size_m, -half_size_m)
	var n := int(ceil(half_size_m * 2.0 / p_texel_m))
	var img := Image.create_empty(n, n, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	for li in polylines.size():
		var line: PackedVector3Array = polylines[li]
		var half_w: float = (widths[li] if li < widths.size() else 11.5) * 0.5 + margin_m
		for i in line.size() - 1:
			var a := Vector2(line[i].x, line[i].z)
			var b := Vector2(line[i + 1].x, line[i + 1].z)
			_paint(img, mask, a, b, half_w, edge_m)
	for d in discs:
		var c: Vector2 = d[0]
		_paint(img, mask, c, c, d[1], edge_m)
	mask.image = img
	return mask


static func _paint(img: Image, mask: VegetationMask, a: Vector2, b: Vector2, radius: float, edge_m: float) -> void:
	var t := mask.texel_m
	var reach := radius + edge_m
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)
	var x0 := maxi(int(floor((lo.x - mask.origin.x) / t)), 0)
	var z0 := maxi(int(floor((lo.y - mask.origin.y) / t)), 0)
	var x1 := mini(int(ceil((hi.x - mask.origin.x) / t)), img.get_width() - 1)
	var z1 := mini(int(ceil((hi.y - mask.origin.y) / t)), img.get_height() - 1)
	for pz in range(z0, z1 + 1):
		for px in range(x0, x1 + 1):
			var p := mask.origin + Vector2(px + 0.5, pz + 0.5) * t
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
			if d >= reach:
				continue
			var v := 1.0 if d <= radius else 1.0 - (d - radius) / edge_m
			var old := img.get_pixel(px, pz).r
			if v > old:
				img.set_pixel(px, pz, Color(v, v, v))
