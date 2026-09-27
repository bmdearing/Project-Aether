extends Node
class_name EquipmentComponent
## Holds a full gear loadout per Section 13 Equipment Slots. Attach to
## Player (or any future equippable actor) - same pattern as
## HealthComponent/WardComponent. compute_stat_bonuses() aggregates
## flat_<stat> affixes (see ItemRoller.gd) into the three core stats.
## Slate stat contributions sum in separately - see ChainCalculator.
## slate_stat_bonuses(), which reuses AFFIX_STAT_KEYS below so a Slate
## modifier's stat_key means exactly what a gear affix's does.

@export var helmet: Armor
@export var body_armour: Armor
@export var gloves: Armor
@export var boots: Armor

## Implementation Brief v3.4 Section 4, user-expanded scope ("build a real
## tap X to swap to a second weapon set. Let players have 2 sets of a main
## hand/off hand weapon."): two full weapon sets (primary/offhand each),
## index 0 or 1 per slot - same small-fixed-array shape `rings` below
## already uses rather than inventing a `_2`-suffixed duplicate field per
## slot. primary_weapon/offhand below are COMPUTED properties reading/
## writing whichever index active_weapon_set points at, so every existing
## caller (get_active_weapon(), get_total_armor(), compute_ward_bonus(),
## get_all_equipped_items(), equip()'s own two-handed-conflict checks,
## etc.) keeps working unchanged.
##
## Patch v3.5: sidearm dropped from each set (was primary/sidearm/offhand,
## now just primary/offhand) - Sidearm-typed weapons now equip into
## Primary or Offhand like anything else, per Weapon.is_main_hand/
## is_offhand. `offhands` holds either a Shield or an offhand-type Weapon
## (Rod/Tome/etc.) - typed Item, not Shield, to allow both.
@export var primary_weapons: Array[Weapon] = [null, null]
@export var offhands: Array[Item] = [null, null]
@export var active_weapon_set: int = 0

var primary_weapon: Weapon:
	get: return primary_weapons[active_weapon_set]
	set(value): primary_weapons[active_weapon_set] = value
var offhand: Item:
	get: return offhands[active_weapon_set]
	set(value): offhands[active_weapon_set] = value

@export var amulet: Item
@export var belt: Item
@export var rings: Array[Item] = [null, null]

signal equip_failed(reason: String)
## Fired on every successful equip()/unequip() (not rejected paths) -
## Player.gd recomputes stat bonuses and visuals on this.
signal equipment_changed
## Fired by toggle_weapon_set() specifically - equipment_changed also
## fires alongside it (visuals/stats need the same refresh a normal
## equip/unequip triggers), this one's for UI that only cares about WHICH
## set is active (InventoryScreen's Set A/B indicator).
signal weapon_set_changed(new_set: int)

const WEAPON_SET_SLOTS := [
	Constants.EquipmentSlot.PRIMARY_WEAPON,
	Constants.EquipmentSlot.OFFHAND,
]

## Tap-to-swap (Player._handle_weapon_swap_input()) and the InventoryScreen
## Set A/B button both call this - one shared place so both stay in sync.
func toggle_weapon_set() -> void:
	active_weapon_set = 1 if active_weapon_set == 0 else 0
	weapon_set_changed.emit(active_weapon_set)
	equipment_changed.emit()

## Only Player currently instances this despite the "any future equippable
## actor" framing above - level/stat requirement checks (2026-08-30) need
## somewhere to read player_level/stat_sheet from, and Player is the only
## real candidate today.
@onready var _player: Player = get_parent()

