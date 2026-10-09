extends RefCounted
class_name WikiCatalog
## Data behind the Wiki's Modifiers and Corruption pages, read from the same
## code drops and Orbs use (GearModifierPool, SlateModifierPool, the
## CraftingResolver's candidate weights), so the page can't drift from play.

const GROUPS := ["Melee", "Ranged", "Conduits", "Armour", "Shields", "Accessories", "Jewels", "Lenses", "Slates"]
const MAX_LEVEL := 100
## One base per equipment slot for the Corruption page's slot icons.
const SLOT_TYPES := [&"greatsword", &"kite_shield", &"helmet", &"body_armour", &"gloves", &"boots", &"ring", &"amulet", &"belt"]

static var _types: Dictionary = {}   # group -> Array[Dictionary] {"name", "key", "base"}
static var _index: Array = []        # By-modifier rows, built on first use

## Base types in a group: {"name": display name, "key": item type, "base": a
## representative Item or Slate}.
static func types_in(group: String) -> Array:
	if _types.is_empty():
		_build_types()
	return _types.get(group, [])

static func all_types() -> Array:
	var all: Array = []
	for group in GROUPS:
		all.append_array(types_in(group))
	return all

## The representative base of an item type (for slot icons).
static func base_of(item_type: StringName) -> Resource:
	for t in all_types():
		if t["key"] == item_type:
			return t["base"]
	return null

static func _build_types() -> void:
	if ItemRoller._candidate_meta_cache.is_empty():
		ItemRoller._build_candidate_meta_cache()
	var lowest: Dictionary = {}  # item type -> [level, path]
	for path in ItemRoller._candidate_meta_cache:
		var meta: Dictionary = ItemRoller._candidate_meta_cache[path]
		var type: String = meta.get("item_type", "")
		if type == "" or type == "currency" or ItemRoller._is_excluded_line(meta.get("base_line_id", "")):
			continue
		if not lowest.has(type) or meta["item_level"] < lowest[type][0]:
			lowest[type] = [meta["item_level"], path]
	for group in GROUPS:
		_types[group] = []
	for type in lowest:
		var base := load(lowest[type][1]) as Item
		if base == null or not base.is_equipment():
			continue
		var group := _group_of(base)
		if group == "":
			continue
		var display: String = (base as Weapon).weapon_type if base is Weapon else String(type).capitalize()
		_types[group].append({"name": display, "key": StringName(type), "base": base})
	_types["Jewels"].append({"name": "Jewel", "key": &"jewel", "base": Jewel.new()})
	_types["Lenses"].append({"name": "Lens", "key": &"lens", "base": Lens.new()})
	for tag in SlateRoller.REAL_DAMAGE_TYPES:
		var slate := Slate.new()
		slate.tag = tag
		slate.display_name = "%s Slate" % Constants.DAMAGE_TYPE_NAME.get(tag, "?")
		var shape: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)]
		slate.shape_cells = shape
		_types["Slates"].append({"name": slate.display_name, "key": StringName("slate_%d" % tag), "base": slate})
	for group in GROUPS:
		_types[group].sort_custom(func(a, b): return a["name"] < b["name"])

static func _group_of(base: Item) -> String:
	if base is Weapon:
		var w := base as Weapon
		return "Conduits" if w.is_conduit else ("Ranged" if w.is_ranged else "Melee")
	if base is Shield:
		return "Shields"
	if base is Armor:
		return "Armour"
	match base.get_item_type():
		&"ring", &"amulet", &"belt":
			return "Accessories"
	return ""

## A blank copy of a base at `level`: implicits only, so every modifier is open.
static func _blank(base: Resource, level: int) -> Resource:
	if base is Slate:
		var slate := (base as Slate).duplicate(true) as Slate
		slate.explicits = []
		return slate
	var item := (base as Item).duplicate(true) as Item
	item.item_level = level
	item.rarity = Constants.ItemRarity.COMMON
	item.affixes = item.affixes.filter(func(a: ItemAffix): return a.is_implicit)
	return item

