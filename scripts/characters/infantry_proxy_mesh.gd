## Static far-view mesh of a loadout for the abstract (bodiless) tier (CHARACTER-01).
##
## UnitProxy shows units beyond the detail radius. Instead of a capsule it uses this mesh:
## every LOD2 piece of the loadout, skinned on the CPU into the first frame of the Idle
## clip (so the soldier stands holding the carbine, not in the A-pose), merged into one
## surface whose vertex colours are the average albedo of each source material. One mesh,
## one material, one draw call per proxy; built once per (loadout, faction) and cached.
class_name InfantryProxyMesh
extends RefCounted

const POSE_CLIP := "Idle"

static var _cache := {}


## COMBAT-01: one mesh per posture (POSTURE_CLIPS: standing, crouched, prone), built on first use.
const POSTURE_CLIPS: Array[String] = ["Idle", "Crouch_Idle", "Prone_Aim"]


static func get_mesh(loadout_id: String, faction: int, posture := 0) -> ArrayMesh:
	var key := "%s/%d/%d" % [loadout_id, faction, posture]
	if _cache.has(key):
		return _cache[key]
	var lo := InfantryLoadout.by_id(loadout_id)
	var mesh: ArrayMesh = _build(lo, faction, POSTURE_CLIPS[posture]) if lo else null
	_cache[key] = mesh
	return mesh


static func _build(lo: InfantryLoadout, faction: int, clip := POSE_CLIP) -> ArrayMesh:
	# Assemble the character off-tree (no rendering, no processing) to reuse the exact
	# piece placement logic, then evaluate the pose from the animation data directly.
	var c := InfantryCharacter.new()
	c.setup(lo, faction, false)
	var sk := c.skeleton
	var pose := _pose_globals(sk, c.anim_player.get_animation(clip if c.anim_player.has_animation(clip) else POSE_CLIP))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(InfantryMaterials.proxy_material())
	var tris := 0
	for mi in c.lod_meshes:
		if not is_instance_valid(mi) or mi.is_queued_for_deletion() or not String(mi.name).ends_with("_LOD2"):
			continue
		var skin := mi.skin
		var rigid_xf := Transform3D.IDENTITY
		if skin == null:
			rigid_xf = _rigid_transform(mi, sk, pose)
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			var col := InfantryMaterials.average_albedo(mat.resource_name if mat else "", faction)
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var out_v := PackedVector3Array()
			var out_n := PackedVector3Array()
			out_v.resize(verts.size())
			out_n.resize(verts.size())
			if skin:
				var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
				var per := bones.size() / maxi(verts.size(), 1)
				var bind_xf := []
				for b in skin.get_bind_count():
					var bone := sk.find_bone(skin.get_bind_name(b)) if skin.get_bind_name(b) != &"" else skin.get_bind_bone(b)
					bind_xf.append(pose[bone] * skin.get_bind_pose(b) if bone >= 0 else Transform3D.IDENTITY)
				for i in verts.size():
					var p := Vector3.ZERO
					var n := Vector3.ZERO
					for k in per:
						var w := weights[i * per + k]
						if w <= 0.0:
							continue
						var xf: Transform3D = bind_xf[bones[i * per + k]]
						p += (xf * verts[i]) * w
						n += (xf.basis * norms[i]) * w
					out_v[i] = p
					out_n[i] = n.normalized()
			else:
				for i in verts.size():
					out_v[i] = rigid_xf * verts[i]
					out_n[i] = (rigid_xf.basis * norms[i]).normalized()
			for i in range(0, idx.size(), 3):
				for k in 3:
					var vi := idx[i + k]
					st.set_color(col)
					st.set_normal(out_n[vi])
					st.add_vertex(out_v[vi])
			tris += idx.size() / 3
	c.free()
	st.index()
	var mesh := st.commit()
	mesh.resource_name = "InfantryProxy_%s_%d" % [lo.id, faction]
	mesh.set_meta("triangles", tris)
	return mesh


## Global (skeleton-space) transform of every bone at t = 0 of the clip.
static func _pose_globals(sk: Skeleton3D, anim: Animation) -> Array:
	var local := []
	for b in sk.get_bone_count():
		local.append(sk.get_bone_rest(b))
	if anim:
		for t in anim.get_track_count():
			var path := String(anim.track_get_path(t))
			var bone := sk.find_bone(path.get_slice(":", 1))
			if bone < 0:
				continue
			var xf: Transform3D = local[bone]
			match anim.track_get_type(t):
				Animation.TYPE_POSITION_3D:
					xf.origin = anim.position_track_interpolate(t, 0.0)
				Animation.TYPE_ROTATION_3D:
					xf.basis = Basis(anim.rotation_track_interpolate(t, 0.0)).scaled(xf.basis.get_scale())
			local[bone] = xf
	var glob := []
	glob.resize(sk.get_bone_count())
	for b in sk.get_bone_count():
		glob[b] = _global(sk, local, glob, b)
	return glob


static func _global(sk: Skeleton3D, local: Array, glob: Array, b: int) -> Transform3D:
	if glob[b] != null:
		return glob[b]
	var p := sk.get_bone_parent(b)
	var g: Transform3D = local[b] if p < 0 else _global(sk, local, glob, p) * local[b]
	glob[b] = g
	return g


## Pose-space transform of a rigid (non-skinned) mesh: walk up to its BoneAttachment3D and
## replace the attachment's rest placement by the posed bone.
static func _rigid_transform(mi: Node3D, sk: Skeleton3D, pose: Array) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n and n != sk:
		if n is BoneAttachment3D:
			var bone := sk.find_bone((n as BoneAttachment3D).bone_name)
			return pose[bone] * xf
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
