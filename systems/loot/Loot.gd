extends RefCounted
class_name Loot
## Item Quantity, Item Rarity and Magic Find, and the rolls they feed.
## Quantity scales how many drop rolls a kill gets (every drop category,
## not just gear); Rarity scales the Uncommon/Rare weights of each rolled
## item or jewel. Sources add together: the player's gear, the active
## Figment's mods and the enemy's own rarity affixes.

## One point of Magic Find is worth this much Item Quantity / Item Rarity (%).
const MAGIC_FIND_QUANTITY := 0.5
const MAGIC_FIND_RARITY := 2.0

## Base rarity weights; Item Rarity multiplies every weight but Common's.
## Unique and Mythic roll a UniqueCatalog item (UniqueRoller).
const RARITY_WEIGHTS := {
	Constants.ItemRarity.COMMON: 72.0,
	Constants.ItemRarity.UNCOMMON: 22.0,
	Constants.ItemRarity.RARE: 6.0,
	Constants.ItemRarity.UNIQUE: 1.5,
	Constants.ItemRarity.MYTHIC: 0.1,
}

## Drop rolls per kill by rank, plus extra for Elite/Champion/Ascendant.
## Each roll gives at most one drop (see Enemy._roll_drop()).
const RANK_DROP_ROLLS := {
	Constants.EnemyRank.NORMAL: 1.0,
	Constants.EnemyRank.MAGIC: 1.5,
	Constants.EnemyRank.RARE: 2.5,
	Constants.EnemyRank.BOSS: 5.0,
}
const RARITY_EXTRA_ROLLS := {
	Constants.EnemyRarity.ELITE: 0.5,
	Constants.EnemyRarity.CHAMPION: 1.5,
	Constants.EnemyRarity.ASCENDANT: 3.0,
}

## Gear stat keys (EquipmentComponent.MISC_BONUS_KEYS).
const QUANTITY_KEY := "item_quantity"
const RARITY_KEY := "item_rarity"
const MAGIC_FIND_KEY := "magic_find"

## % increased Item Quantity from a misc-bonus dictionary, Magic Find included.
static func quantity_percent(bonuses: Dictionary) -> float:
	return bonuses.get(QUANTITY_KEY, 0.0) + bonuses.get(MAGIC_FIND_KEY, 0.0) * MAGIC_FIND_QUANTITY

## % increased Item Rarity from a misc-bonus dictionary, Magic Find included.
static func rarity_percent(bonuses: Dictionary) -> float:
	return bonuses.get(RARITY_KEY, 0.0) + bonuses.get(MAGIC_FIND_KEY, 0.0) * MAGIC_FIND_RARITY

static func player_bonuses() -> Dictionary:
	var equipment: Variant = GameState.player_equipment
	if not is_instance_valid(equipment):
		return {}  # no live player (between scenes)
	return (equipment as EquipmentComponent).compute_misc_bonuses()

## {"quantity": multiplier, "rarity": multiplier} for a kill: the player's
## gear, the active Figment and the enemy's affixes, added together.
static func multipliers(enemy_rarity: EnemyRarityComponent = null, player_override: Variant = null) -> Dictionary:
	var player: Dictionary = player_override if player_override is Dictionary else player_bonuses()
	var quantity := quantity_percent(player)
	var rarity := rarity_percent(player)
	var map := GameState.active_map
	if map:
		quantity += (map.loot_quantity_multiplier - 1.0) * 100.0
		rarity += (map.loot_rarity_multiplier - 1.0) * 100.0
		quantity += FigmentTree.effect("map_quantity") + FigmentTree.effect("family_quantity:" + MapTileset.family_of(map.tileset_id))
		rarity += FigmentTree.effect("map_rarity")
	if enemy_rarity:
		quantity += enemy_rarity.get_effective_quantity_bonus()
		rarity += enemy_rarity.get_effective_rarity_bonus()
		var enemy := enemy_rarity.get_parent() as Enemy
		if enemy and enemy.definition:
			rarity += FigmentTree.effect("faction_rarity:" + enemy.definition.faction)
	return {"quantity": maxf(1.0 + quantity / 100.0, 0.0), "rarity": maxf(1.0 + rarity / 100.0, 0.0)}

## Expected drop rolls for an enemy before Item Quantity.
static func base_drop_rolls(rank: int, enemy_rarity: EnemyRarityComponent = null) -> float:
	var rolls: float = RANK_DROP_ROLLS.get(rank, 1.0)
	if enemy_rarity:
		rolls += RARITY_EXTRA_ROLLS.get(enemy_rarity.rarity, 0.0)
	return rolls

## A whole number of rolls whose average is `expected` (2.3 -> 2, or 3 30% of the time).
static func roll_count(expected: float, rng: RandomNumberGenerator = null) -> int:
	var whole := floori(expected)
	var fraction := expected - whole
	return whole + (1 if _randf(rng) < fraction else 0)

## Weighted rarity for a rolled item or jewel.
static func roll_rarity(rarity_multiplier: float = 1.0, rng: RandomNumberGenerator = null) -> int:
	var weights := rarity_weights(rarity_multiplier)
	var total := 0.0
	for w in weights.values():
		total += w
	var pick := _randf(rng) * total
	for r in weights:
		pick -= weights[r]
		if pick < 0.0:
			return r
	return Constants.ItemRarity.COMMON

static func rarity_weights(rarity_multiplier: float) -> Dictionary:
	var weights := {}
	for r in RARITY_WEIGHTS:
		weights[r] = RARITY_WEIGHTS[r] * (1.0 if r == Constants.ItemRarity.COMMON else rarity_multiplier)
		if r == Constants.ItemRarity.UNIQUE or r == Constants.ItemRarity.MYTHIC:
			weights[r] *= 1.0 + FigmentTree.effect("reward:uniques") / 100.0
	return weights

static func _randf(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng else randf()
