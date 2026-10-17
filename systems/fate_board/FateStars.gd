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
	],
	"amplify_attributes": [
		{"key": "flat_strength", "value": 4.0, "text": "+{v} Strength"},
		{"key": "flat_agility", "value": 4.0, "text": "+{v} Agility"},
		{"key": "flat_intellect", "value": 4.0, "text": "+{v} Intellect"},
		{"key": "flat_life", "value": 10.0, "text": "+{v} Life"},
	],
	"bridge_tag": [
		{"key": "mastery", "value": 0.5, "text": "+{v}% {tag} Mastery"},
		{"key": "ailment_effectiveness", "value": 3.0, "text": "+{v}% increased Ailment Effect"},
		{"key": "skill_effect_duration", "value": 3.0, "text": "+{v}% increased Skill Effect Duration"},
	],
	"free_placement": [
		{"key": "move_speed", "value": 2.0, "text": "+{v}% increased Movement Speed"},
		{"key": "attack_speed", "value": 2.0, "text": "+{v}% increased Attack Speed"},
		{"key": "cast_speed", "value": 2.0, "text": "+{v}% increased Cast Speed"},
		{"key": "cooldown_recovery_rate", "value": 3.0, "text": "+{v}% increased Cooldown Recovery Rate"},
	],
	"cheap": [
		{"key": "flat_aether", "value": 1.0, "text": "+{v} Aether"},
		{"key": "flat_mana", "value": 8.0, "text": "+{v} Mana"},
		{"key": "mana_regen_increased", "value": 5.0, "text": "+{v}% increased Mana Regeneration"},
		{"key": "mana_cost_reduction", "value": 2.0, "text": "+{v}% reduced Mana Cost"},
	],
}

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

static var _site_cache: Dictionary = {}

## The fixed places a Star's bonuses appear, the same on every board.
static func site_cells(star: int) -> Array[Vector2i]:
	if _site_cache.has(star):
		return _site_cache[star]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (star + 1)
	var star_cells := cells()
	var origin: Vector2i = star_cells[star]
	var result: Array[Vector2i] = []
	var tries := 0
	while result.size() < MAX_SITES and tries < 500:
		tries += 1
		# One site per eighth of the circle, so they ring the Star.
		var angle := (result.size() + rng.randf_range(0.15, 0.85)) * TAU / MAX_SITES
		var dist := rng.randf_range(SITE_MIN_DIST, SITE_MAX_DIST)
		var cell := origin + Vector2i(roundi(cos(angle) * dist), roundi(sin(angle) * dist))
		if not FateBoard.in_board(cell) or star_cells.has(cell):
			continue
		if result.any(func(o: Vector2i) -> bool: return Vector2(o - cell).length() < 2.5):
			continue
		result.append(cell)
	_site_cache[star] = result
	return result

## The sites a Lens in `star` lights, with their bonuses. Bonuses cycle
## through the pool from a point set by the Lens, so every bonus shows up.
static func sites_for(star: int, lens: Lens) -> Array[Site]:
	var result: Array[Site] = []
	var pool: Array = POOLS.get(lens.radius_mod, [])
	if pool.is_empty():
		return result
	var count: int = SITES_BY_RADIUS.get(lens.radius, 4)
	var all := site_cells(star)
	var start := absi(hash(lens.item_id)) % pool.size()
	for i in mini(count, all.size()):
		var site := Site.new()
		site.cell = all[i]
		site.star = star
		site.index = i
		site.bonus = pool[(start + i) % pool.size()]
		site.tag = lens.radius_tag
		result.append(site)
	return result

static func bonus_text(bonus: Dictionary, tag: int) -> String:
	var v: float = bonus["value"]
	var v_text := str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
	return String(bonus["text"]).replace("{v}", v_text).replace("{tag}", Constants.DAMAGE_TYPE_NAME.get(tag, "Tag"))

static func pool_name(lens: Lens) -> String:
	return String(POOL_NAMES.get(lens.radius_mod, "?")).replace("{tag}", Constants.DAMAGE_TYPE_NAME.get(lens.radius_tag, "Tag"))

## Card line for a Lens: what it does in a Star.
static func lens_star_text(lens: Lens) -> String:
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
