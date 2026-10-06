extends RefCounted
class_name SlateRoller
## Rolls a random Slate on demand (loot drops - see Enemy._maybe_drop_loot()).
## Section 10's "five independent axes" (Tag, Shape, Size, Modifier Count,
## Modifier Values) are all rolled here - unlike ItemRoller, this doesn't
## duplicate a hand-authored base and reroll on top of it, since a Slate's
## whole identity IS its rolled axes; there's no "base type" underneath it
## the way a Greatsword has one.
##
## Scope: only the 9 real Constants.DamageType tags are rolled (Section
## 10's "Armor/Evasion/Ward/Resistance/Resilience -> relevant defensive
## stat" row for non-damage-type tags isn't modeled - those 5 stats
## aren't uniformly wired anywhere else in this project either).

## Section 10 "Slate Sizes & Rarity" - doc-exact size brackets and rarity
## bands. Picked uniformly (not power_level-gated) since size/rarity is a
## structural tradeoff per the doc (small = rare + no stats, big =
## common + stats + chain-friendly), not a linear "better at higher
## power" axis the way ItemRoller's tiers are.
const SIZE_BRACKETS := [
	{"min_tiles": 2, "max_tiles": 4, "rarities": [Constants.SlateRarity.RARE, Constants.SlateRarity.VERY_RARE]},
	{"min_tiles": 5, "max_tiles": 9, "rarities": [Constants.SlateRarity.COMMON, Constants.SlateRarity.UNCOMMON]},
	{"min_tiles": 10, "max_tiles": 11, "rarities": [Constants.SlateRarity.COMMON]},
]

## Section 10 "Stats Per Tile" - deterministic (not rolled in a range like
## gear affix tiers): a fixed formula off tile_count alone. v4.9 cut these
## from 1.7/0.8 since placed stat lines are now amplified by their chain's
## bonus (ChainCalculator.slate_stat_bonuses()). Main Stat is keyed by tag
## via Constants.DAMAGE_TYPE_MAIN_STAT; Random Stat picks uniformly among
## the 3 core stats (may coincidentally match Main Stat - doc doesn't say
## to exclude that case).
const MAIN_STAT_PER_TILE := 0.6
const RANDOM_STAT_PER_TILE := 0.3

const HYBRID_CHANCE := 0.15

## Aether cost has no doc formula either ("stronger and better rolled
## Slates cost more Aether" is the only guidance) - tile count plus a
## flat per-rarity bonus, loosely calibrated against this project's two
## hand-authored samples (sample_entropic: 8 tiles/Rare -> 14 Aether;
## unbound_chorus: 2 tiles/Unique -> 8 Aether).
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

## Hand-picked shape templates spanning the doc's 2-11 tile range - freely
## rotated/flipped at placement time (Slate.get_transformed_shape()), so
## only one canonical orientation is needed per template. Not doc-sourced
## (the doc says shapes "vary within the same size tier" but gives no
## actual layouts) - an invented pool, same scope as ItemRoller.AFFIX_POOL.
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

## power_level: the active Map's tier, or player level as a fallback in
## the Hub - same signal ItemRoller/FigmentRoller already use. Currently
## unused (nothing rolled here scales with it anymore).
static func roll(power_level: int = 1) -> Slate:
	var bracket: Dictionary = SIZE_BRACKETS[randi() % SIZE_BRACKETS.size()]
	var template := _pick_shape_template(bracket)
	if template.is_empty():
		return null
	var tile_count: int = template.size()

	var slate := Slate.new()
	slate.slate_id = "rolled_slate_%d" % randi()
	# SHAPE_TEMPLATES' entries are plain untyped Arrays (a GDScript const
	# array-of-arrays literal doesn't infer Array[Vector2i] for the inner
	# arrays) - Slate.shape_cells is typed, so it needs an explicit
	# element-by-element copy rather than a same-type duplicate().
	var shape: Array[Vector2i] = []
	for cell in template:
		shape.append(cell)
	slate.shape_cells = shape
	slate.tag = REAL_DAMAGE_TYPES[randi() % REAL_DAMAGE_TYPES.size()]
	slate.is_hybrid = randf() < HYBRID_CHANCE
	if slate.is_hybrid:
		var others := REAL_DAMAGE_TYPES.filter(func(t): return t != slate.tag)
		slate.secondary_tag = others[randi() % others.size()]
	# Rev2: rarity comes from crafted modifiers, so every drop starts Common.
	# The size bracket still sets the drop's Aether cost, unchanged.
	var bracket_rarity: Constants.SlateRarity = bracket["rarities"][randi() % bracket["rarities"].size()]
	slate.rarity = Constants.SlateRarity.COMMON
	slate.display_name = "%s Slate" % Constants.DAMAGE_TYPE_NAME.get(slate.tag, "?")

	slate.modifiers = _roll_modifiers(slate.tag, tile_count, power_level)
	slate.aether_cost = tile_count + RARITY_AETHER_BONUS.get(bracket_rarity, 0)
	CraftingResolver.roll_tolerance(slate)
	return slate

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
