extends RefCounted
class_name FateStars
## The Fate Board's Stars: the Centre Star the board grows from and the
## four cardinal Stars around it. A Star takes a Lens once a Slate chain
## reaches it (the Centre always counts as reached). A Lensed Star lights
## bonus sites at fixed places around it; a Slate covering a site claims its
## bonus. The Lens's radius modifier picks the bonus pool, its size how many
## sites light up.

const NAMES: Array[String] = ["Centre Star", "North Star", "East Star", "South Star", "West Star"]
const CENTRE := 0

## Lens radius -> sites lit.
const SITES_BY_RADIUS := {2: 4, 3: 6, 4: 8}
const MAX_SITES := 8
## Site distance from its Star, in tiles.
const SITE_MIN_DIST := 3.0
const SITE_MAX_DIST := 9.0

## Radius modifier id -> the Star bonuses it lights. "{tag}" is the Lens's
## damage type. "key" is a misc stat key, or a special:
## "type_damage" (increased <tag> damage), "mastery" (<tag> Mastery, percent
## more) and the flat_<attribute> keys (EquipmentComponent.AFFIX_STAT_KEYS).
const POOLS := {
	"amplify_tag": [
		{"key": "type_damage", "value": 4.0, "text": "+{v}% increased {tag} Damage"},
		{"key": "increased_generic_damage", "value": 2.0, "text": "+{v}% increased Damage"},
		{"key": "crit_chance_increased", "value": 3.0, "text": "+{v}% increased Critical Strike Chance"},
		{"key": "crit_damage_increased", "value": 4.0, "text": "+{v}% increased Critical Strike Damage"},
		{"key": "increased_spell_damage", "value": 3.0, "text": "+{v}% increased Spell Damage"},
		{"key": "increased_area_damage", "value": 3.0, "text": "+{v}% increased Area Damage"},
		{"key": "dot_multiplier", "value": 2.0, "text": "+{v}% to Damage over Time Multiplier"},
		{"key": "increased_physical_damage", "value": 3.0, "text": "+{v}% increased Physical Damage"},
	],
	"amplify_attributes": [
		{"key": "flat_strength", "value": 4.0, "text": "+{v} Strength"},
		{"key": "flat_agility", "value": 4.0, "text": "+{v} Agility"},
		{"key": "flat_intellect", "value": 4.0, "text": "+{v} Intellect"},
		{"key": "flat_life", "value": 10.0, "text": "+{v} Life"},
		{"key": "flat_mana", "value": 8.0, "text": "+{v} Mana"},
		{"key": "life_increased", "value": 2.0, "text": "+{v}% increased maximum Life"},
		{"key": "mana_increased", "value": 2.0, "text": "+{v}% increased maximum Mana"},
		{"key": "life_regen_flat", "value": 2.0, "text": "+{v} Life Regeneration per second"},
	],
	"bridge_tag": [
		{"key": "mastery", "value": 0.5, "text": "+{v}% {tag} Mastery"},
		{"key": "ailment_effectiveness", "value": 3.0, "text": "+{v}% increased Ailment Effect"},
		{"key": "skill_effect_duration", "value": 3.0, "text": "+{v}% increased Skill Effect Duration"},
		{"key": "ailment_duration", "value": 3.0, "text": "+{v}% increased Ailment Duration"},
		{"key": "damaging_ailment_chance", "value": 2.0, "text": "+{v}% chance to cause Damaging Ailments"},
		{"key": "debuff_effectiveness", "value": 3.0, "text": "+{v}% increased Debuff Effectiveness"},
		{"key": "ailment_tick_rate", "value": 2.0, "text": "Ailments deal damage {v}% faster"},
	],
	"free_placement": [
		{"key": "move_speed", "value": 2.0, "text": "+{v}% increased Movement Speed"},
		{"key": "attack_speed", "value": 2.0, "text": "+{v}% increased Attack Speed"},
		{"key": "cast_speed", "value": 2.0, "text": "+{v}% increased Cast Speed"},
		{"key": "cooldown_recovery_rate", "value": 3.0, "text": "+{v}% increased Cooldown Recovery Rate"},
		{"key": "reload_speed", "value": 3.0, "text": "+{v}% increased Reload Speed"},
		{"key": "projectile_speed", "value": 3.0, "text": "+{v}% increased Projectile Speed"},
		{"key": "dash_speed", "value": 3.0, "text": "+{v}% increased Dash Speed"},
	],
	"cheap": [
		{"key": "flat_aether", "value": 1.0, "text": "+{v} Aether"},
		{"key": "flat_mana", "value": 8.0, "text": "+{v} Mana"},
		{"key": "mana_regen_increased", "value": 5.0, "text": "+{v}% increased Mana Regeneration"},
		{"key": "mana_cost_reduction", "value": 2.0, "text": "+{v}% reduced Mana Cost"},
		{"key": "mana_on_kill", "value": 2.0, "text": "+{v} Mana on Kill"},
		{"key": "ward_recovery_increased", "value": 3.0, "text": "+{v}% increased Ward Recovery"},
	],
}

