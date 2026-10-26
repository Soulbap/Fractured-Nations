## Difficulty (AI-COMBAT-02): how capable the AI soldiers hostile to the player are - one table of multipliers that CombatBrain
## applies to the same perception and aim model every soldier uses. It changes how fast an enemy notices, reacts and regains a
## lost target, how steady his aim is and how much incoming fire weighs on him; never what he can see (no sight through cover),
## the damage, the ammunition, the bullet physics or the tactics. Soldiers of the player's faction get only a quarter of the
## step (FRIENDLY_SHARE): Easy does not leave the player with a helpless squad. Individual quality (UnitState.proficiency)
## still applies on top, so recruits and veterans differ at every level.
##
## The level is a player setting (UISettings, user://settings.cfg, Settings screen); `--difficulty=easy|normal|hard` overrides
## it, and scripted test runs use NORMAL unless told otherwise (their results must not depend on the tester's settings).
class_name Difficulty
extends RefCounted

enum { EASY, NORMAL, HARD }
const NAMES := ["Easy", "Normal", "Hard"]
const IDS := ["easy", "normal", "hard"]

## Per level, for soldiers hostile to the player: spot = time to notice (x acquire_delay), react = time from noticing to the
## first aimed shot, aim = aim error (one sigma), regain = how long a lost target is picked up again at once (divides
## notice_recall_s), supp = suppression an incoming round adds. HARD is the AI-COMBAT-02 perception with the COMBAT-01 aim.
const TABLE := [
	{"spot": 1.8, "react": 1.7, "aim": 2.0, "regain": 1.7, "supp": 1.3},
	{"spot": 1.3, "react": 1.3, "aim": 1.45, "regain": 1.3, "supp": 1.12},
	{"spot": 1.0, "react": 1.0, "aim": 1.0, "regain": 1.0, "supp": 1.0},
]
const FRIENDLY_SHARE := 0.25
const DESCRIPTIONS := [
	"Enemies are slow to spot you, slow to react and shoot loosely. For learning the game.",
	"Enemies need time to notice you and miss more at range. The intended experience.",
	"Enemies spot and hit as trained soldiers do. Cover and concealment matter most.",
]

static var level := NORMAL


static func id_of(lv: int) -> String:
	return IDS[clampi(lv, 0, 2)]


static func from_id(s: String) -> int:
	var i := IDS.find(s.to_lower())
	return i if i >= 0 else NORMAL


## The multiplier `key` for a soldier of `faction` (the player's faction gets FRIENDLY_SHARE of the step).
static func mult(key: String, faction: int, player_faction: int) -> float:
	var k: float = TABLE[level][key]
	if faction == player_faction:
		return 1.0 + (k - 1.0) * FRIENDLY_SHARE
	return k
