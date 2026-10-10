extends Item
class_name FigmentItem
## A Figment (PoE Map-style currency item, renamed per user request from
## "Map") - selecting one at the Reality Engine (formerly "Map Device")
## rolls the difficulty/reward of the generated Map instance you enter.
## Affixes reuse ItemAffix.gd: each is one FigmentMods mod (stat_key = mod
## id, value = its rolled %, damage_type for conversion).
##
## `equip_slot` (inherited from Item) is meaningless here - a Figment is
## never equipped via EquipmentComponent.
##
## The multipliers below are derived from the mods (recompute_rewards()) and
## saved with the item. enemy_damage/health_multiplier are only set by
## Figments rolled before the mod pools (v4.72); they still apply.
## loot_quantity/rarity_multiplier add to Item Quantity/Rarity on every kill
## in the Map (Loot.multipliers()); pack_size_multiplier adds monsters to
## every pack (GeneratedMap._spawn_pack()).

@export var tier: int = 1
@export var enemy_damage_multiplier: float = 1.0
@export var enemy_health_multiplier: float = 1.0
@export var loot_quantity_multiplier: float = 1.0
@export var loot_rarity_multiplier: float = 1.0
@export var pack_size_multiplier: float = 1.0
## MapTileset style id (data/tilesets/styles/) the generated Map is built in;
## rolled at random. Empty = GeneratedMap picks one on entry.
@export var tileset_id: String = ""

func band() -> FigmentMods.Band:
	return FigmentMods.band_of(tier)

## The rolled % of one mod, 0 when the Figment doesn't have it.
func mod_value(stat_key: String) -> float:
	for affix in affixes:
		if affix.stat_key == stat_key:
			return affix.value
	return 0.0

func get_mod(stat_key: String) -> ItemAffix:
	for affix in affixes:
		if affix.stat_key == stat_key:
			return affix
	return null

## Pack Size / Item Quantity / Item Rarity from the mods.
func recompute_rewards() -> void:
	var pack := 0.0
	var quantity := 0.0
	var rarity := 0.0
	for affix in affixes:
		var entry: Dictionary = FigmentMods.MODS.get(affix.stat_key, {})
		pack += entry.get("pack_size", 0.0)
		quantity += entry.get("quantity", 0.0)
		rarity += entry.get("rarity", 0.0)
	pack_size_multiplier = 1.0 + pack / 100.0
	loot_quantity_multiplier = 1.0 + quantity / 100.0
	loot_rarity_multiplier = 1.0 + rarity / 100.0