## Non-weapon items route by item.equip_slot; a Weapon routes by its own
## is_main_hand/is_offhand instead (Patch v3.5 - Sidearm/Conduit are gone
## as separate slots). Two-handed primary weapons clear the offhand slot
## per Section 13 ("Two-Handed Weapon occupies both weapon slots"). RING
## uses the first open ring slot, or slot 0 if all full.
##
## bypass_requirements: true only for Player._apply_saved_loadout()
## restoring a previous session's save - a save should always restore
## cleanly (silently stripping a slot the player already legitimately
## equipped, just because a later balance change or a level-up-in-reverse
## edge case put it out of reach, would be a real regression, not correct
## gating). A live player-initiated equip (inventory click, GearShop
## purchase) always leaves this at its default false.
##
## weapon_set: -1 (default) targets whichever set is currently active -
## every normal gameplay equip (inventory click, loot pickup) means "put
## this in what I'm using right now." Only InventoryScreen's explicit
## "equip into the OTHER set" UI passes 0/1 directly, and only
## Player._apply_saved_loadout() restoring weapon_set_refs passes both in
## turn regardless of which is active at restore time. Ignored entirely
## for non-weapon slots.
func equip(item: Item, bypass_requirements: bool = false, weapon_set: int = -1) -> void:
	if item == null:
		return
	if not bypass_requirements:
		var block_reason := _requirement_block_reason(item)
		if block_reason != "":
			push_warning(block_reason)
			equip_failed.emit(block_reason)
			return
	var set_index := active_weapon_set if weapon_set == -1 else weapon_set
	if item is Weapon:
		_equip_weapon(item as Weapon, set_index)
		return
	match item.equip_slot:
		Constants.EquipmentSlot.HELMET: helmet = item as Armor
		Constants.EquipmentSlot.BODY_ARMOUR: body_armour = item as Armor
		Constants.EquipmentSlot.GLOVES: gloves = item as Armor
		Constants.EquipmentSlot.BOOTS: boots = item as Armor
		Constants.EquipmentSlot.OFFHAND:
			if primary_weapons[set_index] and primary_weapons[set_index].is_two_handed:
				var reason := "Cannot equip an offhand while a two-handed weapon is equipped."
				push_warning(reason)
				equip_failed.emit(reason)
				return
			offhands[set_index] = item
		Constants.EquipmentSlot.AMULET: amulet = item
		Constants.EquipmentSlot.BELT: belt = item
		Constants.EquipmentSlot.RING: _equip_ring(item)
	equipment_changed.emit()

func _equip_weapon(weapon: Weapon, set_index: int) -> void:
	if weapon.is_offhand:
		if primary_weapons[set_index] and primary_weapons[set_index].is_two_handed:
			var reason := "Cannot equip an offhand while a two-handed weapon is equipped."
			push_warning(reason)
			equip_failed.emit(reason)
			return
		offhands[set_index] = weapon
	else:
		primary_weapons[set_index] = weapon
		if weapon.is_two_handed:
			offhands[set_index] = null
	equipment_changed.emit()

## weapon_set: same meaning as equip()'s own param - which set's slot to
## clear for PRIMARY_WEAPON/OFFHAND, ignored otherwise.
func unequip(slot: Constants.EquipmentSlot, ring_index: int = 0, weapon_set: int = -1) -> void:
	var set_index := active_weapon_set if weapon_set == -1 else weapon_set
	match slot:
		Constants.EquipmentSlot.HELMET: helmet = null
		Constants.EquipmentSlot.BODY_ARMOUR: body_armour = null
		Constants.EquipmentSlot.GLOVES: gloves = null
		Constants.EquipmentSlot.BOOTS: boots = null
		Constants.EquipmentSlot.PRIMARY_WEAPON: primary_weapons[set_index] = null
		Constants.EquipmentSlot.OFFHAND: offhands[set_index] = null
		Constants.EquipmentSlot.AMULET: amulet = null
		Constants.EquipmentSlot.BELT: belt = null
		Constants.EquipmentSlot.RING:
			if ring_index >= 0 and ring_index < rings.size():
				rings[ring_index] = null
	equipment_changed.emit()

