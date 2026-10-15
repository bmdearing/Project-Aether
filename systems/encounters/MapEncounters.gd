extends RefCounted
class_name MapEncounters
## Registry of encounters a Figment can roll into its rooms. Each id builds a
## Node3D that is placed in the map and, to survive a portal trip, may
## implement capture_state() -> Dictionary and restore_state(Dictionary).
## New random content (a league mechanic, an event) adds an id here and a
## table entry where it should appear; SecretRoomBuilder rolls SECRET_TABLE.

const HOARD := "hoard"
const WATCHER := "watcher"

## Placeholder weights.
const SECRET_TABLE: Array[Dictionary] = [
	{"id": HOARD, "weight": 55.0},
	{"id": WATCHER, "weight": 45.0},
]

## A Hoard is a gilded TreasureChest: this many times a chest's drops, with
## this much extra Item Rarity (+1.0 = +100%).
const HOARD_ROLL_SCALE := 3.0
const HOARD_RARITY_BONUS := 1.0

## Weighted pick of an id from `table` (map RNG, so seeded).
static func roll(table: Array[Dictionary]) -> String:
	var total := 0.0
	for entry in table:
		total += float(entry["weight"])
	var r := randf() * total
	for entry in table:
		r -= float(entry["weight"])
		if r <= 0.0:
			return entry["id"]
	return table[table.size() - 1]["id"] if not table.is_empty() else ""

static func create(id: String, map: GeneratedMap) -> Node3D:
	match id:
		HOARD:
			return SecretHoard.new()
		WATCHER:
			var watcher := Watcher.new()
			watcher.map = map
			return watcher
	return null

static func make_hoard_chest() -> TreasureChest:
	var chest := TreasureChest.new()
	chest.roll_scale = HOARD_ROLL_SCALE
	chest.rarity_bonus = HOARD_RARITY_BONUS
	return chest
