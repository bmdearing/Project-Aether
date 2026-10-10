extends RefCounted
class_name UniqueCatalog
## Every Unique and Mythic item. Each is a real base of `base_type` (an
## Item.get_item_type() key; the best base the drop level allows) with a
## fixed name, flavour and modifier list. A modifier is
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
		"base_type": "body_armour", "weight": 100.0,
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
		"base_type": "belt", "weight": 100.0,
		"flavor": "Every debt recorded. Every debt collected.",
		"mods": [
			["unique_debt", 15.0, 15.0, "Every hit you take is recorded as a Debt stack (up to 20). Your next hit while standing still consumes them, dealing %d%% of the recorded damage as Retaliation damage per stack"],
			["unique_reduced_damage_moving", 25.0, 25.0, "You deal %d%% less damage while moving"],
		],
	},
	{
		"id": "the_pale_eye", "name": "The Pale Eye", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "amulet", "weight": 100.0,
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
		"base_type": "claymore", "weight": 100.0, "damage_type": Constants.DamageType.AETHERIC, "grade_bonus": 1,
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
		"base_type": "ring", "weight": 100.0, "no_implicits": true,
		"flavor": "Every wish it grants, you already owned.",
		"mods": [
			["unique_reflect_ring", 1.0, 1.0, "Reflects the modifiers of your other Ring"],
		],
	},
	{
		"id": "sands_of_time", "name": "Sands of Time", "rarity": Constants.ItemRarity.MYTHIC,
		"base_type": "wand", "weight": 100.0, "boss": "ataras", "boss_chance": 0.02, "conduit_stance_type": "time_stop",
		"flavor": "He kept the last grain. Turn it over, and the world waits for you.",
		"mods": [
			["local_increased_cast_speed", 1.0, 100.0, "%d%% increased Cast Speed"],
			["local_increased_spell_damage", 200.0, 260.0, "%d%% increased Spell Damage"],
			["esoteric_resistance", 30.0, 35.0, "+%d%% Esoteric Resistance"],
			["life_increased", 10.0, 10.0, "%d%% increased Life"],
		],
	},
	# ---- Placeholders until the Unique design session ----
	{
		"id": "crown_of_the_ninth_bell", "name": "Crown of the Ninth Bell", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "helmet", "weight": 100.0,
		"flavor": "Eight bells for the hours. The ninth for whoever is still listening.",
		"mods": [
			["skill_level_spells", 2.0, 2.0, "+%d to Level of all Spells"],
			["max_mana", 30.0, 45.0, "+%d Mana"],
			["mana_cost_reduction", -50.0, -50.0, "Spells cost %d%% more Mana"],
		],
	},
	{
		"id": "hands_of_the_last_toll", "name": "Hands of the Last Toll", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "gloves", "weight": 100.0,
		"flavor": "Paid in full, every time.",
		"mods": [
			["attack_speed", 8.0, 12.0, "+%d%% increased Attack Speed"],
			["unique_life_on_kill", 3.0, 5.0, "Killing an enemy restores %d%% of your Maximum Life"],
			["unique_no_life_regen", 1.0, 1.0, "You have no Life Regeneration"],
		],
	},
	{
		"id": "stride_of_the_unwound", "name": "Stride of the Unwound", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "boots", "weight": 100.0,
		"flavor": "Stop, and the thread catches up with you.",
		"mods": [
			["move_speed", 20.0, 25.0, "+%d%% increased Move Speed"],
			["unique_more_damage_moving", 15.0, 20.0, "You deal %d%% more damage while moving"],
			["unique_no_ward_recovery_moving", 1.0, 1.0, "Your Ward does not recover while you are moving"],
		],
	},
	{
		"id": "seal_of_the_lesser_sun", "name": "Seal of the Lesser Sun", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "ring", "weight": 100.0,
		"flavor": "A small sun is still a sun.",
		"mods": [
			["unique_more_fire_damage", 20.0, 30.0, "%d%% more Fire damage"],
			["ailment_chance_ignite", 20.0, 20.0, "+%d%% chance to cause Ignite"],
			["cold_resistance_pct", -30.0, -30.0, "-%d%% to Cold Resistance"],
		],
	},
	{
		"id": "the_unpaid_wall", "name": "The Unpaid Wall", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "kite_shield", "weight": 100.0,
		"flavor": "The masons were never paid. The wall remembers.",
		"mods": [
			["block_chance_bonus", 8.0, 12.0, "+%d%% Block Chance"],
			["unique_ward_on_block", 10.0, 10.0, "Blocking restores %d%% of your Maximum Ward"],
			["unique_spell_damage_taken", 20.0, 20.0, "You take %d%% increased damage from Spells"],
		],
	},
	{
		"id": "widows_patience", "name": "Widow's Patience", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "crossbow", "weight": 100.0,
		"flavor": "She only ever needed the one.",
		"mods": [
			["unique_patient_shot", 40.0, 60.0, "Hits deal %d%% more damage if you haven't hit an enemy for 2 seconds"],
			["attack_speed", -25.0, -25.0, "%d%% reduced Attack Speed"],
		],
	},
	{
		"id": "butterfly", "name": "Butterfly", "rarity": Constants.ItemRarity.UNIQUE,
		"base_type": "crossbow", "weight": 100.0,
		"flavor": "Never where the blade expects. Always where the bolt lands.",
		"mods": [
			["unique_damage_from_move_speed", 60.0, 60.0, "Increases your damage by %d%% of your increased Movement Speed"],
			["move_speed", 15.0, 25.0, "+%d%% increased Movement Speed"],
			["attack_speed", 10.0, 15.0, "+%d%% increased Attack Speed"],
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
