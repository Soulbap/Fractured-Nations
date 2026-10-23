## EDITOR-WORLD-02C benchmark of the override layer on the real ref_20km chunks.
## Run: Godot --headless --path . -s res://tools/bench_world_overrides.gd -- [old|new] [out=<json path>]
## "old" loads the pre-revision layer copy from .godot/ew02_old (only exists in the author's tree).
## Overrides are programmatic generated-instance moves of 1 m inside their own cell; the chunk
## files and the override file on disk are never written (the layer is in memory only).
extends SceneTree

const MESHES := [1, 2, 3, 4, 5, 13, 14, 15, 16, 17, 18]
const COUNTS := [100, 500, 1000]

func _initialize() -> void:
	call_deferred("run")

func _layer_script(kind: String) -> GDScript:
	if kind == "old":
		return load("res://.godot/ew02_old/world_overrides_old.gd")
	return load("res://scripts/vegetation/world_overrides.gd")

func _stat(layer: Object, key: String) -> int:
	return int(layer.stats.get(key, 0))

func _summary(times: Array) -> Dictionary:
	var sum := 0.0
	var mx := 0.0
	for t in times:
		sum += t
		mx = maxf(mx, t)
	return {"avg_ms": snappedf(sum / maxi(times.size(), 1), 0.001), "max_ms": snappedf(mx, 0.001), "n": times.size()}

func _lookups(s: VegetationStreamer, cells: Array, n: int) -> Array:
	var times := []
	for i in n:
		var t0 := Time.get_ticks_usec()
		s.get_cell_instances(cells[i % cells.size()], MESHES)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
	return times

func run() -> void:
	var kind := "new"
	var out_path := ""
	for a in OS.get_cmdline_user_args():
		if a == "old" or a == "new":
			kind = a
		elif a.begins_with("out="):
			out_path = a.substr(4)
	var script := _layer_script(kind)
	var lib: VegetationLibrary = load("res://assets/environment/nordic_library.tres")
	var report := {"layer": kind}
	for count in COUNTS:
		var s := VegetationStreamer.new()
		s.data_directory = "res://worlds/ref_20km/vegetation"
		s.library = lib
		root.add_child(s)
		var layer = script.new(s, "res://.godot/ew02_bench.json")
		s.overrides = layer
		# Collect `count` real instances from chunks around Haugen, nearest chunk first.
		var recs := {}
		var cells := {}
		var per_cell := {}
		for loc in [Vector2i(-1, -1), Vector2i(-2, -5), Vector2i(-1, -2), Vector2i(-2, -2), Vector2i(0, -1), Vector2i(-2, -1), Vector2i(0, 0), Vector2i(-1, 0)]:
			var ch := s.get_chunk_sync(loc)
			if ch == null:
				continue
			var digest: String = layer.chunk_hash(loc)
			for cell in ch.cells:
				for mesh in ch.cells[cell]:
					if not MESHES.has(mesh):
						continue
					var buf: PackedFloat32Array = ch.cells[cell][mesh]
					for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
						if recs.size() >= count or per_cell.get(cell, 0) >= 10:
							break
						var xf := VegetationChunk.instance_transform(buf, i)
						xf.origin += Vector3(1, 0, 0)
						if VegetationChunk.cell_of(xf.origin, s.cell_size_m) != cell:
							continue
						recs[layer.generated_id(cell, mesh, i)] = {"kind": "generated", "cell": [cell.x, cell.y], "mesh": mesh,
							"index": i, "chunk_hash": digest, "transform": layer._encode(xf), "removed": false}
						cells[cell] = true
						per_cell[cell] = per_cell.get(cell, 0) + 1
		assert(recs.size() == count, "not enough instances: %d" % recs.size())
		var cell_list := cells.keys()
		var res := {"overrides": count, "cells": cell_list.size()}
		# Cold start: fresh layer state (no revision/index knowledge), chunks loaded.
		layer.records = recs.duplicate(true)
		if layer.has_method("reindex"):
			layer.reindex()
		if layer.has_method("forget_revisions"):
			layer.forget_revisions()
		var h0 := _stat(layer, "hashes")
		var t0 := Time.get_ticks_usec()
		var cold := _lookups(s, cell_list, 100)
		res.cold_100_lookups = _summary(cold)
		res.cold_first_load_ms = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
		res.cold_hashes = _stat(layer, "hashes") - h0
		# Warm lookups (everything already validated).
		h0 = _stat(layer, "hashes")
		res.warm_100_lookups = _summary(_lookups(s, cell_list, 100))
		res.warm_hashes = _stat(layer, "hashes") - h0
		res.warm_1000_lookups = _summary(_lookups(s, cell_list, 1000 if kind == "new" else 100))
		res.warm_hashes_1000 = _stat(layer, "hashes") - h0 - res.warm_hashes
		# Chunk unload / reload through the streamer path.
		h0 = _stat(layer, "hashes")
		var unloaded := 0
		var rt0 := Time.get_ticks_usec()
		for loc in s.chunks.keys():
			s.unload_chunk(loc) if s.has_method("unload_chunk") else s.chunks.erase(loc)
			unloaded += 1
		var reload := _lookups(s, cell_list, 100)
		res.reload_100_lookups = _summary(reload)
		res.reload_total_ms = snappedf((Time.get_ticks_usec() - rt0) / 1000.0, 0.01)
		res.reload_hashes = _stat(layer, "hashes") - h0
		res.chunks_unloaded = unloaded
		# Edit one override, then look up the affected cell.
		h0 = _stat(layer, "hashes")
		var first_id: String = recs.keys()[0]
		var rec: Dictionary = layer.records[first_id].duplicate(true)
		var xf: Transform3D = layer._decode(rec.transform)
		xf.origin += Vector3(0.5, 0, 0)
		rec.transform = layer._encode(xf)
		var e0 := Time.get_ticks_usec()
		if layer.has_method("put"):
			layer.put(first_id, rec)
		else:
			var before: Array = layer.affected_cells()
			layer.records[first_id] = rec
			layer._changed(before)
		var edit_ms := (Time.get_ticks_usec() - e0) / 1000.0
		var after := _lookups(s, cell_list, 100)
		res.edit_one_ms = snappedf(edit_ms, 0.001)
		res.after_edit_100_lookups = _summary(after)
		res.edit_hashes = _stat(layer, "hashes") - h0
		report["n%d" % count] = res
		print("EW02 BENCH ", kind, " ", JSON.stringify(res))
		s.free()
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	quit()