## Read counterpart to equip()/unequip()'s routing, so callers (UI) don't
## need 15 bespoke field accesses. weapon_set: same meaning as equip()'s.
func get_equipped(slot: Constants.EquipmentSlot, ring_index: int = 0, weapon_set: int = -1) -> Item:
	var set_index := active_weapon_set if weapon_set == -1 else weapon_set
	match slot:
		Constants.EquipmentSlot.HELMET: return helmet
		Constants.EquipmentSlot.BODY_ARMOUR: return body_armour
		Constants.EquipmentSlot.GLOVES: return gloves
		Constants.EquipmentSlot.BOOTS: return boots
		Constants.EquipmentSlot.PRIMARY_WEAPON: return primary_weapons[set_index]
		Constants.EquipmentSlot.OFFHAND: return offhands[set_index]
		Constants.EquipmentSlot.AMULET: return amulet
		Constants.EquipmentSlot.BELT: return belt
		Constants.EquipmentSlot.RING:
			return rings[ring_index] if ring_index >= 0 and ring_index < rings.size() else null
	return null

## Same shape as get_total_evasion(): base armor_value per slot, plus
## flat_armor affixes from any equipped item, times any increased_armor.
func get_total_armor() -> float:
	var total := 0.0
	if helmet: total += helmet.armor_value
	if body_armour: total += body_armour.armor_value
	if gloves: total += gloves.armor_value
	if boots: total += boots.armor_value
	if offhand is Shield: total += (offhand as Shield).armor_value
	var affixes := compute_misc_bonuses()
	var flat: float = affixes.get("flat_armor", 0.0)
	var increased: float = affixes.get("increased_armor", 0.0) / 100.0
	return (total + flat) * (1.0 + increased)

## Patch v4.4. Gear's Evasion: every equipped Armor/Shield's evasion_value,
## plus flat_evasion affixes from any equipped item, times any
## increased_evasion. extra_increased is Agility's +1%/point (a fraction,
## passed in by StatSheet.get_total_evasion()) - same increased% bracket.
func get_total_evasion(extra_increased: float = 0.0) -> float:
	var base := 0.0
	if helmet: base += helmet.evasion_value
	if body_armour: base += body_armour.evasion_value
	if gloves: base += gloves.evasion_value
	if boots: base += boots.evasion_value
	if offhand is Shield: base += (offhand as Shield).evasion_value
	var affixes := compute_misc_bonuses()
	var flat: float = affixes.get("flat_evasion", 0.0)
	var increased: float = affixes.get("increased_evasion", 0.0) / 100.0 + extra_increased
	return (base + flat) * (1.0 + increased)

## Patch v3.2: "Ward pool size scales through gear rolls." Two real
## sources sum together: each equipped Armor/Shield's own base
## `ward_value` (Section 25's doc-sourced "Base Ward" column - same
## mechanical treatment get_total_armor() already gives armor_value; added
## 2026-08-30 after a user bug report that Ward "isn't actually being
## applied anymore" - the Section 25 generator gave ~170 armor pieces a
## real, prominent ward_value that this method was silently ignoring,
## reading only the separate, much rarer rolled flat_ward AFFIX) plus any
## flat_ward affixes rolled onto ANY equipped item (existed since
## ItemRoller.AFFIX_POOL's first pass, purely descriptive per README gap
## #18 until Patch v3.2 gave Ward a real formula to feed).
func compute_ward_bonus() -> float:
	var total := 0.0
	if helmet: total += helmet.ward_value
	if body_armour: total += body_armour.ward_value
	if gloves: total += gloves.ward_value
	if boots: total += boots.ward_value
	if offhand is Shield: total += (offhand as Shield).ward_value
	for item in get_all_equipped_items():
		for affix in item.affixes:
			if affix.stat_key == "flat_ward":
				total += affix.value
	return total

