extends RefCounted
class_name LensRoller
## Rolls a Lens drop: a radius (Small 2 / Medium 3 / Large 4 tiles), one
## radius modifier, and jewel modifiers by rarity (Uncommon 1, Rare 2) from
## JewelModifierPool.

## id -> {"text": card text ({tag}, {v}), "min"/"max": value range, "tagged": rolls a tag}
const RADIUS_MODS := {
	"amplify_tag": {"text": "{tag} Slates in radius have {v}% stronger modifiers", "min": 20.0, "max": 40.0, "tagged": true},
	"amplify_attributes": {"text": "Attribute lines of Slates in radius are {v}% stronger", "min": 20.0, "max": 40.0, "tagged": false},
	"bridge_tag": {"text": "Slates in radius also count as {tag} for chains and connections", "min": 0.0, "max": 0.0, "tagged": true},
	"free_placement": {"text": "Slates in radius can be placed without a matching connection", "min": 0.0, "max": 0.0, "tagged": false},
	"cheap": {"text": "Slates in radius cost 1 less Aether (minimum 1)", "min": 1.0, "max": 1.0, "tagged": false},
}
## Radius -> weight.
const RADIUS_WEIGHTS := {2: 50, 3: 35, 4: 15}
const JEWEL_MODS_BY_RARITY := {Constants.ItemRarity.UNCOMMON: 1, Constants.ItemRarity.RARE: 2}

static func roll(item_level: int = 1, loot_rarity_multiplier: float = 1.0, rng: RandomNumberGenerator = null) -> Lens:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var lens := Lens.new()
	lens.item_id = "lens_rolled_%d" % rng.randi()
	lens.item_level = maxi(item_level, 1)
	lens.radius = _roll_radius(rng)
	var ids := RADIUS_MODS.keys()
	lens.radius_mod = ids[rng.randi() % ids.size()]
	var def: Dictionary = RADIUS_MODS[lens.radius_mod]
	lens.radius_value = roundf(rng.randf_range(def["min"], def["max"]))
	if def["tagged"]:
		lens.radius_tag = SlateRoller.REAL_DAMAGE_TYPES[rng.randi() % SlateRoller.REAL_DAMAGE_TYPES.size()]
	lens.display_name = "%s %s" % [Lens.SIZE_NAMES.get(lens.radius, ""), Lens.LENS_NAME]
	lens.rarity = mini(Loot.roll_rarity(loot_rarity_multiplier, rng), Constants.ItemRarity.RARE)
	JewelRoller.add_random_modifiers(lens, JEWEL_MODS_BY_RARITY.get(lens.rarity, 0), rng)
	return lens

static func _roll_radius(rng: RandomNumberGenerator) -> int:
	var total := 0
	for w in RADIUS_WEIGHTS.values():
		total += w
	var pick := rng.randi() % total
	for r in RADIUS_WEIGHTS:
		pick -= RADIUS_WEIGHTS[r]
		if pick < 0:
			return r
	return 2
