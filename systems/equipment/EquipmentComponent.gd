extends Node
class_name EquipmentComponent
## Holds a full gear loadout per Section 13 Equipment Slots. Attach to
## Player (or any future equippable actor) - same pattern as
## HealthComponent/WardComponent. compute_stat_bonuses() aggregates
## flat_<stat> affixes (see ItemRoller.gd) into the six core stats per
## Section 12 ("all stats come from gear..."). Slate stat contributions
## now sum in too - see FateBoard.compute_stat_bonuses(), which reuses
## AFFIX_STAT_KEYS below so a Slate modifier's stat_key means exactly
## what a gear affix's does.

@export var helmet: Armor
@export var body_armour: Armor
@export var gloves: Armor
@export var boots: Armor

@export var primary_weapon: Weapon
@export var sidearm_weapon: Weapon
@export var offhand: Shield
@export var conduit: Weapon
@export var secondary_throwable: Weapon

@export var amulet: Item
@export var belt: Item
@export var rings: Array[Item] = [null, null, null, null]

signal equip_failed(reason: String)
## Fired on every successful equip()/unequip() (not rejected paths) -
## Player.gd recomputes stat bonuses and visuals on this.
signal equipment_changed

## Only Player currently instances this despite the "any future equippable
## actor" framing above - level/stat requirement checks (2026-08-30) need
## somewhere to read player_level/stat_sheet from, and Player is the only
## real candidate today.
@onready var _player: Player = get_parent()

## Routes by item.equip_slot. Two-handed primary weapons clear the sidearm
## and offhand slots per Section 13 ("Two-Handed Weapon occupies both
## weapon slots"). RING uses the first open ring slot, or slot 0 if all full.
##
## bypass_requirements: true only for Player._apply_saved_loadout()
## restoring a previous session's save - a save should always restore
## cleanly (silently stripping a slot the player already legitimately
## equipped, just because a later balance change or a level-up-in-reverse
## edge case put it out of reach, would be a real regression, not correct
## gating). A live player-initiated equip (inventory click, GearShop
## purchase) always leaves this at its default false.
func equip(item: Item, bypass_requirements: bool = false) -> void:
	if item == null:
		return
	if not bypass_requirements:
		var block_reason := _requirement_block_reason(item)
		if block_reason != "":
			push_warning(block_reason)
			equip_failed.emit(block_reason)
			return
	match item.equip_slot:
		Constants.EquipmentSlot.HELMET: helmet = item as Armor
		Constants.EquipmentSlot.BODY_ARMOUR: body_armour = item as Armor
		Constants.EquipmentSlot.GLOVES: gloves = item as Armor
		Constants.EquipmentSlot.BOOTS: boots = item as Armor
		Constants.EquipmentSlot.PRIMARY_WEAPON:
			primary_weapon = item as Weapon
			if primary_weapon and primary_weapon.is_two_handed:
				sidearm_weapon = null
				offhand = null
		Constants.EquipmentSlot.SIDEARM_WEAPON:
			if primary_weapon and primary_weapon.is_two_handed:
				var reason := "Cannot equip a sidearm weapon while a two-handed weapon is equipped."
				push_warning(reason)
				equip_failed.emit(reason)
				return
			sidearm_weapon = item as Weapon
		Constants.EquipmentSlot.OFFHAND:
			if primary_weapon and primary_weapon.is_two_handed:
				var reason := "Cannot equip an offhand while a two-handed weapon is equipped."
				push_warning(reason)
				equip_failed.emit(reason)
				return
			offhand = item as Shield
		Constants.EquipmentSlot.CONDUIT: conduit = item as Weapon
		Constants.EquipmentSlot.SECONDARY_THROWABLE: secondary_throwable = item as Weapon
		Constants.EquipmentSlot.AMULET: amulet = item
		Constants.EquipmentSlot.BELT: belt = item
		Constants.EquipmentSlot.RING: _equip_ring(item)
	equipment_changed.emit()

