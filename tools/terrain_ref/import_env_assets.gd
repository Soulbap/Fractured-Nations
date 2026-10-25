## Turns the Blender environment GLBs (assets/environment/glb/*.glb) into LOD scenes the
## VegetationStreamer and the world builder use (assets/environment/scenes/<asset>.tscn).
##
## Each GLB holds <Asset>_LOD0 and <Asset>_LOD1 objects. The meshes are copied out of the
## import (assets/environment/meshes/<asset>_lod<n>.res) and their surfaces get project
## materials chosen by the Blender material name:
##   Bark_*            -> shaders/environment/bark.gdshader (+ wind)
##   Needles_*/Leaves_*/Foliage_* -> shaders/environment/foliage.gdshader (alpha cards + wind)
##   Impostor_*        -> foliage.gdshader as far-LOD cards
##   Rock_*            -> shaders/environment/rock.gdshader (triplanar rock, lichen, moss)
##   anything else     -> StandardMaterial3D from the GLB colours (structures, props)
## Run after a `--import` so the GLBs are imported:
##   Godot_console.exe --headless --path . --script res://tools/terrain_ref/import_env_assets.gd [-- --only=pine_a]
extends SceneTree

const GLB_DIR := "res://assets/environment/glb/"
const SCENE_DIR := "res://assets/environment/scenes/"
const MESH_DIR := "res://assets/environment/meshes/"
const MAT_DIR := "res://assets/environment/materials/"
const TEX_DIR := "res://assets/environment/textures/"
const TERRAIN_TEX := "res://assets/terrain/textures/"

## Per-material overrides: tint, wind, translucency, sway height.
const FOLIAGE := {
	"Needles_Pine": {"tex": "pine_tuft", "tint": Color(0.95, 0.98, 0.9), "wind": 0.10, "sway": 16.0, "trans": 0.25, "flutter": 0.006},
	"Needles_Spruce": {"tex": "spruce_spray", "tint": Color(0.95, 1.0, 0.95), "wind": 0.08, "sway": 15.0, "trans": 0.2, "flutter": 0.005},
	"Leaves_Birch": {"tex": "birch_twig", "tint": Color(1, 1, 1), "wind": 0.16, "sway": 12.0, "trans": 0.45, "flutter": 0.03},
	"Foliage_Juniper": {"tex": "juniper", "tint": Color(1, 1, 1), "wind": 0.03, "sway": 3.0, "trans": 0.2, "flutter": 0.004},
	"Leaves_Willow": {"tex": "willow", "tint": Color(1, 1, 1), "wind": 0.06, "sway": 3.0, "trans": 0.45, "flutter": 0.02},
	"Leaves_Fern": {"tex": "fern", "tint": Color(1, 1, 1), "wind": 0.04, "sway": 1.2, "trans": 0.5, "flutter": 0.02},
	# WORLD-VISUALS-01 card atlases (tools/blender/env/make_cards_v3.py).
	"Needles_Spruce3": {"tex": "spruce3", "tint": Color(1.04, 1.12, 0.76), "wind": 0.07, "sway": 15.0, "trans": 0.25, "flutter": 0.004},
	"Needles_Pine3": {"tex": "pine3", "tint": Color(1.06, 1.08, 0.8), "wind": 0.09, "sway": 16.0, "trans": 0.3, "flutter": 0.005},
	"Leaves_Birch3": {"tex": "birch3", "tint": Color(1.0, 1.0, 1.0), "wind": 0.16, "sway": 12.0, "trans": 0.5, "flutter": 0.03},
	"Foliage_Bush3": {"tex": "bush3", "tint": Color(1.0, 1.0, 1.0), "wind": 0.05, "sway": 2.5, "trans": 0.45, "flutter": 0.02},
	"Leaves_Fern3": {"tex": "fern3", "tint": Color(1.0, 1.0, 1.0), "wind": 0.04, "sway": 1.2, "trans": 0.5, "flutter": 0.02},
}
const BARK := {
	"Bark_PineLower": "bark_pine_lower", "Bark_PineUpper": "bark_pine_upper", "Bark_Spruce": "bark_spruce",
	"Bark_Birch": "bark_birch", "Bark_BirchBase": "bark_birch_base", "Bark_Log": "bark_spruce",
	"Bark_Spruce3": "bark_spruce3", "Bark_Log3": "bark_log3",
}
## WORLD-VISUALS-01 scan props ("Scan_<source>", tools/blender/env/make_props_v3.py): colour grade, moss, lichen per source.
const SCAN := {
	"rock_moss_set_01": {"sat": 0.3, "grade": Color(0.96, 0.96, 0.98), "bright": 0.95, "moss": 0.35, "lichen": 0.5},
	"rock_moss_set_02": {"sat": 0.45, "grade": Color(0.97, 0.97, 0.98), "bright": 1.0, "moss": 0.3, "lichen": 0.45},
	"rock_07": {"sat": 0.35, "grade": Color(1, 1, 1), "bright": 0.95, "moss": 0.2, "lichen": 0.25},
	"rock_09": {"sat": 0.3, "grade": Color(1, 1, 1), "bright": 0.95, "moss": 0.2, "lichen": 0.25},
	"stone_01": {"sat": 0.35, "grade": Color(1, 1, 1), "bright": 0.95, "moss": 0.1, "lichen": 0.2},
	"tree_stump_01": {"sat": 0.85, "grade": Color(1, 1, 1), "bright": 0.95, "moss": 0.25, "lichen": 0.0},
	"tree_stump_02": {"sat": 0.85, "grade": Color(1, 1, 1), "bright": 0.95, "moss": 0.25, "lichen": 0.0},
	"dead_tree_trunk": {"sat": 0.8, "grade": Color(1, 1, 1), "bright": 0.95, "moss": 0.2, "lichen": 0.1},
	"dead_tree_trunk_02": {"sat": 0.8, "grade": Color(1, 1, 1), "bright": 0.95, "moss": 0.2, "lichen": 0.1},
	"dry_branches_medium_01": {"sat": 0.8, "grade": Color(1, 1, 1), "bright": 1.0, "moss": 0.0, "lichen": 0.0},
}

