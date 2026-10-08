extends RefCounted
class_name Pinnacle
## The Pinnacle: four Maw Fragments, one dropped by every Figment boss, open
## a Pinnacle boss fight from the Reality Engine. Fragments are currency
## (they stack in the inventory); a full set is one of each.

const ARENA_SCENE := "res://levels/pinnacle_boss/PinnacleArena.tscn"
const FRAGMENT_IDS: Array[StringName] = [&"maw_fragment_ash", &"maw_fragment_tide", &"maw_fragment_storm", &"maw_fragment_hollow"]

## Pinnacle bosses the Reality Engine offers. "Herald of the Maw" is a
## placeholder name (the model/ids are still Xalatath's; to be replaced).
const BOSSES := {
	"lord_of_the_elements": {"name": "Lord of the Elements", "scene": "res://entities/enemies/lord_of_the_elements/LordOfTheElements.tscn"},
	"herald_of_the_maw": {"name": "Herald of the Maw", "scene": "res://entities/enemies/xalatath/Xalatath.tscn"},
}

static func roll_fragment() -> StringName:
	return FRAGMENT_IDS[randi() % FRAGMENT_IDS.size()]

static func is_fragment(id: StringName) -> bool:
	return FRAGMENT_IDS.has(id)

## Fragments still needed for a set (empty when it's complete).
static func missing_fragments(inventory: GridInventory) -> Array[StringName]:
	var missing: Array[StringName] = []
	for id in FRAGMENT_IDS:
		if inventory.count_of(id) <= 0:
			missing.append(id)
	return missing

static func has_full_set(inventory: GridInventory) -> bool:
	return missing_fragments(inventory).is_empty()

static func consume_set(inventory: GridInventory) -> bool:
	if not has_full_set(inventory):
		return false
	for id in FRAGMENT_IDS:
		inventory.remove_currency(id)
	return true

## Spends a set and loads the arena with boss_id.
static func enter(tree: SceneTree, boss_id: String) -> bool:
	if not BOSSES.has(boss_id) or not consume_set(GameState.inventory):
		return false
	GameState.pending_pinnacle = boss_id
	GameState.active_map = null
	SaveManager.save_game()
	tree.paused = false
	tree.change_scene_to_file(ARENA_SCENE)
	return true
