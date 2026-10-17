extends RefCounted
class_name ItemRoller
## Rolls a random piece of gear on demand - dropped by Enemy.gd on death,
## picked up via LootPickup.gd, or stocked by the Hub's GearShop. Picks a
## real, balanced base item (weapon_type/damage_type/etc.)
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
## for how a kill's own power_level is derived from Area Level + rarity.
##
## Rarity -> affix count (Common 0, Uncommon 1-2, Rare RARE_AFFIX_COUNT).
## Rarity is a weighted roll (Loot.roll_rarity()), not set by affix count. Affix
## values roll in tiers (TIER_COUNT bands, Tier 1 best) gated by
## `power_level`. flat_<stat> affixes are the only source of stat growth
## in this project (Section 12: gear only) - summed into StatSheet by
## EquipmentComponent.compute_stat_bonuses().
##
## loot_rarity_multiplier is the kill's total Item Rarity (Loot.multipliers():
## gear, Figment and enemy affixes). Item Quantity sets how many drop rolls
## a kill gets instead (Enemy._maybe_drop_loot()).

const BASE_ITEM_DIRS := [
	"res://data/weapons/instances/",
	"res://data/armor/instances/",
	"res://data/shields/instances/",
	"res://data/items/instances/",
]

## Base lines that are throwables, not gear (Patch v4.3): their old .tres
## bases sit in data/items/instances/ and were being rolled as rings with
## garbled stats. Matched as substrings of Item.base_line_id ("grenade"
## also covers "infusion_grenade"; "throwing_kni" covers the knife lines).
## Excluded from loot/shop rolls only - the files stay, for a future
## throwable consumable system.
const EXCLUDED_ITEM_TYPES := ["throwing_kni", "impact_hatchet", "pressure_javelin", "grenade", "infusion_grenade"]

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
			if weapon.is_offhand:
				return "conduit_offhand"
			return "conduit_two_handed" if weapon.is_two_handed else "conduit_main_hand"
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

## 6 tiers per affix, Tier 1 best - the doc's own tier counts vary per
## mod (5 to 11+); this project picks one consistent count for every affix.
## v4.83 added today's Tier 1 above the old five (TIER_LADDER_VERSION).
const TIER_COUNT := 6
## Saves from before the new top tier store every gear tier one lower.
const TIER_LADDER_VERSION := 2
## Each tier's range is TIER_DECAY of the tier above's - an invented
## approximation of the doc's tables' shape.
const TIER_DECAY := 0.8