func unequip(slot: Constants.EquipmentSlot, ring_index: int = 0) -> void:
	match slot:
		Constants.EquipmentSlot.HELMET: helmet = null
		Constants.EquipmentSlot.BODY_ARMOUR: body_armour = null
		Constants.EquipmentSlot.GLOVES: gloves = null
		Constants.EquipmentSlot.BOOTS: boots = null
		Constants.EquipmentSlot.PRIMARY_WEAPON: primary_weapon = null
		Constants.EquipmentSlot.SIDEARM_WEAPON: sidearm_weapon = null
		Constants.EquipmentSlot.OFFHAND: offhand = null
		Constants.EquipmentSlot.CONDUIT: conduit = null
		Constants.EquipmentSlot.SECONDARY_THROWABLE: secondary_throwable = null
		Constants.EquipmentSlot.AMULET: amulet = null
		Constants.EquipmentSlot.BELT: belt = null
		Constants.EquipmentSlot.RING:
			if ring_index >= 0 and ring_index < rings.size():
				rings[ring_index] = null
	equipment_changed.emit()

## Read counterpart to equip()/unequip()'s routing, so callers (UI) don't
## need 15 bespoke field accesses.
func get_equipped(slot: Constants.EquipmentSlot, ring_index: int = 0) -> Item:
	match slot:
		Constants.EquipmentSlot.HELMET: return helmet
		Constants.EquipmentSlot.BODY_ARMOUR: return body_armour
		Constants.EquipmentSlot.GLOVES: return gloves
		Constants.EquipmentSlot.BOOTS: return boots
		Constants.EquipmentSlot.PRIMARY_WEAPON: return primary_weapon
		Constants.EquipmentSlot.SIDEARM_WEAPON: return sidearm_weapon
		Constants.EquipmentSlot.OFFHAND: return offhand
		Constants.EquipmentSlot.CONDUIT: return conduit
		Constants.EquipmentSlot.SECONDARY_THROWABLE: return secondary_throwable
		Constants.EquipmentSlot.AMULET: return amulet
		Constants.EquipmentSlot.BELT: return belt
		Constants.EquipmentSlot.RING:
			return rings[ring_index] if ring_index >= 0 and ring_index < rings.size() else null
	return null

func get_total_armor() -> float:
	var total := 0.0
	if helmet: total += helmet.armor_value
	if body_armour: total += body_armour.armor_value
	if gloves: total += gloves.armor_value
	if boots: total += boots.armor_value
	if offhand: total += offhand.armor_value
	return total

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
	if offhand: total += offhand.ward_value
	for item in get_all_equipped_items():
		for affix in item.affixes:
			if affix.stat_key == "flat_ward":
				total += affix.value
	return total

## Restore-descriptor per equipped item for GameState.sync_equipment() -
## a resource_path String, or an ItemSerializer Dictionary for rolled
## items (no resource_path to save as a path).
func get_all_equipped_refs() -> Array:
	var refs: Array = []
	for item in get_all_equipped_items():
		refs.append(_ref_for(item))
	return refs

## Not the only source of stat growth anymore - FateBoard.
## compute_stat_bonuses() reuses this same dict for Slate modifiers'
## stat_key. Together they're the only two (Section 12: gear + Slates,
## no level-up allocation).
const AFFIX_STAT_KEYS := {
	"flat_vitality": Constants.Stat.VITALITY,
	"flat_strength": Constants.Stat.STRENGTH,
	"flat_instinct": Constants.Stat.INSTINCT,
	"flat_arcane": Constants.Stat.ARCANE,
	"flat_enigma": Constants.Stat.ENIGMA,
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
const RESISTANCE_AFFIX_KEYS := {
	"fire_resistance_pct": "fire",
	"cold_resistance_pct": "cold",
	"lightning_resistance_pct": "lightning",
	"esoteric_resistance_pct": "esoteric",
}

func compute_resistance_bonuses() -> Dictionary:
	var totals := {}
	for item in get_all_equipped_items():
		for affix in item.affixes:
			if RESISTANCE_AFFIX_KEYS.has(affix.stat_key):
				var key: String = RESISTANCE_AFFIX_KEYS[affix.stat_key]
				totals[key] = totals.get(key, 0.0) + affix.value
	return totals

func get_all_equipped_items() -> Array[Item]:
	var items: Array[Item] = [helmet, body_armour, gloves, boots, primary_weapon, sidearm_weapon, offhand, conduit, secondary_throwable, amulet, belt]
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
