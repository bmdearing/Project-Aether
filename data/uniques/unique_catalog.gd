extends RefCounted
class_name UniqueCatalog
## Every Unique and Mythic item. Each sits on one fixed `base_item` of
## `base_type` (an Item.get_item_type() key), so its level requirement and
## defence type never change; world drops below that base's item level
## skip it. It has a fixed name, flavour and modifier list. A modifier is
## [stat_key, min, max, text]: ordinary stat keys feed the usual stat totals,
## `unique_*` keys are mechanics read by UniqueEffects. Values roll between
## min and max; text takes the rolled value through "%d" (unsigned: the
## text carries the sign, e.g. "%d%% reduced Attack Speed" for -25).
##
## The first four are the design doc's own examples (Master v3 Section 19;
## Aetherburn is not in the game, so Solen Vrath applies an enhanced
## Unraveling instead). The Band of Wishes (a ring that reflects the other
## ring) is the user's Mythic design. The rest are placeholders in the same "build
## problem" style until the dedicated Unique design session. The Cartographer
## of Ruin (Patch v3.1) needs throwables, which aren't in the game yet.
##
## corrupted_only entries never drop; the Shard of Tharsis' Transcendent
## outcome turns an item into one (UniquePool). "any" fits every gear slot.
## "boss": a Pinnacle.BOSSES id; the unique only drops from that boss, at
## "boss_chance" per kill, never as a world drop. Without it, a unique is a
## world drop.

