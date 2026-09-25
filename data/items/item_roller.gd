extends RefCounted
class_name ItemRoller
## Rolls a random piece of gear on demand - dropped by Enemy.gd on death,
## picked up via LootPickup.gd, or stocked by the Hub's GearShop. Picks a
## real, balanced base item (weapon_type/damage_type/scaling_grade/etc.)
## and re-rolls only its rarity + affix list.
##
## User request (2026-08-30): Section 25's full tiered base-type catalog
## is now real (see tools/generate_base_types.gd - ~750 generated .tres
## across data/weapons|armor|shields/instances/, each tagged item_level +
## base_line_id) alongside the original hand-authored singles (untagged,
## base_line_id == ""). power_level now doubles as the target item level:
## _pick_base_item() picks, per doc "Line", the single highest-item_level
## tier still <= power_level - "always the current best base your level
## has unlocked" - then rolls uniformly among every line's current pick
## plus every untagged standalone base. See Enemy._compute_item_level()
## for how a kill's own power_level is derived from area level + rank.
##
## Rarity -> affix count (Common 0, Uncommon 1-2, Rare 1-6 - v4.7 raised
## the minimum from Section 18's 0 so a colored drop always has a mod;
## rarity is determined by base quality, not affix count). Affix
## values roll in tiers (TIER_COUNT bands, Tier 1 best) gated by
## `power_level`. flat_<stat> affixes are the only source of stat growth
## in this project (Section 12: gear only) - summed into StatSheet by
## EquipmentComponent.compute_stat_bonuses().
##
## loot_rarity_multiplier (from the active Map, see FigmentItem.gd) shifts
## the rarity roll. loot_quantity_multiplier is consumed by Enemy.gd's
## drop-chance roll instead, not here.

const BASE_ITEM_DIRS := [
	"res://data/weapons/instances/",
	"res://data/armor/instances/",
	"res://data/shields/instances/",
	"res://data/items/instances/",
]

## Base lines that are throwables, not gear (Patch v4.3): their old .tres
## bases sit in data/items/instances/ and were being rolled as rings with
## garbled stats. Matched as substrings of Item.base_line_id ("grenade"
## also covers "infusion_grenade"). Excluded from loot/shop rolls only -
## the files stay, for a future throwable consumable system.
const EXCLUDED_ITEM_TYPES := ["throwing_knife", "impact_hatchet", "pressure_javelin", "grenade", "infusion_grenade"]

static func _is_excluded_line(base_line_id: String) -> bool:
	for excluded in EXCLUDED_ITEM_TYPES:
		if base_line_id.contains(excluded):
			return true
	return false

## Fills a pool entry's "%d" placeholder. A binary mod ("Triggers Retaliation
## on Block") has none, and formatting it anyway is a script error that aborts
## the whole roll - Patch v4.0 shipped that bug for retaliate_on_block.
static func format_desc(desc: String, value: float) -> String:
	return desc % round(value) if "%" in desc else desc

## Which Constants.MAX_SOCKETS_BY_CATEGORY row an item falls in.
static func get_socket_category(item: Item) -> String:
	if item is Weapon:
		var weapon := item as Weapon
		if weapon.is_conduit:
			return "conduit_offhand" if weapon.is_offhand else "conduit_main_hand"
		if weapon.is_ranged:
			return "two_handed_ranged" if weapon.is_two_handed else "one_handed_ranged"
		return "two_handed_melee" if weapon.is_two_handed else "one_handed_melee"
	if item is Shield:
		return "shield"
	match item.equip_slot:
		Constants.EquipmentSlot.BODY_ARMOUR: return "body_armour"
		Constants.EquipmentSlot.HELMET: return "helmet"
		Constants.EquipmentSlot.GLOVES: return "gloves"
		Constants.EquipmentSlot.BOOTS: return "boots"
		Constants.EquipmentSlot.RING: return "ring"
		Constants.EquipmentSlot.AMULET: return "amulet"
		Constants.EquipmentSlot.BELT: return "belt"
		Constants.EquipmentSlot.OFFHAND: return "shield"
	return ""

## 0 for anything with no socket category (throwables, currency).
static func get_socket_cap(item: Item) -> int:
	return Constants.MAX_SOCKETS_BY_CATEGORY.get(get_socket_category(item), 0)

## 5 tiers per affix, Tier 1 best - the doc's own tier counts vary per
## mod (5 to 11+); this project picks one consistent count for every affix.
const TIER_COUNT := 5
## Each tier's range is TIER_DECAY of the tier above's - an invented
## approximation of the doc's tables' shape.
const TIER_DECAY := 0.8

