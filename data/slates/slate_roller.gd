extends RefCounted
class_name SlateRoller
## Rolls a random Slate for loot: tag, shape, size, modifier count and
## values. No base type underneath. Only damage-type tags are rolled.

## Size brackets and their rarity, picked uniformly: size is a tradeoff
## (small = rare, no stats; big = common, stats), not a power axis.
const SIZE_BRACKETS := [
	{"min_tiles": 2, "max_tiles": 4, "rarities": [Constants.SlateRarity.RARE, Constants.SlateRarity.VERY_RARE]},
	{"min_tiles": 5, "max_tiles": 9, "rarities": [Constants.SlateRarity.COMMON, Constants.SlateRarity.UNCOMMON]},
	{"min_tiles": 10, "max_tiles": 11, "rarities": [Constants.SlateRarity.COMMON]},
]

## Fixed stats per tile (not rolled); placed Slates' chains amplify them.
## Main Stat follows the tag; Random Stat may match it.
const MAIN_STAT_PER_TILE := 0.6
const RANDOM_STAT_PER_TILE := 0.3

const HYBRID_CHANCE := 0.15

## Aether cost = tile count + a per-rarity bonus.
const RARITY_AETHER_BONUS := {
	Constants.SlateRarity.COMMON: 0,
	Constants.SlateRarity.UNCOMMON: 1,
	Constants.SlateRarity.RARE: 3,
	Constants.SlateRarity.VERY_RARE: 5,
	Constants.SlateRarity.UNIQUE: 8,
	Constants.SlateRarity.MYTHIC: 12,
}

const REAL_DAMAGE_TYPES: Array[Constants.DamageType] = [
	Constants.DamageType.KINETIC, Constants.DamageType.PIERCING, Constants.DamageType.EXPLOSIVE,
	Constants.DamageType.FIRE, Constants.DamageType.COLD, Constants.DamageType.LIGHTNING,
	Constants.DamageType.AETHERIC, Constants.DamageType.ENTROPIC, Constants.DamageType.PALE,
]

## Shapes from 2-11 tiles, one orientation each (rotated/flipped on placement).
const SHAPE_TEMPLATES := [
	[Vector2i(0, 0), Vector2i(1, 0)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(2, 1)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 2)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(1, -1)],
]

## power_level is currently unused.
## rarity_multiplier is Item Rarity (Loot.multipliers()): a drop rolls its
## rarity like gear does, and Uncommon/Rare drops get modifiers from the
## Slate pool, the same way the matching Orbs would add them.
static func roll(power_level: int = 1, rarity_multiplier: float = 1.0) -> Slate:
	var bracket: Dictionary = SIZE_BRACKETS[randi() % SIZE_BRACKETS.size()]
	var template := _pick_shape_template(bracket)
	if template.is_empty():
		return null
	var tile_count: int = template.size()

	var slate := Slate.new()
	slate.slate_id = "rolled_slate_%d" % randi()
	# Copy element-wise: the template arrays are untyped, shape_cells is typed.
	var shape: Array[Vector2i] = []
	for cell in template:
		shape.append(cell)
	slate.shape_cells = shape
	slate.tag = REAL_DAMAGE_TYPES[randi() % REAL_DAMAGE_TYPES.size()]
	slate.is_hybrid = randf() < HYBRID_CHANCE
	if slate.is_hybrid:
		var others := REAL_DAMAGE_TYPES.filter(func(t): return t != slate.tag)
		slate.secondary_tag = others[randi() % others.size()]
	# Rev2: rarity comes from modifiers - it starts Common and
	# roll_rarity_modifiers() below raises it. The size bracket sets the cost.
	var bracket_rarity: Constants.SlateRarity = bracket["rarities"][randi() % bracket["rarities"].size()]
	slate.rarity = Constants.SlateRarity.COMMON
	slate.display_name = "%s Slate" % Constants.DAMAGE_TYPE_NAME.get(slate.tag, "?")

	slate.modifiers = _roll_modifiers(slate.tag, tile_count, power_level)
	slate.aether_cost = tile_count + RARITY_AETHER_BONUS.get(bracket_rarity, 0)
	CraftingResolver.roll_tolerance(slate)
	roll_rarity_modifiers(slate, Loot.roll_rarity(rarity_multiplier))
	return slate

## Uncommon: 1-2 modifiers (Quickening, then maybe Grafting); Rare and above:
## 3-4 (Forging). Applied without spending the Slate's Aether Tolerance.
static func roll_rarity_modifiers(slate: Slate, item_rarity: int) -> void:
	var orbs: Array[StringName] = []
	if item_rarity == Constants.ItemRarity.UNCOMMON:
		orbs.append(&"quickening")
		if randf() < 0.5:
			orbs.append(&"grafting")
	elif item_rarity >= Constants.ItemRarity.RARE:
		orbs.append(&"forging")
	if orbs.is_empty():
		return
	var resolver := CraftingResolver.create_default()
	for orb in orbs:
		var target := CraftTarget.wrap(slate)
		var ctx := resolver._resolve_brands(orb, null)
		if resolver._check(target, orb, ctx, null) != CraftResult.CraftError.NONE:
			return
		var sim := resolver._simulate(target, orb, ctx, null)
		if sim["error"] != CraftResult.CraftError.NONE:
			return
		target.set_explicits(sim["explicits"])
		target.set_rarity(sim["rarity"])

static func _pick_shape_template(bracket: Dictionary) -> Array:
	var candidates: Array = []
	for template in SHAPE_TEMPLATES:
		var size: int = template.size()
		if size >= bracket["min_tiles"] and size <= bracket["max_tiles"]:
			candidates.append(template)
	if candidates.is_empty():
		return []
	return candidates[randi() % candidates.size()]

## Small (2-4 tile) Slates get no modifier lines - "no stat contribution"
## per Section 10 - they only contribute to chains.
static func _roll_modifiers(tag: Constants.DamageType, tile_count: int, _power_level: int) -> Array[SlateModifier]:
	var modifiers: Array[SlateModifier] = []
	if tile_count >= 5:
		modifiers.append(_stat_modifier(Constants.DAMAGE_TYPE_MAIN_STAT.get(tag, Constants.Stat.STRENGTH), tile_count * MAIN_STAT_PER_TILE, "Main Stat"))
		var random_stat: Constants.Stat = Constants.Stat.values()[randi() % Constants.Stat.values().size()]
		modifiers.append(_stat_modifier(random_stat, tile_count * RANDOM_STAT_PER_TILE, "Random Stat"))
	return modifiers

static func _stat_modifier(stat: Constants.Stat, value: float, label: String) -> SlateModifier:
	var stat_key := "flat_%s" % Constants.Stat.keys()[stat].to_lower()
	var modifier := SlateModifier.new()
	modifier.stat_key = stat_key
	modifier.value = value
	modifier.description = "+%.1f %s (%s)" % [value, Constants.Stat.keys()[stat].capitalize(), label]
	return modifier
