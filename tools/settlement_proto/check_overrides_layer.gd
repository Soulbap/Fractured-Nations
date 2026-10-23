## WORLD-SETTLEMENT-02 check: the user's overrides load over the settlement layer and saving writes only the user's records.
##   Godot --headless --path . --script res://tools/settlement_proto/check_overrides_layer.gd -- <copy of the user's file>
extends SceneTree

const WorldOverrides = preload("res://scripts/vegetation/world_overrides.gd")


func _init() -> void:
	var user_copy: String = OS.get_cmdline_user_args()[0]
	var user: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(user_copy)).records
	var streamer := VegetationStreamer.new()
	streamer.data_directory = "res://worlds/ref_20km/vegetation"
	var ov := WorldOverrides.new(streamer, user_copy)
	ov.layer_path = SettlementLayer.overrides_path("ref_20km")
	ov.load_file()
	var all_user := user.keys().all(func(id: String) -> bool: return ov.records.has(id) and ov.records[id] == user[id])
	var layer_n := ov.records.size() - user.size()
	ov.save_file()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(user_copy)).records
	print("OVERRIDES_LAYER user=%d layer=%d merged=%d user_kept=%s saved=%d saved_equals_user=%s"
		% [user.size(), layer_n, ov.records.size(), all_user, saved.size(), saved == user])
	streamer.free()
	quit()