## VISUAL-02 settlement buildings and fences ("Bld_*" in tools/blender/env/make_structures.py) ->
## shaders/environment/building.gdshader: texture, own paint colour, how much of the instance colour it takes, roughness.
const BUILDING := {
	"Bld_SidingLap": {"tex": "bld_siding_lap", "base": Color(0.96, 0.95, 0.92), "tint": 1.0, "rough": 0.82},
	"Bld_SidingBoard": {"tex": "bld_siding_board", "base": Color(0.66, 0.18, 0.12), "tint": 0.25, "rough": 0.86},
	"Bld_RoofTile": {"tex": "bld_roof_tile", "base": Color(1, 1, 1), "tint": 0.0, "rough": 0.78},
	"Bld_RoofSheet": {"tex": "bld_roof_sheet", "base": Color(1, 1, 1), "tint": 0.0, "rough": 0.55},
	"Bld_Stone": {"tex": "bld_stone", "base": Color(1, 1, 1), "tint": 0.0, "rough": 0.9},
	"Bld_Trim": {"tex": "bld_siding_board", "base": Color(1.0, 0.99, 0.96), "tint": 0.0, "rough": 0.8},
	"Bld_WoodGrey": {"tex": "bld_wood_grey", "base": Color(1, 1, 1), "tint": 0.0, "rough": 0.9},
	"Bld_FenceWood": {"tex": "bld_wood_grey", "base": Color(1, 1, 1), "tint": 0.0, "rough": 0.9, "swap_uv": true},
	"Bld_Window": {"tex": "bld_window", "base": Color(1, 1, 1), "tint": 0.0, "rough": 0.25},
	"Bld_Door": {"tex": "bld_door", "base": Color(0.9, 0.88, 0.84), "tint": 0.7, "rough": 0.8},
}

