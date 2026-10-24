## A starting configuration of the persistent war (GAMEPLAY-01B): who plays, who owns what, which
## forces, bases and resources exist at minute zero, and the economy rules of the game. Data only -
## SandboxSetup.create reads it through the same world initialisation for every scenario, so New Game and
## the Development Scenario differ in these numbers, never in code paths.
##
## The world's places (objectives at base sites, towns and bridges) stay SandboxSetup.OBJECTIVES; a scenario
## renames them, changes kind, value or owner. Files: assets/scenarios/<id>.tres.
class_name ScenarioDef
extends Resource

@export var id: StringName = &"dev"
@export var title := "Development Scenario"
@export_multiline var description := ""
@export var player_faction := 0
## Per objective (SandboxSetup.OBJECTIVES name): {"name": new name, "kind": ..., "value": ..., "owner": ...}.
@export var objective_overrides := {}
## Per faction id: {"profile": StringName, "reserves": int, "hq": objective name (after renaming) or "",
## "squads": {objective name: squad count}, "developments": [DevelopmentDef ids known from the start beyond the initial
## ones (GAMEPLAY-04B; an AI faction whose start base has a barracks knows how to build one)]}. Every faction of
## WorldState.FACTION_NAMES must be listed.
@export var factions: Array[Dictionary] = []
## Squads placed at a world position instead of an objective: {"faction", "x", "z", "size", "yaw"}.
@export var start_squads: Array[Dictionary] = []
@export var squad_size := 8
## Objectives (after renaming) that get the HESCO perimeter of an HQ.
@export var fortify: PackedStringArray = []
## AI factions get their main base beside their HQ objective (AiBases.create_start_base).
@export var ai_bases := true
## Starting resources of the player's faction pool (FactionState.pool): {"supplies": kg, "ammo": kg, "fuel": l}.
@export var start_pool := {}
## Supply caches (WarState.caches): {"name", "x", "z", "supplies", "ammo", "radius", "known"}.
@export var caches: Array[Dictionary] = []
## Where the camera starts: "squad" (the player's first squad) or "hq" (the player's HQ objective).
@export var camera := "hq"
## Economy and progression switches, copied into WarState.rules at creation (saved with the game):
##   free_reserves      the player's reserves arrive as free squads at his HQ (WarSim._update_reserves)
##   start_stock_gift   the player's first supply depot receives FacilityDefs.START_STOCK
##   player_income      WarEconomy.income for the player (rates: income_supplies / income_ammo / income_fuel)
##   build_costs        player construction is paid (BuildCosts)
##   build_sites        player construction makes a site that soldiers build (else instant)
##   bed_limit          the player cannot recruit beyond the beds of his bases
##   recovery_delay_s / recovery_size   a small section after total loss (0 = off)
##   guide              early-game hints in the HUD
##   development        GAMEPLAY-04B Military Development: buildings, weapons and roles are unlocked by developments (off: all open)
@export var rules := {}


static func load_id(scenario_id: String) -> ScenarioDef:
	var path := "res://assets/scenarios/%s.tres" % scenario_id
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ScenarioDef


func faction_entry(i: int) -> Dictionary:
	return factions[i] if i >= 0 and i < factions.size() else {}