const DEFS := [
	{
		"id": "hollowed_kings_mantle", "name": "The Hollowed King's Mantle", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "body_armour", "base_item": "res://data/armor/instances/gen_body_armour_threshold_coat.tres", "weight": 100.0,
		"flavor": "It belonged to someone who lasted longer than they should have.",
		"mods": [
			["unique_more_ward", 40.0, 50.0, "%d%% more Ward"],
			["unique_esoteric_to_mana", 1.0, 1.0, "Incoming Esoteric damage is taken from Mana before Ward and Life"],
			["unique_esoteric_overflow", 200.0, 200.0, "When Esoteric damage empties your Mana, you take %d%% of the rest as Physical damage, bypassing Ward"],
			["unique_esoteric_damage", 20.0, 20.0, "%d%% more Esoteric damage"],
		],
	},
	{
		"id": "grevanes_accounting", "name": "Grevane's Accounting", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "belt", "base_item": "res://data/items/instances/iron_belt.tres", "weight": 100.0,
		"flavor": "Every debt recorded. Every debt collected.",
		"mods": [
			["unique_debt", 15.0, 15.0, "Every hit you take is recorded as a Debt stack (up to 20). Your next hit while standing still consumes them, dealing %d%% of the recorded damage as Retaliation damage per stack"],
			["unique_reduced_damage_moving", 25.0, 25.0, "You deal %d%% less damage while moving"],
		],
	},
	{
		"id": "the_pale_eye", "name": "The Pale Eye", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "amulet", "base_item": "res://data/items/instances/agility_pendant.tres", "weight": 100.0,
		"flavor": "It sees what you are becoming.",
		"mods": [
			["unique_crit_applies_pallid", 1.0, 1.0, "Your Critical Strikes apply Pallid"],
			["unique_crit_vs_pallid", 30.0, 30.0, "Pallid enemies take %d%% increased damage from your Critical Strikes"],
			["unique_no_ward_recovery", 1.0, 1.0, "You cannot recover Ward"],
			["crit_chance_increased", 40.0, 40.0, "+%d%% increased Critical Strike Chance"],
			["crit_damage_increased", 60.0, 60.0, "+%d%% increased Critical Strike Damage"],
		],
	},
	{
		"id": "unmaking_of_solen_vrath", "name": "The Unmaking of Solen Vrath", "rarity": Constants.ItemRarity.MYTHIC,
		"base_type": "claymore", "base_item": "res://data/weapons/instances/gen_claymore_colossus_claymore.tres", "weight": 100.0, "damage_type": Constants.DamageType.AETHERIC,
		"flavor": "He sought to understand what the Maw was. This is what remained of the attempt.",
		"mods": [
			["local_increased_weapon_damage", 60.0, 80.0, "%d%% increased Weapon Damage"],
			["unique_esoteric_echo", 40.0, 40.0, "Your Aetheric hits also deal %d%% of their damage as Entropic, and Entropic hits as Aetheric"],
			["unique_echo_unraveling", 1.0, 1.0, "Hitting with both applies Unraveling at double effectiveness"],
			["unique_reduced_max_life", 30.0, 30.0, "%d%% reduced Maximum Life"],
			["unique_no_infusion", 1.0, 1.0, "Cannot be Infused"],
		],
	},
	{
		"id": "band_of_wishes", "name": "Band of Wishes", "rarity": Constants.ItemRarity.MYTHIC,
		"base_type": "ring", "base_item": "res://data/items/instances/iron_ring.tres", "weight": 100.0, "no_implicits": true,
		"flavor": "Every wish it grants, you already owned.",
		"mods": [
			["unique_reflect_ring", 1.0, 1.0, "Reflects the modifiers of your other Ring"],
		],
	},
	{
		"id": "arkanus", "name": "Arkanus, the Forbidden Staff", "rarity": Constants.ItemRarity.MYTHIC,
		"base_type": "staff", "base_item": "res://data/weapons/instances/gen_staff_grand_staff.tres", "weight": 100.0, "boss": "aurelia", "boss_chance": 0.02, "conduit_stance_type": "arkanus",
		"flavor": "Four words of power, and nothing left over for anything else.",
		"mods": [
			["unique_more_ailment_effect", 20.0, 30.0, "%d%% more Ailment effect"],
			["unique_more_ailment_damage", 35.0, 50.0, "%d%% more Ailment damage"],
			["increased_spell_damage", 105.0, 250.0, "%d%% increased Spell Damage"],
			["unique_arkanus", 1.0, 1.0, "Your spells are replaced by Elemental Lightning, Fire, Water and Earth, and Elemental Aether on right-click, each costing 2 Mana"],
			["unique_arkanus_mana", 10.0, 10.0, "Your maximum Mana is %d, and can't be changed"],
			["unique_arkanus_regen", 2.0, 2.0, "You regenerate %d Mana per second, and it can't be changed"],
		],
	},
	{
		"id": "sands_of_time", "name": "Sands of Time", "rarity": Constants.ItemRarity.MYTHIC,
		"base_type": "wand", "base_item": "res://data/weapons/instances/gen_wand_transcendent_wand.tres", "weight": 100.0, "boss": "ataras", "boss_chance": 0.02, "conduit_stance_type": "time_stop",
		"flavor": "He kept the last grain. Turn it over, and the world waits for you.",
		"mods": [
			["local_increased_cast_speed", 1.0, 100.0, "%d%% increased Cast Speed"],
			["local_increased_spell_damage", 200.0, 260.0, "%d%% increased Spell Damage"],
			["esoteric_resistance", 30.0, 35.0, "+%d%% Esoteric Resistance"],
			["life_increased", 10.0, 10.0, "%d%% increased Life"],
		],
	},
	{
		"id": "blade_of_runes", "name": "Blade of Runes", "rarity": Constants.ItemRarity.MYTHIC,
		"base_type": "shortsword", "base_item": "res://data/weapons/instances/gen_shortsword_champions_blade.tres", "weight": 100.0, "fixed_sockets": 6,
		"flavor": "Every rune it ever drank still speaks through the steel.",
		"mods": [
			["unique_fixed_sockets", 6.0, 6.0, "Always has %d Sockets"],
			["unique_jewel_effect", 250.0, 250.0, "%d%% increased effect of Socketed Jewels"],
		],
	},
	# ---- Placeholders until the Unique design session ----
	{
		"id": "crown_of_the_ninth_bell", "name": "Crown of the Ninth Bell", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "helmet", "base_item": "res://data/armor/instances/gen_helmet_threshold_cap.tres", "weight": 100.0,
		"flavor": "Eight bells for the hours. The ninth for whoever is still listening.",
		"mods": [
			["skill_level_spells", 2.0, 2.0, "+%d to Level of all Spells"],
			["max_mana", 30.0, 45.0, "+%d Mana"],
			["mana_cost_reduction", -50.0, -50.0, "Spells cost %d%% more Mana"],
		],
	},
	{
		"id": "hands_of_the_last_toll", "name": "Hands of the Last Toll", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "gloves", "base_item": "res://data/armor/instances/gen_gloves_wardens_mitts.tres", "weight": 100.0,
		"flavor": "Paid in full, every time.",
		"mods": [
			["attack_speed", 8.0, 12.0, "+%d%% increased Attack Speed"],
			["unique_life_on_kill", 3.0, 5.0, "Killing an enemy restores %d%% of your Maximum Life"],
			["unique_no_life_regen", 1.0, 1.0, "You have no Life Regeneration"],
		],
	},
	{
		"id": "stride_of_the_unwound", "name": "Stride of the Unwound", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "boots", "base_item": "res://data/armor/instances/gen_boots_striders_boots.tres", "weight": 100.0,
		"flavor": "Stop, and the thread catches up with you.",
		"mods": [
			["move_speed", 20.0, 25.0, "+%d%% increased Move Speed"],
			["unique_more_damage_moving", 15.0, 20.0, "You deal %d%% more damage while moving"],
			["unique_no_ward_recovery_moving", 1.0, 1.0, "Your Ward does not recover while you are moving"],
		],
	},
	{
		"id": "seal_of_the_lesser_sun", "name": "Seal of the Lesser Sun", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "ring", "base_item": "res://data/items/instances/ember_ring.tres", "weight": 100.0,
		"flavor": "A small sun is still a sun.",
		"mods": [
			["unique_more_fire_damage", 20.0, 30.0, "%d%% more Fire damage"],
			["ailment_chance_ignite", 20.0, 20.0, "+%d%% chance to cause Ignite"],
			["cold_resistance_pct", -30.0, -30.0, "-%d%% to Cold Resistance"],
		],
	},
	{
		"id": "the_unpaid_wall", "name": "The Unpaid Wall", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "kite_shield", "base_item": "res://data/shields/instances/gen_kite_shield_sentinels_kite_shield.tres", "weight": 100.0,
		"flavor": "The masons were never paid. The wall remembers.",
		"mods": [
			["block_chance_bonus", 8.0, 12.0, "+%d%% Block Chance"],
			["unique_ward_on_block", 10.0, 10.0, "Blocking restores %d%% of your Maximum Ward"],
			["unique_spell_damage_taken", 20.0, 20.0, "You take %d%% increased damage from Spells"],
		],
	},
	{
		"id": "widows_patience", "name": "Widow's Patience", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "crossbow", "base_item": "res://data/weapons/instances/gen_crossbow_deadeyes_crossbow.tres", "weight": 100.0,
		"flavor": "She only ever needed the one.",
		"mods": [
			["unique_patient_shot", 40.0, 60.0, "Hits deal %d%% more damage if you haven't hit an enemy for 2 seconds"],
			["attack_speed", -25.0, -25.0, "%d%% reduced Attack Speed"],
		],
	},
	{
		"id": "butterfly", "name": "Butterfly", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "crossbow", "base_item": "res://data/weapons/instances/gen_crossbow_phantom_crossbow.tres", "weight": 100.0,
		"flavor": "Never where the blade expects. Always where the bolt lands.",
		"mods": [
			["unique_damage_from_move_speed", 60.0, 60.0, "Increases your damage by %d%% of your increased Movement Speed"],
			["move_speed", 15.0, 25.0, "+%d%% increased Movement Speed"],
			["attack_speed", 10.0, 15.0, "+%d%% increased Attack Speed"],
		],
	},
	# ---- User designs (2026-10-26) ----
	{
		"id": "sanctum_of_the_mage", "name": "Sanctum of the Mage", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "body_armour", "base_item": "res://data/armor/instances/gen_body_armour_aetherial_coat.tres", "weight": 100.0,
		"flavor": "Within these walls, every element answers.",
		"mods": [
			["unique_elemental_levels_per_res", 22.0, 40.0, "+1 Level to all Elemental Spells for every %d%% Elemental Resistance"],
			["flat_ward", 100.0, 100.0, "+%d Ward"],
			["increased_ward", 120.0, 220.0, "%d%% increased Ward"],
			["unique_no_crit_damage", 1.0, 1.0, "Deal no extra Critical Strike Damage"],
			["mana_regen_increased", 20.0, 100.0, "%d%% increased Mana Regeneration Rate"],
			["flat_intellect", 36.0, 36.0, "+%d to Intellect"],
		],
	},
	{
		"id": "armament_to_battle", "name": "Armament to Battle", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "gloves", "base_item": "res://data/armor/instances/gen_gloves_threshold_grips.tres", "weight": 100.0,
		"flavor": "Every wound you open is another reason to keep going.",
		"mods": [
			["flat_life", 50.0, 110.0, "+%d to Life"],
			["flat_strength", 10.0, 10.0, "+%d to Strength"],
			["unique_damage_per_ailment", 20.0, 20.0, "You have %d%% increased damage for each type of Ailment on an enemy"],
			["all_elemental_resistance", 10.0, 10.0, "+%d%% to all Elemental Resistances"],
		],
	},
	{
		"id": "bastille", "name": "Bastille", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "warded_barrier", "base_item": "res://data/shields/instances/gen_warded_barrier_bulwark_barrier.tres", "weight": 100.0,
		"flavor": "No gate has ever opened from the inside.",
		"mods": [
			["unique_armor_as_ward_on_block", 2.0, 2.0, "Gain %d%% of your Armour as Ward when you Block"],
			["increased_armor", 1000.0, 1000.0, "%d%% increased Armour"],
			["flat_ward", 150.0, 150.0, "+%d to Ward"],
			["cold_resistance", 20.0, 45.0, "+%d%% to Cold Resistance"],
			["fire_resistance", 10.0, 20.0, "+%d%% to Fire Resistance"],
		],
	},
	# ---- Corrupted only (Shard of Tharsis, Transcendent) ----
	{
		"id": "debt_of_tharsis", "name": "The Debt of Tharsis", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "any", "weight": 100.0, "corrupted_only": true,
		"flavor": "Everything you take from Tharsis, it takes back with interest.",
		"mods": [
			["magic_find", 20.0, 30.0, "+%d Magic Find"],
			["item_rarity", 25.0, 35.0, "%d%% increased Item Rarity"],
			["unique_damage_taken", 10.0, 10.0, "You take %d%% increased damage"],
		],
	},
]