var _mats := {}


func _init() -> void:
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	for d in [SCENE_DIR, MESH_DIR, MAT_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	for f in DirAccess.get_files_at(GLB_DIR):
		if not f.ends_with(".glb"):
			continue
		var asset := f.get_basename()
		if only.size() > 0 and not only.has(asset):
			continue
		_convert(asset)
	quit()


func _convert(asset: String) -> void:
	var ps: PackedScene = load(GLB_DIR + asset + ".glb")
	if ps == null:
		push_error("import_env_assets: cannot load %s.glb (run --import first)" % asset)
		return
	var src := ps.instantiate()
	var found: Array = []
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		found.append(mi)
	found.sort_custom(func(a: Node, b: Node) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	var root := Node3D.new()
	root.name = asset.to_pascal_case()
	var report := []
	for mi: MeshInstance3D in found:
		var lod := String(mi.name).get_slice("_LOD", 1)
		if lod == "":
			lod = "0"
		var mesh: ArrayMesh = mi.mesh.duplicate(true)
		# The glTF importer may wrap objects in transforms; bake the node transform.
		var xf := mi.global_transform if mi.is_inside_tree() else _accum(mi)
		if not xf.is_equal_approx(Transform3D.IDENTITY):
			mesh = _transformed(mesh, xf)
		var tris := 0
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var mname := m.resource_name if m else ""
			mesh.surface_set_material(s, _material_for(mname, m))
			tris += mesh.surface_get_array_index_len(s) / 3
		mesh.resource_name = "%s_lod%s" % [asset, lod]
		var mpath := MESH_DIR + "%s_lod%s.res" % [asset, lod]
		ResourceSaver.save(mesh, mpath)
		var out := MeshInstance3D.new()
		out.name = "%s_LOD%s" % [asset, lod]
		out.mesh = load(mpath)
		root.add_child(out)
		out.owner = root
		report.append("LOD%s %d tris" % [lod, tris])
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, SCENE_DIR + asset + ".tscn")
	print("ENV ", asset, " -> ", SCENE_DIR + asset + ".tscn  ", ", ".join(report))
	root.free()
	src.free()


## WORLD-VISUALS-01 far LOD of a tree id with variants: impostor_v3 with the side or top atlas and, per variant, its tile
## and its size relative to variant 0 (assets/environment/glb/<base>_variants.json from make_trees_v3.py).
func _impostor_v3(mname: String) -> Material:
	var top := mname.ends_with("_Top")
	var base := mname.substr(10).trim_suffix("_Top")
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GLB_DIR + base + "_variants.json"))
	var vars: Array = info.variants
	var rects: Array = info.rects
	var v0: Dictionary = vars[0]
	var rect_arr := PackedVector4Array()
	var scale_arr := PackedVector3Array()
	for i in 8:
		var k := mini(i, vars.size() - 1)
		var r: Dictionary = rects[k]
		var v: Dictionary = vars[k]
		rect_arr.append(Vector4(r.u0, r.v0, r.du, r.dv))
		scale_arr.append(Vector3(float(v.w) / float(v0.w), float(v.h) / float(v0.h), float(v.half_w) / float(v0.half_w)))
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/environment/impostor_v3.gdshader")
	sm.set_shader_parameter("albedo_tex", _tex(base + ("_imp3_top" if top else "_imp3")))
	sm.set_shader_parameter("var_rect", rect_arr)
	sm.set_shader_parameter("var_scale", scale_arr)
	sm.set_shader_parameter("var_count", vars.size())
	sm.set_shader_parameter("is_top", top)
	# The atlas is an unlit render; the cards get the scene's light: a lighter tint than the old impostors (they read black).
	sm.set_shader_parameter("tint", Color(0.95, 0.97, 0.92))
	sm.set_shader_parameter("alpha_cut", 0.5)
	sm.set_shader_parameter("edge_fade", 0.3 if top else 0.0)
	sm.set_shader_parameter("wind_strength", 0.06)
	sm.set_shader_parameter("sway_height", 16.0)
	return sm


