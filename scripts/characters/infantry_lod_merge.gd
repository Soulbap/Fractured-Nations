## Runtime LOD merging for the infantry character (CHARACTER-01).
##
## LOD0 keeps every equipment piece as its own mesh (close FPS view, swappable). For
## distance the pieces of a loadout are merged once and cached per (loadout, faction):
##   LOD1  one skinned mesh, one surface per shared material (textures kept)
##   LOD2  one skinned mesh, one surface, vertex colours = average material albedo
## Rigid pieces (helmet, pack, weapon) become 100 % weighted to their attachment bone, so
## the merged meshes follow the same skeleton and animation. A soldier at medium/far
## distance therefore costs ~10 draw calls (LOD1) or 1 (LOD2) instead of ~35.
class_name InfantryLodMerge
extends RefCounted

static var _cache := {}


## Returns {"lod1": ArrayMesh, "lod2": ArrayMesh, "skin": Skin} for the character's pieces.
static func get_merged(c: InfantryCharacter) -> Dictionary:
	var key := "%s/%d" % [c.loadout.id, c.faction]
	if not _cache.has(key):
		_cache[key] = _build(c)
	return _cache[key]


static func _build(c: InfantryCharacter) -> Dictionary:
	var sk := c.skeleton
	# One bind per skeleton bone: bind pose = inverse global rest.
	var skin := Skin.new()
	for b in sk.get_bone_count():
		skin.add_named_bind(sk.get_bone_name(b), sk.get_bone_global_rest(b).affine_inverse())
	var out := {"skin": skin}
	for lod in [1, 2]:
		var groups := {}      # material name -> accumulated arrays
		for mi in c.lod_meshes:
			if not is_instance_valid(mi) or mi.is_queued_for_deletion() or not String(mi.name).ends_with("_LOD%d" % lod):
				continue
			_append(mi, sk, groups, lod == 2, c.faction)
		var mesh := ArrayMesh.new()
		mesh.resource_name = "Infantry_%s_LOD%d" % [c.loadout.id, lod]
		for mat_name in groups:
			var g: Dictionary = groups[mat_name]
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = g.v
			arr[Mesh.ARRAY_NORMAL] = g.n
			if lod == 2:
				arr[Mesh.ARRAY_COLOR] = g.col
			else:
				arr[Mesh.ARRAY_TANGENT] = g.t
				arr[Mesh.ARRAY_TEX_UV] = g.uv
			arr[Mesh.ARRAY_BONES] = g.b
			arr[Mesh.ARRAY_WEIGHTS] = g.w
			arr[Mesh.ARRAY_INDEX] = g.i
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var s := mesh.get_surface_count() - 1
			mesh.surface_set_material(s, InfantryMaterials.proxy_material() if lod == 2 else InfantryMaterials.get_material(mat_name, c.faction))
			mesh.surface_set_name(s, mat_name)
		out["lod%d" % lod] = mesh
	return out


static func _new_group() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "t": PackedFloat32Array(), "uv": PackedVector2Array(),
		"col": PackedColorArray(), "b": PackedInt32Array(), "w": PackedFloat32Array(), "i": PackedInt32Array()}


static func _append(mi: MeshInstance3D, sk: Skeleton3D, groups: Dictionary, vcol: bool, faction: int) -> void:
	var skin := mi.skin
	var rigid_bone := -1
	var rigid_xf := Transform3D.IDENTITY
	if skin == null:
		# Rest placement relative to the skeleton: attachment bone rest x local chain.
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n and n != sk:
			if n is BoneAttachment3D:
				rigid_bone = sk.find_bone((n as BoneAttachment3D).bone_name)
				break
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		if rigid_bone < 0:
			return
		rigid_xf = sk.get_bone_global_rest(rigid_bone) * xf
	var bind_map := PackedInt32Array()
	if skin:
		for b in skin.get_bind_count():
			var name := skin.get_bind_name(b)
			bind_map.append(sk.find_bone(name) if name != &"" else skin.get_bind_bone(b))
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s)
		var mat_name := mat.resource_name if mat else "Default"
		var gkey := "all" if vcol else mat_name
		if not groups.has(gkey):
			groups[gkey] = _new_group()
		var g: Dictionary = groups[gkey]
		var arr := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var base: int = g.v.size()
		var col := InfantryMaterials.average_albedo(mat_name, faction) if vcol else Color.WHITE
		if skin:
			g.v.append_array(verts)
			g.n.append_array(norms)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(verts.size(), 1)
			for i in verts.size():
				for k in 4:
					if k < per:
						g.b.append(maxi(bind_map[bones[i * per + k]], 0))
						g.w.append(weights[i * per + k])
					else:
						g.b.append(0)
						g.w.append(0.0)
			if not vcol:
				_append_tangents(g, arr, Transform3D.IDENTITY, verts.size())
		else:
			for i in verts.size():
				g.v.append(rigid_xf * verts[i])
				g.n.append((rigid_xf.basis * norms[i]).normalized())
				g.b.append_array([rigid_bone, 0, 0, 0])
				g.w.append_array([1.0, 0.0, 0.0, 0.0])
			if not vcol:
				_append_tangents(g, arr, rigid_xf, verts.size())
		if vcol:
			for i in verts.size():
				g.col.append(col)
		else:
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] else PackedVector2Array()
			if uv.size() != verts.size():
				uv.resize(verts.size())
			g.uv.append_array(uv)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for k in idx:
			g.i.append(base + k)


static func _append_tangents(g: Dictionary, arr: Array, xf: Transform3D, count: int) -> void:
	var t: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] else PackedFloat32Array()
	if t.size() != count * 4:
		for i in count:
			g.t.append_array([1.0, 0.0, 0.0, 1.0])
		return
	for i in count:
		var tv := (xf.basis * Vector3(t[i * 4], t[i * 4 + 1], t[i * 4 + 2])).normalized()
		g.t.append_array([tv.x, tv.y, tv.z, t[i * 4 + 3]])