## Item level each tier of a modifier needs. `def` comes from a level-100
## pool, so it carries every tier.
static func tier_level(def: ModifierDef, tier: int, base: Resource) -> int:
	if base is Slate:
		return 1
	var table := ItemRoller.levelled_table(def.stat_key)
	if not table.is_empty():
		return int(table[tier - 1][0])
	if base is Jewel:
		return ItemRoller.tier_min_level(tier, JewelModifierPool.TIER_COUNT)
	return ItemRoller.tier_min_level(tier, ItemRoller.TIER_COUNT, _top_level(def))

## The item level a modifier's Tier 1 needs (weapon library mods set their own).
static func _top_level(def: ModifierDef) -> int:
	if ItemRoller._weapon_affix_cache.is_empty():
		ItemRoller._build_weapon_affix_cache()
	for source in ItemRoller._weapon_affix_cache:
		if StringName(source.affix_id) == def.id:
			return ItemRoller.top_level_of(source)
	return ItemRoller.TOP_TIER_LEVEL

## Every modifier the base can roll, with its tiers and the chance an Orb
## adds it to a blank item of `level` (no Brands). Rows:
## {"def", "text", "prefix", "local", "chance", "min_level",
##  "tiers": [{"tier", "min", "max", "level", "chance"}]}
static func modifier_rows(base: Resource, level: int) -> Array:
	var full := _defs(base, MAX_LEVEL)
	var resolver := CraftingResolver.create_default()
	var target := CraftTarget.wrap(_blank(base, level))
	var ctx := resolver._resolve_brands(&"quickening", null)
	var none: Array[ItemAffix] = []
	var cands := resolver._candidates(target, none, Constants.ItemRarity.RARE, ctx, null)
	var total := 0.0
	for c in cands:
		total += c["weight"]
	var chance_of: Dictionary = {}  # "<def id>|<tier>" -> chance
	for c in cands:
		var key := "%s|%d" % [c["def"].id, c["tier"].tier]
		chance_of[key] = chance_of.get(key, 0.0) + (c["weight"] / total if total > 0.0 else 0.0)
	var rows: Array = []
	for def in full:
		var tiers: Array = []
		var row_chance := 0.0
		for t in def.tiers:
			var tier_chance: float = chance_of.get("%s|%d" % [def.id, t.tier], 0.0)
			row_chance += tier_chance
			tiers.append({"tier": t.tier, "min": t.value_min, "max": t.value_max, "level": tier_level(def, t.tier, base), "chance": tier_chance})
		tiers.sort_custom(func(a, b): return a["tier"] < b["tier"])
		rows.append({
			"def": def, "text": template_text(def.text), "prefix": def.affix_type == ModifierDef.AffixType.PREFIX,
			"local": def.is_local, "chance": row_chance, "tiers": tiers,
			"min_level": tiers.map(func(t): return t["level"]).min() if not tiers.is_empty() else 1,
		})
	rows.sort_custom(_row_order)
	return rows

static func _defs(base: Resource, level: int) -> Array[ModifierDef]:
	var blank := _blank(base, level)
	if blank is Slate:
		return SlateModifierPool.defs_for(blank)
	return GearModifierPool.defs_for(blank)

## A modifier's text with its numbers as "#": "+#% increased Fire damage".
static func template_text(text: String) -> String:
	return text.replace("%.1f", "#").replace("%d", "#").replace("%%", "%")

## By-modifier rows: one per modifier text, with every base type it rolls on.
## {"text", "prefix", "types": [type dicts], "t1_level"}
static func modifier_index() -> Array:
	if not _index.is_empty():
		return _index
	var by_text: Dictionary = {}
	for t in all_types():
		for row in modifier_rows(t["base"], MAX_LEVEL):
			var key: String = row["text"]
			if not by_text.has(key):
				by_text[key] = {"text": key, "prefix": row["prefix"], "types": [], "t1_level": row["tiers"][0]["level"] if not row["tiers"].is_empty() else 1}
			by_text[key]["types"].append(t)
	_index = by_text.values()
	_index.sort_custom(func(a, b): return a["text"].to_lower() < b["text"].to_lower())
	return _index