static func get_def(id: String) -> Dictionary:
	for def in DEFS:
		if def["id"] == id:
			return def
	return {}

## Unique Slates: SlateRoller.roll() swaps one in for UNIQUE_SLATE_CHANCE of
## Slate drops (times Item Rarity, at most UNIQUE_SLATE_CHANCE_CAP). Modifiers
## are [stat_key, min, max, text] like gear uniques and reach the character
## through the Fate Board.
const UNIQUE_SLATE_CHANCE := 0.015
const UNIQUE_SLATE_CHANCE_CAP := 0.1
const SLATE_DEFS := [
	{
		"id": "brimming_edge", "name": "The Brimming Edge", "tag": Constants.DamageType.KINETIC, "weight": 100.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
		"flavor": "A full mind makes a heavy blade.",
		"mods": [["mana_as_weapon_damage", 4.0, 6.0, "Gain %d%% of your maximum Mana as added Weapon Damage"]],
	},
	{
		"id": "wellspring_codex", "name": "The Wellspring Codex", "tag": Constants.DamageType.AETHERIC, "weight": 100.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		"flavor": "Every page drinks from the same well.",
		"mods": [["mana_as_spell_damage", 4.0, 6.0, "Gain %d%% of your maximum Mana as added Spell Damage"]],
	},
	{
		"id": "mindward_seal", "name": "The Mindward Seal", "tag": Constants.DamageType.AETHERIC, "weight": 100.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		"flavor": "Let the blow land on thought instead of flesh.",
		"mods": [["damage_from_mana", 40.0, 40.0, "%d%% of Damage is taken from Mana before Life"]],
	},
]
