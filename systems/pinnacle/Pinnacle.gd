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
	"ataras": {"name": "Ataras", "scene": "res://entities/enemies/ataras/Ataras.tscn"},
}

## The Herald of the Maw's exclusive Lens: its drop chance rises with each
## Anchor pylon still standing when she dies (MawArena). Placeholder odds.
const MAW_LENS_BASE_CHANCE := 0.04
const MAW_LENS_CHANCE_PER_PYLON := 0.04

static func maw_lens_chance(pylons_standing: int) -> float:
	return MAW_LENS_BASE_CHANCE + MAW_LENS_CHANCE_PER_PYLON * clampi(pylons_standing, 0, MawArena.PYLONS.size())

## Builds the Herald's exclusive Lens. The Lens item is still being
## designed, so this returns null and nothing drops yet.
static func make_maw_lens(_item_level: int) -> Item:
	return null

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

## Testing switch: the Reality Engine opens Pinnacle bosses without
## spending (or holding) Maw Fragments. Set false to restore the cost.
static var free_entry := true

## Spends a set (unless free_entry) and loads the arena with boss_id.
static func enter(tree: SceneTree, boss_id: String) -> bool:
	if not BOSSES.has(boss_id) or not (free_entry or consume_set(GameState.inventory)):
		return false
	GameState.pending_pinnacle = boss_id
	GameState.active_map = null
	SaveManager.save_game()
	tree.paused = false
	LoadingScreen.change_scene(ARENA_SCENE)
	return true
