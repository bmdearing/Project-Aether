extends Node
class_name AbilityLoadoutComponent
## Holds the player's equipped ability bar (SLOT_COUNT slots, matching
## AbilityBar's UI and ability_1..4 input actions). Same "owns one of
## each" stand-in as EquipmentComponent/FateBoard's Slate palette - no
## real ability acquisition/loot system exists yet, so AbilitiesScreen
## just offers every .tres under data/abilities/instances/.

const SLOT_COUNT := 4

@export var slots: Array[Ability] = [null, null, null, null]

signal loadout_changed

func equip(ability: Ability, slot_index: int) -> void:
	if ability == null or slot_index < 0 or slot_index >= SLOT_COUNT:
		return
	slots[slot_index] = ability
	loadout_changed.emit()

## Convenience for AbilitiesScreen's click-to-equip - any ability can go
## in any slot (unlike EquipmentComponent's slots, which are typed by
## equip_slot), so there's no "correct" slot to route to. Mirrors
## EquipmentComponent._equip_ring()'s same first-open-else-slot-0 pattern.
func equip_first_open(ability: Ability) -> void:
	for i in range(SLOT_COUNT):
		if slots[i] == null:
			equip(ability, i)
			return
	equip(ability, 0)

func unequip(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return
	slots[slot_index] = null
	loadout_changed.emit()

func get_equipped(slot_index: int) -> Ability:
	return slots[slot_index] if slot_index >= 0 and slot_index < SLOT_COUNT else null

## Per-slot resource_path ("" for an empty slot) - unlike
## EquipmentComponent.get_all_equipped_paths(), order matters here (slot
## index = ability_N hotkey), so this stays a fixed-length parallel array
## rather than a compacted list. Used by GameState.sync_ability_loadout().
func get_all_paths() -> Array[String]:
	var paths: Array[String] = []
	for slot in slots:
		paths.append(slot.resource_path if slot else "")
	return paths
