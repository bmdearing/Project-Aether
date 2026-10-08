extends RefCounted
class_name FigmentRoller
## Rolls a fresh FigmentItem - either a flat request (roll(), the Reality
## Engine's always-available free Tier 1 offer) or a drop-scaled one
## (roll_for_drop(), used by Enemy.gd's loot table). Invented and
## undocumented: no Figment/Map table exists in the referenced docs (this
## whole system predates any doc content - a user-requested addition), so
## the affix pool and tier curve here are placeholder tuning throughout.

## Invented ceiling - nothing else in this project defines a "how high
## can this go" rule for Figments.
const MAX_TIER := 10

const AFFIX_POOL := [
	{"target": "enemy_damage_multiplier", "min": 10.0, "max": 40.0, "desc": "%d%% increased Monster Damage"},
	{"target": "enemy_health_multiplier", "min": 10.0, "max": 50.0, "desc": "%d%% increased Monster Life"},
	{"target": "loot_quantity_multiplier", "min": 10.0, "max": 60.0, "desc": "%d%% increased Item Quantity"},
	{"target": "loot_rarity_multiplier", "min": 10.0, "max": 40.0, "desc": "%d%% increased Item Rarity"},
]

## affix_count: how many of the 4 pool entries to roll (no duplicates).
## Higher tiers roll more affixes and a higher rarity band.
static func roll(tier: int) -> FigmentItem:
	var figment := FigmentItem.new()
	figment.item_id = "rolled_figment_t%d_%d" % [tier, randi()]
	figment.tier = clamp(tier, 1, MAX_TIER)
	figment.tileset_id = MapTileset.random_id()
	var style := MapTileset.load_style(figment.tileset_id)
	figment.display_name = "%s Figment" % style.display_name if style else "Tier %d Figment" % figment.tier
	figment.flavor_text = "Reality bends where the Engine points it."

	var affix_count: int = clamp(1 + figment.tier / 2, 1, AFFIX_POOL.size())
	figment.rarity = Constants.ItemRarity.RARE if affix_count >= 3 else Constants.ItemRarity.UNCOMMON

	var pool := AFFIX_POOL.duplicate()
	pool.shuffle()
	for i in range(affix_count):
		_roll_one_affix(figment, pool[i])

	return figment

## Section-less/invented "scaling" for dropped Figments: lands near
## power_level (the killing Map's own tier, or player level in the Hub),
## with a chance to roll a tier higher or lower - the doc-adjacent
## convention this project already uses for gear power scaling
## (ItemRoller.roll()'s power_level param), applied here since the user
## asked for Figments to scale but gave no specific curve.
static func roll_for_drop(power_level: int) -> FigmentItem:
	var tier: int = clamp(power_level + randi_range(-1, 1), 1, MAX_TIER)
	return roll(tier)

## Strengthens or adds one affix at the Figment's (already raised) tier,
## using the same pool as roll().
static func strengthen(figment: FigmentItem) -> void:
	_roll_one_affix(figment, AFFIX_POOL[randi() % AFFIX_POOL.size()])

static func _roll_one_affix(figment: FigmentItem, entry: Dictionary) -> void:
	var roll_value: float = randf_range(entry["min"], entry["max"]) * (1.0 + figment.tier * 0.1)
	var affix: ItemAffix = null
	for existing in figment.affixes:
		if existing.stat_key == entry["target"]:
			affix = existing
			break
	if affix == null:
		affix = ItemAffix.new()
		figment.affixes.append(affix)
	affix.stat_key = entry["target"]
	affix.value = roll_value
	affix.description = entry["desc"] % round(roll_value)
	match entry["target"]:
		"enemy_damage_multiplier": figment.enemy_damage_multiplier = 1.0 + roll_value / 100.0
		"enemy_health_multiplier": figment.enemy_health_multiplier = 1.0 + roll_value / 100.0
		"loot_quantity_multiplier": figment.loot_quantity_multiplier = 1.0 + roll_value / 100.0
		"loot_rarity_multiplier": figment.loot_rarity_multiplier = 1.0 + roll_value / 100.0