## Each site rolls its bonus from the pool and its value within
## VALUE_ROLL of the pool value, all from the Lens's seed (like a Timeless
## Jewel: two Lenses of a kind light different bonuses). One site in
## NOTABLE_ONE_IN (at least one per Lens from Rare up) is a notable at
## NOTABLE_MULT. Aether sites stay whole numbers.
const VALUE_ROLL := Vector2(0.6, 1.4)
const NOTABLE_ONE_IN := 6
const NOTABLE_MULT := 3.0

## Pool display name per radius modifier, for cards and the wiki.
const POOL_NAMES := {
	"amplify_tag": "{tag} power",
	"amplify_attributes": "attributes",
	"bridge_tag": "{tag} Mastery and ailments",
	"free_placement": "speed",
	"cheap": "Aether and Mana",
}

class Site:
	var cell: Vector2i
	var star: int
	var index: int
	## POOLS entry and the Lens's tag.
	var bonus: Dictionary
	var tag: int = -1

	func text() -> String:
		return FateStars.bonus_text(bonus, tag)

## Every Star's cell: the Centre, then N/E/S/W at STAR_DISTANCE.
static func cells() -> Array[Vector2i]:
	var c := FateBoard.ANCHOR_CELL
	var d := FateBoard.STAR_DISTANCE
	return [c, c + Vector2i(0, -d), c + Vector2i(d, 0), c + Vector2i(0, d), c + Vector2i(-d, 0)]

static func star_at(cell: Vector2i) -> int:
	return cells().find(cell)

## Star bonus values are POOLS x this, then x the Lens's rarity.
const VALUE_MULT := 2.0
const RARITY_MULT := {
	Constants.ItemRarity.COMMON: 1.0,
	Constants.ItemRarity.UNCOMMON: 1.25,
	Constants.ItemRarity.RARE: 1.5,
	Constants.ItemRarity.UNIQUE: 1.75,
	Constants.ItemRarity.MYTHIC: 2.0,
}

static var _site_cache: Dictionary = {}