## tier1_min/tier1_max define only the best (Tier 1) range - lower tiers
## are derived via _tier_range(). "applies_to": [] means any base item
## type; otherwise a list of category strings (see _pool_for()).
##
## "brand_tags": which Brand.category_tag value(s) (Section 20) a Cube
## craft's Damage Type/Defensive Type/Umbrella Brand can draw this entry
## from - see _pool_for_brand_tag(), used by CraftingSystem.gd. Evasion/
## Resistance/Resilience/Skills have no other stat anywhere in this
## project to hang a REAL affix off yet (same as flat_armor/flat_ward
## already were before this - README gap #18: descriptive-only, not
## aggregated into a formula), so their 4 entries below just extend that
## same existing gap rather than opening a new one.
const AFFIX_POOL := [
	# Patch v3.8: six stats collapsed to three (renamed in v4.8).
	{"stat_key": "flat_strength", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Strength", "applies_to": [], "brand_tags": ["kinetic", "piercing", "explosive"]},
	{"stat_key": "flat_agility", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Agility", "applies_to": [], "brand_tags": ["movement", "evasion"]},
	{"stat_key": "flat_intellect", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Intellect", "applies_to": [], "brand_tags": ["fire", "cold", "lightning", "aetheric", "entropic", "pale"]},
	# physical_dmg_increased removed (Patch v4.0) - superseded by the new
	# "increased_physical_damage" entry below, doc-exact value (28-34%,
	# was this entry's own invented 16-20%).
	{"stat_key": "elemental_dmg_increased", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d%% increased Elemental damage", "applies_to": ["weapon"], "brand_tags": ["fire", "cold", "lightning"]},
	{"stat_key": "esoteric_dmg_increased", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d%% increased Esoteric damage", "applies_to": ["weapon"], "brand_tags": ["aetheric", "entropic", "pale"]},
	{"stat_key": "flat_armor", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d Armor", "applies_to": ["armor", "shield"], "brand_tags": ["armor"]},
	{"stat_key": "flat_ward", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d Ward", "applies_to": ["armor"], "brand_tags": ["ward"]},
	{"stat_key": "flat_evasion", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d Evasion", "applies_to": ["armor"], "brand_tags": ["evasion"]},
	# Patch v3.2 "Revision - Resistance System": doc-exact range, matching
	# the Ember/Frost/Volt/Void Ring implicits (+11-27%) - Esoteric is
	# unified across Aetheric/Entropic/Pale per the patch, one stat covers
	# all three. applies_to: [] (any item) since the doc's own examples
	# are Rings, not armor.
	{"stat_key": "fire_resistance_pct", "tier1_min": 11.0, "tier1_max": 27.0, "desc": "+%d%% Fire Resistance", "applies_to": [], "brand_tags": ["resistance", "fire"]},
	{"stat_key": "cold_resistance_pct", "tier1_min": 11.0, "tier1_max": 27.0, "desc": "+%d%% Cold Resistance", "applies_to": [], "brand_tags": ["resistance", "cold"]},
	{"stat_key": "lightning_resistance_pct", "tier1_min": 11.0, "tier1_max": 27.0, "desc": "+%d%% Lightning Resistance", "applies_to": [], "brand_tags": ["resistance", "lightning"]},
	{"stat_key": "esoteric_resistance_pct", "tier1_min": 11.0, "tier1_max": 27.0, "desc": "+%d%% Esoteric Resistance", "applies_to": [], "brand_tags": ["resistance", "aetheric", "entropic", "pale"]},
	{"stat_key": "flat_resilience", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d Resilience", "applies_to": [], "brand_tags": ["resilience"]},
	{"stat_key": "skill_cooldown_reduced", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "+%d%% reduced skill cooldowns", "applies_to": [], "brand_tags": ["skills"]},
	# Patch v3.8 Section 2 "Removed expressions" - max_life/life_regen/
	# max_mana/mana_regen/attack_speed/cast_speed/move_speed used to
	# derive from a character stat (Vitality/Instinct/Intellect), now
	# purely gear-affix-driven; crit_damage/debuff_effectiveness/stamina
	# never had a stat source. attack_speed/move_speed/cast_speed are
	# real, consumed bonuses (EquipmentComponent.compute_misc_bonuses(),
	# Player.get_action_speed_multiplier()/get_move_speed_multiplier(),
	# StatSheet.cast_speed_bonus); the rest are descriptive-only for now,
	# same "real affix, no formula to feed it yet" footing flat_evasion/
	# the 4 resistance entries/flat_resilience/skill_cooldown_reduced
	# already had before this patch.
	{"stat_key": "max_life", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Life", "applies_to": [], "brand_tags": []},
	{"stat_key": "life_regen", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%.1f Life Regeneration per second", "applies_to": [], "brand_tags": []},
	{"stat_key": "max_mana", "tier1_min": 15.0, "tier1_max": 20.0, "desc": "+%d Mana", "applies_to": [], "brand_tags": ["resource"]},
	{"stat_key": "mana_regen", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%.1f Mana Regeneration per second", "applies_to": [], "brand_tags": ["resource"]},
	{"stat_key": "attack_speed", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "+%d%% increased Attack Speed", "applies_to": ["weapon"], "brand_tags": ["skills"]},
	{"stat_key": "cast_speed", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "+%d%% increased Cast Speed", "applies_to": [], "brand_tags": ["skills"]},
	{"stat_key": "move_speed", "tier1_min": 4.0, "tier1_max": 8.0, "desc": "+%d%% increased Move Speed", "applies_to": [], "brand_tags": ["movement"]},
	{"stat_key": "crit_damage", "tier1_min": 15.0, "tier1_max": 20.0, "desc": "+%d%% increased Critical Strike Damage", "applies_to": [], "brand_tags": []},
	{"stat_key": "debuff_effectiveness", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "+%d%% Debuff Effectiveness", "applies_to": [], "brand_tags": ["skills"]},
	{"stat_key": "stamina", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Stamina", "applies_to": [], "brand_tags": []},

	# Patch v4.0 Ailment Build Mod Pool - [type] = bleed/ignite/chill/
	# electrocute/shock/aetherburn/unraveling/pallid, 8 distinct affixes
	# per mod. Weapons+Gloves = [PRIMARY_WEAPON, GLOVES].
	{"stat_key": "ailment_chance_bleed", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Bleed", "applies_to": ["weapon", "armor"], "slots": [4, 2], "brand_tags": []},
	{"stat_key": "ailment_chance_ignite", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Ignite", "applies_to": ["weapon", "armor"], "slots": [4, 2], "brand_tags": []},
	{"stat_key": "ailment_chance_chill", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Chill", "applies_to": ["weapon", "armor"], "slots": [4, 2], "brand_tags": []},
	{"stat_key": "ailment_chance_electrocute", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Electrocute", "applies_to": ["weapon", "armor"], "slots": [4, 2], "brand_tags": []},
	{"stat_key": "ailment_chance_shock", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Shock", "applies_to": ["weapon", "armor"], "slots": [4, 2], "brand_tags": []},
	{"stat_key": "ailment_chance_aetherburn", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Aetherburn", "applies_to": ["weapon", "armor"], "slots": [4, 2], "brand_tags": []},
	{"stat_key": "ailment_chance_unraveling", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Unraveling", "applies_to": ["weapon", "armor"], "slots": [4, 2], "brand_tags": []},
	{"stat_key": "ailment_chance_pallid", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Pallid", "applies_to": ["weapon", "armor"], "slots": [4, 2], "brand_tags": []},
	{"stat_key": "increased_ailment_damage_bleed", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Bleed damage", "applies_to": ["weapon", "armor"], "slots": [4, 2, 0], "brand_tags": []},
	{"stat_key": "increased_ailment_damage_ignite", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Ignite damage", "applies_to": ["weapon", "armor"], "slots": [4, 2, 0], "brand_tags": []},
	{"stat_key": "increased_ailment_damage_chill", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Chill damage", "applies_to": ["weapon", "armor"], "slots": [4, 2, 0], "brand_tags": []},
	{"stat_key": "increased_ailment_damage_electrocute", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Electrocute damage", "applies_to": ["weapon", "armor"], "slots": [4, 2, 0], "brand_tags": []},
	{"stat_key": "increased_ailment_damage_shock", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Shock damage", "applies_to": ["weapon", "armor"], "slots": [4, 2, 0], "brand_tags": []},
	{"stat_key": "increased_ailment_damage_aetherburn", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Aetherburn damage", "applies_to": ["weapon", "armor"], "slots": [4, 2, 0], "brand_tags": []},
	{"stat_key": "increased_ailment_damage_unraveling", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Unraveling damage", "applies_to": ["weapon", "armor"], "slots": [4, 2, 0], "brand_tags": []},
	{"stat_key": "increased_ailment_damage_pallid", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Pallid damage", "applies_to": ["weapon", "armor"], "slots": [4, 2, 0], "brand_tags": []},
	{"stat_key": "dot_multiplier", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% more Damage over Time (rare)", "applies_to": ["weapon"], "brand_tags": []},
	{"stat_key": "ailment_tick_rate", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% faster Ailment Tick Rate", "applies_to": ["weapon", "armor"], "slots": [4, 2], "brand_tags": []},
	{"stat_key": "increased_ailment_duration_bleed", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Bleed duration", "applies_to": ["weapon", "armor"], "slots": [4, 0, 9], "brand_tags": []},
	{"stat_key": "increased_ailment_duration_ignite", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Ignite duration", "applies_to": ["weapon", "armor"], "slots": [4, 0, 9], "brand_tags": []},
	{"stat_key": "increased_ailment_duration_chill", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Chill duration", "applies_to": ["weapon", "armor"], "slots": [4, 0, 9], "brand_tags": []},
	{"stat_key": "increased_ailment_duration_electrocute", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Electrocute duration", "applies_to": ["weapon", "armor"], "slots": [4, 0, 9], "brand_tags": []},
	{"stat_key": "increased_ailment_duration_shock", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Shock duration", "applies_to": ["weapon", "armor"], "slots": [4, 0, 9], "brand_tags": []},
	{"stat_key": "increased_ailment_duration_aetherburn", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Aetherburn duration", "applies_to": ["weapon", "armor"], "slots": [4, 0, 9], "brand_tags": []},
	{"stat_key": "increased_ailment_duration_unraveling", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Unraveling duration", "applies_to": ["weapon", "armor"], "slots": [4, 0, 9], "brand_tags": []},
	{"stat_key": "increased_ailment_duration_pallid", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Pallid duration", "applies_to": ["weapon", "armor"], "slots": [4, 0, 9], "brand_tags": []},
	{"stat_key": "ailment_ignore_chance", "tier1_min": 14.0, "tier1_max": 18.0, "desc": "+%d%% chance to ignore Ailments", "applies_to": ["armor"], "slots": [0, 1, 9], "brand_tags": []},

	# Patch v4.0 Physical Hit Build Mod Pool (increased_kinetic/piercing/
	# explosive_damage live in the Patch v3.9 weapon-specific .tres pool
	# instead, renamed to these exact stat_keys - see tools/
	# rename_v39_weapon_affixes.gd)
	{"stat_key": "increased_physical_damage", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Physical damage", "applies_to": ["weapon"], "brand_tags": ["kinetic", "piercing", "explosive"]},
	{"stat_key": "crit_chance_increased", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Critical Strike Chance", "applies_to": ["weapon"], "slots": [4, 11, 9], "brand_tags": []},
	{"stat_key": "crit_damage_increased", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Critical Strike Bonus", "applies_to": ["weapon"], "slots": [4, 9], "brand_tags": []},

	# Patch v4.0 Spell Hit Build Mod Pool - Conduits use weapon_kind, not
	# slots (a conduit can occupy PRIMARY_WEAPON or OFFHAND).
	{"stat_key": "increased_spell_damage", "tier1_min": 34.0, "tier1_max": 40.0, "desc": "+%d%% increased Spell damage", "applies_to": ["weapon", "armor"], "weapon_kind": "conduit", "slots": [0, 9], "brand_tags": ["fire", "cold", "lightning", "aetheric", "entropic", "pale"]},
	{"stat_key": "skill_effect_duration", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Skill Effect Duration", "applies_to": ["weapon", "armor"], "weapon_kind": "conduit", "slots": [0, 9], "brand_tags": []},
	{"stat_key": "mana_cost_reduction", "tier1_min": 12.0, "tier1_max": 16.0, "desc": "%d%% reduced Mana cost of skills", "applies_to": ["weapon", "item"], "weapon_kind": "conduit", "slots": [11, 10], "brand_tags": ["resource"]},
	{"stat_key": "cooldown_recovery_rate", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "+%d%% increased Cooldown Recovery Rate", "applies_to": ["weapon", "item"], "weapon_kind": "conduit", "slots": [10], "brand_tags": []},

	# Patch v4.0 Ranged Build Mod Pool
	{"stat_key": "increased_aoe_radius", "tier1_min": 34.0, "tier1_max": 40.0, "desc": "+%d%% increased Area of Effect", "applies_to": ["weapon", "armor"], "slots": [4, 2, 0], "brand_tags": []},
	{"stat_key": "increased_area_damage", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Area damage", "applies_to": ["weapon", "armor"], "slots": [4, 2, 0], "brand_tags": []},
	{"stat_key": "projectile_speed", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Projectile Speed", "applies_to": ["weapon"], "weapon_kind": "ranged", "brand_tags": ["movement"]},
	{"stat_key": "reduced_projectile_speed", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "%d%% reduced Projectile Speed", "applies_to": ["weapon"], "weapon_kind": "ranged", "brand_tags": []},

	# Patch v4.0 Parry/Riposte Build Mod Pool - Melee Weapons via
	# weapon_kind, Shields via the "shield" category (equip_slot OFFHAND
	# already covers Body Armour separately where listed).
	{"stat_key": "parry_window_duration", "tier1_min": 44.0, "tier1_max": 52.0, "desc": "+%d%% increased Parry Window Duration", "applies_to": ["weapon", "shield"], "weapon_kind": "melee", "brand_tags": []},
	{"stat_key": "ward_on_parry", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "+%d%% of max Ward restored on successful Parry", "applies_to": ["weapon", "shield", "armor"], "weapon_kind": "melee", "slots": [1], "brand_tags": ["ward"]},
	{"stat_key": "increased_riposte_damage", "tier1_min": 54.0, "tier1_max": 64.0, "desc": "+%d%% increased Riposte damage", "applies_to": ["weapon"], "weapon_kind": "melee", "brand_tags": []},
	{"stat_key": "riposte_crit_chance", "tier1_min": 44.0, "tier1_max": 52.0, "desc": "Riposte has +%d%% increased Critical Strike Chance", "applies_to": ["weapon", "shield"], "weapon_kind": "melee", "brand_tags": []},

	# Patch v4.0 Healing/Sustain Mod Pool (flat_ward already existed pre-v4.0)
	{"stat_key": "life_regen_flat", "tier1_min": 28.0, "tier1_max": 36.0, "desc": "Regenerate %d Life per second", "applies_to": ["armor", "item"], "slots": [0, 1, 2, 3, 9, 10], "brand_tags": []},
	{"stat_key": "life_regen_increased", "tier1_min": 44.0, "tier1_max": 52.0, "desc": "+%d%% increased Life Regeneration", "applies_to": ["armor", "item"], "slots": [0, 1, 2, 3, 9, 10], "brand_tags": []},
	{"stat_key": "flat_life", "tier1_min": 88.0, "tier1_max": 110.0, "desc": "+%d to Life", "applies_to": ["armor", "item"], "slots": [0, 1, 2, 3, 9, 10, 11], "brand_tags": []},
	{"stat_key": "life_increased", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "+%d%% increased Life", "applies_to": ["armor", "item"], "slots": [0, 1, 2, 3, 9, 10], "brand_tags": []},
	{"stat_key": "mana_regen_increased", "tier1_min": 44.0, "tier1_max": 52.0, "desc": "+%d%% increased Mana Regeneration", "applies_to": ["armor", "weapon", "item"], "weapon_kind": "conduit", "slots": [0, 1, 2, 3, 9], "brand_tags": ["resource"]},
	{"stat_key": "flat_mana", "tier1_min": 68.0, "tier1_max": 90.0, "desc": "+%d to Mana", "applies_to": ["armor", "weapon", "item"], "weapon_kind": "conduit", "slots": [0, 1, 2, 3, 9, 11], "brand_tags": ["resource"]},
	{"stat_key": "mana_increased", "tier1_min": 14.0, "tier1_max": 18.0, "desc": "+%d%% increased Mana", "applies_to": ["armor", "weapon", "item"], "weapon_kind": "conduit", "slots": [0, 1, 2, 3, 9], "brand_tags": ["resource"]},
	{"stat_key": "ward_recovery_increased", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Ward Recovery", "applies_to": ["armor", "item"], "slots": [0, 1, 2, 3, 9], "brand_tags": ["ward"]},

	# Patch v4.0 Offensive Mod Pool
	{"stat_key": "fire_penetration", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "+%d%% Fire Penetration", "applies_to": ["weapon", "item"], "slots": [4, 9], "brand_tags": ["fire"]},
	{"stat_key": "cold_penetration", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "+%d%% Cold Penetration", "applies_to": ["weapon", "item"], "slots": [4, 9], "brand_tags": ["cold"]},
	{"stat_key": "lightning_penetration", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "+%d%% Lightning Penetration", "applies_to": ["weapon", "item"], "slots": [4, 9], "brand_tags": ["lightning"]},
	{"stat_key": "elemental_penetration", "tier1_min": 12.0, "tier1_max": 16.0, "desc": "+%d%% Elemental Penetration", "applies_to": ["weapon", "item"], "slots": [4, 9], "brand_tags": ["fire", "cold", "lightning"]},
	{"stat_key": "physical_shred", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "+%d%% Physical Shred", "applies_to": ["weapon", "armor"], "slots": [4, 2], "brand_tags": ["kinetic", "piercing", "explosive"]},

	# Patch v4.0 Retaliation Mod Pool
	{"stat_key": "increased_retaliation_damage", "tier1_min": 54.0, "tier1_max": 64.0, "desc": "+%d%% increased Retaliation damage", "applies_to": ["weapon", "shield", "armor"], "slots": [1, 2], "brand_tags": []},
	# Patch v4.3: replaces the never-implemented "of Warding" (Block Threshold). Flat
	# points added to the shield's own block chance (see StatSheet.get_block_chance_bonus()).
	{"stat_key": "block_chance_bonus", "tier1_min": 8.0, "tier1_max": 10.0, "desc": "+%d%% increased Block Chance", "applies_to": ["shield"], "brand_tags": []},
	{"stat_key": "retaliate_on_block", "tier1_min": 1.0, "tier1_max": 1.0, "desc": "Triggers Retaliation on Block", "applies_to": ["shield"], "brand_tags": []},

	# Patch v4.0 Defensive Mod Pool
	{"stat_key": "reduced_physical_taken", "tier1_min": 9.0, "tier1_max": 11.0, "desc": "%d%% reduced Physical Damage taken", "applies_to": ["armor", "shield"], "slots": [1, 0], "brand_tags": []},
	{"stat_key": "reduced_elemental_taken", "tier1_min": 9.0, "tier1_max": 11.0, "desc": "%d%% reduced Elemental Damage taken", "applies_to": ["armor", "shield"], "slots": [1, 0], "brand_tags": []},
	{"stat_key": "reduced_esoteric_taken", "tier1_min": 9.0, "tier1_max": 11.0, "desc": "%d%% reduced Esoteric Damage taken", "applies_to": ["armor", "shield"], "slots": [1, 0], "brand_tags": []},
	{"stat_key": "ward_delay_reduction", "tier1_min": 0.8, "tier1_max": 1.2, "desc": "Faster Ward Delay by %.1f seconds", "applies_to": ["armor", "item"], "slots": [1, 0, 9], "brand_tags": ["ward"]},
	{"stat_key": "armor_to_elemental", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "%d%% of Armor applies to Elemental", "applies_to": ["armor", "item"], "slots": [1, 0, 9], "brand_tags": []},
	{"stat_key": "evasion_to_spells", "tier1_min": 14.0, "tier1_max": 18.0, "desc": "%d%% of Evasion applies to Spell Hits", "applies_to": ["armor", "item"], "slots": [1, 3, 9], "brand_tags": ["evasion"]},
	{"stat_key": "dash_speed", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Dash Speed", "applies_to": ["armor"], "slots": [3, 2, 10], "brand_tags": ["movement"]},
	{"stat_key": "damage_from_mana", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "%d%% of Damage taken from Mana before Life", "applies_to": ["armor", "item"], "slots": [1, 0, 9], "brand_tags": ["resource"]},
	{"stat_key": "all_elemental_resistance", "tier1_min": 12.0, "tier1_max": 16.0, "desc": "+%d%% to all Elemental Resistances", "applies_to": ["armor", "shield", "item"], "brand_tags": ["fire", "cold", "lightning"]},
	{"stat_key": "esoteric_resistance", "tier1_min": 22.0, "tier1_max": 28.0, "desc": "+%d%% to Esoteric Resistance", "applies_to": ["armor", "shield", "item"], "brand_tags": ["resistance", "aetheric", "entropic", "pale"]},
	{"stat_key": "fire_resistance", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% to Fire Resistance", "applies_to": ["armor", "shield", "item"], "brand_tags": ["resistance", "fire"]},
	{"stat_key": "cold_resistance", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% to Cold Resistance", "applies_to": ["armor", "shield", "item"], "brand_tags": ["resistance", "cold"]},
	{"stat_key": "lightning_resistance", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% to Lightning Resistance", "applies_to": ["armor", "shield", "item"], "brand_tags": ["resistance", "lightning"]},
	{"stat_key": "phys_as_fire", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "%d%% Physical Damage taken as Fire", "applies_to": ["armor", "item"], "slots": [0, 1, 9], "brand_tags": []},
	{"stat_key": "phys_as_cold", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "%d%% Physical Damage taken as Cold", "applies_to": ["armor", "item"], "slots": [0, 1, 9], "brand_tags": []},
	{"stat_key": "phys_as_lightning", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "%d%% Physical Damage taken as Lightning", "applies_to": ["armor", "item"], "slots": [0, 1, 9], "brand_tags": []},

	# Patch v4.0 Armor Base Specific Mods (flat_ward/flat_armor/flat_evasion
	# pre-existing, "Varies by type" per the doc - no new T1 given for those)
	{"stat_key": "increased_ward", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Ward", "applies_to": ["armor"], "brand_tags": ["ward"]},
	{"stat_key": "increased_armor", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Armor", "applies_to": ["armor", "shield"], "brand_tags": ["armor"]},
	{"stat_key": "increased_evasion", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Evasion", "applies_to": ["armor"], "brand_tags": ["evasion"]},
	{"stat_key": "hybrid_defense_life", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d to primary defense and Life (hybrid)", "applies_to": ["armor"], "brand_tags": []},

	# Patch v4.0 Amulet Exclusive Mod Pool - Prefix, +1-2 at T1 (item level
	# 80+), lower tiers +1 only. "Among the rarest amulet rolls" - kept at
	# the doc's own tight T1 range rather than this pool's usual wider spreads.
	{"stat_key": "flat_aether", "tier1_min": 40.0, "tier1_max": 55.0, "desc": "+%d to Aether capacity", "applies_to": ["item"], "slots": [9], "brand_tags": []},
	{"stat_key": "skill_level_all", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all active Skills", "applies_to": ["item"], "slots": [9], "brand_tags": []},
	{"stat_key": "skill_level_spells", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Spells", "applies_to": ["item"], "slots": [9], "brand_tags": []},
	{"stat_key": "skill_level_kinetic", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Kinetic Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["kinetic"]},
	{"stat_key": "skill_level_spell_kinetic", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Kinetic Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["kinetic"]},
	{"stat_key": "skill_level_piercing", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Piercing Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["piercing"]},
	{"stat_key": "skill_level_spell_piercing", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Piercing Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["piercing"]},
	{"stat_key": "skill_level_explosive", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Explosive Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["explosive"]},
	{"stat_key": "skill_level_spell_explosive", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Explosive Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["explosive"]},
	{"stat_key": "skill_level_fire", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Fire Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["fire"]},
	{"stat_key": "skill_level_spell_fire", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Fire Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["fire"]},
	{"stat_key": "skill_level_cold", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Cold Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["cold"]},
	{"stat_key": "skill_level_spell_cold", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Cold Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["cold"]},
	{"stat_key": "skill_level_lightning", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Lightning Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["lightning"]},
	{"stat_key": "skill_level_spell_lightning", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Lightning Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["lightning"]},
	{"stat_key": "skill_level_aetheric", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Aetheric Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["aetheric"]},
	{"stat_key": "skill_level_spell_aetheric", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Aetheric Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["aetheric"]},
	{"stat_key": "skill_level_entropic", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Entropic Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["entropic"]},
	{"stat_key": "skill_level_spell_entropic", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Entropic Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["entropic"]},
	{"stat_key": "skill_level_pale", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Pale Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["pale"]},
	{"stat_key": "skill_level_spell_pale", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Pale Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["pale"]},
]

## power_level: the active Map's tier, or player level as a fallback in
## the Hub - a rough "how strong should this roll be" signal.
## loot_rarity_multiplier: shifts the rarity roll upward.
static func roll(power_level: int = 1, loot_rarity_multiplier: float = 1.0) -> Item:
	var base := _pick_base_item(power_level)
	if base == null:
		return null
	var item: Item = base.duplicate(true)
	item.item_id = "%s_rolled_%d" % [base.item_id, randi()]

	# Patch v3.7 Section 5: roll a real value within the base's own damage/
	# spell power range, same "the base is a range, the drop is a point
	# within it" pattern affix values already use.
	if item is Weapon:
		var weapon := item as Weapon
		weapon.rolled_base_damage = randf_range(weapon.base_damage_min, weapon.base_damage_max)
		if weapon.is_conduit:
			weapon.rolled_spell_power = randf_range(weapon.spell_power_min, weapon.spell_power_max)

	# Patch v3.8 Section 3: how many of the base's own max_sockets this
	# specific drop actually has - 0 to max_sockets inclusive, same "the
	# base sets a ceiling, the roll picks a point under it" shape as
	# affix tiers. max_sockets itself is untouched (still the item type's
	# overall cap, raised by Bore/Corruption exactly as before).
	# Patch v4.3: never past the item category's ceiling, whatever an old
	# base .tres or a saved copy says.
	item.max_sockets = mini(item.max_sockets, get_socket_cap(item))
	item.sockets = randi() % (item.max_sockets + 1)

	var rarity_roll := randf() * loot_rarity_multiplier
	var affix_count := 0
	# v4.7: an Uncommon/Rare roll always gets at least one affix (it used to
	# roll 0, e.g. a mod-less "magic" Crude Machine Gun).
	if rarity_roll >= 1.4:
		item.rarity = Constants.ItemRarity.RARE
		affix_count = randi_range(1, 6)
	elif rarity_roll >= 0.9:
		item.rarity = Constants.ItemRarity.UNCOMMON
		affix_count = randi_range(1, 2)
	else:
		item.rarity = Constants.ItemRarity.COMMON

	# A rolled item's affix list is fully re-rolled, not additive on top
	# of the base's own hand-authored implicit(s).
	item.affixes = []
	if item is Weapon:
		_roll_weapon_affixes(item as Weapon, affix_count, power_level)
	else:
		var pool := _pool_for(item)
		pool.shuffle()
		for i in range(min(affix_count, pool.size())):
			var entry: Dictionary = pool[i]
			var rolled_tier := _roll_tier(power_level)
			var value_range := _tier_range(entry["tier1_min"], entry["tier1_max"], rolled_tier)
			var value: float = randf_range(value_range.x, value_range.y)
			var affix := ItemAffix.new()
			affix.stat_key = entry["stat_key"]
			affix.value = value
			affix.value_min = value_range.x
			affix.value_max = value_range.y
			affix.tier = rolled_tier
			affix.description = "%s (Tier %d)" % [format_desc(entry["desc"], value), rolled_tier]
			affix.is_prefix = i % 2 == 0
			item.affixes.append(affix)

	# An empty eligible pool (low power_level, narrow base) can still leave
	# nothing rolled - such an item is Common, not a mod-less Uncommon/Rare.
	if not item.affixes.any(func(a: ItemAffix): return not a.is_implicit):
		item.rarity = Constants.ItemRarity.COMMON

	return item

## Tier N's range = Tier 1's range scaled by TIER_DECAY^(N-1).
static func _tier_range(tier1_min: float, tier1_max: float, tier: int) -> Vector2:
	var scale: float = pow(TIER_DECAY, tier - 1)
	return Vector2(tier1_min * scale, tier1_max * scale)

## Invented - the doc never defines what gates tier access. The best
## tier reachable improves by one per power_level point; the actual roll
## is uniform between that and the worst tier.
static func _roll_tier(power_level: int) -> int:
	var best_reachable: int = clamp(TIER_COUNT - power_level, 1, TIER_COUNT)
	return randi_range(best_reachable, TIER_COUNT)

## Patch v3.9 Weapon Affix Library - data/affixes/weapons/<type>/*.tres,
## loaded once and cached (~96 files, same one-time-scan reasoning as
## _candidate_meta_cache below). Each is Tier-1-only data (see tools/
## generate_weapon_affixes.gd's own header for why) - scaled the exact
## same way every OTHER AFFIX_POOL entry already is, via _tier_range()/
## _roll_tier() below, rather than a bespoke per-affix tier table.
const WEAPON_AFFIX_DIR := "res://data/affixes/weapons/"
static var _weapon_affix_cache: Array[ItemAffix] = []

static func _build_weapon_affix_cache() -> void:
	var root := DirAccess.open(WEAPON_AFFIX_DIR)
	if root == null:
		return
	root.list_dir_begin()
	var subdir := root.get_next()
	while subdir != "":
		if root.current_is_dir():
			var dir := DirAccess.open(WEAPON_AFFIX_DIR + subdir + "/")
			if dir:
				dir.list_dir_begin()
				var file_name := dir.get_next()
				while file_name != "":
					if file_name.ends_with(".tres"):
						var affix: ItemAffix = load(WEAPON_AFFIX_DIR + subdir + "/" + file_name)
						if affix:
							_weapon_affix_cache.append(affix)
					file_name = dir.get_next()
				dir.list_dir_end()
		subdir = root.get_next()
	root.list_dir_end()

## Same base_line_id (stripped of "_lineN") -> weapon_type -> item_id-
## substring fallback chain tools/repair_item_requirements.gd already
## established for resolving a weapon's real type key.
static func _weapon_type_key(weapon: Weapon) -> String:
	if weapon.base_line_id != "":
		var underscore := weapon.base_line_id.rfind("_line")
		return weapon.base_line_id.substr(0, underscore) if underscore != -1 else weapon.base_line_id
	if weapon.weapon_type != "":
		return weapon.weapon_type.to_lower().replace(" ", "_")
	return ""

## Eligible = generic, OR matches the weapon's own (infused-aware) damage
## type, OR is a base-type exclusive whose weapon_type_filter contains
## this weapon's resolved type key - AND available at this power_level
## (brief's own algorithm: "available at item level").
static func _eligible_weapon_affixes(weapon: Weapon, power_level: int, want_prefix: bool) -> Array[ItemAffix]:
	if _weapon_affix_cache.is_empty():
		_build_weapon_affix_cache()
	var dtype: Constants.DamageType = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
	var type_key := _weapon_type_key(weapon)
	var result: Array[ItemAffix] = []
	for affix in _weapon_affix_cache:
		if affix.is_prefix != want_prefix:
			continue
		if power_level < affix.min_item_level:
			continue
		var matches := affix.is_generic
		if not matches and affix.weapon_type_filter.is_empty():
			matches = affix.damage_type == dtype
		elif not matches:
			matches = affix.weapon_type_filter.has(type_key)
		if matches:
			result.append(affix)
	return result

## Splits the rarity roll's flat affix_count into a prefix pool (max 3)
## and a suffix pool (max 3, Section 18's own Rare "0-6" ceiling, "0-3
## prefixes, 0-3 suffixes" per the brief) - alternating so an uneven count
## favors prefixes first, then falls back to whichever pool still has
## eligible, unused entries if the other runs dry.
static func _roll_weapon_affixes(weapon: Weapon, affix_count: int, power_level: int) -> void:
	var prefix_pool := _eligible_weapon_affixes(weapon, power_level, true)
	var suffix_pool := _eligible_weapon_affixes(weapon, power_level, false)
	prefix_pool.shuffle()
	suffix_pool.shuffle()

	var prefix_target: int = min(3, ceili(affix_count / 2.0))
	var suffix_target: int = min(3, affix_count - prefix_target)
	var picked: Array[ItemAffix] = []
	picked.append_array(prefix_pool.slice(0, min(prefix_target, prefix_pool.size())))
	picked.append_array(suffix_pool.slice(0, min(suffix_target, suffix_pool.size())))
	# Fill any remaining budget (a pool ran dry) from whichever pool still
	# has unused entries, still respecting the 3-per-side cap.
	var picked_prefix_count := picked.filter(func(a: ItemAffix): return a.is_prefix).size()
	var picked_suffix_count := picked.size() - picked_prefix_count
	for extra in prefix_pool.slice(picked_prefix_count):
		if picked.size() >= affix_count or picked_prefix_count >= 3:
			break
		picked.append(extra)
		picked_prefix_count += 1
	for extra in suffix_pool.slice(picked_suffix_count):
		if picked.size() >= affix_count or picked_suffix_count >= 3:
			break
		picked.append(extra)
		picked_suffix_count += 1

	for source in picked:
		var rolled_tier := _roll_tier(power_level)
		var value_range := _tier_range(source.value_min, source.value_max, rolled_tier)
		var value: float = randf_range(value_range.x, value_range.y)
		var affix := ItemAffix.new()
		affix.affix_id = source.affix_id
		affix.stat_key = source.stat_key
		affix.display_name = source.display_name
		affix.value = value
		affix.value_min = value_range.x
		affix.value_max = value_range.y
		affix.tier = rolled_tier
		affix.is_prefix = source.is_prefix
		affix.damage_type = source.damage_type
		affix.is_generic = source.is_generic
		# Bug fix (2026-09-07, user-reported): source.description is a
		# template (one %d or %.1f placeholder) - the rolled value must be
		# substituted in, same as the OLD AFFIX_POOL's own "desc" dict
		# entries already do, or the card only ever shows "(Tier N)" with
		# no actual number.
		var formatted: String = source.description % value if source.description.contains("%.1f") else source.description % round(value)
		affix.description = "%s (Tier %d)" % [formatted, rolled_tier]
		weapon.affixes.append(affix)

## path -> {"item_level": int, "base_line_id": String} for every base item
## file across BASE_ITEM_DIRS - built once (loading ~750 generated .tres
## just to read 2 fields off each, every single kill, would be a real
## per-roll hitch) and reused for the process's whole lifetime; base items
## are static content, never added/removed/edited at runtime.
static var _candidate_meta_cache: Dictionary = {}

static func _pick_base_item(target_item_level: int) -> Item:
	if _candidate_meta_cache.is_empty():
		_build_candidate_meta_cache()
	if _candidate_meta_cache.is_empty():
		return null

	# Group tiered-line candidates (base_line_id != "") down to just the
	# single highest-item_level tier still <= target_item_level per line -
	# "always drop the current-tier base this level has unlocked," the
	# same ilvl-gated-base principle PoE-style tiered bases follow.
	# Standalone hand-authored items (base_line_id == "", every pre-
	# Section-25 base) are never grouped - always their own candidate,
	# gated only by their own item_level (1 by default, i.e. always in).
	var best_per_line: Dictionary = {}  # base_line_id -> {"path": String, "item_level": int}
	var pool: Array[String] = []
	for path in _candidate_meta_cache:
		var meta: Dictionary = _candidate_meta_cache[path]
		var item_level: int = meta["item_level"]
		if item_level > target_item_level:
			continue
		var line_id: String = meta["base_line_id"]
		if line_id == "":
			pool.append(path)
			continue
		var current: Dictionary = best_per_line.get(line_id, {})
		if current.is_empty() or item_level > int(current["item_level"]):
			best_per_line[line_id] = {"path": path, "item_level": item_level}
	for entry in best_per_line.values():
		pool.append(entry["path"])
	if pool.is_empty():
		return null
	return load(pool[randi() % pool.size()]) as Item

static func _build_candidate_meta_cache() -> void:
	for dir_path in BASE_ITEM_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				var path: String = dir_path + file_name
				var item := load(path) as Item
				if item and not _is_excluded_line(item.base_line_id):
					_candidate_meta_cache[path] = {"item_level": item.item_level, "base_line_id": item.base_line_id}
			file_name = dir.get_next()
		dir.list_dir_end()

## Patch v4.0: "slots" (optional, Array[Constants.EquipmentSlot]) and
## "weapon_kind" (optional, "melee"/"ranged"/"conduit") narrow eligibility
## further than the old applies_to category alone - _pool_for() itself
## still gates by applies_to first, unchanged, since several v4.0 mods
## span multiple categories at once (e.g. "All armor" = every Armor slot,
## no slots restriction needed; "Body Armour, Helmet, Shield" = armor +
## shield categories, narrowed further by slots for the armor half only).
static func _pool_for(item: Item) -> Array:
	var category := _category_of(item)
	var result := []
	for entry in AFFIX_POOL:
		var applies: Array = entry["applies_to"]
		if not (applies.is_empty() or applies.has(category)):
			continue
		var slots: Array = entry.get("slots", [])
		if not slots.is_empty() and not slots.has(item.equip_slot):
			continue
		var weapon_kind: String = entry.get("weapon_kind", "")
		if weapon_kind != "" and item is Weapon:
			var weapon := item as Weapon
			var kind_ok := false
			match weapon_kind:
				"melee": kind_ok = not weapon.is_ranged and not weapon.is_conduit
				"ranged": kind_ok = weapon.is_ranged
				"conduit": kind_ok = weapon.is_conduit
			if not kind_ok:
				continue
		result.append(entry)
	return result

## Used by CraftingSystem.gd (Section 20's Cube) - same item-type
## filtering as _pool_for(), further narrowed to entries whose brand_tags
## include the Brand.category_tag driving the craft.
static func _pool_for_brand_tag(item: Item, tag: String) -> Array:
	var result := []
	for entry in _pool_for(item):
		var tags: Array = entry["brand_tags"]
		if tags.has(tag):
			result.append(entry)
	return result

static func _category_of(item: Item) -> String:
	if item is Weapon:
		return "weapon"
	if item is Armor:
		return "armor"
	if item is Shield:
		return "shield"
	return "item"