## tier1_min/tier1_max define one range (Tier 2 since v4.83) - other tiers
## are derived via _tier_range(). "applies_to": [] means any base item
## type; otherwise a list of category strings (see _pool_for()).
##
## "slots" (EquipmentSlot) narrow armour, shields and accessories; weapons
## ignore them. Slot roles (v4.55): Gloves offence (hits, ailments, speed,
## crit, Riposte); Rings offence (crit, damage %, Penetration) with
## resistances, Life and flat defences as filler; Amulet build-defining
## (skill levels, damage, Aether); Helmet caster and utility; Body and Shield
## the major defences (Shield also block and parry); Boots mobility and
## defence; Belt sustain and resources. Attributes, Resilience, Life and
## resistances roll everywhere as filler.
##
## "brand_tags": the category tags this entry carries. GearModifierPool turns
## them into ModifierDef tags (what Rev2 Category Brands filter on), and
## Shard of Tharsis outcomes use _pool_for_brand_tag().
const AFFIX_POOL := [
	# Patch v3.8: six stats collapsed to three (renamed in v4.8).
	{"stat_key": "flat_strength", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Strength", "applies_to": [], "brand_tags": ["kinetic", "piercing", "explosive"]},
	{"stat_key": "flat_agility", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Agility", "applies_to": [], "brand_tags": ["movement", "evasion"]},
	{"stat_key": "flat_intellect", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Intellect", "applies_to": [], "brand_tags": ["fire", "cold", "lightning", "aetheric", "entropic", "pale"]},
	# physical_dmg_increased removed (Patch v4.0) - superseded by the new
	# "increased_physical_damage" entry below, doc-exact value (28-34%,
	# was this entry's own invented 16-20%).
	{"stat_key": "elemental_dmg_increased", "tier1_min": 24.0, "tier1_max": 30.0, "desc": "+%d%% increased Elemental damage", "applies_to": ["weapon", "item"], "slots": [9, 11], "brand_tags": ["fire", "cold", "lightning"]},
	{"stat_key": "esoteric_dmg_increased", "tier1_min": 24.0, "tier1_max": 30.0, "desc": "+%d%% increased Esoteric damage", "applies_to": ["weapon", "item"], "slots": [9, 11], "brand_tags": ["aetheric", "entropic", "pale"]},
	{"stat_key": "flat_armor", "defense": "armor", "tier1_min": 75.0, "tier1_max": 85.0, "desc": "+%d Armor", "applies_to": ["armor", "shield", "item"], "slots": [0, 1, 2, 3, 6, 11], "brand_tags": ["armor"]},
	{"stat_key": "flat_ward", "defense": "ward", "tier1_min": 45.0, "tier1_max": 52.0, "desc": "+%d Ward", "applies_to": ["armor", "shield", "item"], "slots": [0, 1, 2, 3, 6, 11], "brand_tags": ["ward"]},
	{"stat_key": "flat_evasion", "defense": "evasion", "tier1_min": 112.0, "tier1_max": 128.0, "desc": "+%d Evasion", "applies_to": ["armor", "shield", "item"], "slots": [0, 1, 2, 3, 6, 11], "brand_tags": ["evasion"]},
	{"stat_key": "flat_resilience", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d Resilience", "applies_to": [], "brand_tags": ["resilience"]},
	{"stat_key": "skill_cooldown_reduced", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "+%d%% reduced skill cooldowns", "applies_to": ["armor"], "slots": [0], "brand_tags": ["skills"], "no_roll": true},
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
	{"stat_key": "mana_regen", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%.1f Mana Regeneration per second", "applies_to": ["armor", "item"], "slots": [0, 9, 10], "brand_tags": ["resource"]},
	{"stat_key": "attack_speed", "tier1_min": 10.0, "tier1_max": 14.0, "desc": "+%d%% increased Attack Speed", "applies_to": ["weapon", "armor", "item"], "slots": [2, 11], "brand_tags": ["skills"]},
	{"stat_key": "reload_speed", "tier1_min": 53.0, "tier1_max": 61.0, "desc": "+%d%% increased Reload Speed", "applies_to": ["armor"], "slots": [2], "brand_tags": ["skills"]},
	{"stat_key": "cast_speed", "tier1_min": 10.0, "tier1_max": 14.0, "desc": "+%d%% increased Cast Speed", "applies_to": ["armor", "item"], "slots": [2, 9, 11], "brand_tags": ["skills"]},
	{"stat_key": "move_speed", "tier1_min": 4.0, "tier1_max": 8.0, "desc": "+%d%% increased Move Speed", "applies_to": ["armor"], "slots": [3], "brand_tags": ["movement"]},
	{"stat_key": "debuff_effectiveness", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "+%d%% Debuff Effectiveness", "applies_to": ["armor", "item"], "slots": [0, 9], "brand_tags": ["skills"], "no_roll": true},
	# Stamina no longer rolls; kept so items that already have it still read.
	{"stat_key": "stamina", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Stamina", "applies_to": ["armor", "item"], "slots": [1, 3, 10], "brand_tags": [], "no_roll": true},
	# Loot: Item Rarity on helmets, boots and jewellery, Quantity on accessories.
	# Magic Find (0.5% Quantity + 2% Rarity per point, Loot.gd) no longer rolls.
	{"stat_key": "item_rarity", "tier1_min": 14.0, "tier1_max": 20.0, "desc": "%d%% increased Item Rarity", "applies_to": ["armor", "item"], "slots": [0, 3, 9, 11], "brand_tags": []},
	{"stat_key": "item_quantity", "tier1_min": 4.0, "tier1_max": 6.0, "desc": "%d%% increased Item Quantity", "applies_to": ["item"], "slots": [9, 10, 11], "brand_tags": []},
	{"stat_key": "magic_find", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "+%d Magic Find", "applies_to": ["armor", "item"], "slots": [0, 1, 2, 3, 9, 10, 11], "brand_tags": [], "no_roll": true},

	# Patch v4.0 Ailment Build Mod Pool. Since v5.5 chance and duration roll by
	# family (below); the per-ailment lines no longer roll.
	{"stat_key": "ailment_chance_bleed", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Bleed", "applies_to": ["weapon", "armor"], "slots": [2], "brand_tags": [], "no_roll": true},
	{"stat_key": "ailment_chance_ignite", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Ignite", "applies_to": ["weapon", "armor"], "slots": [2], "brand_tags": [], "no_roll": true},
	{"stat_key": "ailment_chance_chill", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Chill", "applies_to": ["weapon", "armor"], "slots": [2], "brand_tags": [], "no_roll": true},
	{"stat_key": "ailment_chance_electrocute", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Electrocute", "applies_to": ["weapon", "armor"], "slots": [2], "brand_tags": [], "no_roll": true},
	{"stat_key": "ailment_chance_shock", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Shock", "applies_to": ["weapon", "armor"], "slots": [2], "brand_tags": [], "no_roll": true},
	{"stat_key": "ailment_chance_aetherburn", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Aetherburn", "applies_to": ["weapon", "armor"], "slots": [2], "brand_tags": [], "no_roll": true},
	{"stat_key": "ailment_chance_unraveling", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Unraveling", "applies_to": ["weapon", "armor"], "slots": [2], "brand_tags": [], "no_roll": true},
	{"stat_key": "ailment_chance_pallid", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% chance to cause Pallid", "applies_to": ["weapon", "armor"], "slots": [2], "brand_tags": [], "no_roll": true},
	# Chill, Electrocute, Shock, Unraveling and Pallid deal no damage, so their
	# damage lines no longer roll (kept so existing items still read).
	{"stat_key": "increased_ailment_damage_bleed", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Bleed damage", "applies_to": ["weapon", "armor"], "slots": [0, 2], "brand_tags": []},
	{"stat_key": "increased_ailment_damage_ignite", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Ignite damage", "applies_to": ["weapon", "armor"], "slots": [0, 2], "brand_tags": []},
	{"stat_key": "increased_ailment_damage_chill", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Chill damage", "applies_to": ["weapon", "armor"], "slots": [0, 2], "brand_tags": [], "no_roll": true},
	{"stat_key": "increased_ailment_damage_electrocute", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Electrocute damage", "applies_to": ["weapon", "armor"], "slots": [0, 2], "brand_tags": [], "no_roll": true},
	{"stat_key": "increased_ailment_damage_shock", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Shock damage", "applies_to": ["weapon", "armor"], "slots": [0, 2], "brand_tags": [], "no_roll": true},
	{"stat_key": "increased_ailment_damage_aetherburn", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Aetherburn damage", "applies_to": ["weapon", "armor"], "slots": [0, 2], "brand_tags": []},
	{"stat_key": "increased_ailment_damage_unraveling", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Unraveling damage", "applies_to": ["weapon", "armor"], "slots": [0, 2], "brand_tags": [], "no_roll": true},
	{"stat_key": "increased_ailment_damage_pallid", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Pallid damage", "applies_to": ["weapon", "armor"], "slots": [0, 2], "brand_tags": [], "no_roll": true},
	{"stat_key": "dot_multiplier", "tier1_min": 28.0, "tier1_max": 33.0, "desc": "+%d%% to Damage over Time Multiplier", "applies_to": ["weapon", "item"], "slots": [9], "brand_tags": []},
	{"stat_key": "ailment_tick_rate", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "Damaging Ailments deal their damage %d%% faster", "applies_to": ["weapon", "armor"], "slots": [2], "brand_tags": []},
	{"stat_key": "increased_ailment_duration_bleed", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Bleed duration", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9], "brand_tags": [], "no_roll": true},
	{"stat_key": "increased_ailment_duration_ignite", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Ignite duration", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9], "brand_tags": [], "no_roll": true},
	{"stat_key": "increased_ailment_duration_chill", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Chill duration", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9], "brand_tags": [], "no_roll": true},
	{"stat_key": "increased_ailment_duration_electrocute", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Electrocute duration", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9], "brand_tags": [], "no_roll": true},
	{"stat_key": "increased_ailment_duration_shock", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Shock duration", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9], "brand_tags": [], "no_roll": true},
	{"stat_key": "increased_ailment_duration_aetherburn", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Aetherburn duration", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9], "brand_tags": [], "no_roll": true},
	{"stat_key": "increased_ailment_duration_unraveling", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Unraveling duration", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9], "brand_tags": [], "no_roll": true},
	{"stat_key": "increased_ailment_duration_pallid", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Pallid duration", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9], "brand_tags": [], "no_roll": true},
	# v5.5: ailment chance, duration and effect by family, not per ailment.
	{"stat_key": "damaging_ailment_chance", "tier1_min": 20.0, "tier1_max": 26.0, "desc": "+%d%% chance to inflict Bleed, Ignite and Aetherburn", "applies_to": ["armor"], "slots": [2], "brand_tags": []},
	{"stat_key": "control_ailment_chance", "tier1_min": 20.0, "tier1_max": 26.0, "desc": "+%d%% chance to inflict Chill, Shock, Electrocute, Unraveling and Pallid", "applies_to": ["armor"], "slots": [2], "brand_tags": []},
	{"stat_key": "ailment_duration", "tier1_min": 20.0, "tier1_max": 26.0, "desc": "+%d%% increased Ailment duration", "applies_to": ["armor", "item"], "slots": [0, 9], "brand_tags": []},
	{"stat_key": "control_ailment_effect", "tier1_min": 20.0, "tier1_max": 26.0, "desc": "+%d%% increased effect of Chill, Shock, Electrocute, Unraveling and Pallid", "applies_to": ["armor"], "slots": [0, 2], "brand_tags": []},
	# Sustain on kill and on ailments (were weapon suffixes).
	{"stat_key": "mana_on_kill", "tier1_min": 12.0, "tier1_max": 16.0, "desc": "Gain %d Mana on kill", "applies_to": ["armor", "item"], "slots": [2, 11], "brand_tags": ["resource"]},
	{"stat_key": "ward_percent_on_kill", "tier1_min": 3.0, "tier1_max": 5.0, "desc": "%d%% of maximum Ward restored on kill", "applies_to": ["armor", "item"], "slots": [2, 11], "brand_tags": ["ward"]},
	{"stat_key": "mana_on_ailment", "tier1_min": 4.0, "tier1_max": 6.0, "desc": "Gain %d Mana when you inflict an Ailment", "applies_to": ["armor", "item"], "slots": [2, 11], "brand_tags": ["resource"]},
	{"stat_key": "ward_percent_on_ailment", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "%.1f%% of maximum Ward restored when you inflict an Ailment", "applies_to": ["armor", "item"], "slots": [2, 11], "brand_tags": ["ward"]},
	{"stat_key": "ailment_ignore_chance", "tier1_min": 14.0, "tier1_max": 18.0, "desc": "+%d%% chance to ignore Ailments", "applies_to": ["armor", "shield", "item"], "slots": [1, 6, 10], "brand_tags": []},

	# Patch v4.0 Physical Hit Build Mod Pool (increased_kinetic/piercing/
	# explosive_damage live in the Patch v3.9 weapon-specific .tres pool
	# instead, renamed to these exact stat_keys - see tools/
	# rename_v39_weapon_affixes.gd)
	{"stat_key": "increased_physical_damage", "tier1_min": 24.0, "tier1_max": 30.0, "desc": "+%d%% increased Physical damage", "applies_to": ["weapon", "item"], "slots": [9, 11], "brand_tags": ["kinetic", "piercing", "explosive"]},
	{"stat_key": "crit_chance_increased", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Critical Strike Chance", "applies_to": ["weapon", "armor", "item"], "slots": [2, 9, 11], "brand_tags": []},
	{"stat_key": "crit_damage_increased", "tier1_min": 38.0, "tier1_max": 44.0, "desc": "+%d%% increased Critical Strike Bonus", "applies_to": ["weapon", "item"], "slots": [9, 11], "brand_tags": []},

	# Patch v4.0 Spell Hit Build Mod Pool - Conduits use weapon_kind, not
	# slots (a conduit can occupy PRIMARY_WEAPON or OFFHAND).
	{"stat_key": "increased_spell_damage", "tier1_min": 24.0, "tier1_max": 30.0, "desc": "+%d%% increased Spell damage", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9, 11], "weapon_kind": "conduit", "brand_tags": ["fire", "cold", "lightning", "aetheric", "entropic", "pale"]},
	# Minions (Wraith).
	{"stat_key": "minion_damage", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Minion damage", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9, 11], "weapon_kind": "conduit", "brand_tags": ["minion"]},
	{"stat_key": "minion_attack_speed", "tier1_min": 12.0, "tier1_max": 16.0, "desc": "+%d%% increased Minion Attack Speed", "applies_to": ["armor", "item"], "slots": [2, 9], "brand_tags": ["minion"]},
	{"stat_key": "minion_duration", "tier1_min": 20.0, "tier1_max": 26.0, "desc": "+%d%% increased Minion Duration", "applies_to": ["armor", "item"], "slots": [1, 9], "brand_tags": ["minion"]},
	{"stat_key": "skill_effect_duration", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Skill Effect Duration", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9], "weapon_kind": "conduit", "brand_tags": []},
	{"stat_key": "mana_cost_reduction", "tier1_min": 12.0, "tier1_max": 16.0, "desc": "%d%% reduced Mana cost of skills", "applies_to": ["weapon", "armor", "item"], "slots": [0, 10], "weapon_kind": "conduit", "brand_tags": ["resource"]},
	{"stat_key": "cooldown_recovery_rate", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "+%d%% increased Cooldown Recovery Rate", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9], "weapon_kind": "conduit", "brand_tags": []},

	# Patch v4.0 Ranged Build Mod Pool
	{"stat_key": "increased_aoe_radius", "tier1_min": 34.0, "tier1_max": 40.0, "desc": "+%d%% increased Area of Effect", "applies_to": ["weapon", "armor"], "slots": [0, 2], "brand_tags": []},
	{"stat_key": "increased_area_damage", "tier1_min": 24.0, "tier1_max": 30.0, "desc": "+%d%% increased Area damage", "applies_to": ["weapon", "armor"], "slots": [0, 2], "brand_tags": []},
	{"stat_key": "reduced_projectile_speed", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "%d%% reduced Projectile Speed", "applies_to": ["weapon"], "weapon_kind": "ranged", "brand_tags": [], "no_roll": true},

	# Patch v4.0 Parry/Riposte Build Mod Pool - Melee Weapons via
	# weapon_kind, Shields via the "shield" category (equip_slot OFFHAND
	# already covers Body Armour separately where listed).
	{"stat_key": "parry_window_duration", "tier1_min": 44.0, "tier1_max": 52.0, "desc": "+%d%% increased Parry Window Duration", "applies_to": ["weapon", "shield"], "slots": [6], "weapon_kind": "melee", "brand_tags": []},
	{"stat_key": "ward_on_parry", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "+%d%% of max Ward restored on successful Parry", "applies_to": ["weapon", "armor", "shield"], "slots": [1, 6], "weapon_kind": "melee", "brand_tags": ["ward"]},
	{"stat_key": "increased_riposte_damage", "tier1_min": 34.0, "tier1_max": 44.0, "desc": "+%d%% increased Riposte damage", "applies_to": ["armor", "shield"], "slots": [2, 6], "brand_tags": []},
	{"stat_key": "riposte_crit_chance", "tier1_min": 44.0, "tier1_max": 52.0, "desc": "Riposte has +%d%% increased Critical Strike Chance", "applies_to": ["weapon", "shield"], "slots": [6], "weapon_kind": "melee", "brand_tags": [], "no_roll": true},

	# Patch v4.0 Healing/Sustain Mod Pool (flat_ward already existed pre-v4.0)
	{"stat_key": "life_regen_flat", "tier1_min": 28.0, "tier1_max": 36.0, "desc": "Regenerate %d Life per second", "applies_to": ["armor", "shield", "item"], "slots": [1, 6, 9, 10], "brand_tags": []},
	{"stat_key": "life_regen_increased", "tier1_min": 44.0, "tier1_max": 52.0, "desc": "+%d%% increased Life Regeneration", "applies_to": ["armor", "shield", "item"], "slots": [0, 1, 2, 3, 6, 9, 10], "brand_tags": [], "no_roll": true},
	# Body armour tops out at 179 Life, every other slot at 129 (Tier 1).
	{"stat_key": "flat_life", "tier1_min": 80.0, "tier1_max": 100.0, "desc": "+%d to Life", "applies_to": ["armor", "shield", "item"], "slot_tiers": {1: [114.56, 143.2]}, "brand_tags": []},
	{"stat_key": "life_increased", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "+%d%% increased Life", "applies_to": ["armor", "shield", "item"], "slots": [0, 1, 2, 3, 6, 9, 10], "brand_tags": []},
	{"stat_key": "mana_regen_increased", "tier1_min": 44.0, "tier1_max": 52.0, "desc": "+%d%% increased Mana Regeneration", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9, 10], "weapon_kind": "conduit", "brand_tags": ["resource"]},
	{"stat_key": "flat_mana", "tier1_min": 68.0, "tier1_max": 90.0, "desc": "+%d to Mana", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9, 10], "weapon_kind": "conduit", "brand_tags": ["resource"]},
	{"stat_key": "mana_increased", "tier1_min": 14.0, "tier1_max": 18.0, "desc": "+%d%% increased Mana", "applies_to": ["weapon", "armor", "item"], "slots": [0, 9, 10], "weapon_kind": "conduit", "brand_tags": ["resource"]},
	{"stat_key": "ward_recovery_increased", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Ward Recovery", "applies_to": ["armor", "shield", "item"], "slots": [0, 1, 6, 9, 10], "brand_tags": ["ward"]},

	# Patch v4.0 Offensive Mod Pool
	{"stat_key": "fire_penetration", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "+%d%% Fire Penetration", "applies_to": ["weapon", "item"], "slots": [9, 11], "brand_tags": ["fire"]},
	{"stat_key": "cold_penetration", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "+%d%% Cold Penetration", "applies_to": ["weapon", "item"], "slots": [9, 11], "brand_tags": ["cold"]},
	{"stat_key": "lightning_penetration", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "+%d%% Lightning Penetration", "applies_to": ["weapon", "item"], "slots": [9, 11], "brand_tags": ["lightning"]},
	{"stat_key": "elemental_penetration", "tier1_min": 12.0, "tier1_max": 16.0, "desc": "+%d%% Elemental Penetration", "applies_to": ["weapon", "item"], "slots": [9, 11], "brand_tags": ["fire", "cold", "lightning"]},
	{"stat_key": "esoteric_penetration", "tier1_min": 12.0, "tier1_max": 16.0, "desc": "+%d%% Esoteric Penetration", "applies_to": ["weapon", "item"], "slots": [9, 11], "brand_tags": ["aetheric", "entropic", "pale"]},
	{"stat_key": "physical_shred", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "+%d%% Physical Shred", "applies_to": ["weapon", "armor"], "slots": [2], "brand_tags": ["kinetic", "piercing", "explosive"]},

	# Patch v4.0 Retaliation Mod Pool
	{"stat_key": "increased_retaliation_damage", "tier1_min": 54.0, "tier1_max": 64.0, "desc": "+%d%% increased Retaliation damage", "applies_to": ["weapon", "armor", "shield"], "slots": [1, 2, 6], "brand_tags": []},
	# Block (Player.try_block_melee_hit()): flat points added to the shield's own
	# chance (prefix), then scaled by the increased line (suffix).
	{"stat_key": "block_chance_bonus", "tier1_min": 7.0, "tier1_max": 8.0, "desc": "+%d%% Chance to Block", "applies_to": ["shield"], "slots": [6], "brand_tags": []},
	{"stat_key": "increased_block_chance", "tier1_min": 85.0, "tier1_max": 95.0, "desc": "+%d%% increased Chance to Block", "applies_to": ["shield"], "slots": [6], "brand_tags": []},
	# Curses: stronger curses (helmet, amulet), and room for one more (amulet only).
	{"stat_key": "curse_effect", "tier1_min": 10.0, "tier1_max": 14.0, "desc": "+%d%% increased effect of Curses and Debuffs", "applies_to": ["armor", "item"], "slots": [0, 9], "brand_tags": ["skills"]},
	{"stat_key": "additional_curses", "tier1_min": 1.0, "tier1_max": 1.0, "desc": "Enemies can have +%d additional Curse", "applies_to": ["item"], "slots": [9], "brand_tags": ["skills"]},
	{"stat_key": "retaliate_on_block", "tier1_min": 25.0, "tier1_max": 35.0, "desc": "%d%% chance to Retaliate on Block", "applies_to": ["shield"], "slots": [6], "brand_tags": []},

	# Patch v4.0 Defensive Mod Pool
	{"stat_key": "reduced_physical_taken", "tier1_min": 9.0, "tier1_max": 11.0, "desc": "%d%% reduced Physical Damage taken", "applies_to": ["armor", "shield"], "slots": [1, 6], "brand_tags": []},
	{"stat_key": "reduced_elemental_taken", "tier1_min": 9.0, "tier1_max": 11.0, "desc": "%d%% reduced Elemental Damage taken", "applies_to": ["armor", "shield"], "slots": [1, 6], "brand_tags": []},
	{"stat_key": "reduced_esoteric_taken", "tier1_min": 9.0, "tier1_max": 11.0, "desc": "%d%% reduced Esoteric Damage taken", "applies_to": ["armor", "shield"], "slots": [1, 6], "brand_tags": []},
	{"stat_key": "ward_delay_reduction", "tier1_min": 0.8, "tier1_max": 1.2, "desc": "Faster Ward Delay by %.1f seconds", "applies_to": ["armor", "shield", "item"], "slots": [0, 1, 6, 9, 10], "brand_tags": ["ward"]},
	{"stat_key": "armor_to_elemental", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "%d%% of Armor applies to Elemental", "applies_to": ["armor", "shield", "item"], "slots": [1, 6, 9], "brand_tags": []},
	{"stat_key": "evasion_to_spells", "tier1_min": 14.0, "tier1_max": 18.0, "desc": "%d%% of Evasion applies to Spell Hits", "applies_to": ["armor", "shield"], "slots": [1, 3, 6], "brand_tags": ["evasion"]},
	{"stat_key": "dash_speed", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Dash Speed", "applies_to": ["armor"], "slots": [3], "brand_tags": ["movement"]},
	{"stat_key": "damage_from_mana", "tier1_min": 18.0, "tier1_max": 22.0, "desc": "%d%% of Damage taken from Mana before Life", "applies_to": ["armor", "item"], "slots": [0, 1, 9], "brand_tags": ["resource"]},
	{"stat_key": "all_elemental_resistance", "tier1_min": 12.0, "tier1_max": 16.0, "desc": "+%d%% to all Elemental Resistances", "applies_to": ["armor", "shield", "item"], "brand_tags": ["fire", "cold", "lightning"]},
	{"stat_key": "esoteric_resistance", "tier1_min": 22.0, "tier1_max": 28.0, "desc": "+%d%% to Esoteric Resistance", "applies_to": ["armor", "shield", "item"], "brand_tags": ["resistance", "aetheric", "entropic", "pale"]},
	{"stat_key": "fire_resistance", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% to Fire Resistance", "applies_to": ["armor", "shield", "item"], "brand_tags": ["resistance", "fire"]},
	{"stat_key": "cold_resistance", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% to Cold Resistance", "applies_to": ["armor", "shield", "item"], "brand_tags": ["resistance", "cold"]},
	{"stat_key": "lightning_resistance", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% to Lightning Resistance", "applies_to": ["armor", "shield", "item"], "brand_tags": ["resistance", "lightning"]},
	{"stat_key": "phys_as_fire", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "%d%% Physical Damage taken as Fire", "applies_to": ["armor", "shield", "item"], "slots": [1, 6, 9], "brand_tags": [], "no_roll": true},
	{"stat_key": "phys_as_cold", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "%d%% Physical Damage taken as Cold", "applies_to": ["armor", "shield", "item"], "slots": [1, 6, 9], "brand_tags": [], "no_roll": true},
	{"stat_key": "phys_as_lightning", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "%d%% Physical Damage taken as Lightning", "applies_to": ["armor", "shield", "item"], "slots": [1, 6, 9], "brand_tags": [], "no_roll": true},
	{"stat_key": "phys_as_elemental", "tier1_min": 12.0, "tier1_max": 16.0, "desc": "%d%% of Physical Damage taken as Elemental", "applies_to": ["armor", "shield", "item"], "slots": [1, 6, 9], "brand_tags": []},


	# Patch v4.0 Armor Base Specific Mods (flat_ward/flat_armor/flat_evasion
	# pre-existing, "Varies by type" per the doc - no new T1 given for those)
	{"stat_key": "increased_ward", "defense": "ward", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Ward", "applies_to": ["armor", "shield"], "slots": [0, 1, 2, 3, 6], "brand_tags": ["ward"]},
	{"stat_key": "increased_armor", "defense": "armor", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Armor", "applies_to": ["armor", "shield"], "slots": [0, 1, 2, 3, 6], "brand_tags": ["armor"]},
	{"stat_key": "increased_evasion", "defense": "evasion", "tier1_min": 28.0, "tier1_max": 34.0, "desc": "+%d%% increased Evasion", "applies_to": ["armor", "shield"], "slots": [0, 1, 2, 3, 6], "brand_tags": ["evasion"]},
	# Amulet only (v5.5.1): % increased to all of your Armour, Evasion or Ward, 30% (Tier 6) to 50% (Tier 1).
	{"stat_key": "amulet_increased_armor", "tier1_min": 44.0, "tier1_max": 46.0, "desc": "+%d%% increased Armor", "applies_to": ["item"], "slots": [9], "brand_tags": ["armor"]},
	{"stat_key": "amulet_increased_evasion", "tier1_min": 44.0, "tier1_max": 46.0, "desc": "+%d%% increased Evasion", "applies_to": ["item"], "slots": [9], "brand_tags": ["evasion"]},
	{"stat_key": "amulet_increased_ward", "tier1_min": 44.0, "tier1_max": 46.0, "desc": "+%d%% increased Ward", "applies_to": ["item"], "slots": [9], "brand_tags": ["ward"]},
	# 40% of the slot's flat Life cap: 71.6 on body armour, 51.6 elsewhere (Tier 1).
	{"stat_key": "hybrid_defense_life", "tier1_min": 33.02, "tier1_max": 41.28, "desc": "+%d to Life, and to the base's own defence (hybrid)", "applies_to": ["armor", "shield"], "slots": [0, 1, 2, 3, 6], "slot_tiers": {1: [45.82, 57.28]}, "brand_tags": []},

	# Patch v4.0 Amulet Exclusive Mod Pool - Prefix, +1-2 at T1 (item level
	# 80+), lower tiers +1 only. "Among the rarest amulet rolls" - kept at
	# the doc's own tight T1 range rather than this pool's usual wider spreads.
	{"stat_key": "flat_aether", "tier1_min": 40.0, "tier1_max": 55.0, "desc": "+%d to Aether capacity", "applies_to": ["item"], "slots": [9], "brand_tags": []},
	{"stat_key": "skill_level_all", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all active Skills", "applies_to": ["item"], "slots": [9], "brand_tags": []},
	{"stat_key": "skill_level_spells", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Spells", "applies_to": ["item"], "slots": [9], "brand_tags": [], "no_roll": true},
	{"stat_key": "skill_level_kinetic", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Kinetic Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["kinetic"]},
	{"stat_key": "skill_level_spell_kinetic", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Kinetic Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["kinetic"], "no_roll": true},
	{"stat_key": "skill_level_piercing", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Piercing Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["piercing"]},
	{"stat_key": "skill_level_spell_piercing", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Piercing Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["piercing"], "no_roll": true},
	{"stat_key": "skill_level_explosive", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Explosive Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["explosive"], "no_roll": true},
	{"stat_key": "skill_level_spell_explosive", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Explosive Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["explosive"], "no_roll": true},
	{"stat_key": "skill_level_fire", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Fire Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["fire"]},
	{"stat_key": "skill_level_spell_fire", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Fire Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["fire"], "no_roll": true},
	{"stat_key": "skill_level_cold", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Cold Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["cold"]},
	{"stat_key": "skill_level_spell_cold", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Cold Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["cold"], "no_roll": true},
	{"stat_key": "skill_level_lightning", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Lightning Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["lightning"]},
	{"stat_key": "skill_level_spell_lightning", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Lightning Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["lightning"], "no_roll": true},
	{"stat_key": "skill_level_aetheric", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Aetheric Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["aetheric"]},
	{"stat_key": "skill_level_spell_aetheric", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Aetheric Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["aetheric"], "no_roll": true},
	{"stat_key": "skill_level_entropic", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Entropic Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["entropic"]},
	{"stat_key": "skill_level_spell_entropic", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Entropic Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["entropic"], "no_roll": true},
	{"stat_key": "skill_level_pale", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Pale Skills", "applies_to": ["item"], "slots": [9], "brand_tags": ["pale"]},
	{"stat_key": "skill_level_spell_pale", "tier1_min": 1.0, "tier1_max": 2.0, "desc": "+%d to level of all Pale Spells", "applies_to": ["item"], "slots": [9], "brand_tags": ["pale"], "no_roll": true},
]

## power_level: the active Map's tier, or player level as a fallback in
## the Hub - a rough "how strong should this roll be" signal.
## loot_rarity_multiplier: shifts the rarity roll upward.
## Modifiers on a dropped Rare.
const RARE_AFFIX_COUNT := Vector2i(3, 6)
## Gear lines offered on only this share of drops (chase modifiers).
const RARE_GEAR_MODIFIERS := {"skill_level_all": 0.35}

static func roll(power_level: int = 1, loot_rarity_multiplier: float = 1.0) -> Item:
	var base := _pick_base_item(power_level)
	if base == null:
		return null
	var item: Item = base.duplicate(true)
	item.item_id = "%s_rolled_%d" % [base.item_id, randi()]
	item.base_level = base.item_level
	item.item_level = maxi(power_level, base.item_level)

	# No per-drop damage/spell power roll: a weapon's base range is rolled
	# per hit instead (Weapon.roll_damage()/Ability.roll_damage()).

	# Patch v3.8 Section 3: how many of the base's own max_sockets this
	# specific drop actually has - 0 to max_sockets inclusive, same "the
	# base sets a ceiling, the roll picks a point under it" shape as
	# affix tiers. max_sockets itself is untouched (still the item type's
	# overall cap, raised by Bore/Corruption exactly as before).
	# Patch v4.3: never past the item category's ceiling, whatever an old
	# base .tres or a saved copy says.
	item.max_sockets = mini(item.max_sockets, get_socket_cap(item))
	item.sockets = randi() % (item.max_sockets + 1)
	CraftingResolver.roll_tolerance(item)

	# Loot.roll_rarity() weights Common/Uncommon/Rare; loot_rarity_multiplier
	# (Item Rarity) scales the non-Common weights.
	item.rarity = Loot.roll_rarity(loot_rarity_multiplier)
	if item.rarity >= Constants.ItemRarity.UNIQUE:
		var unique := UniqueRoller.roll(item.rarity, power_level)
		if unique:
			return unique
		item.rarity = Constants.ItemRarity.RARE
	var affix_count := 0
	match item.rarity:
		Constants.ItemRarity.UNCOMMON:
			affix_count = randi_range(1, 2)
		Constants.ItemRarity.RARE:
			affix_count = randi_range(RARE_AFFIX_COUNT.x, RARE_AFFIX_COUNT.y)

	# Explicits are rolled fresh; the base's implicits stay.
	item.affixes = item.affixes.filter(func(a: ItemAffix): return a.is_implicit)
	if item is Weapon:
		_roll_weapon_affixes(item as Weapon, affix_count, power_level)
	else:
		# Prefix/suffix by stat, as Orbs classify it, within the rarity's limits.
		var pool := _pool_for(item)
		pool = pool.filter(func(e: Dictionary) -> bool: return randf() < RARE_GEAR_MODIFIERS.get(e["stat_key"], 1.0))
		pool.shuffle()
		var used := {}
		var entries: Array = []
		var limits: Vector2i = Constants.AFFIX_LIMITS_GEAR.get(item.rarity, Vector2i.ZERO)
		var side_counts := {true: 0, false: 0}
		for entry in pool:
			var stat := StatKeys.canonical(entry["stat_key"])
			var is_prefix := not GearModifierPool._is_suffix(entry["stat_key"])
			if entries.size() < affix_count and not used.has(stat) and side_counts[is_prefix] < (limits.x if is_prefix else limits.y):
				used[stat] = true
				side_counts[is_prefix] += 1
				entries.append(entry)
		for i in entries.size():
			var entry: Dictionary = entries[i]
			var rolled := roll_tier_range(entry["stat_key"], entry_tiers(entry, item.equip_slot).x, entry_tiers(entry, item.equip_slot).y, power_level)
			var rolled_tier: int = rolled["tier"]
			var value_range := Vector2(rolled["min"], rolled["max"])
			var value := roll_value(entry["stat_key"], value_range)
			var affix := ItemAffix.new()
			affix.stat_key = entry["stat_key"]
			affix.value = value
			affix.value_min = value_range.x
			affix.value_max = value_range.y
			affix.tier = rolled_tier
			affix.description = "%s (Tier %d)" % [describe_value(entry["desc"], entry["stat_key"], value), rolled_tier]
			affix.is_prefix = not GearModifierPool._is_suffix(entry["stat_key"])
			item.affixes.append(affix)

	# An empty eligible pool (low power_level, narrow base) can still leave
	# nothing rolled - such an item is Common, not a mod-less Uncommon/Rare.
	if not item.affixes.any(func(a: ItemAffix): return not a.is_implicit):
		item.rarity = Constants.ItemRarity.COMMON

	return item

## The tier1_min/tier1_max ranges in AFFIX_POOL (and a weapon library
## modifier's value range) are Tier 2's since v4.83; Tier 1 is them over
## TIER_DECAY, and each tier below is TIER_DECAY of the one above.
static func _tier_range(tier1_min: float, tier1_max: float, tier: int) -> Vector2:
	var scale: float = pow(TIER_DECAY, tier - 2)
	return Vector2(tier1_min * scale, tier1_max * scale)

## Patch v3.5: tiers are gated by item level. TOP_TIER_LEVEL is the level the
## authored ranges (Tier 2) need on the old spread; gear's own ladder is
## GEAR_TIER_LEVELS, so the Edicts of 61, 72 and 83 each open a tier.
const TOP_TIER_LEVEL := 80
const GEAR_TIER_LEVELS: Array[int] = [83, 72, 61, 40, 21, 1]
## Tier 1 of a weapon library modifier with its own top level.
const NEW_TOP_TIER_LEVEL := 83

static func tier_min_level(tier: int, tier_count: int = TIER_COUNT, top_level: int = TOP_TIER_LEVEL) -> int:
	if tier_count == TIER_COUNT:
		if top_level == TOP_TIER_LEVEL:
			return GEAR_TIER_LEVELS[clampi(tier, 1, TIER_COUNT) - 1]
		# Library modifiers: Tier 2 keeps the doc's level, the rest spread below it.
		if tier <= 1:
			return NEW_TOP_TIER_LEVEL
		return _spread_level(tier - 1, TIER_COUNT - 1, top_level)
	return _spread_level(tier, tier_count, top_level)

## Tiers' levels spread evenly from top_level (tier 1) down to 1.
static func _spread_level(tier: int, tier_count: int, top_level: int) -> int:
	if tier_count <= 1:
		return 1
	return 1 + roundi((top_level - 1) * float(tier_count - tier) / float(tier_count - 1))

## Item level a rolled gear modifier's tier needs, or 0 when it has no tier
## data (Uniques, hand-authored, corrupted specials).
static func affix_tier_level(affix: ItemAffix) -> int:
	if affix.tier <= 0 or affix.is_implicit:
		return 0
	var table := levelled_table(affix.stat_key)
	if not table.is_empty():
		return int(table[clampi(affix.tier, 1, table.size()) - 1][0])
	if _weapon_affix_cache.is_empty():
		_build_weapon_affix_cache()
	for source in _weapon_affix_cache:
		if source.affix_id != "" and source.affix_id == affix.affix_id:
			return tier_min_level(affix.tier, TIER_COUNT, top_level_of(source))
	return tier_min_level(affix.tier)

## Item level `tier` of a gear pool ModifierDef needs (GearModifierPool).
static func def_tier_level(def: ModifierDef, tier: int) -> int:
	var table := levelled_table(def.stat_key)
	if not table.is_empty():
		return int(table[clampi(tier, 1, table.size()) - 1][0])
	if _weapon_affix_cache.is_empty():
		_build_weapon_affix_cache()
	for source in _weapon_affix_cache:
		if source.affix_id != "" and StringName(source.affix_id) == def.id:
			return tier_min_level(tier, TIER_COUNT, top_level_of(source))
	return tier_min_level(tier)

## Whether a modifier's tiers gained the v4.83 top tier (old saves shift up).
static func gained_new_top_tier(affix: ItemAffix) -> bool:
	if affix.tier <= 0 or affix.is_implicit:
		return false
	var table := levelled_table(affix.stat_key)
	return table.is_empty() or int(table[0][0]) == NEW_TOP_TIER_LEVEL

## Best (lowest-numbered) tier an item of this level can roll.
static func best_tier_for_level(level: int, tier_count: int = TIER_COUNT, top_level: int = TOP_TIER_LEVEL) -> int:
	for t in range(1, tier_count + 1):
		if tier_min_level(t, tier_count, top_level) <= level:
			return t
	return tier_count

## Weapon library modifiers carry the doc's "T1 item level" in min_item_level
## (e.g. 78): their Tier 1 needs that level, lower tiers open earlier.
static func top_level_of(source: ItemAffix) -> int:
	return source.min_item_level if source.min_item_level > 1 else TOP_TIER_LEVEL

## A tier the level allows, weighted by GEAR_TIER_WEIGHTS (better tiers rarer).
static func _roll_tier(power_level: int, top_level: int = TOP_TIER_LEVEL) -> int:
	var best := best_tier_for_level(power_level, TIER_COUNT, top_level)
	var total := 0
	for t in range(best, TIER_COUNT + 1):
		total += Constants.GEAR_TIER_WEIGHTS[t - 1]
	var pick := randi() % maxi(total, 1)
	for t in range(best, TIER_COUNT + 1):
		pick -= Constants.GEAR_TIER_WEIGHTS[t - 1]
		if pick < 0:
			return t
	return TIER_COUNT

## Modifiers with their own tier table instead of Tier 1 x TIER_DECAY: each
## row is [item level needed, min, max], best tier (Tier 1) first.
## % Weapon / Spell Damage run from 30% to 190% (user request). Flat damage
## is "Adds X to (X x FLAT_DAMAGE_SPREAD)"; the hybrid's value is its %
## part and its flat part is HYBRID_FLAT_PER_PERCENT of that.
const DAMAGE_PERCENT_TIERS := [[83, 191.0, 225.0], [80, 160.0, 190.0],[68, 128.0, 155.0], [56, 105.0, 127.0], [45, 85.0, 104.0], [34, 68.0, 84.0], [23, 53.0, 67.0], [12, 40.0, 52.0], [1, 30.0, 39.0]]
## Additional arrows / spell projectiles: +1, +2, +3.
const ADDITIONAL_PROJECTILE_TIERS := [[75, 3.0, 3.0], [40, 2.0, 2.0], [1, 1.0, 1.0]]
## Displayed scale: Evasion > Armour > Ward (v5.5.2).
const FLAT_ARMOUR_TIERS := [[83, 100.0, 115.0], [72, 75.0, 85.0], [61, 55.0, 65.0], [40, 30.0, 40.0], [21, 20.0, 25.0], [1, 10.0, 15.0]]
const FLAT_EVASION_TIERS := [[83, 150.0, 172.0], [72, 112.0, 128.0], [61, 82.0, 98.0], [40, 45.0, 60.0], [21, 30.0, 38.0], [1, 15.0, 22.0]]
const AMULET_DEFENCE_TIERS := [[83, 47.0, 50.0], [72, 44.0, 46.0], [61, 40.0, 43.0], [40, 37.0, 39.0], [21, 34.0, 36.0], [1, 30.0, 33.0]]
const RESISTANCE_TIERS := [[83, 39.0, 48.0], [72, 33.0, 38.0], [61, 27.0, 32.0], [40, 22.0, 26.0], [21, 18.0, 21.0], [1, 15.0, 17.0]]
const LEVELLED_TIERS := {
	"local_increased_weapon_damage": DAMAGE_PERCENT_TIERS,
	"local_increased_spell_damage": DAMAGE_PERCENT_TIERS,
	"local_flat_weapon_damage": [[83, 35.0, 41.0], [80, 29.0, 34.0],[68, 24.0, 28.0], [56, 19.0, 23.0], [45, 14.0, 18.0], [34, 10.0, 13.0], [23, 7.0, 9.0], [12, 4.0, 6.0], [1, 2.0, 3.0]],
	"local_hybrid_weapon_damage": [[83, 86.0, 101.0], [80, 71.0, 85.0],[64, 59.0, 70.0], [48, 47.0, 58.0], [32, 35.0, 46.0], [16, 25.0, 34.0], [1, 15.0, 24.0]],
	"local_additional_arrows": ADDITIONAL_PROJECTILE_TIERS,
	"local_additional_spell_projectiles": ADDITIONAL_PROJECTILE_TIERS,
	# One tier only, from item level 61.
	"additional_curses": [[61, 1.0, 1.0]],
	# Reload Speed spans 10% (Tier 6) to 35% (Tier 1); Active Reload does the rest.
	"reload_speed": [[83, 31.0, 35.0], [72, 27.0, 30.0], [61, 22.0, 26.0], [40, 18.0, 21.0], [21, 14.0, 17.0], [1, 10.0, 13.0]],
	# Flat defences follow the bases' curves (tools/rescale_defence_bases.pl):
	# about 15% of the top body base at each tier's level.
	"flat_armor": FLAT_ARMOUR_TIERS,
	"flat_evasion": FLAT_EVASION_TIERS,
	"flat_ward": [[83, 62.0, 72.0], [72, 45.0, 52.0], [61, 32.0, 37.0], [40, 17.0, 20.0], [21, 10.0, 12.0], [1, 5.0, 6.0]],
	"amulet_increased_armor": AMULET_DEFENCE_TIERS,
	"amulet_increased_evasion": AMULET_DEFENCE_TIERS,
	"amulet_increased_ward": AMULET_DEFENCE_TIERS,
	# Move Speed tops out at 35% (user).
	"move_speed": [[83, 30.0, 35.0], [72, 25.0, 29.0], [61, 20.0, 24.0], [40, 15.0, 19.0], [21, 10.0, 14.0], [1, 6.0, 9.0]],
	# Single Resistances span 15% (Tier 6) to 48% (Tier 1).
	"fire_resistance": RESISTANCE_TIERS,
	"cold_resistance": RESISTANCE_TIERS,
	"lightning_resistance": RESISTANCE_TIERS,
	"esoteric_resistance": RESISTANCE_TIERS,
	"block_chance_bonus": [[80, 7.0, 8.0], [56, 5.0, 6.0], [28, 3.0, 4.0], [1, 2.0, 2.0]],
	"increased_block_chance": [[80, 26.0, 30.0], [64, 22.0, 25.0], [48, 18.0, 21.0], [32, 15.0, 17.0], [16, 12.0, 14.0], [1, 10.0, 11.0]],
	# Damage over Time Multiplier: 7% (Tier 6) to 20% (Tier 1). Jewels and
	# Lenses scale their own from tier1_min/tier1_max (about 10-20%).
	"dot_multiplier": [[80, 18.0, 20.0], [64, 15.0, 17.0], [48, 13.0, 14.0], [32, 11.0, 12.0], [16, 9.0, 10.0], [1, 7.0, 8.0]],
}
## "+N to level of ... Skills/Spells" (amulets): whole levels, +1 at Tier 2 and
## +2 at Tier 1 (user decision).
const SKILL_LEVEL_TIERS := [[80, 2.0, 2.0], [1, 1.0, 1.0]]
const FLAT_DAMAGE_SPREAD := 1.75
const HYBRID_FLAT_PER_PERCENT := 0.2

## The modifier's own tier table, or [] when it uses Tier 1 x TIER_DECAY.
static func levelled_table(stat_key: String) -> Array:
	var key := StatKeys.canonical(stat_key)
	if key.begins_with("skill_level_"):
		return SKILL_LEVEL_TIERS
	return LEVELLED_TIERS.get(key, [])

static func has_levelled_tiers(stat_key: String) -> bool:
	return not levelled_table(stat_key).is_empty()

## Rows of `stat_key`'s table that `level` allows, best first.
static func levelled_tiers_for(stat_key: String, level: int) -> Array:
	return levelled_table(stat_key).filter(func(row): return row[0] <= level)

## {"tier", "min", "max"} rolled from the table; the best allowed tier is the
## rarest (weights 1, 2, 3... down the allowed rows).
static func roll_levelled_tier(stat_key: String, level: int) -> Dictionary:
	var table := levelled_table(stat_key)
	var rows := levelled_tiers_for(stat_key, level)
	if rows.is_empty():
		rows = [table[-1]]
	var total := rows.size() * (rows.size() + 1) / 2
	var pick := randi() % total
	for i in rows.size():
		pick -= i + 1
		if pick < 0:
			return {"tier": table.find(rows[i]) + 1, "min": rows[i][1], "max": rows[i][2]}
	var last: Array = rows[-1]
	return {"tier": table.find(last) + 1, "min": last[1], "max": last[2]}

## {"tier", "min", "max"} for one roll of a modifier at power_level: its own
## tier table if it has one, else a gated tier of Tier 1 x TIER_DECAY.
static func roll_tier_range(stat_key: String, tier1_min: float, tier1_max: float, power_level: int, top_level: int = TOP_TIER_LEVEL) -> Dictionary:
	if has_levelled_tiers(stat_key):
		return roll_levelled_tier(stat_key, power_level)
	var tier := _roll_tier(power_level, top_level)
	var r := _tier_range(tier1_min, tier1_max, tier)
	return {"tier": tier, "min": r.x, "max": r.y}

## A value in range; whole numbers for table modifiers (levels, flat damage).
static func roll_value(stat_key: String, value_range: Vector2) -> float:
	var value := randf_range(value_range.x, value_range.y)
	return roundf(value) if has_levelled_tiers(stat_key) else value

## Up to `count` entries of `pool` whose stat isn't in `used` yet (marks them).
static func _take_distinct(pool: Array[ItemAffix], count: int, used: Dictionary) -> Array[ItemAffix]:
	var taken: Array[ItemAffix] = []
	for affix in pool:
		if taken.size() >= count:
			break
		if used.has(affix.key()):
			continue
		used[affix.key()] = true
		taken.append(affix)
	return taken

## Card text for a rolled value: two-number templates ("Adds %d to %d")
## get the flat range, the hybrid gets its % and flat range.
static func describe_value(template: String, stat_key: String, value: float) -> String:
	if value < 0.0:
		template = negated_template(template)
		value = -value
	match StatKeys.canonical(stat_key):
		"local_flat_weapon_damage":
			return template % [roundi(value), roundi(value * FLAT_DAMAGE_SPREAD)]
		"local_hybrid_weapon_damage":
			var flat := maxf(roundf(value * HYBRID_FLAT_PER_PERCENT), 1.0)
			return template % [roundi(value), roundi(flat), roundi(flat * FLAT_DAMAGE_SPREAD)]
	if template.contains("%.1f"):
		return template % value
	return template % round(value) if "%" in template else template

## A template for a negative value, filled with the value's magnitude:
## increased/reduced and more/less swap and a leading "+" goes ("+%d%%
## increased Attack Speed" at -25 reads "25% reduced Attack Speed"); with
## no such word the "+" becomes "-" ("-30% to Cold Resistance").
static func negated_template(template: String) -> String:
	var swaps := {" increased ": " reduced ", " reduced ": " increased ", " more ": " less ", " less ": " more "}
	for word in swaps:
		if template.contains(word):
			return template.trim_prefix("+").replace(word, swaps[word])
	return "-" + template.substr(1) if template.begins_with("+") else template

## Patch v3.9 Weapon Affix Library - data/affixes/weapons/<type>/*.tres,
## loaded once and cached (~96 files, same one-time-scan reasoning as
## _candidate_meta_cache below). Each is Tier-1-only data (see tools/
## generate_weapon_affixes.gd's own header for why) - scaled the exact
## same way every OTHER AFFIX_POOL entry already is, via _tier_range()/
## _roll_tier() below, rather than a bespoke per-affix tier table.
const WEAPON_AFFIX_DIR := "res://data/affixes/weapons/"
## v4.10 local mods that belong on Conduits (every other local is martial).
const CONDUIT_LOCAL_KEYS := ["local_increased_spell_damage", "local_increased_cast_speed", "local_additional_spell_projectiles"]
## Weapon modifiers that make it onto only this share of drops' pools.
const RARE_WEAPON_MODIFIERS := {"local_additional_arrows": 0.3, "local_additional_spell_projectiles": 0.3}
## Weapon library modifiers that no longer roll on weapons (drops or Orbs).
## Items that already have them keep them.
const OFF_WEAPON_AFFIXES := [
	"kinetic_pulverising",  # Armor Shred effectiveness
	"aetheric_aetheric", "cold_glacial", "entropic_entropic", "fire_scorching", "lightning_arcing", "pale_pallid",
	"increased_explosive_damage", "increased_kinetic_damage", "increased_piercing_damage",  # % increased <type> damage
	"generic_savage",  # % increased damage
	"generic_of_conservation",  # Skills cost less Mana
	"piercing_barbed",  # Bleed duration
	"generic_of_the_ward",  # Ward on hit
	"piercing_penetrating",  # ignore % of Armor
	"riposte_damage", "excl_riposte_edge",  # increased Riposte damage
	"aetheric_eroding", "cold_brittle", "entropic_decaying", "fire_pyretic", "kinetic_hammering",
	"lightning_conducting", "pale_threshold",  # damage vs <status> enemies
	"aetheric_consuming",  # drain Ward on hit
	"excl_of_the_weave",  # reduced Mana cost of spells
	"aetheric_of_the_veil", "explosive_of_impact",  # Ward on kill
	"excl_resonant",  # Cooldown Recovery Rate
	"projectile_speed",
	# v5.5: per-type ailment chance (generic_virulent / generic_hindering replace them)
	"fire_immolating", "cold_freezing", "lightning_discharging", "piercing_haemorrhaging",
	"explosive_incendiary", "aetheric_devouring", "entropic_fraying", "pale_draining",
	# Resource on ailment or kill (gloves and rings roll these now)
	"fire_of_the_pyre", "cold_of_the_frost", "lightning_of_conductance", "entropic_of_dissolution", "pale_of_the_threshold",
	# Per-type copies of the generic attribute suffixes
	"fire_of_the_calcine", "cold_of_the_quench", "lightning_of_the_galvanic", "kinetic_of_the_ironhand", "piercing_of_the_duelist",
	"explosive_of_the_wrecker", "aetheric_of_the_invoke", "entropic_of_efface", "pale_of_the_hollow",
	# Duplicates of a generic or local modifier
	"generic_fluid", "kinetic_of_rending", "lightning_of_static", "fire_of_conflagration",
	"piercing_of_precision", "entropic_of_collapse", "fire_kindling",
	"excl_channelers",  # weaker than local Spell Damage
]
## Removed from the game (files deleted); ItemSerializer strips them from saved items.
const REMOVED_WEAPON_AFFIXES := ["generic_opportunist", "excl_of_the_hunt"]  # damage vs full Life
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
				var file_name := dir.get_next().trim_suffix(".remap")
				while file_name != "":
					if file_name.ends_with(".tres"):
						var affix: ItemAffix = load(WEAPON_AFFIX_DIR + subdir + "/" + file_name)
						if affix:
							_weapon_affix_cache.append(affix)
					file_name = dir.get_next().trim_suffix(".remap")
				dir.list_dir_end()
		subdir = root.get_next()
	root.list_dir_end()

static func weapon_kind(weapon: Weapon) -> String:
	if weapon.is_conduit:
		return "conduit"
	return "ranged" if weapon.is_ranged else "melee"

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
## this weapon's resolved type key or its kind ("melee", "ranged",
## "conduit") - AND available at this power_level (brief's own algorithm:
## "available at item level").
static func _eligible_weapon_affixes(weapon: Weapon, power_level: int, want_prefix: bool) -> Array[ItemAffix]:
	if _weapon_affix_cache.is_empty():
		_build_weapon_affix_cache()
	var dtype: Constants.DamageType = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
	var type_key := _weapon_type_key(weapon)
	var result: Array[ItemAffix] = []
	for affix in _weapon_affix_cache:
		if affix.is_prefix != want_prefix:
			continue
		if OFF_WEAPON_AFFIXES.has(affix.affix_id):
			continue
		# Local mods: caster ones only on real Conduits, the rest only on
		# martial weapons - by is_conduit, not type key (worn_staff is a melee
		# "staff" that shares the Conduit staff line's key).
		if affix.is_local and weapon.is_conduit != CONDUIT_LOCAL_KEYS.has(affix.stat_key):
			continue
		# A weapon that never attacks gets no local hit mods (Fluid's attack
		# speed, of the Sharp's crit chance) - they'd do nothing on it.
		if not weapon.can_attack():
			var key := StatKeys.canonical(affix.stat_key)
			if key.begins_with("local_") and not CONDUIT_LOCAL_KEYS.has(key):
				continue
		var matches := affix.is_generic
		if not matches and affix.weapon_type_filter.is_empty():
			matches = affix.damage_type == dtype
		elif not matches:
			matches = affix.weapon_type_filter.has(type_key) or affix.weapon_type_filter.has(weapon_kind(weapon))
		if matches:
			result.append(affix)
	return result

## Splits the rarity roll's flat affix_count into a prefix pool (max 3)
## and a suffix pool (max 3, Section 18's own Rare "0-6" ceiling, "0-3
## prefixes, 0-3 suffixes" per the brief) - alternating so an uneven count
## favors prefixes first, then falls back to whichever pool still has
## eligible, unused entries if the other runs dry.
static func _roll_weapon_affixes(weapon: Weapon, affix_count: int, power_level: int) -> void:
	var is_offered := func(a: ItemAffix) -> bool: return randf() < RARE_WEAPON_MODIFIERS.get(a.stat_key, 1.0)
	var prefix_pool := _eligible_weapon_affixes(weapon, power_level, true).filter(is_offered)
	var suffix_pool := _eligible_weapon_affixes(weapon, power_level, false).filter(is_offered)
	prefix_pool.shuffle()
	suffix_pool.shuffle()

	var prefix_target: int = min(3, ceili(affix_count / 2.0))
	var suffix_target: int = min(3, affix_count - prefix_target)
	# One modifier per stat: several library mods feed the same stat (StatKeys).
	var used := {}
	var prefixes := _take_distinct(prefix_pool, prefix_target, used)
	var suffixes := _take_distinct(suffix_pool, suffix_target, used)
	var picked: Array[ItemAffix] = prefixes + suffixes
	# Fill any remaining budget (a pool ran dry) from the other side, still
	# respecting the 3-per-side cap.
	if picked.size() < affix_count:
		picked.append_array(_take_distinct(prefix_pool, mini(3 - prefixes.size(), affix_count - picked.size()), used))
	if picked.size() < affix_count:
		picked.append_array(_take_distinct(suffix_pool, mini(3 - suffixes.size(), affix_count - picked.size()), used))

	for source in picked:
		var rolled := roll_tier_range(source.stat_key, source.value_min, source.value_max, power_level, top_level_of(source))
		var rolled_tier: int = rolled["tier"]
		var value_range := Vector2(rolled["min"], rolled["max"])
		var value := roll_value(source.stat_key, value_range)
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
		affix.is_local = source.is_local
		var formatted := describe_value(source.description, source.stat_key, value)
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
		var file_name := dir.get_next().trim_suffix(".remap")
		while file_name != "":
			if file_name.ends_with(".tres"):
				var path: String = dir_path + file_name
				var item := load(path) as Item
				if item and not _is_excluded_line(item.base_line_id):
					_candidate_meta_cache[path] = {"item_level": item.item_level, "base_line_id": item.base_line_id, "item_type": String(item.get_item_type()), "equip_slot": item.equip_slot}
			file_name = dir.get_next().trim_suffix(".remap")
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
		if entry.get("no_roll", false):
			continue
		var applies: Array = entry["applies_to"]
		if not (applies.is_empty() or applies.has(category)):
			continue
		# Defence mods only roll on a base that has that defence (no Armour
		# mods on an Evasion hood).
		var defense: String = entry.get("defense", "")
		if defense != "" and (item is Armor or item is Shield) and not _has_defense(item, defense):
			continue
		var slots: Array = entry.get("slots", [])
		if not slots.is_empty() and not item is Weapon and not slots.has(item.equip_slot):
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

## _pool_for() narrowed to entries carrying the given brand tag (Shard of
## Tharsis outcomes).
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

static func _has_defense(item: Item, defense: String) -> bool:
	match defense:
		"armor": return item.get("armor_value") > 0.0
		"evasion": return item.get("evasion_value") > 0.0
		"ward": return item.get("ward_value") > 0.0
	return true

## An AFFIX_POOL entry's Tier 2 range (tier1_min/tier1_max) for an item in
## `slot`: its slot_tiers row when it has one for that slot.
static func entry_tiers(entry: Dictionary, slot: int = -1) -> Vector2:
	var by_slot: Dictionary = entry.get("slot_tiers", {})
	if by_slot.has(slot):
		return Vector2(by_slot[slot][0], by_slot[slot][1])
	return Vector2(entry["tier1_min"], entry["tier1_max"])

## How many tiers a rolled modifier has (its own table, or TIER_COUNT).
static func tier_count_for(affix: ItemAffix) -> int:
	var table := levelled_table(affix.stat_key)
	return table.size() if not table.is_empty() else TIER_COUNT

## The value range of `tier` for a rolled modifier, or Vector2(-1, -1) when
## its source can't be found (hand-authored, Unique, corrupted). slot picks a
## per-slot range (slot_tiers) where the modifier has one.
static func tier_range_for(affix: ItemAffix, tier: int, slot: int = -1) -> Vector2:
	var table := levelled_table(affix.stat_key)
	if not table.is_empty():
		var row: Array = table[clampi(tier, 1, table.size()) - 1]
		return Vector2(row[1], row[2])
	for entry in AFFIX_POOL:
		if entry["stat_key"] == affix.stat_key:
			return _tier_range(entry_tiers(entry, slot).x, entry_tiers(entry, slot).y, tier)
	if _weapon_affix_cache.is_empty():
		_build_weapon_affix_cache()
	for source in _weapon_affix_cache:
		if source.affix_id != "" and source.affix_id == affix.affix_id:
			return _tier_range(source.value_min, source.value_max, tier)
	return Vector2(-1.0, -1.0)

## Moves a rolled modifier to `tier`, keeping its value's place in the range,
## and rewrites its text. False when the modifier has no tier data.
static func retier(affix: ItemAffix, tier: int, slot: int = -1) -> bool:
	var new_range := tier_range_for(affix, tier, slot)
	if new_range.x < 0.0:
		return false
	var at := inverse_lerp(affix.value_min, affix.value_max, affix.value) if affix.value_max > affix.value_min else 1.0
	affix.tier = tier
	affix.value_min = new_range.x
	affix.value_max = new_range.y
	affix.value = lerpf(new_range.x, new_range.y, clampf(at, 0.0, 1.0))
	if has_levelled_tiers(affix.stat_key):
		affix.value = roundf(affix.value)
	var template := CraftingResolver._template_for(affix)
	if template != "":
		affix.description = "%s (Tier %d)" % [describe_value(template, affix.stat_key, affix.value), tier]
	return true
