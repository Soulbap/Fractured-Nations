## VISUAL-03: builds an InfantryCharacter for every shipped loadout and reports missing scenes, attach
## points, mounts, clips and detachable magazines:
##   Godot_console.exe --headless --path . --script res://tools/visual03/check_loadouts.gd
extends SceneTree

const CLIPS := ["Idle", "Ready_Idle", "Crouch_Idle", "Walk_F", "Walk_B", "Walk_L", "Walk_R", "Brisk_F", "Jog_F", "Jog_B",
	"Jog_L", "Jog_R", "Run_F", "Run_B", "Run_L", "Run_R", "Sprint_F", "CrouchWalk_F", "CrouchWalk_B", "CrouchWalk_L",
	"CrouchWalk_R", "Turn_L", "Turn_R", "Aim", "Fire", "Reload"]
## Weapons built with a detachable magazine (char_weapon.split_magazine).
const MAG_WEAPONS := ["carbine", "nato_rifle", "ru_rifle", "cn_rifle", "dmr"]


func _init() -> void:
	var dir := InfantryLoadout.DIR
	var bad := []
	var n := 0
	var mags := 0
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".tres"):
			continue
		var lo: InfantryLoadout = load(dir + f)
		var c := InfantryCharacter.new()
		root.add_child(c)
		c.setup(lo, 0, false)
		n += 1
		for it in lo.items:
			if not c.pieces.has(it.id) or (c.pieces[it.id] as Array).is_empty():
				bad.append("%s: piece %s not built" % [lo.id, it.id])
		if c.skeleton == null or c.skeleton.find_bone("ATT_Weapon") < 0:
			bad.append("%s: no ATT_Weapon bone" % lo.id)
		for clip in CLIPS:
			if not c.anim_player.has_animation(clip):
				bad.append("%s: clip %s missing" % [lo.id, clip])
		if c.muzzle() == null and lo.item_in_slot("weapon") != null:
			bad.append("%s: weapon without muzzle mount" % lo.id)
		var w := lo.item_in_slot("weapon")
		if w and w.id in MAG_WEAPONS:
			if not (c.pieces[w.id] as Array).any(func(n: Node) -> bool: return n.name == "Magazine"):
				bad.append("%s: %s magazine not on ATT_Magazine" % [lo.id, w.id])
			else:
				mags += 1
		c.queue_free()
	print("LOADOUTS %s checked %d magazines %d problems %d %s" % [dir, n, mags, bad.size(), JSON.stringify(bad)])
	quit(1 if bad.size() > 0 else 0)
