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

static var _display_names: Dictionary = {}
static var _known_names: Dictionary = {}

static func source_display_name(source: String) -> String:
	if _display_names.has(source):
		return _display_names[source]
	var shown := source.capitalize()
	var path := DEFINITIONS_DIR % source
	if ResourceLoader.exists(path):
		var def := load(path) as EnemyDefinition
		if def and def.display_name != "":
			shown = def.display_name
	_display_names[source] = shown
	return shown

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

## Fused: two or more perks (the Recombinator, or a Vestige perk on an MI).
static func is_fused(item: Item) -> bool:
	return item != null and item.perks.size() >= 2

const FACTIONS := ["Unchartered", "Directorate", "Legion", "Synod", "Veilborne", "Hollowed"]

## A source's name without its faction: "Unchartered Brigand" -> "Brigand".
static func short_source_name(source: String) -> String:
	var full := source_display_name(source)
	var first := full.get_slice(" ", 0)
	return full.substr(first.length() + 1) if FACTIONS.has(first) and full.contains(" ") else full

## The item's name with any "<Source>'s " or "<A>-<B>'s " MI prefix removed.
static func base_name(item: Item) -> String:
	var text := item.display_name
	var cut := text.find("'s ")
	if cut < 0:
		return text
	if _known_names.is_empty():
		for id in PerkCatalog.PERKS:
			for source in PerkCatalog.PERKS[id]["sources"]:
				_known_names[source_display_name(source)] = true
				_known_names[short_source_name(source)] = true
	var known := _known_names
	for part in text.substr(0, cut).split("-"):
		if not known.has(part):
			return text
	return text.substr(cut + 3)

## Names an MI after its perks' sources: "Brigand-Cutthroat's Gloves" when
## fused, "Unchartered Brigand's Gloves" for one perk.
static func rename(item: Item) -> void:
	var base := base_name(item)
	var names: Array[String] = []
	for id in item.perks:
		var sources: Array = PerkCatalog.PERKS.get(StringName(id), {}).get("sources", [])
		if sources.is_empty():
			continue
		var short := short_source_name(sources[0]) if item.perks.size() >= 2 else source_display_name(sources[0])
		if not names.has(short):
			names.append(short)
	item.display_name = "%s's %s" % ["-".join(names), base] if not names.is_empty() else base