func _accum(n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p := n
	while p and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _transformed(mesh: ArrayMesh, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] = xf * v[i]
		arr[Mesh.ARRAY_VERTEX] = v
		if arr[Mesh.ARRAY_NORMAL] != null:
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in n.size():
				n[i] = (xf.basis * n[i]).normalized()
			arr[Mesh.ARRAY_NORMAL] = n
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out


func _tex(name: String) -> Texture2D:
	var p := TEX_DIR + name + ".png"
	return load(p) if ResourceLoader.exists(p) else null


func _material_for(mname: String, original: Material) -> Material:
	# Blender numbers a second copy of a material ("Scan_rock_07.001") when scan parts are joined: one material per name.
	var dup := RegEx.create_from_string("[.][0-9]{3}$")
	mname = dup.sub(mname, "")
	if _mats.has(mname):
		return _mats[mname]
	var path := MAT_DIR + mname.to_snake_case() + ".tres"
	var mat: Material
	if FOLIAGE.has(mname):
		var f: Dictionary = FOLIAGE[mname]
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/environment/foliage.gdshader")
		sm.set_shader_parameter("albedo_tex", _tex(f.tex + "_alb"))
		sm.set_shader_parameter("normal_tex", _tex(f.tex + "_nrm"))
		sm.set_shader_parameter("tint", f.tint)
		sm.set_shader_parameter("wind_strength", f.wind)
		sm.set_shader_parameter("sway_height", f.sway)
		sm.set_shader_parameter("translucency", f.trans)
		sm.set_shader_parameter("flutter", f.flutter)
		mat = sm
	elif mname.begins_with("Impostor3_"):
		mat = _impostor_v3(mname)
	elif mname.begins_with("Bark_Pine3_s") or mname.begins_with("Bark_Birch3_s"):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/environment/bark.gdshader")
		var pine := mname.begins_with("Bark_Pine3")
		sm.set_shader_parameter("albedo_tex", _tex("bark_pine3_lower_alb" if pine else "bark_birch_base3_alb"))
		sm.set_shader_parameter("normal_tex", _tex("bark_pine3_lower_nrm" if pine else "bark_birch_base3_nrm"))
		if pine:
			sm.set_shader_parameter("use_upper", true)
			sm.set_shader_parameter("upper_albedo_tex", _tex("bark_pine3_upper_alb"))
			sm.set_shader_parameter("upper_normal_tex", _tex("bark_pine3_upper_nrm"))
			sm.set_shader_parameter("split_y", float(mname.get_slice("_s", 1)))
			sm.set_shader_parameter("split_soft", 2.5)
		sm.set_shader_parameter("sway_height", 16.0 if pine else 12.0)
		sm.set_shader_parameter("wind_strength", 0.09 if pine else 0.16)
		mat = sm
	elif mname.begins_with("Scan_"):
		var src := mname.substr(5)
		var sc: Dictionary = SCAN.get(src, {"sat": 1.0, "grade": Color(1, 1, 1), "bright": 1.0, "moss": 0.0, "lichen": 0.0})
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/environment/scan_prop.gdshader")
		sm.set_shader_parameter("albedo_tex", _tex("scan_%s_alb" % src))
		sm.set_shader_parameter("normal_tex", _tex("scan_%s_nrm" % src))
		sm.set_shader_parameter("orm_tex", _tex("scan_%s_orm" % src))
		sm.set_shader_parameter("saturation", sc.sat)
		sm.set_shader_parameter("grade", sc.grade)
		sm.set_shader_parameter("brightness", sc.bright)
		sm.set_shader_parameter("moss_amount", sc.moss)
		sm.set_shader_parameter("lichen_amount", sc.lichen)
		mat = sm
	elif mname.begins_with("Impostor_"):
		var asset := mname.substr(9).to_lower()
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/environment/foliage.gdshader")
		sm.set_shader_parameter("albedo_tex", _tex(asset + "_impostor"))
		sm.set_shader_parameter("use_normal_tex", false)
		sm.set_shader_parameter("normal_up_blend", 0.45)
		# The impostor texture is an unlit albedo render: darken it to match the shaded,
		# self-occluded LOD0 crown at the switch distance.
		sm.set_shader_parameter("tint", Color(0.72, 0.74, 0.70))
		sm.set_shader_parameter("alpha_cut", 0.5)
		sm.set_shader_parameter("translucency", 0.2)
		sm.set_shader_parameter("flutter", 0.0)
		sm.set_shader_parameter("wind_strength", 0.06)
		sm.set_shader_parameter("sway_height", 16.0)
		mat = sm
	elif BARK.has(mname):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/environment/bark.gdshader")
		sm.set_shader_parameter("albedo_tex", _tex(BARK[mname] + "_alb"))
		sm.set_shader_parameter("normal_tex", _tex(BARK[mname] + "_nrm"))
		var sway := 12.0 if mname.contains("Birch") else 16.0
		sm.set_shader_parameter("sway_height", sway)
		sm.set_shader_parameter("wind_strength", 0.0 if mname == "Bark_Log" else (0.16 if mname.contains("Birch") else 0.1))
		mat = sm
	elif mname.begins_with("Rock_"):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/environment/rock.gdshader")
		sm.set_shader_parameter("rock_albedo", load(TERRAIN_TEX + "rock023_alb_ht.png"))
		sm.set_shader_parameter("rock_normal", load(TERRAIN_TEX + "rock023_nrm_rgh.png"))
		sm.set_shader_parameter("moss_albedo", load(TERRAIN_TEX + "ground037_alb_ht.png"))
		if mname.contains("Outcrop"):
			sm.set_shader_parameter("moss_amount", 0.45)
			sm.set_shader_parameter("lichen_amount", 0.6)
			sm.set_shader_parameter("rock_scale", 0.3)
		elif mname.contains("Small"):
			sm.set_shader_parameter("moss_amount", 0.3)
			sm.set_shader_parameter("rock_scale", 0.6)
		mat = sm
	elif BUILDING.has(mname):
		var bd: Dictionary = BUILDING[mname]
		var bm := ShaderMaterial.new()
		bm.shader = load("res://shaders/environment/building.gdshader")
		bm.set_shader_parameter("albedo_tex", _tex(bd.tex + "_alb"))
		bm.set_shader_parameter("normal_tex", _tex(bd.tex + "_nrm"))
		bm.set_shader_parameter("base_color", bd.base)
		bm.set_shader_parameter("tint_strength", bd.tint)
		bm.set_shader_parameter("roughness", bd.rough)
		bm.set_shader_parameter("normal_depth", bd.get("normal", 0.7))
		bm.set_shader_parameter("swap_uv", bd.get("swap_uv", false))
		mat = bm
	else:
		# Structures and props: keep the Blender colours, add instance tint support.
		var std := StandardMaterial3D.new()
		if original is BaseMaterial3D:
			var o := original as BaseMaterial3D
			std.albedo_color = o.albedo_color
			std.albedo_texture = o.albedo_texture
			std.roughness = o.roughness
			std.metallic = o.metallic
			std.normal_enabled = o.normal_enabled
			std.normal_texture = o.normal_texture
			std.transparency = o.transparency
			std.alpha_scissor_threshold = o.alpha_scissor_threshold
			std.cull_mode = o.cull_mode
		std.vertex_color_use_as_albedo = true
		mat = std
	mat.resource_name = mname
	ResourceSaver.save(mat, path)
	mat = load(path)
	_mats[mname] = mat
	return mat
