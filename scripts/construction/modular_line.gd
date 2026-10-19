## Layout of linear structures (HESCO, fences, concrete barriers): one implementation for
## every type, driven by StructureDef.module_length and StructureDef.layout.
##
## Segments are whole multiples of the module length (the cursor end is snapped), so
## modules are never stretched. A segment that ends on a snapped connection point may be
## up to MAX_SPACING_DEVIATION off; its modules are then spaced evenly (overlapping or
## leaving a hairline joint) but keep their real size. SPAN lays modules end to end between the points
## (fence panels, barriers); CENTERED puts a module center on every point and lets the
## next segment skip the shared corner module, so square HESCO cells meet face to face
## at right angles. Pure 2D math here; StructureManager fits the result to the terrain.
class_name ModularLine
extends RefCounted

## Largest relative change of module spacing accepted when an end snaps to a structure.
const MAX_SPACING_DEVIATION := 0.15


## End point for a segment from `from` toward `to`: whole modules, at least one.
## angle_step_deg > 0 snaps the direction to multiples of that angle, measured from
## ref_dir (the previous segment) when given, otherwise from world +X.
static func snap_end(def: StructureDef, from: Vector3, to: Vector3, angle_step_deg := 0.0, ref_dir := Vector2.ZERO) -> Vector3:
	var d := Vector2(to.x - from.x, to.z - from.z)
	var length := d.length()
	if length < 0.001:
		d = ref_dir if ref_dir != Vector2.ZERO else Vector2.RIGHT
		length = 0.0
	var ang := d.angle()
	if angle_step_deg > 0.0:
		var base := ref_dir.angle() if ref_dir != Vector2.ZERO else 0.0
		var step := deg_to_rad(angle_step_deg)
		ang = base + roundf((ang - base) / step) * step
	var n := maxi(1, roundi(length / def.module_length))
	var dir := Vector2.from_angle(ang)
	var e := Vector2(from.x, from.z) + dir * n * def.module_length
	return Vector3(e.x, to.y, e.y)


## True when a segment from a to b can end exactly at b without changing module spacing
## by more than MAX_SPACING_DEVIATION.
static func fits_exactly(def: StructureDef, a: Vector3, b: Vector3) -> bool:
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var n := maxi(1, roundi(length / def.module_length))
	return absf(length / n - def.module_length) <= def.module_length * MAX_SPACING_DEVIATION


## Number of modules a segment of this length holds.
static func segment_modules(def: StructureDef, a: Vector3, b: Vector3) -> int:
	return maxi(1, roundi(Vector2(b.x - a.x, b.z - a.z).length() / def.module_length))


## Modules of a polyline: [{center: Vector2, dir: Vector2 (unit, along the line), segment: int}].
static func modules(def: StructureDef, points: PackedVector3Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if points.size() < 2:
		return out
	var len_m := def.module_length
	var closed := def.layout == StructureDef.Layout.CENTERED and points.size() > 2 \
		and Vector2(points[0].x - points[-1].x, points[0].z - points[-1].z).length() < len_m * 0.25
	for s in points.size() - 1:
		var a := Vector2(points[s].x, points[s].z)
		var b := Vector2(points[s + 1].x, points[s + 1].z)
		var seg := b - a
		if seg.length() < 0.001:
			continue
		var dir := seg.normalized()
		var n := maxi(1, roundi(seg.length() / len_m))
		var step := seg.length() / n
		if def.layout == StructureDef.Layout.CENTERED:
			var last := n
			if closed and s == points.size() - 2:
				last = n - 1  # the closing corner is the first module of the line
			for i in range(0 if out.is_empty() else 1, last + 1):
				out.append({"center": a + dir * (i * step), "dir": dir, "segment": s})
		else:
			for i in n:
				out.append({"center": a + dir * ((i + 0.5) * step), "dir": dir, "segment": s})
	return out


## Total length of a polyline in meters (XZ).
static func length_of(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += Vector2(points[i + 1].x - points[i].x, points[i + 1].z - points[i].z).length()
	return total


## Yaw that turns local +X onto a horizontal direction.
static func yaw_of(dir: Vector2) -> float:
	return atan2(-dir.y, dir.x)
