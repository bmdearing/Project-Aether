extends Node
## One-shot data generator (Implementation Brief v3.9 Priority 2) - writes
## every weapon prefix/suffix from the Patch v3.9 "Weapon Affix Library"
## section into data/affixes/weapons/<type>/*.tres. Run headlessly via
## tools/generate_weapon_affixes.tscn, not part of the game itself.
##
## Every value_min/value_max/min_item_level below is transcribed directly
## from the doc's own Tier-1 column (its ONLY given tier - T2 and up are
## never given a number anywhere in the document). Per user direction
## (2026-09-06): do NOT invent the missing T2+ progression - ItemRoller's
## existing generic TIER_DECAY scaling (the same mechanism every AFFIX_POOL
## entry already uses) derives weaker rolls at lower item levels from this
## Tier-1 data alone, so no fabricated tier table is stored anywhere.
##
## affix_id doubles as stat_key - nothing mechanically consumes any of
## these yet (same "real data, no consumer yet" footing as flat_evasion/
## flat_resilience/skill_cooldown_reduced/crit_damage before this patch),
## so there's no separate naming scheme to invent; affix_id alone already
## guarantees the "no duplicate stat_keys" uniqueness ItemRoller needs.
##
## is_prefix follows this project's own established naming convention
## (already used by every suffix in this project - "of X"/"of the X") -
## the doc doesn't label its Base-Type Exclusive rows prefix/suffix
## explicitly, so those are classified the same way: "of ..." = suffix,
## everything else = prefix. Confirmed consistent with every one of the
## doc's own per-damage-type rows, which ARE explicitly split into
## "Prefixes"/"Suffixes" tables and match this same naming pattern 100%.
##
## weapon_type_filter for the two exclusive categories not tied to a
## specific base-type list (Conduit Only, Ranged Only) uses the real
## conduit/ranged weapon type keys already established in tools/
## repair_item_requirements.gd's WEAPON_STAT_MAP (single-Resolve entries
## for conduits, single-Finesse gun/bow entries for ranged) rather than
## inventing a new boolean-property filter mechanism ItemAffix doesn't have.

const OUT_ROOT := "res://data/affixes/weapons/"

const CONDUIT_TYPES := ["wand", "staff", "athame", "spell_gauntlet", "gauntlet", "rod", "grimoire", "tome", "talisman", "fetish"]
const RANGED_TYPES := ["shortbow", "longbow", "service_pistol", "revolver", "machine_pistol", "submachine_gun",
	"lever_action_rifle", "bolt_action_rifle", "crossbow", "loaded_shotgun", "pump_action_shotgun", "machine_gun", "battle_rifle"]

