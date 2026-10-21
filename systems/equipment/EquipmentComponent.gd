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
## to_offhand: put a one-handed weapon in the offhand slot (dual wielding)
## even when it would otherwise replace the main hand.
func equip(item: Item, bypass_requirements: bool = false, weapon_set: int = -1, to_offhand: bool = false) -> void:
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
		_equip_weapon(item as Weapon, set_index, to_offhand)
		return
	match item.equip_slot:
		Constants.EquipmentSlot.HELMET: helmet = item as Armor
		Constants.EquipmentSlot.BODY_ARMOUR: body_armour = item as Armor
		Constants.EquipmentSlot.GLOVES: gloves = item as Armor
		Constants.EquipmentSlot.BOOTS: boots = item as Armor
		Constants.EquipmentSlot.OFFHAND when item.is_ranged_offhand():
			if not item.fits_weapon(primary_weapons[set_index]):
				var reason := "A quiver needs a bow or crossbow in your main hand." if item.item_type == &"quiver" else "A pouch needs a gun in your main hand."
				push_warning(reason)
				equip_failed.emit(reason)
				return
			offhands[set_index] = item
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

func _equip_weapon(weapon: Weapon, set_index: int, to_offhand: bool = false) -> void:
	var main := primary_weapons[set_index]
	var dual_main := main != null and main.can_dual_wield()
	if weapon.can_dual_wield() and (to_offhand or (dual_main and offhands[set_index] == null)):
		if not dual_main:
			var reason := "Dual wielding needs a one-handed weapon (not a conduit) in your main hand."
			push_warning(reason)
			equip_failed.emit(reason)
			return
		offhands[set_index] = weapon
		_emit_changed()
		return
	if weapon.is_offhand:
		if primary_weapons[set_index] and primary_weapons[set_index].is_two_handed:
			var reason := "Cannot equip an offhand while a two-handed weapon is equipped."
			push_warning(reason)
			equip_failed.emit(reason)
			return
		offhands[set_index] = weapon
	else:
		primary_weapons[set_index] = weapon
		var off := offhands[set_index]
		if off and off.is_ranged_offhand():
			if not off.fits_weapon(weapon):
				offhands[set_index] = null
		elif weapon.is_two_handed:
			offhands[set_index] = null
		elif not weapon.can_dual_wield() and offhands[set_index] is Weapon and (offhands[set_index] as Weapon).can_dual_wield():
			offhands[set_index] = null  # a conduit doesn't dual wield
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

## Total Armour, Evasion or Ward from gear (v5.5.1). An armour piece's or
## shield's own flat and % increased modifiers are local: they scale only that
## item's base (Item.get_local_defence(), what its card shows). Flat from
## anything else (rings, jewels) adds after, and the global % (the amulet's
## line, Agility for Evasion) multiplies the whole total.
func _defence_total(defence: String, extra_increased: float = 0.0) -> float:
	var flat_key := "flat_" + defence
	var increased_key := "increased_" + defence
	var affixes := compute_misc_bonuses()
	var flat: float = affixes.get(flat_key, 0.0)
	var increased: float = affixes.get(increased_key, 0.0) + affixes.get("amulet_" + increased_key, 0.0)
	var local := 0.0
	for item in [helmet, body_armour, gloves, boots, offhand if offhand is Shield else null]:
		if item == null:
			continue
		local += (item as Item).get_local_defence(defence)
		flat -= (item as Item).own_affix_total(flat_key)
		increased -= (item as Item).own_affix_total(increased_key)
		var hybrid := {}
		for affix in (item as Item).affixes:
			if affix.key() == "hybrid_defense_life":
				_add_hybrid_defense(hybrid, item, affix.value)
		flat -= float(hybrid.get(flat_key, 0.0))
	return (local + flat) * (1.0 + increased / 100.0 + extra_increased)

func get_total_armor() -> float:
	return _defence_total("armor")

## extra_increased is Agility's +1%/point (a fraction, passed in by
## StatSheet.get_total_evasion()), global like the amulet's line.
func get_total_evasion(extra_increased: float = 0.0) -> float:
	return _defence_total("evasion", extra_increased)

## Ward pool from gear; Intellect's increased Ward applies on top (Player).
func compute_ward_bonus() -> float:
	return _defence_total("ward")


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

## "+N to Life and the base's own defence": N flat Life, plus N x
## HYBRID_DEFENCE_SHARE of whichever defence the item itself has most of
## (v5.5 bases are small next to Life, and Ward is a pool like Life).
const HYBRID_DEFENCE_SHARE := {"flat_armor": 2.0, "flat_evasion": 3.0, "flat_ward": 1.2}
## Each defence's base scale (top body: Armour 855, Evasion 1283, Ward 572), so
## "most of" compares like for like.
const DEFENCE_BASE_SCALE := {"flat_armor": 5.0, "flat_evasion": 7.5, "flat_ward": 3.35}
static func _add_hybrid_defense(totals: Dictionary, item: Item, value: float) -> void:
	totals["flat_life"] = totals.get("flat_life", 0.0) + value
	var defences := {}
	for k in DEFENCE_BASE_SCALE:
		var v = item.get(k.trim_prefix("flat_") + "_value")
		defences[k] = float(v) / DEFENCE_BASE_SCALE[k] if v != null else null
	var best := "flat_armor"
	for k in defences:
		if defences[k] != null and float(defences[k]) > float(defences[best] if defences[best] != null else 0.0):
			best = k
	totals[best] = totals.get(best, 0.0) + roundf(value * HYBRID_DEFENCE_SHARE[best])

func get_all_equipped_items() -> Array[Item]:
	var items: Array[Item] = [helmet, body_armour, gloves, boots, primary_weapon, offhand, amulet, belt]
	items.append_array(rings)
	items = items.filter(func(i): return i != null)
	return items

func _ref_for(item: Item):
	return item.resource_path if item.resource_path != "" else ItemSerializer.to_dict(item)

## Empty string = OK to equip (ItemRequirements: level and stats from the
## item itself). Shown by InventoryScreen's "Can't equip" line.
func _requirement_block_reason(item: Item) -> String:
	return ItemRequirements.block_reason(item, GameState.player_level, _player.stat_sheet if _player else null)

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