## Restore-descriptor per equipped item for GameState.sync_equipment() -
## a resource_path String, or an ItemSerializer Dictionary for rolled
## items (no resource_path to save as a path). Excludes primary_weapon and
## offhand (whichever ACTIVE set they belong to) - a flat "everything
## currently equipped" list has no way to represent an INACTIVE weapon
## set's own items, so both persist separately per set instead, see
## get_weapon_set_refs()/GameState.weapon_set_refs. Checked by reference
## (`==`), not equip_slot - a Weapon's equip_slot is no longer the routing
## source of truth (see equip()'s own is_offhand check), so it can't be
## trusted to reliably mark "this is set-tracked," and an offhand Shield
## needs the same per-set treatment as an offhand Weapon.
func get_all_equipped_refs() -> Array:
	var refs: Array = []
	for item in get_all_equipped_items():
		if item == primary_weapon or item == offhand:
			continue
		refs.append(_ref_for(item))
	return refs

## Refs for ONE weapon set's own primary/offhand (nulls skipped) - the
## counterpart get_all_equipped_refs() deliberately excludes, called once
## per set index by GameState.sync_weapon_sets().
func get_weapon_set_refs(set_index: int) -> Array:
	var items: Array = [primary_weapons[set_index], offhands[set_index]]
	var refs: Array = []
	for item in items:
		if item:
			refs.append(_ref_for(item))
	return refs

## Not the only source of stat growth anymore - FateBoard.
## compute_stat_bonuses() reuses this same dict for Slate modifiers'
## stat_key (plus the level bonus, see StatSheet.level_bonus).
const AFFIX_STAT_KEYS := {
	"flat_strength": Constants.Stat.STRENGTH,
	"flat_agility": Constants.Stat.AGILITY,
	"flat_intellect": Constants.Stat.INTELLECT,
}

func compute_stat_bonuses() -> Dictionary:
	var totals := {}
	for item in get_all_equipped_items():
		for affix in item.affixes:
			if AFFIX_STAT_KEYS.has(affix.stat_key):
				var stat: Constants.Stat = AFFIX_STAT_KEYS[affix.stat_key]
				totals[stat] = totals.get(stat, 0.0) + affix.value
	return totals

## Patch v3.2 "Revision - Resistance System": fire_resistance_pct/
## cold_resistance_pct/lightning_resistance_pct/esoteric_resistance_pct
## (ItemRoller.AFFIX_POOL) sum straight into a percent per type - keys
## match StatSheet.resistance_key_for()'s own "fire"/"cold"/"lightning"/
## "esoteric" strings.
## Patch v4.0 added a second, "_pct"-less naming for the same 4 resistance
## buckets (fire_resistance vs the original fire_resistance_pct, etc.) as
## part of its Defensive Mod Pool - both map to the same "fire"/"cold"/
## "lightning"/"esoteric" keys rather than the new names replacing the
## old ones outright, so the 4 existing named rings' hand-authored
## implicits (still using the old "_pct" keys) don't need a risky data
## migration to keep working.
const RESISTANCE_AFFIX_KEYS := {
	"fire_resistance_pct": "fire",
	"cold_resistance_pct": "cold",
	"lightning_resistance_pct": "lightning",
	"esoteric_resistance_pct": "esoteric",
	"fire_resistance": "fire",
	"cold_resistance": "cold",
	"lightning_resistance": "lightning",
	"esoteric_resistance": "esoteric",
}

## Patch v4.0 "+% to all Elemental Resistances" - Elemental means Fire/
## Cold/Lightning only (Constants.DamageCategory.ELEMENTAL), NOT Esoteric,
## so this adds to all three of those buckets at once rather than being a
## 1:1 RESISTANCE_AFFIX_KEYS entry.
const ALL_ELEMENTAL_RESISTANCE_KEY := "all_elemental_resistance"

func compute_resistance_bonuses() -> Dictionary:
	var totals := {}
	for item in get_all_equipped_items():
		for affix in item.affixes:
			if RESISTANCE_AFFIX_KEYS.has(affix.stat_key):
				var key: String = RESISTANCE_AFFIX_KEYS[affix.stat_key]
				totals[key] = totals.get(key, 0.0) + affix.value
			elif affix.stat_key == ALL_ELEMENTAL_RESISTANCE_KEY:
				for key in ["fire", "cold", "lightning"]:
					totals[key] = totals.get(key, 0.0) + affix.value
	return totals

