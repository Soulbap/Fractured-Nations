## Compact vegetation instances for one world chunk (default 1024 x 1024 m), grouped by
## world cell (default 128 m) and mesh id.
##
## This is the stored form of trees, bushes and rocks: plain packed floats, no nodes.
## Each instance is 16 floats in MultiMesh buffer layout (3x4 transform rows + RGBA
## color), so a cell can be uploaded to a MultiMesh with one buffer assignment.
## Chunks are written by WorldBuilder.scatter_vegetation (deterministic per cell) and
## read by VegetationStreamer. Future persistent world state (felled trees, cover
## values) can live next to the same cell keys without touching the visuals.
@tool
class_name VegetationChunk
extends Resource

const FLOATS_PER_INSTANCE := 16

@export var location := Vector2i.ZERO
@export var chunk_size_m := 1024.0
@export var cell_size_m := 128.0
## world cell (Vector2i) -> { mesh_id (int): PackedFloat32Array }
@export var cells := {}


static func cell_of(pos: Vector3, cell_size: float) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.z / cell_size))


static func chunk_of(pos: Vector3, chunk_size: float) -> Vector2i:
	return Vector2i(floori(pos.x / chunk_size), floori(pos.z / chunk_size))


static func file_name(loc: Vector2i) -> String:
	return "veg_%d_%d.res" % [loc.x, loc.y]


## Appends one instance to the cell that contains it.
func add_instance(mesh_id: int, xf: Transform3D, color: Color) -> void:
	var cell := cell_of(xf.origin, cell_size_m)
	var by_mesh: Dictionary = cells.get(cell, {})
	append_to(by_mesh, mesh_id, xf, color)
	cells[cell] = by_mesh


## Appends one instance in MultiMesh buffer layout to a { mesh_id: buffer } dictionary.
static func append_to(by_mesh: Dictionary, mesh_id: int, xf: Transform3D, color: Color) -> void:
	var buf: PackedFloat32Array = by_mesh.get(mesh_id, PackedFloat32Array())
	var b := xf.basis
	var o := xf.origin
	buf.append_array(PackedFloat32Array([
		b.x.x, b.y.x, b.z.x, o.x,
		b.x.y, b.y.y, b.z.y, o.y,
		b.x.z, b.y.z, b.z.z, o.z,
		color.r, color.g, color.b, color.a]))
	by_mesh[mesh_id] = buf


static func instance_transform(buf: PackedFloat32Array, i: int) -> Transform3D:
	var k := i * FLOATS_PER_INSTANCE
	return Transform3D(
		Vector3(buf[k], buf[k + 4], buf[k + 8]),
		Vector3(buf[k + 1], buf[k + 5], buf[k + 9]),
		Vector3(buf[k + 2], buf[k + 6], buf[k + 10]),
		Vector3(buf[k + 3], buf[k + 7], buf[k + 11]))


func instance_count() -> int:
	var n := 0
	for cell in cells:
		for mesh_id in cells[cell]:
			n += cells[cell][mesh_id].size() / FLOATS_PER_INSTANCE
	return n


func counts_by_mesh() -> Dictionary:
	var out := {}
	for cell in cells:
		for mesh_id in cells[cell]:
			out[mesh_id] = out.get(mesh_id, 0) + cells[cell][mesh_id].size() / FLOATS_PER_INSTANCE
	return out
