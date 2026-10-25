## GAMEPLAY-05B: prints structure names that differ between StructureCatalog (StructureDef.display_name), FacilityDefs and the
## build menu's base entries.
##   Godot_console.exe --headless --path . --script res://tools/ui/names_audit.gd
extends SceneTree


func _init() -> void:
	var seen := {}
	for id in FacilityDefs.TABLE.keys() + ConstructionPanel.BASE_ENTRIES.keys():
		if seen.has(id):
			continue
		seen[id] = true
		var def := StructureCatalog.get_def(id)
		var cat := def.display_name if def else "-"
		var fac := FacilityDefs.display_name(id) if FacilityDefs.TABLE.has(id) else "-"
		var menu: String = cat if ConstructionPanel.BASE_ENTRIES.has(id) else "-"
		var mark := "" if (fac == "-" or fac == cat) and (menu == "-" or menu == cat) else "   <-- differs"
		print("NAMES %s | catalog %s | facility %s | menu %s%s" % [id, cat, fac, menu, mark])
	quit(0)