## Where a Star's bonuses appear for a layout seed. Seed 0 is the Star's
## default ring; a Lens passes lens_seed(), so its sites move when its
## modifiers change or it goes into a different Star.
static func site_cells(star: int, layout_seed: int = 0) -> Array[Vector2i]:
	var cache_key := Vector2i(star, layout_seed)
	if _site_cache.has(cache_key):
		return _site_cache[cache_key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (star + 1) + layout_seed
	var star_cells := cells()
	var origin: Vector2i = star_cells[star]
	var turn := rng.randf() * TAU if layout_seed != 0 else 0.0
	var result: Array[Vector2i] = []
	var tries := 0
	while result.size() < MAX_SITES and tries < 500:
		tries += 1
		# One site per eighth of the circle, so they ring the Star.
		var angle := turn + (result.size() + rng.randf_range(0.15, 0.85)) * TAU / MAX_SITES
		var dist := rng.randf_range(SITE_MIN_DIST, SITE_MAX_DIST)
		var cell := origin + Vector2i(roundi(cos(angle) * dist), roundi(sin(angle) * dist))
		if not FateBoard.in_board(cell) or star_cells.has(cell):
			continue
		if result.any(func(o: Vector2i) -> bool: return Vector2(o - cell).length() < 2.5):
			continue
		result.append(cell)
	_site_cache[cache_key] = result
	return result

## A seed from the Star and everything rolled on the Lens (radius modifier,
## jewel modifiers, rarity): re-rolling any of them reshuffles its sites.
static func lens_seed(star: int, lens: Lens) -> int:
	var parts: Array = [star, lens.radius, lens.radius_mod, snappedf(lens.radius_value, 0.01), lens.radius_tag, lens.rarity]
	for affix in lens.affixes:
		parts.append(affix.key())
		parts.append(snappedf(affix.value, 0.01))
	return absi(hash(parts)) % 1000003 + 1

static func value_multiplier(lens: Lens) -> float:
	return VALUE_MULT * float(RARITY_MULT.get(lens.rarity, 1.0))

## The sites a Lens in `star` lights, with their bonuses: each site rolls its
## bonus, value and notable chance from the Lens's seed, so the same Lens in
## the same Star always lights the same set and any re-roll changes it.
static func sites_for(star: int, lens: Lens) -> Array[Site]:
	var result: Array[Site] = []
	var pool: Array = POOLS.get(lens.radius_mod, [])
	if pool.is_empty():
		return result
	var count: int = SITES_BY_RADIUS.get(lens.radius, 4)
	var layout_seed := lens_seed(star, lens)
	var all := site_cells(star, layout_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed * 31 + 17
	var mult := value_multiplier(lens)
	var shown := mini(count, all.size())
	var forced_notable := rng.randi_range(0, shown - 1) if lens.rarity >= Constants.ItemRarity.RARE else -1
	for i in shown:
		var site := Site.new()
		site.cell = all[i]
		site.star = star
		site.index = i
		var bonus: Dictionary = (pool[rng.randi_range(0, pool.size() - 1)] as Dictionary).duplicate()
		var notable := i == forced_notable or rng.randi_range(1, NOTABLE_ONE_IN) == 1
		var value := float(bonus["value"]) * mult * rng.randf_range(VALUE_ROLL.x, VALUE_ROLL.y) * (NOTABLE_MULT if notable else 1.0)
		var key := String(bonus["key"])
		if key.begins_with("flat_"):
			value = maxf(roundf(value), 1.0)
		elif key != "mastery":
			value = maxf(snappedf(value, 0.5), 0.5)
		else:
			value = snappedf(value, 0.1)
		bonus["value"] = value
		bonus["notable"] = notable
		site.bonus = bonus
		site.tag = lens.radius_tag
		result.append(site)
	return result

## The "star_gifts" unique Lens: every placed Slate with a cell within the
## Lens's radius of its Star gains one of these, picked from the Slate's
## placement and the Lens (re-placing the Slate re-picks it). The damage
## one also picks a damage type. Values are fixed.
const GIFTS := [
	{"key": "flat_life", "value": 10.0, "text": "+{v} Life"},
	{"key": "flat_mana", "value": 10.0, "text": "+{v} Mana"},
	{"key": "type_damage", "value": 10.0, "text": "+{v}% increased {tag} Damage"},
	{"key": "increased_defences", "value": 2.0, "text": "+{v}% increased Defences"},
]
## increased_defences counts as each of these.
const DEFENCE_KEYS: Array[String] = ["increased_armor", "increased_evasion", "increased_ward"]

## One site per Slate in a gift Lens's radius, on the Slate's cell nearest the Star.
static func gift_sites(board: FateBoard, star: int, lens: Lens) -> Array[Site]:
	var result: Array[Site] = []
	var origin: Vector2i = cells()[star]
	for id in board.placements:
		var data: FateBoard.PlacedSlateData = board.placements[id]
		var nearest := Vector2i.ZERO
		var best := INF
		for c in data.cells:
			var dist := Vector2(c - origin).length()
			if dist < best:
				best = dist
				nearest = c
		if best > lens.radius + 0.01:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([id, lens.item_id])
		var site := Site.new()
		site.cell = nearest
		site.star = star
		site.index = result.size()
		site.bonus = (GIFTS[rng.randi_range(0, GIFTS.size() - 1)] as Dictionary).duplicate()
		site.bonus["notable"] = false
		if site.bonus["key"] == "type_damage":
			site.tag = SlateRoller.REAL_DAMAGE_TYPES[rng.randi_range(0, SlateRoller.REAL_DAMAGE_TYPES.size() - 1)]
		result.append(site)
	return result

static func bonus_text(bonus: Dictionary, tag: int) -> String:
	var v: float = bonus["value"]
	var v_text := str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
	var text := String(bonus["text"]).replace("{v}", v_text).replace("{tag}", Constants.DAMAGE_TYPE_NAME.get(tag, "Tag"))
	return "Notable: " + text if bonus.get("notable", false) else text

static func pool_name(lens: Lens) -> String:
	return String(POOL_NAMES.get(lens.radius_mod, "?")).replace("{tag}", Constants.DAMAGE_TYPE_NAME.get(lens.radius_tag, "Tag"))

## Card line for a Lens: what it does in a Star.
static func lens_star_text(lens: Lens) -> String:
	if lens.radius_mod == "star_gifts":
		return "Only fits the %s; its radius counts from there" % NAMES[lens.star_only()]
	return "In a Star: lights %d %s bonuses on the Fate Board" % [SITES_BY_RADIUS.get(lens.radius, 4), pool_name(lens)]

## Claimed bonuses on a board, split by where they apply:
## {"stats": {Stat: v}, "misc": {key: v}, "mastery": {tag: fraction}}.
## Jewel modifiers of Lenses in lit Stars count here too.
static func totals(board: FateBoard) -> Dictionary:
	var stats := {}
	var misc := {}
	var mastery := {}
	for site in board.claimed_sites():
		_add_bonus(stats, misc, mastery, site.bonus["key"], float(site.bonus["value"]), site.tag)
	for star in board.lit_stars():
		var lens: Lens = board.star_lenses[star]
		for affix in lens.affixes:
			_add_bonus(stats, misc, mastery, affix.key(), affix.value, -1)
	return {"stats": stats, "misc": misc, "mastery": mastery}

static func _add_bonus(stats: Dictionary, misc: Dictionary, mastery: Dictionary, key: String, value: float, tag: int) -> void:
	if key == "mastery":
		mastery[tag] = mastery.get(tag, 0.0) + value / 100.0
	elif key == "increased_defences":
		for k in DEFENCE_KEYS:
			misc[k] = misc.get(k, 0.0) + value
	elif key == "type_damage":
		var type_key := StatKeys.type_damage_key(tag)
		misc[type_key] = misc.get(type_key, 0.0) + value
	elif EquipmentComponent.AFFIX_STAT_KEYS.has(key):
		var stat: Constants.Stat = EquipmentComponent.AFFIX_STAT_KEYS[key]
		stats[stat] = stats.get(stat, 0.0) + value
	elif EquipmentComponent.is_misc_key(key):
		misc[key] = misc.get(key, 0.0) + value

## Adds `extra` into `into` (both key -> float).
static func merge(into: Dictionary, extra: Dictionary) -> Dictionary:
	var result := into.duplicate()
	for k in extra:
		result[k] = result.get(k, 0.0) + extra[k]
	return result
