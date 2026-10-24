extends RefCounted
class_name Pinnacle
## The Pinnacle: four Maw Fragments, one dropped by every Figment boss, open
## a Pinnacle boss fight from the Reality Engine. Fragments are currency
## (they stack in the inventory); a full set is one of each.

const ARENA_SCENE := "res://levels/pinnacle_boss/PinnacleArena.tscn"
const FRAGMENT_IDS: Array[StringName] = [&"maw_fragment_ash", &"maw_fragment_tide", &"maw_fragment_storm", &"maw_fragment_hollow"]

## Pinnacle bosses the Reality Engine offers. "Herald of the Maw" is a
## placeholder name (the model/ids are still Xalatath's; to be replaced).
## "music": the fight's track, looped by PinnacleArena (optional).
## "hidden": kept working (tests, a direct GameState.pending_pinnacle) but
## not offered by the Reality Engine. Aurelia is the final boss; until the
## story reaches her she is a Pinnacle choice too.
const BOSSES := {
	"aurelia": {"name": "Aurelia", "scene": "res://entities/enemies/aurelia/Aurelia.tscn", "music": "res://assets/music/boss/aurelia.mp3"},
	"lord_of_the_elements": {"name": "Lord of the Elements", "scene": "res://entities/enemies/lord_of_the_elements/LordOfTheElements.tscn", "hidden": true},
	"herald_of_the_maw": {"name": "Herald of the Maw", "scene": "res://entities/enemies/xalatath/Xalatath.tscn", "music": "res://assets/music/boss/herald.mp3"},
	"ataras": {"name": "Ataras", "scene": "res://entities/enemies/ataras/Ataras.tscn", "music": "res://assets/music/boss/ataras.mp3"},
	# A model test (classic MDX + BLP); the model is a fan Bleach model, placeholder only.
	"almighty": {"name": "The Sealed King", "scene": "res://entities/enemies/almighty/Almighty.tscn"},
}

## The Herald of the Maw's exclusive Lens: its drop chance rises with each
## Anchor pylon still standing when she dies (MawArena). Placeholder odds.
const MAW_LENS_BASE_CHANCE := 0.04
const MAW_LENS_CHANCE_PER_PYLON := 0.04

static func maw_lens_chance(pylons_standing: int) -> float:
	return MAW_LENS_BASE_CHANCE + MAW_LENS_CHANCE_PER_PYLON * clampi(pylons_standing, 0, MawArena.PYLONS.size())

## Radius of the Lodestar, in tiles from the North Star.
const LODESTAR_RADIUS := 9

## Builds the Herald's exclusive Lens, the Lodestar: North Star only, it
## rolls one of FateStars.GIFTS for every Slate in its radius, and drops
## corrupted so it can't be changed.
static func make_maw_lens(item_level: int) -> Item:
	var lens := Lens.new()
	lens.item_id = "lens_lodestar_%d" % randi()
	lens.unique_id = "lodestar"
	lens.display_name = "The Lodestar"
	lens.rarity = Constants.ItemRarity.UNIQUE
	lens.item_level = maxi(item_level, 1)
	lens.radius = LODESTAR_RADIUS
	lens.radius_mod = "star_gifts"
	FateStars.roll_gift(lens)
	lens.is_craftable = false
	lens.is_corrupted = true
	lens.flavor_text = "Every road north ends at the same light."
	return lens

## The Pinnacle bosses the Reality Engine offers (BOSSES minus the hidden ones).
static func offered_bosses() -> Array[String]:
	var ids: Array[String] = []
	for id in BOSSES:
		if not BOSSES[id].get("hidden", false):
			ids.append(id)
	return ids

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

## Testing switch (on with Dev.enabled): the Reality Engine opens Pinnacle bosses without
## spending (or holding) Maw Fragments. Set false to restore the cost.
static var free_entry := Dev.enabled

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
