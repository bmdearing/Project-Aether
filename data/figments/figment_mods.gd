extends RefCounted
class_name FigmentMods
## Figment tiers, bands and the three modifier pools.
##
## Tiers run 1-21 in three bands: Low (1-7), Mid (8-14), High (15-21).
## Each band opens one more pool: Low rolls only Pool I, Mid rolls I-II and
## High rolls I-III. Every mod makes the Figment harder and pays it back in
## Pack Size, Item Quantity and Item Rarity. Pool I mods are mild and mostly
## pay in Pack Size; Pool III mods are brutal and pay in Quantity/Rarity.
##
## "boss_*" mods affect the Figment boss and Ascendants only
## (Enemy.is_map_boss_target()). Values are percentages.

enum Band { LOW, MID, HIGH }

const MAX_TIER := 21
const BAND_SIZE := 7
const BAND_NAMES := ["Low", "Mid", "High"]
const BAND_COLORS := [Color(0.62, 0.82, 0.62), Color(0.95, 0.8, 0.4), Color(0.95, 0.45, 0.35)]

## Mod count range per band; tiers late in a band lean to the top of it.
const MOD_COUNT := [Vector2i(1, 3), Vector2i(2, 5), Vector2i(4, 7)]

## Every roll's value grows this much per tier above the band's first.
const VALUE_GROWTH_PER_BAND_TIER := 0.05

## Damage types a conversion mod can roll.
const CONVERSION_TYPES := [
	Constants.DamageType.FIRE, Constants.DamageType.COLD, Constants.DamageType.LIGHTNING,
	Constants.DamageType.AETHERIC, Constants.DamageType.ENTROPIC, Constants.DamageType.PALE,
]

## id: stat_key on the Figment's affix. desc: "%d" takes the rolled value
## (conversion also takes the type name). rewards are per mod, in %.
const MODS := {
	# ---- Pool I: mild, pays mostly in Pack Size ----
	"monster_move_speed": {"pool": 1, "min": 10.0, "max": 15.0, "desc": "Monsters have %d%% increased Movement Speed",
		"pack_size": 8.0, "quantity": 3.0, "rarity": 0.0},
	"monster_area": {"pool": 1, "min": 15.0, "max": 25.0, "desc": "Monsters have %d%% increased Area of Effect",
		"pack_size": 8.0, "quantity": 3.0, "rarity": 0.0},
	"monster_cast_speed": {"pool": 1, "min": 10.0, "max": 15.0, "desc": "Monsters have %d%% increased Cast Speed",
		"pack_size": 8.0, "quantity": 2.0, "rarity": 2.0},
	"boss_life": {"pool": 1, "min": 20.0, "max": 30.0, "desc": "Boss and Ascendants have %d%% more Life",
		"pack_size": 6.0, "quantity": 4.0, "rarity": 2.0},
	# ---- Pool II: Mid and High ----
	"monster_attack_speed": {"pool": 2, "min": 15.0, "max": 25.0, "desc": "Monsters have %d%% increased Attack Speed",
		"pack_size": 4.0, "quantity": 8.0, "rarity": 5.0},
	"monster_crit": {"pool": 2, "min": 5.0, "max": 8.0, "desc": "Monsters have +%d%% Critical Strike Chance and +%d%% Critical Strike Damage",
		"pack_size": 3.0, "quantity": 8.0, "rarity": 6.0},
	"monster_projectiles": {"pool": 2, "min": 1.0, "max": 1.0, "desc": "Monsters fire %d additional Projectile(s)",
		"pack_size": 3.0, "quantity": 9.0, "rarity": 5.0},
	"boss_area": {"pool": 2, "min": 25.0, "max": 40.0, "desc": "Boss and Ascendants have %d%% more Area of Effect",
		"pack_size": 3.0, "quantity": 7.0, "rarity": 5.0},
	"boss_speed": {"pool": 2, "min": 15.0, "max": 20.0, "desc": "Boss and Ascendants have %d%% more Cast, Attack and Movement Speed",
		"pack_size": 3.0, "quantity": 8.0, "rarity": 6.0},
	# ---- Pool III: High only, pays in Quantity/Rarity ----
	"monster_damage": {"pool": 3, "min": 30.0, "max": 45.0, "desc": "Monsters deal %d%% increased Damage",
		"pack_size": 2.0, "quantity": 14.0, "rarity": 10.0},
	"monster_conversion": {"pool": 3, "min": 30.0, "max": 50.0, "desc": "Monsters convert %d%% of their Damage to %s",
		"pack_size": 2.0, "quantity": 12.0, "rarity": 10.0},
	"boss_damage": {"pool": 3, "min": 30.0, "max": 45.0, "desc": "Boss and Ascendants deal %d%% more Damage",
		"pack_size": 2.0, "quantity": 12.0, "rarity": 10.0},
}

## Crit mod: its rolled value is the added crit chance; crit damage is this
## multiple of it (+5% chance -> +30% damage).
const CRIT_DAMAGE_PER_CHANCE := 6.0
## Monsters with no crit mod never crit; with one they crit for this x.
const MONSTER_BASE_CRIT_MULTIPLIER := 1.5
## A cast-speed bonus can't shorten a telegraph below this share of itself.
const MIN_TELEGRAPH_SHARE := 0.6

static func band_of(tier: int) -> Band:
	return clampi((clampi(tier, 1, MAX_TIER) - 1) / BAND_SIZE, 0, 2) as Band

static func band_name(tier: int) -> String:
	return BAND_NAMES[band_of(tier)]

static func band_range(band: int) -> Vector2i:
	return Vector2i(band * BAND_SIZE + 1, band * BAND_SIZE + BAND_SIZE)

## Highest pool a tier can roll from: 1 (Low), 2 (Mid) or 3 (High).
static func max_pool(tier: int) -> int:
	return band_of(tier) + 1

static func ids_for_tier(tier: int) -> Array[String]:
	var ids: Array[String] = []
	for id in MODS:
		if MODS[id]["pool"] <= max_pool(tier):
			ids.append(id)
	return ids

## How many mods a tier rolls: the band's range, skewed up within the band.
static func roll_mod_count(tier: int) -> int:
	var band := band_of(tier)
	var span: Vector2i = MOD_COUNT[band]
	var progress := float(tier - band_range(band).x) / float(BAND_SIZE - 1)
	var low := span.x + roundi((span.y - span.x) * progress * 0.5)
	return randi_range(mini(low, span.y), span.y)

static func pool_of(id: String) -> int:
	return MODS[id]["pool"] if MODS.has(id) else 0

## Rolled value for a mod at a tier (projectiles stay whole).
static func roll_value(id: String, tier: int) -> float:
	var entry: Dictionary = MODS[id]
	var band_tier := tier - band_range(band_of(tier)).x
	var value := randf_range(entry["min"], entry["max"]) * (1.0 + VALUE_GROWTH_PER_BAND_TIER * band_tier)
	return float(roundi(value)) if id == "monster_projectiles" else value

static func describe(id: String, value: float, damage_type: int = -1) -> String:
	var desc: String = MODS[id]["desc"]
	match id:
		"monster_crit":
			return desc % [roundi(value), roundi(value * CRIT_DAMAGE_PER_CHANCE)]
		"monster_conversion":
			return desc % [roundi(value), Constants.DAMAGE_TYPE_NAME.get(damage_type, "?")]
	return desc % roundi(value)
