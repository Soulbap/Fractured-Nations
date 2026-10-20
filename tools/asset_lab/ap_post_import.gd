@tool
extends EditorScenePostImport
## Import script for the ASSET-PRODUCTION-01 library (assets/military/**/*.glb).
##
## The GLBs carry material names only. This script
##  * replaces every surface material with the shared library material of the same name
##    (res://assets/military/materials/<name>.tres), so all assets share a few materials;
##  * sets visibility ranges on the authored <id>_LOD0/1/2 meshes from the asset's JSON
##    sidecar (lod_ranges), with a small margin so LODs do not flicker at the boundary;
##  * stores the sidecar's numbers (id, size, footprint, markers) as root metadata
##    "fn_asset" for tools and later gameplay integration.
## Asset-side only: no gameplay code depends on it.

const MAT_DIR := "res://assets/military/materials/"
const DEFAULT_RANGES := [[0.0, 60.0], [60.0, 240.0], [240.0, 1500.0]]


func _post_import(scene: Node) -> Object:
	var meta := {}
	var json_path := get_source_file().get_basename() + ".json"
	if FileAccess.file_exists(json_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary:
			meta = parsed
	var ranges: Array = meta.get("lod_ranges", DEFAULT_RANGES)
	_walk(scene, ranges)
	if not meta.is_empty():
		scene.set_meta("fn_asset", {
			"id": meta.get("id", ""), "family": meta.get("family", ""),
			"size_above_ground": meta.get("size_above_ground", []), "footprint_xy": meta.get("footprint_xy", []),
			"foundation_depth": meta.get("foundation_depth", 0.0), "markers": meta.get("markers", []),
		})
	return scene


func _walk(n: Node, ranges: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i)
				var path := MAT_DIR + (m.resource_name if m else "") + ".tres"
				if m and ResourceLoader.exists(path):
					mesh.surface_set_material(i, load(path))
		var nm := String(mi.name)
		if nm.contains("_LOD"):
			var lod := clampi(int(nm.get_slice("_LOD", 1)), 0, ranges.size() - 1)
			var r: Array = ranges[lod]
			mi.visibility_range_begin = float(r[0])
			mi.visibility_range_end = float(r[1])
			# One hysteresis margin per boundary, shared by both LODs that meet there, so
			# there is never a distance band where neither is visible.
			mi.visibility_range_begin_margin = _margin(float(r[0])) if lod > 0 else 0.0
			mi.visibility_range_end_margin = _margin(float(r[1]))
	for c in n.get_children():
		_walk(c, ranges)


static func _margin(boundary: float) -> float:
	return maxf(boundary * 0.03, 1.0)
