extends RefCounted
class_name MonsterInfrequent
## Monster Infrequent drops: an Uncommon or Rare item carrying one perk from
## the enemy that dropped it (PerkCatalog sources). Rolled per kill, apart
## from the normal gear roll. Numbers are placeholders.

const DEFINITIONS_DIR := "res://data/enemies/definitions/%s.tres"
const DROP_CHANCE := {"light": 0.004, "standard": 0.006, "heavy": 0.012, "elite": 0.04, "boss": 0.5}
const RARITY_MULT := {
	Constants.EnemyRarity.NORMAL: 1.0,
	Constants.EnemyRarity.ELITE: 2.0,
	Constants.EnemyRarity.CHAMPION: 4.0,
	Constants.EnemyRarity.ASCENDANT: 8.0,
}
const UNCOMMON_WEIGHT := 3.0
const RARE_WEIGHT := 1.0
const MAX_PERKS := 2

## The enemy definition's file name, which PerkCatalog sources list.
static func source_of(definition: EnemyDefinition) -> String:
	return definition.resource_path.get_file().get_basename() if definition else ""

static func source_display_name(source: String) -> String:
	var path := DEFINITIONS_DIR % source
	if ResourceLoader.exists(path):
		var def := load(path) as EnemyDefinition
		if def and def.display_name != "":
			return def.display_name
	return source.capitalize()

## Chance this kill drops an MI (0 when the enemy is no perk's source).
static func drop_chance(definition: EnemyDefinition, enemy_rarity: int, reward_mult: float) -> float:
	if PerkCatalog.perks_from(source_of(definition)).is_empty():
		return 0.0
	return DROP_CHANCE.get(definition.archetype_category, 0.006) * RARITY_MULT.get(enemy_rarity, 1.0) * reward_mult

## An MI from this enemy at `item_level`, or null when no base fits.
static func roll(definition: EnemyDefinition, item_level: int, rarity_mult: float = 1.0) -> Item:
	var perks := PerkCatalog.perks_from(source_of(definition))
	if perks.is_empty():
		return null
	return roll_perk(perks.pick_random(), item_level, rarity_mult)

## An MI carrying `perk`, named after its first source enemy.
static func roll_perk(perk: StringName, item_level: int, rarity_mult: float = 1.0) -> Item:
	var rarity: int = Constants.ItemRarity.RARE if randf() * (UNCOMMON_WEIGHT + RARE_WEIGHT) < RARE_WEIGHT * rarity_mult else Constants.ItemRarity.UNCOMMON
	var item := ItemRoller.roll(item_level, 1.0, func(base: Item) -> bool: return PerkCatalog.fits(perk, base), rarity)
	if item == null:
		return null
	add_perk(item, perk, PerkCatalog.roll_value(perk))
	var sources: Array = PerkCatalog.PERKS[perk]["sources"]
	item.display_name = "%s's %s" % [source_display_name(sources[0]), item.display_name]
	return item

static func add_perk(item: Item, id: StringName, value: float) -> void:
	item.perks[String(id)] = value

static func is_mi(item: Item) -> bool:
	return item != null and not item.perks.is_empty()
