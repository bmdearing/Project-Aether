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
	_emit_changed()

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
	if item == null or not item.is_equipment():
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
	_emit_changed()

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
	_emit_changed()

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
	_emit_changed()

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

## Ward pool: every equipped Armor/Shield's base ward_value plus flat Ward
## from any item, times increased Ward.
func compute_ward_bonus() -> float:
	var total := 0.0
	if helmet: total += helmet.ward_value
	if body_armour: total += body_armour.ward_value
	if gloves: total += gloves.ward_value
	if boots: total += boots.ward_value
	if offhand is Shield: total += (offhand as Shield).ward_value
	var affixes := compute_misc_bonuses()
	return (total + affixes.get("flat_ward", 0.0)) * (1.0 + affixes.get("increased_ward", 0.0) / 100.0)


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
		for affix in item.get_effective_affixes():
			if AFFIX_STAT_KEYS.has(affix.key()):
				var stat: Constants.Stat = AFFIX_STAT_KEYS[affix.key()]
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
		for affix in item.get_effective_affixes():
			if RESISTANCE_AFFIX_KEYS.has(affix.key()):
				var key: String = RESISTANCE_AFFIX_KEYS[affix.key()]
				totals[key] = totals.get(key, 0.0) + affix.value
			elif affix.key() == ALL_ELEMENTAL_RESISTANCE_KEY:
				for key in ["fire", "cold", "lightning"]:
					totals[key] = totals.get(key, 0.0) + affix.value
	return totals

## Every other gear stat (life, mana, speeds, damage, ailments, defences...)
## summed per canonical key (StatKeys) into StatSheet.misc_bonus. Local
## weapon mods stay on their weapon and Unique mechanics go to UniqueEffects.
const AILMENT_IDS := ["bleed", "ignite", "chill", "electrocute", "shock", "aetherburn", "unraveling", "pallid"]
const V40_DAMAGE_TYPE_KEYS := ["kinetic", "piercing", "explosive", "fire", "cold", "lightning", "aetheric", "entropic", "pale"]

func compute_misc_bonuses() -> Dictionary:
	var totals := {}
	for item in get_all_equipped_items():
		for affix in item.get_effective_affixes():
			var key := affix.key()
			if not is_misc_key(key):
				continue
			totals[key] = totals.get(key, 0.0) + affix.value
			if key == "hybrid_defense_life":
				_add_hybrid_defense(totals, item, affix.value)
	return totals

## Attributes and resistances have their own sums; local and Unique keys
## aren't character stats.
static func is_misc_key(key: String) -> bool:
	return not (key.begins_with("local_") or key.begins_with("unique_") or AFFIX_STAT_KEYS.has(key) or RESISTANCE_AFFIX_KEYS.has(key) or key == ALL_ELEMENTAL_RESISTANCE_KEY)

## "+N to primary defence and Life": the Life half is flat Life, the other
## half goes to whichever defence the item itself has most of.
static func _add_hybrid_defense(totals: Dictionary, item: Item, value: float) -> void:
	totals["flat_life"] = totals.get("flat_life", 0.0) + value
	var defences := {"flat_armor": item.get("armor_value"), "flat_evasion": item.get("evasion_value"), "flat_ward": item.get("ward_value")}
	var best := "flat_armor"
	for k in defences:
		if defences[k] != null and float(defences[k]) > float(defences[best] if defences[best] != null else 0.0):
			best = k
	totals[best] = totals.get(best, 0.0) + value

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

## Updates ring reflection (Band of Wishes), then tells listeners.
func _emit_changed() -> void:
	_update_ring_reflections()
	equipment_changed.emit()

var _reflecting: Array[Item] = []

## A ring with the reflect mechanic copies the other equipped ring's
## modifiers (Item.reflect_source). Two reflecting rings reflect nothing.
func _update_ring_reflections() -> void:
	for ring in _reflecting:
		ring.reflect_source = null
	_reflecting.clear()
	for i in rings.size():
		var ring := rings[i]
		var other: Item = rings[1 - i] if rings.size() == 2 else null
		if ring and other and ring.reflects_other_ring() and not other.reflects_other_ring():
			ring.reflect_source = other
			_reflecting.append(ring)