## Patch v3.8 Section 2 "Removed expressions" - max_life/life_regen/
## max_mana/mana_regen/resilience/cast_speed used to derive from a
## character stat, now purely gear-affix-driven (same shape as
## compute_resistance_bonuses() above, just a different key set). flat_
## resilience already existed (pre-v3.8, previously descriptive-only);
## the rest are new ItemRoller.AFFIX_POOL entries added alongside this.
## Patch v4.0 "Full Mod Pool Framework" - every new stat_key routes
## through this SAME existing misc_bonus mechanism rather than ~50 new
## individual StatSheet fields (the brief's own literal ask) - several of
## its own listed stat_keys (attack_speed, cast_speed, cooldown_recovery_
## rate, flat_armor, flat_evasion, flat_ward) are ALREADY real, working
## keys under this exact mechanism; adding parallel dedicated fields for
## those would either silently double-count them or fork into two
## divergent, easy-to-desync code paths for the same effect. See
## StatSheet.gd's own new v4.0 section for the few stat_keys needing
## real combination logic (per-ailment, per-damage-type, resistance
## unification) - those get thin getter methods instead of bespoke fields.
## Section 09-style status effect ids and the 9 damage types, spelled out
## directly below (Ailment Build's 8 x 3 per-ailment keys, Amulet
## Exclusive's 9 x 2 per-damage-type skill_level keys) - GDScript consts
## can't be built by calling a function, so no programmatic loop here.
const AILMENT_IDS := ["bleed", "ignite", "chill", "electrocute", "shock", "aetherburn", "unraveling", "pallid"]
const V40_DAMAGE_TYPE_KEYS := ["kinetic", "piercing", "explosive", "fire", "cold", "lightning", "aetheric", "entropic", "pale"]