## Corruption outcomes by tier: {"tier", "chance", "outcomes": [{"name", "label",
## "chance", "text", "slots": [bool per SLOT_TYPES]}]}
static func corruption_tiers() -> Array:
	var total := 0.0
	for w in CorruptionSystem.TIER_WEIGHTS.values():
		total += w
	var tiers: Array = []
	for tier in CorruptionSystem.TIER_WEIGHTS:
		var outcomes: Array = []
		for outcome_name in CorruptionSystem.outcomes_in_tier(tier):
			var slots: Array = []
			for type in SLOT_TYPES:
				var base := base_of(type) as Item
				slots.append(base != null and CorruptionSystem.can_change(outcome_name, base))
			outcomes.append({
				"name": outcome_name, "label": outcome_name.capitalize(), "chance": CorruptionSystem.outcome_chance(outcome_name),
				"text": CorruptionSystem.DESCRIPTIONS.get(outcome_name, ""), "slots": slots,
			})
		tiers.append({"tier": tier, "chance": CorruptionSystem.TIER_WEIGHTS[tier] / total, "outcomes": outcomes})
	return tiers

## Prefixes first, then likeliest first.
static func _row_order(a: Dictionary, b: Dictionary) -> bool:
	if a["prefix"] != b["prefix"]:
		return a["prefix"]
	return a["chance"] > b["chance"]

## ---- Status effects ------------------------------------------------------

## Every status effect, ailments first: {"id", "name", "ailment", "types"
## (damage type names that can cause it from gear chance), "text"}. Numbers
## are read from StatusEffectComponent so the page can't drift from the game.
static func status_effects() -> Array:
	var pct := func(f: float) -> String: return "%d%%" % roundi(f * 100.0)
	var texts := {
		"ignite": "Fire damage over %.0fs: %s of the hit that caused it." % [StatusEffectComponent.IGNITE_DURATION, pct.call(StatusEffectComponent.IGNITE_DAMAGE_PERCENT)],
		"bleed": "Physical damage over %.0fs that ignores Armour: %s of the hit." % [StatusEffectComponent.BLEED_DURATION, pct.call(StatusEffectComponent.BLEED_DAMAGE_PERCENT)],
		"chill": "%s slower movement for %.1fs. %d Chills at once Freeze." % [pct.call(StatusEffectComponent.CHILL_MOVE_SLOW_PERCENT), StatusEffectComponent.CHILL_DURATION, StatusEffectComponent.CHILL_STACKS_TO_FREEZE],
		"freeze": "Can't move or act for %.1fs. Caused by %d stacks of Chill." % [StatusEffectComponent.FREEZE_DURATION, StatusEffectComponent.CHILL_STACKS_TO_FREEZE],
		"shock": "Takes %s more Lightning damage for %.0fs. Doesn't stun." % [pct.call(StatusEffectComponent.SHOCK_DAMAGE_INCREASE), StatusEffectComponent.SHOCK_DURATION],
		"electrocute": "Stunned for %.1fs." % StatusEffectComponent.ELECTROCUTE_DURATION,
		"unraveling": "Takes %s more Esoteric (Aetheric, Entropic, Pale) damage for %.0fs." % [pct.call(StatusEffectComponent.UNRAVELING_DAMAGE_TAKEN_PERCENT), StatusEffectComponent.UNRAVELING_DURATION],
		"pallid": "Deals %s less damage for %.0fs." % [pct.call(StatusEffectComponent.PALLID_DAMAGE_REDUCTION), StatusEffectComponent.PALLID_DURATION],
		"aetherburn": "Aetheric damage over %.0fs (%s of the hit) that also burns as much Ward, or Mana on you." % [StatusEffectComponent.AETHERBURN_DURATION, pct.call(StatusEffectComponent.AETHERBURN_DAMAGE_PERCENT)],
		"scorch": "Each stack: %s more Fire damage taken, Ignite included, up to %d stacks for %.0fs." % [pct.call(StatusEffectComponent.SCORCH_DAMAGE_PER_STACK), StatusEffectComponent.SCORCH_MAX_STACKS, StatusEffectComponent.SCORCH_DURATION],
		"slow": "%s slower movement while it lasts (Caltrops)." % pct.call(StatusEffectComponent.SLOW_MOVE_SLOW_PERCENT),
		"armor_shred": "Each stack strips %s of Armour, up to %d stacks for %.0fs." % [pct.call(StatusEffectComponent.ARMOR_SHRED_PER_STACK), StatusEffectComponent.ARMOR_SHRED_MAX_STACKS, StatusEffectComponent.ARMOR_SHRED_DURATION],
		"suppressed": "Each stack: %s slower movement, up to %d stacks for %.0fs (Machine Pistol)." % [pct.call(StatusEffectComponent.SUPPRESSED_SLOW_PER_STACK), StatusEffectComponent.SUPPRESSED_MAX_STACKS, StatusEffectComponent.SUPPRESSED_DURATION],
		"intimidated": "Takes %s more damage of every type (Intimidating Shout)." % pct.call(StatusEffectComponent.INTIMIDATED_DAMAGE_TAKEN),
		"stun": "Can't move or act for a moment.",
		"guard_break": "Its guard is broken: briefly stunned.",
		"entangle": "Rooted in place (Whip).",
		"marked": "Marked by a ranged stance: your shots deal more to it.",
	}
	var rows := []
	for id in texts:
		var types: Array = StatusEffectComponent.AILMENT_DAMAGE_TYPES.get(id, [])
		rows.append({
			"id": id, "name": Constants.STATUS_EFFECT_NAME.get(id, String(id).capitalize()),
			"ailment": StatusEffectComponent.AILMENT_IDS.has(id), "types": types.map(func(t): return Constants.DAMAGE_TYPE_NAME.get(t, "?")),
			"text": texts[id],
		})
	rows.sort_custom(func(a, b): return a["ailment"] and not b["ailment"])
	return rows

