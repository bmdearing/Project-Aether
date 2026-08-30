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

## Routes by item.equip_slot. Two-handed primary weapons clear the sidearm
## and offhand slots per Section 13 ("Two-Handed Weapon occupies both
## weapon slots"). RING uses the first open ring slot, or slot 0 if all full.
func equip(item: Item) -> void:
	if item == null:
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

func get_all_equipped_items() -> Array[Item]:
	var items: Array[Item] = [helmet, body_armour, gloves, boots, primary_weapon, sidearm_weapon, offhand, conduit, secondary_throwable, amulet, belt]
	items.append_array(rings)
	items = items.filter(func(i): return i != null)
	return items

func _ref_for(item: Item):
	return item.resource_path if item.resource_path != "" else ItemSerializer.to_dict(item)

func _equip_ring(item: Item) -> void:
	for i in range(rings.size()):
		if rings[i] == null:
			rings[i] = item
			return
	rings[0] = item
