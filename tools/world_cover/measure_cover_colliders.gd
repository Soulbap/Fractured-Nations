## WORLD-COVER-01.1: measures the natural cover assets (library ids 25-30) against their colliders and fits a few boxes per variant.
##
##   Godot_console.exe --headless --path . --script res://tools/world_cover/measure_cover_colliders.gd [--write]
##
## Every variant's LOD0 mesh is rasterised into a 0.1 m height map over its local XZ plane (instance space, scale 1). The fit walks
## along the local x axis in 0.2 m slices (the long axis of every kind): a slice's top is the 85th percentile of the heights it
## covers, its depth the cells at least half that tall; neighbouring slices of similar top join into one box; a gap (no cell over
## 0.2 m) ends a box. At most MAX_PARTS boxes per variant (the most alike neighbours merge).
## For the single box of the id and for the fitted boxes it reports:
##   covered  share of the mesh's solid cells (>= 0.3 m tall) inside a box up to that height (protection that is modelled)
##   phantom  share of the boxes' footprint where the mesh is lower than half the box (bullets stopped by nothing visible)
## --write puts the fitted parts into assets/environment/nordic_library.tres (VegetationMeshDef.parts, one list per variant).
extends SceneTree

const LIB := "res://assets/environment/nordic_library.tres"
const IDS := [25, 26, 27, 28, 29, 30]
## Ids whose fitted boxes are written (--write): the timber stack keeps its one box (its fit trims the stack's protruding log ends).
const WRITE_IDS := [25, 26, 27, 28, 29]
const CELL := 0.1
const SLICE := 0.2
const MAX_PARTS := 4


func _init() -> void:
	var lib: Resource = load(LIB)
	var out := {}
	var parts_by_id := {}
	for d in lib.meshes:
		if not int(d.id) in IDS:
			continue
		var scenes: Array = [d.scene] + Array(d.variants)
		var rows: Array = []
		var plist: Array[PackedFloat32Array] = []
		for vi in scenes.size():
			var hm := _height_map(scenes[vi])
			var single := [PackedFloat32Array([2.0, 0.0, 0.0, d.box.x, d.box.y, d.box.z])]
			var fitted := _fit(hm)
			var flat := PackedFloat32Array()
			for p: PackedFloat32Array in fitted:
				flat.append_array(p)
			plist.append(flat)
			rows.append({"variant": vi, "size": hm.size, "single": _score(hm, single), "fitted": _score(hm, fitted),
				"parts": fitted.map(func(p: PackedFloat32Array) -> Array: return Array(p).map(func(v: float) -> float: return snappedf(v, 0.01)))})
		out[str(d.id) + " " + String(d.name)] = rows
		parts_by_id[int(d.id)] = plist
	print("COVER_COLLIDERS ", JSON.stringify(out, "  "))
	if "--write" in OS.get_cmdline_user_args() or "--write" in OS.get_cmdline_args():
		_write(parts_by_id)
	quit()


## {cells: Dictionary Vector2i -> max height, size: [x0, x1, z0, z1]} of the scene's LOD0 meshes (local space of the scene root).
func _height_map(ps: PackedScene) -> Dictionary:
	var root := ps.instantiate()
	var cells := {}
	var lo := Vector2(INF, INF)
	var hi := -lo
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not String(mi.name).ends_with("LOD0"):
			continue
		var xf := _local_xf(mi, root)
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a := xf * faces[i]
			var b := xf * faces[i + 1]
			var c := xf * faces[i + 2]
			var n := maxi(1, ceili(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / (CELL * 0.6)))
			for u in n + 1:
				for v in n + 1 - u:
					var p := a + (b - a) * (float(u) / n) + (c - a) * (float(v) / n)
					var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
					if p.y > float(cells.get(k, -INF)):
						cells[k] = p.y
					lo = lo.min(Vector2(p.x, p.z))
					hi = hi.max(Vector2(p.x, p.z))
	root.free()
	return {"cells": cells, "size": [snappedf(lo.x, 0.01), snappedf(hi.x, 0.01), snappedf(lo.y, 0.01), snappedf(hi.y, 0.01)]}