## ---- Monster rarity ------------------------------------------------------

const RARITY_INTENT := {
	Constants.EnemyRarity.NORMAL: "No modifiers.",
	Constants.EnemyRarity.ELITE: "The whole pack is Elite and shares one pack affix.",
	Constants.EnemyRarity.CHAMPION: "Leads a pack of Normal enemies. Its aura affects every enemy nearby, whether it spawned with them or not.",
	Constants.EnemyRarity.ASCENDANT: "A Synod Vindicator, Legion Dreadknight or Veilborne Cantor: stronger, scarier, with affixes from its own pool. Shown on the large health bar.",
}

## {"rarity", "name", "color", "chance" (per pack), "life", "damage", "text",
## "affixes": [EnemyAffix]} per tier.
static func monster_tiers() -> Array:
	var total := 0.0
	for w in Constants.ENEMY_PACK_RARITY_WEIGHTS.values():
		total += w
	var category := {
		Constants.EnemyRarity.ELITE: EnemyAffix.AffixCategory.PACK,
		Constants.EnemyRarity.CHAMPION: EnemyAffix.AffixCategory.CHAMPION,
		Constants.EnemyRarity.ASCENDANT: EnemyAffix.AffixCategory.ASCENDANT,
	}
	var tiers := []
	for rarity in Constants.ENEMY_PACK_RARITY_WEIGHTS:
		var affixes: Array = EnemyRarityComponent.affixes_for_category(category[rarity]) if category.has(rarity) else []
		affixes.sort_custom(func(a, b): return a.display_name < b.display_name)
		tiers.append({
			"rarity": rarity, "name": Constants.ENEMY_RARITY_NAME[rarity], "color": Constants.ENEMY_RARITY_NAME_COLOR[rarity],
			"chance": Constants.ENEMY_PACK_RARITY_WEIGHTS[rarity] / total,
			"life": Constants.ENEMY_RARITY_HEALTH_MULT.get(rarity, 1.0), "damage": Constants.ENEMY_RARITY_DAMAGE_MULT.get(rarity, 1.0),
			"text": RARITY_INTENT[rarity], "affixes": affixes,
		})
	return tiers
