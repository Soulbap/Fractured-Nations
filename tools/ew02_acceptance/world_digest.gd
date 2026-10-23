## Digest of the effective static world data of a VegetationStreamer, shared by the editor probe and the
## runtime test so both can be compared byte for byte (EW02B-08 / C5).
@tool
extends RefCounted


## Effective instances of every cell in `cells` as sorted text lines "cell mesh f0..f15".
static func lines(streamer: VegetationStreamer, cells: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for cell: Vector2i in cells:
		var by_mesh: Dictionary = streamer._effective_cell(cell)
		for mesh_id in by_mesh:
			var buf: PackedFloat32Array = streamer._filtered(cell, mesh_id, by_mesh[mesh_id])
			for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
				var parts := PackedStringArray([str(cell), str(mesh_id)])
				for k in VegetationChunk.FLOATS_PER_INSTANCE:
					parts.append("%.4f" % buf[i * VegetationChunk.FLOATS_PER_INSTANCE + k])
				out.append(" ".join(parts))
	out.sort()
	return out


## Same for what is displayed: the buffers of the active MultiMeshes in `cells` (+ their LOD).
static func displayed_lines(streamer: VegetationStreamer, cells: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for key: Vector3i in streamer.active:
		if not cells.has(Vector2i(key.x, key.y)):
			continue
		var buf: PackedFloat32Array = streamer.active[key].multimesh.buffer
		for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
			var parts := PackedStringArray([str(Vector2i(key.x, key.y)), str(key.z)])
			for k in VegetationChunk.FLOATS_PER_INSTANCE:
				parts.append("%.4f" % buf[i * VegetationChunk.FLOATS_PER_INSTANCE + k])
			out.append(" ".join(parts))
	out.sort()
	return out


static func sha(text_lines: PackedStringArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(text_lines).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Cells within `radius` cells of `centre`.
static func cells_around(centre: Vector2i, radius: int) -> Array:
	var out := []
	for x in range(centre.x - radius, centre.x + radius + 1):
		for z in range(centre.y - radius, centre.y + radius + 1):
			out.append(Vector2i(x, z))
	return out