## Each entry: [affix_id, display_name, description, is_prefix, value_min, value_max, min_item_level, weapon_type_filter]
## damage_type/is_generic/dir are supplied per-section below, not per-row.
##
## description is a TEMPLATE (bug fix 2026-09-07, user-reported: rolled
## items were showing "(Tier N)" with no actual number at all) - exactly
## one %d or %.1f placeholder, substituted with the rolled value by
## ItemRoller._roll_weapon_affixes() the same way the OLD AFFIX_POOL's
## own "desc" dict entries already work ("+%d Prowess" % round(value)).
## %.1f only for the two Critical Strike Chance affixes (3.5-4.5%%, doc-
## exact decimal precision); every other value rounds to a whole number,
## matching this project's existing display convention everywhere else.
const SECTIONS := [
	{"dir": "kinetic", "damage_type": Constants.DamageType.KINETIC, "is_generic": false, "rows": [
		["kinetic_impacting", "Impacting", "%d%% increased Kinetic damage", true, 46.0, 50.0, 80, []],
		["kinetic_pulverising", "Pulverising", "%d%% increased Armor Shred effectiveness", true, 38.0, 44.0, 76, []],
		["kinetic_forceful", "Forceful", "Adds %d flat Kinetic damage to attacks", true, 28.0, 42.0, 78, []],
		["kinetic_hammering", "Hammering", "%d%% increased damage against Staggered enemies", true, 34.0, 40.0, 74, []],
		["kinetic_concussive", "Concussive", "%d%% chance to Stagger on hit", true, 22.0, 26.0, 72, []],
		["kinetic_of_the_ironhand", "of the Ironhand", "+%d Prowess", false, 24.0, 30.0, 1, []],
		["kinetic_of_rending", "of Rending", "%d%% increased Attack Speed", false, 14.0, 16.0, 1, []],
		["kinetic_of_the_bruiser", "of the Bruiser", "Gain %d Life on hit", false, 14.0, 18.0, 1, []],
	]},
	{"dir": "piercing", "damage_type": Constants.DamageType.PIERCING, "is_generic": false, "rows": [
		["piercing_lancing", "Lancing", "%d%% increased Piercing damage", true, 46.0, 50.0, 80, []],
		["piercing_serrated", "Serrated", "%d%% increased Bleed damage", true, 38.0, 44.0, 76, []],
		["piercing_barbed", "Barbed", "%d%% increased Bleed duration", true, 38.0, 44.0, 72, []],
		["piercing_penetrating", "Penetrating", "Piercing attacks ignore %d%% of enemy Armor", true, 30.0, 35.0, 76, []],
		["piercing_haemorrhaging", "Haemorrhaging", "%d%% chance to apply Bleed on hit", true, 28.0, 34.0, 70, []],
		["piercing_of_the_duelist", "of the Duelist", "+%d Finesse", false, 24.0, 30.0, 1, []],
		["piercing_of_precision", "of Precision", "+%.1f%% Critical Strike Chance", false, 3.5, 4.5, 1, []],
		["piercing_of_the_bleeder", "of the Bleeder", "Bleed deals damage %d%% faster", false, 34.0, 40.0, 1, []],
	]},
	{"dir": "explosive", "damage_type": Constants.DamageType.EXPLOSIVE, "is_generic": false, "rows": [
		["explosive_detonating", "Detonating", "%d%% increased Explosive damage", true, 46.0, 50.0, 80, []],
		["explosive_concussive", "Concussive", "%d%% increased AoE radius", true, 34.0, 40.0, 72, []],
		["explosive_volatile", "Volatile", "Explosions have %d%% chance to Stun", true, 22.0, 28.0, 72, []],
		["explosive_shrapnel", "Shrapnel", "Explosions leave a Bleed zone for 2 seconds (%d%% per second)", true, 18.0, 22.0, 74, []],
		["explosive_incendiary", "Incendiary", "Explosions apply Ignite (%d%% chance)", true, 28.0, 34.0, 70, []],
		["explosive_of_the_wrecker", "of the Wrecker", "+%d Prowess", false, 24.0, 30.0, 1, []],
		["explosive_of_detonation", "of Detonation", "%d%% reduced skill cooldowns", false, 14.0, 18.0, 1, []],
		["explosive_of_impact", "of Impact", "%d Ward gained on kill", false, 22.0, 28.0, 1, []],
	]},
	{"dir": "fire", "damage_type": Constants.DamageType.FIRE, "is_generic": false, "rows": [
		["fire_scorching", "Scorching", "%d%% increased Fire damage", true, 46.0, 50.0, 80, []],
		["fire_incendiary", "Incendiary", "%d%% increased Ignite damage", true, 38.0, 44.0, 76, []],
		["fire_kindling", "Kindling", "%d%% increased Ignite duration", true, 38.0, 44.0, 70, []],
		["fire_pyretic", "Pyretic", "%d%% increased damage against Ignited enemies", true, 34.0, 40.0, 74, []],
		["fire_immolating", "Immolating", "%d%% chance to Ignite on hit", true, 28.0, 34.0, 70, []],
		["fire_of_the_calcine", "of the Calcine", "+%d Resolve", false, 24.0, 30.0, 1, []],
		["fire_of_conflagration", "of Conflagration", "%d%% increased Cast Speed", false, 18.0, 22.0, 1, []],
		["fire_of_the_pyre", "of the Pyre", "Gain %d Mana on Ignite application", false, 8.0, 12.0, 1, []],
	]},
	{"dir": "cold", "damage_type": Constants.DamageType.COLD, "is_generic": false, "rows": [
		["cold_glacial", "Glacial", "%d%% increased Cold damage", true, 46.0, 50.0, 80, []],
		["cold_biting", "Biting", "%d%% increased Chill effect magnitude", true, 34.0, 40.0, 74, []],
		["cold_crystallising", "Crystallising", "%d%% reduced Freeze threshold", true, 28.0, 34.0, 78, []],
		["cold_brittle", "Brittle", "%d%% increased damage against Chilled enemies", true, 34.0, 40.0, 74, []],
		["cold_freezing", "Freezing", "%d%% chance to apply Chill on hit", true, 34.0, 40.0, 68, []],
		["cold_of_the_quench", "of the Quench", "+%d Resolve", false, 24.0, 30.0, 1, []],
		["cold_of_permafrost", "of Permafrost", "%d%% increased Chill duration", false, 38.0, 44.0, 1, []],
		["cold_of_the_frost", "of the Frost", "%d Ward gained on Chill application", false, 16.0, 22.0, 1, []],
	]},
	{"dir": "lightning", "damage_type": Constants.DamageType.LIGHTNING, "is_generic": false, "rows": [
		["lightning_arcing", "Arcing", "%d%% increased Lightning damage", true, 46.0, 50.0, 80, []],
		["lightning_crackling", "Crackling", "%d%% increased Electrocute duration", true, 38.0, 44.0, 74, []],
		["lightning_galvanised", "Galvanised", "%d%% increased Shock damage bonus (more effective)", true, 34.0, 40.0, 72, []],
		["lightning_conducting", "Conducting", "%d%% increased damage against Shocked enemies", true, 34.0, 40.0, 74, []],
		["lightning_discharging", "Discharging", "%d%% chance to apply Shock on hit", true, 28.0, 34.0, 68, []],
		["lightning_of_the_galvanic", "of the Galvanic", "+%d Resolve", false, 24.0, 30.0, 1, []],
		["lightning_of_static", "of Static", "%d%% increased Attack Speed", false, 14.0, 16.0, 1, []],
		["lightning_of_conductance", "of Conductance", "%d Mana on Electrocute application", false, 10.0, 14.0, 1, []],
	]},
	{"dir": "aetheric", "damage_type": Constants.DamageType.AETHERIC, "is_generic": false, "rows": [
		["aetheric_aetheric", "Aetheric", "%d%% increased Aetheric damage", true, 46.0, 50.0, 80, []],
		["aetheric_unmaking", "Unmaking", "%d%% increased Aetherburn damage", true, 38.0, 44.0, 76, []],
		["aetheric_consuming", "Consuming", "Hits drain %d%% of target's max Ward on hit", true, 8.0, 10.0, 74, []],
		["aetheric_eroding", "Eroding", "%d%% increased damage vs Aetherburn enemies", true, 34.0, 40.0, 72, []],
		["aetheric_devouring", "Devouring", "%d%% chance to apply Aetherburn on hit", true, 22.0, 28.0, 70, []],
		["aetheric_of_the_invoke", "of the Invoke", "+%d Resolve", false, 24.0, 30.0, 1, []],
		["aetheric_of_the_veil", "of the Veil", "%d%% of max Ward restored on kill", false, 6.0, 8.0, 1, []],
		["aetheric_of_resonance", "of Resonance", "%d%% increased Aether capacity", false, 18.0, 22.0, 1, []],
	]},
	{"dir": "entropic", "damage_type": Constants.DamageType.ENTROPIC, "is_generic": false, "rows": [
		["entropic_entropic", "Entropic", "%d%% increased Entropic damage", true, 46.0, 50.0, 80, []],
		["entropic_unraveling", "Unraveling", "%d%% increased Unraveling effectiveness", true, 34.0, 40.0, 74, []],
		["entropic_decaying", "Decaying", "%d%% increased damage vs Unraveled enemies", true, 38.0, 44.0, 76, []],
		["entropic_dissolving", "Dissolving", "Unraveled enemies deal %d%% reduced damage", true, 12.0, 16.0, 74, []],
		["entropic_fraying", "Fraying", "%d%% chance to apply Unraveling on hit", true, 22.0, 28.0, 68, []],
		["entropic_of_efface", "of Efface", "+%d Resolve", false, 24.0, 30.0, 1, []],
		["entropic_of_collapse", "of Collapse", "%d%% increased Critical Strike damage", false, 38.0, 44.0, 1, []],
		["entropic_of_dissolution", "of Dissolution", "%d Mana gained on kill", false, 14.0, 18.0, 1, []],
	]},
	{"dir": "pale", "damage_type": Constants.DamageType.PALE, "is_generic": false, "rows": [
		["pale_pallid", "Pallid", "%d%% increased Pale damage", true, 46.0, 50.0, 80, []],
		["pale_hollowing", "Hollowing", "%d%% increased Pallid effectiveness", true, 34.0, 40.0, 74, []],
		["pale_threshold", "Threshold", "%d%% increased damage vs Pallid enemies", true, 38.0, 44.0, 76, []],
		["pale_withering", "Withering", "Pallid enemies take %d%% increased damage from all sources", true, 12.0, 16.0, 74, []],
		["pale_draining", "Draining", "%d%% chance to apply Pallid on hit", true, 22.0, 28.0, 68, []],
		["pale_of_the_hollow", "of the Hollow", "+%d Resolve", false, 24.0, 30.0, 1, []],
		["pale_of_fading", "of Fading", "%d%% increased Ward Threshold", false, 18.0, 22.0, 1, []],
		["pale_of_the_threshold", "of the Threshold", "%d Ward on Pallid application", false, 18.0, 24.0, 1, []],
	]},
	{"dir": "generic", "damage_type": -1, "is_generic": true, "rows": [
		["generic_savage", "Savage", "%d%% increased damage (generic - does not travel through conversion chains)", true, 34.0, 38.0, 80, []],
		["generic_deadly", "Deadly", "%d%% increased Critical Strike damage", true, 38.0, 44.0, 78, []],
		["generic_fluid", "Fluid", "%d%% increased Attack Speed", true, 14.0, 16.0, 74, []],
		["generic_opportunist", "Opportunist", "%d%% increased damage vs full-health enemies (first hit only per enemy)", true, 44.0, 52.0, 70, []],
		["generic_relentless", "Relentless", "%d%% increased damage vs enemies below 35%% health", true, 34.0, 40.0, 72, []],
		["generic_of_prowess", "of Prowess", "+%d Prowess", false, 24.0, 30.0, 1, []],
		["generic_of_finesse", "of Finesse", "+%d Finesse", false, 24.0, 30.0, 1, []],
		["generic_of_resolve", "of Resolve", "+%d Resolve", false, 24.0, 30.0, 1, []],
		["generic_of_the_sharp", "of the Sharp", "+%.1f%% Critical Strike Chance", false, 3.5, 4.5, 1, []],
		["generic_of_conservation", "of Conservation", "Skills cost %d%% less Mana", false, 12.0, 14.0, 1, []],
		["generic_of_the_ward", "of the Ward", "Gain %d Ward on hit", false, 18.0, 24.0, 1, []],
	]},
	{"dir": "exclusive", "damage_type": -1, "is_generic": false, "rows": [
		["excl_riposte_edge", "Riposte's Edge", "%d%% increased Riposte damage (Rapier/Saber only)", true, 54.0, 64.0, 76, ["rapier", "saber"]],
		["excl_of_the_counterstrike", "of the Counterstrike", "Riposte deals bonus damage equal to %d%% of triggering hit (Rapier/Saber only)", false, 18.0, 22.0, 72, ["rapier", "saber"]],
		["excl_assassins_mark", "Assassin's Mark", "%d%% increased damage against unaware enemies (Dagger only)", true, 64.0, 76.0, 74, ["dagger"]],
		["excl_of_the_shadow", "of the Shadow", "%d%% increased Stealth duration (Dagger only)", false, 44.0, 52.0, 68, ["dagger"]],
		["excl_shattering", "Shattering", "%d%% increased Stagger effect (Mace/War Pick/Pressure Fist only)", true, 44.0, 52.0, 74, ["mace", "war_pick", "pressure_fist"]],
		["excl_of_the_colossus", "of the Colossus", "Staggered enemies take %d%% increased damage (Mace/War Pick/Pressure Fist only)", false, 28.0, 34.0, 72, ["mace", "war_pick", "pressure_fist"]],
		["excl_of_warding", "of Warding", "%d%% increased Block Threshold (all shields)", false, 28.0, 34.0, 74, ["tower_shield", "great_shield", "kite_shield", "pavise", "rune_shield", "warded_barrier", "buckler", "spiked_shield"]],
		["excl_retaliating", "Retaliating", "%d%% increased Retaliation damage (Spiked Shield and Buckler only)", true, 44.0, 52.0, 70, ["spiked_shield", "buckler"]],
		["excl_channelers", "Channeler's", "%d%% increased Spell damage (Conduit only)", true, 34.0, 40.0, 76, CONDUIT_TYPES],
		["excl_of_the_weave", "of the Weave", "%d%% reduced Mana cost of spells (Conduit only)", false, 16.0, 20.0, 70, CONDUIT_TYPES],
		["excl_resonant", "Resonant", "+%d%% Cooldown Recovery Rate (Conduit only)", true, 18.0, 22.0, 72, CONDUIT_TYPES],
		["excl_marksmans", "Marksman's", "%d%% increased Critical Strike damage (ranged only)", true, 54.0, 64.0, 74, RANGED_TYPES],
		["excl_of_the_hunt", "of the Hunt", "%d%% increased damage vs full-health enemies (ranged only)", false, 54.0, 64.0, 70, RANGED_TYPES],
	]},
]

var _written := 0

func _ready() -> void:
	for section in SECTIONS:
		var dir_path: String = OUT_ROOT + section["dir"] + "/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		for row in section["rows"]:
			_write_affix(dir_path, row, section["damage_type"], section["is_generic"])
	print("Generated %d weapon affix .tres files under %s" % [_written, OUT_ROOT])
	get_tree().quit()

func _write_affix(dir_path: String, row: Array, damage_type: int, is_generic: bool) -> void:
	var affix := ItemAffix.new()
	affix.affix_id = row[0]
	affix.display_name = row[1]
	affix.description = row[2]
	affix.is_prefix = row[3]
	affix.value_min = row[4]
	affix.value_max = row[5]
	affix.value = row[4]
	affix.min_item_level = row[6]
	var filter: Array[String] = []
	for t in row[7]:
		filter.append(t)
	affix.weapon_type_filter = filter
	affix.stat_key = row[0]
	affix.damage_type = damage_type
	affix.is_generic = is_generic

	var path: String = dir_path + row[0] + ".tres"
	if ResourceSaver.save(affix, path) == OK:
		_written += 1
	else:
		push_error("Failed to save %s" % path)