func _local_xf(n: Node3D, root: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Boxes [2, centre x, centre z, half x, height, half z] along local x.
func _fit(hm: Dictionary) -> Array:
	var cells: Dictionary = hm.cells
	var by_slice := {}
	for k: Vector2i in cells:
		var h: float = cells[k]
		if h < 0.2:
			continue
		var s := floori(k.x * CELL / SLICE)
		if not by_slice.has(s):
			by_slice[s] = []
		by_slice[s].append([k.y, h])
	var keys := by_slice.keys()
	keys.sort()
	var slices: Array = []  # [s, top, zmin, zmax]
	for s: int in keys:
		var hs: Array = (by_slice[s] as Array).map(func(e: Array) -> float: return e[1])
		hs.sort()
		var top: float = hs[int(hs.size() * 0.85)]
		var zmin := INF
		var zmax := -INF
		for e: Array in by_slice[s]:
			if float(e[1]) >= top * 0.5:
				zmin = minf(zmin, int(e[0]) * CELL)
				zmax = maxf(zmax, (int(e[0]) + 1) * CELL)
		slices.append([s, top, zmin, zmax])
	# Runs of neighbouring slices with a similar top.
	var parts: Array = []
	var cur: Array = []
	for sl: Array in slices:
		if not cur.is_empty():
			var last: Array = cur[cur.size() - 1]
			var avg := _avg_top(cur)
			if int(sl[0]) != int(last[0]) + 1 or absf(float(sl[1]) - avg) > 0.25:
				parts.append(cur)
				cur = []
		cur.append(sl)
	if not cur.is_empty():
		parts.append(cur)
	# Short slivers (< 0.4 m) join their neighbour; then the most alike neighbours merge down to MAX_PARTS.
	while parts.size() > 1:
		var worst := -1
		var worst_cost := INF
		for i in parts.size() - 1:
			var cost := absf(_avg_top(parts[i]) - _avg_top(parts[i + 1])) + 0.2 * float(int(parts[i + 1][0][0]) - int(parts[i][parts[i].size() - 1][0]) - 1)
			var short := mini(parts[i].size(), parts[i + 1].size()) * SLICE < 0.4
			if short:
				cost -= 10.0
			if cost < worst_cost:
				worst_cost = cost
				worst = i
		if parts.size() <= MAX_PARTS and worst_cost > -5.0:
			break
		parts[worst] = parts[worst] + parts[worst + 1]
		parts.remove_at(worst + 1)
	var out: Array = []
	for run: Array in parts:
		var x0 := int(run[0][0]) * SLICE
		var x1 := (int(run[run.size() - 1][0]) + 1) * SLICE
		var zs0: Array = run.map(func(sl: Array) -> float: return sl[2])
		var zs1: Array = run.map(func(sl: Array) -> float: return sl[3])
		zs0.sort()
		zs1.sort()
		var z0: float = zs0[int(zs0.size() * 0.15)]
		var z1: float = zs1[int(zs1.size() * 0.85)]
		var tops: Array = run.map(func(sl: Array) -> float: return sl[1])
		tops.sort()
		out.append(PackedFloat32Array([2.0, (x0 + x1) * 0.5, (z0 + z1) * 0.5, (x1 - x0) * 0.5, tops[tops.size() / 2], (z1 - z0) * 0.5]))
	return out


func _avg_top(run: Array) -> float:
	var t := 0.0
	for sl: Array in run:
		t += float(sl[1])
	return t / run.size()


func _score(hm: Dictionary, parts: Array) -> Dictionary:
	var cells: Dictionary = hm.cells
	var solid := 0
	var covered := 0
	for k: Vector2i in cells:
		var h: float = cells[k]
		if h < 0.3:
			continue
		solid += 1
		var p := Vector2((k.x + 0.5) * CELL, (k.y + 0.5) * CELL)
		for b: PackedFloat32Array in parts:
			if absf(p.x - b[1]) <= b[3] and absf(p.y - b[2]) <= b[5] and b[4] >= h * 0.8:
				covered += 1
				break
	var area := 0
	var phantom := 0
	for b: PackedFloat32Array in parts:
		for ix in range(floori((b[1] - b[3]) / CELL), ceili((b[1] + b[3]) / CELL)):
			for iz in range(floori((b[2] - b[5]) / CELL), ceili((b[2] + b[5]) / CELL)):
				area += 1
				if float(cells.get(Vector2i(ix, iz), 0.0)) < b[4] * 0.5:
					phantom += 1
	return {"covered": snappedf(float(covered) / maxi(solid, 1), 0.01), "phantom": snappedf(float(phantom) / maxi(area, 1), 0.01)}


## Writes `parts = Array[PackedFloat32Array]([...])` into each id's sub-resource of the library (text edit: the rest of the file
## stays as it is).
func _write(parts_by_id: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(LIB)
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var out := PackedStringArray()
	var cur_id := -1
	for line in lines:
		if line.begins_with("parts = "):
			continue
		if line.begins_with("[sub_resource"):
			cur_id = -1
		if line.begins_with("id = "):
			cur_id = int(line.trim_prefix("id = "))
		out.append(line)
		if line.begins_with("variants = ") and parts_by_id.has(cur_id) and cur_id in WRITE_IDS:
			var lists: Array = []
			for p: PackedFloat32Array in parts_by_id[cur_id]:
				lists.append("PackedFloat32Array(%s)" % ", ".join(Array(p).map(func(v: float) -> String: return str(snappedf(v, 0.001)))))
			out.append("parts = Array[PackedFloat32Array]([%s])" % ", ".join(lists))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	print("COVER_COLLIDERS written to ", LIB)
