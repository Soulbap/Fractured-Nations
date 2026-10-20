## One buildable structure type (building, barrier module, gate ...).
##
## Pure description: size, how it sits on the terrain, how it is validated, its collision
## boxes and which mesh shows it. Placed structures (StructureState) only store the type
## id; everything that follows from the type is read from here. Linear types (HESCO,
## fences, concrete barriers) are placed as lines of repeated modules by ModularLine.
## Local axes follow the asset convention: +X is the module's length / the building's
## width, -Z is its front (Blender +Y), origin on the ground at the footprint center.
class_name StructureDef
extends Resource

enum Layout {
	## Modules end to end from point to point (fences, concrete barriers).
	SPAN,
	## Module centers on the points, consecutive segments share the corner module (HESCO
	## cells: square cells meet face to face at right-angle corners).
	CENTERED,
}

## WORLD-PLAYTEST-01: ground surfaces built into the terrain itself (graded and painted,
## no mesh, no collision box): roads drawn as curves and paved areas drawn as polygons.
enum Surface {
	## A structure with a mesh (everything before WORLD-PLAYTEST-01).
	NONE,
	## A road: a curve through control points, graded along its length; part of the world's
	## road network (RoadNetwork), so routes prefer it.
	ROAD,
	## A paved area (vehicle yard, motor pool, hardstanding): a polygon graded to one plane.
	## Not a road: it opens no navigation shortcut.
	AREA,
}

enum Fit {
	## Level, set into the ground at the mean height (buildings).
	LEVEL,
	## Level steps per module (HESCO cells on a slope are stepped, never tilted).
	STEP,
	## Rotated to follow the slope along the line (rigid concrete).
	PITCH,
	## Posts stay vertical, the module is sheared along the slope (fences).
	SHEAR,
}

@export var id: StringName
@export var display_name := ""
@export var category := "Buildings"
@export_multiline var description := ""
## GLB with one mesh (Blender pipeline output). Empty: a placeholder box of `size`.
@export_file("*.glb") var mesh_path := ""
## Footprint width (X) x height (Y) x depth (Z) in meters.
@export var size := Vector3(4, 3, 4)
@export var linear := false
## Module length along local X for linear types (also the line length step).
@export var module_length := 0.0
@export var layout := Layout.SPAN
@export var fit := Fit.LEVEL
## Steepest ground slope accepted under the footprint / along a module.
@export var max_slope_deg := 8.0
## Largest height difference accepted under the footprint (the asset's foundation skirt
## hides up to half of it below the floor).
@export var max_ground_gap := 0.8
## Lowered into the ground by this much after fitting.
@export var sink := 0.05
## Carved out of the navmesh (gates are not: soldiers walk through them).
@export var blocks_navigation := true
## Local-space collision boxes; empty means one box of `size` (unless `walkable`).
@export var collision_boxes: Array[AABB] = []
## WORLD-INTEGRATION-03: no collision body and no navmesh obstacle at all (parking pads,
## low-crawl wire, tyre runs, camouflage nets, signs): units walk over / under it. The
## footprint (`size`) is still used for overlap and terrain checks.
@export var walkable := false
## Local-space walkable wedges (stairs): the box rises from y0 at max Z to y1 at min Z.
@export var ramps: Array[AABB] = []
## Lines snap their ends to structures with the same group (fence <-> gate, hesco <-> hesco).
@export var connect_group: StringName
## Local points other lines can snap to (gate posts). Lines expose their two ends.
@export var snap_points: PackedVector3Array = PackedVector3Array()
## Placeholder colour when no mesh exists.
@export var color := Color(0.5, 0.5, 0.45)
## Cells farther than this from the camera do not draw the type at all.
@export var visible_range := 1600.0
## WORLD-PLAYTEST-01 ground surfaces (roads, areas). surface != NONE: no mesh or collision;
## StructureManager grades the terrain and paints the control map instead.
@export var surface := Surface.NONE
## Full surface width (m) of a road (carriageway and shoulders).
@export var surface_width := 0.0
## Terrain3D texture ids and blend painted on the surface.
@export var surface_texture := 0
@export var surface_overlay := 0
@export_range(0.0, 1.0) var surface_blend := 0.3
## Steepest grade (rise / run) along a road or across an area after grading.
@export var max_grade := 0.12
## Largest cut or fill (m) the grading may make.
@export var max_cut := 3.0
## Travel cost per metre on the strategic grid (open ground = 1.0; world tracks 0.45).
@export var travel_cost := 0.5


func is_surface() -> bool:
	return surface != Surface.NONE


func footprint() -> Vector2:
	return Vector2(size.x, size.z)


## Footprint used for overlap tests (a line module is module_length long).
func module_footprint() -> Vector2:
	return Vector2(module_length if linear else size.x, size.z)


## Local bounds of everything solid (collision boxes and ramps); the footprint used for
## overlap and terrain checks, which may be off-center (tower stairs).
func bounds() -> AABB:
	var b := AABB()
	var first := true
	for box in get_collision_boxes() + ramps:
		b = box if first else b.merge(box)
		first = false
	if first:
		# Nothing solid (walkable): the footprint is the asset's size.
		b = AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
	if linear:
		b.position.x = -module_length * 0.5
		b.size.x = module_length
	return b


func get_collision_boxes() -> Array[AABB]:
	if walkable:
		return []
	if not collision_boxes.is_empty():
		return collision_boxes
	return [AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)]