const MISC_BONUS_KEYS := [
	"block_chance_bonus",
	"flat_armor",  # see get_total_armor() - had to be listed here or compute_misc_bonuses() dropped it, same as flat_evasion
	"flat_evasion",  # Patch v4.4 - see get_total_evasion(). NOT summed anywhere before this: v4.0's note calling it "already real" was wrong
	"max_life", "life_regen", "max_mana", "mana_regen",
	"flat_resilience", "cast_speed", "attack_speed", "move_speed",
	"crit_damage",
	# Patch v4.0 Ailment Build Mod Pool
	"dot_multiplier", "ailment_tick_rate", "ailment_ignore_chance",
	"ailment_chance_bleed", "increased_ailment_damage_bleed", "increased_ailment_duration_bleed",
	"ailment_chance_ignite", "increased_ailment_damage_ignite", "increased_ailment_duration_ignite",
	"ailment_chance_chill", "increased_ailment_damage_chill", "increased_ailment_duration_chill",
	"ailment_chance_electrocute", "increased_ailment_damage_electrocute", "increased_ailment_duration_electrocute",
	"ailment_chance_shock", "increased_ailment_damage_shock", "increased_ailment_duration_shock",
	"ailment_chance_aetherburn", "increased_ailment_damage_aetherburn", "increased_ailment_duration_aetherburn",
	"ailment_chance_unraveling", "increased_ailment_damage_unraveling", "increased_ailment_duration_unraveling",
	"ailment_chance_pallid", "increased_ailment_damage_pallid", "increased_ailment_duration_pallid",
	# Patch v4.0 Physical Hit Build Mod Pool
	"increased_physical_damage", "crit_chance_increased", "crit_damage_increased",
	# Patch v4.0 Spell Hit Build Mod Pool
	"increased_spell_damage", "skill_effect_duration", "mana_cost_reduction", "cooldown_recovery_rate",
	# Patch v4.0 Ranged Build Mod Pool
	"increased_aoe_radius", "increased_area_damage", "projectile_speed", "reduced_projectile_speed",
	# Patch v4.0 Parry/Riposte Build Mod Pool
	"parry_window_duration", "ward_on_parry", "increased_riposte_damage", "riposte_crit_chance",
	# Patch v4.0 Healing/Sustain Mod Pool
	"life_regen_flat", "life_regen_increased", "flat_life", "life_increased",
	"mana_regen_increased", "flat_mana", "mana_increased", "ward_recovery_increased",
	# Patch v4.0 Offensive Mod Pool
	"fire_penetration", "cold_penetration", "lightning_penetration", "elemental_penetration", "physical_shred",
	# Patch v4.0 Retaliation Mod Pool
	"increased_retaliation_damage", "retaliate_on_block",
	# Patch v4.0 Defensive Mod Pool
	"reduced_physical_taken", "reduced_elemental_taken", "reduced_esoteric_taken", "ward_delay_reduction",
	"armor_to_elemental", "evasion_to_spells", "dash_speed", "damage_from_mana",
	"phys_as_fire", "phys_as_cold", "phys_as_lightning",
	# fire_resistance/cold_resistance/lightning_resistance/esoteric_resistance/
	# all_elemental_resistance are NOT here - they route through
	# RESISTANCE_AFFIX_KEYS/compute_resistance_bonuses() below, the
	# existing dedicated resistance mechanism, not misc_bonus.
	# Patch v4.0 Armor Base Specific Mods (flat_ward/flat_armor/flat_evasion already existed pre-v4.0)
	"increased_ward", "increased_armor", "increased_evasion", "hybrid_defense_life",
	# Patch v4.0 Amulet Exclusive Mod Pool
	"flat_aether", "skill_level_all", "skill_level_spells",
	"skill_level_kinetic", "skill_level_spell_kinetic",
	"skill_level_piercing", "skill_level_spell_piercing",
	"skill_level_explosive", "skill_level_spell_explosive",
	"skill_level_fire", "skill_level_spell_fire",
	"skill_level_cold", "skill_level_spell_cold",
	"skill_level_lightning", "skill_level_spell_lightning",
	"skill_level_aetheric", "skill_level_spell_aetheric",
	"skill_level_entropic", "skill_level_spell_entropic",
	"skill_level_pale", "skill_level_spell_pale",
]

func compute_misc_bonuses() -> Dictionary:
	var totals := {}
	for item in get_all_equipped_items():
		for affix in item.affixes:
			if MISC_BONUS_KEYS.has(affix.stat_key):
				totals[affix.stat_key] = totals.get(affix.stat_key, 0.0) + affix.value
	return totals

func get_all_equipped_items() -> Array[Item]:
	var items: Array[Item] = [helmet, body_armour, gloves, boots, primary_weapon, offhand, amulet, belt]
	items.append_array(rings)
	items = items.filter(func(i): return i != null)
	return items

func _ref_for(item: Item):
	return item.resource_path if item.resource_path != "" else ItemSerializer.to_dict(item)

## User request (2026-08-30): "They should also have the appropriate
## level requirement and stat requirement to equip." Empty string = OK to
## equip. Checked at the top of equip() itself (same spot the existing
## two-handed-conflict checks already live), so the existing equip_failed
## signal / InventoryScreen's "Can't equip: %s" status line handle display
## for free - no new UI plumbing needed.
func _requirement_block_reason(item: Item) -> String:
	if GameState.player_level < item.item_level:
		return "Requires character level %d" % item.item_level
	if item.stat_requirement != -1 and _player:
		var have := _player.stat_sheet.get_stat(item.stat_requirement)
		if have < item.stat_requirement_value:
			var stat_name: String = Constants.STAT_NAME.get(item.stat_requirement, "?")
			return "Requires %.0f %s (have %.0f)" % [item.stat_requirement_value, stat_name, have]
	return ""

func _equip_ring(item: Item) -> void:
	for i in range(rings.size()):
		if rings[i] == null:
			rings[i] = item
			return
	rings[0] = item
