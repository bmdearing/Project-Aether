extends Node
class_name AbilityLoadoutComponent
## Holds the player's equipped ability bar (SLOT_COUNT slots, matching
## AbilityBar's UI and ability_1..4 input actions), plus the stance page:
## SLOT_COUNT more that a Spell Library conduit casts while RMB is held
## (CasterStance). Stored after the bar: slots[SLOT_COUNT + i].

const SLOT_COUNT := 4

@export var slots: Array[Ability] = [null, null, null, null, null, null, null, null]

signal loadout_changed

## While set (Arkanus), the bar casts these instead of its own slots; the
## slots themselves stay as saved and come back when it's cleared.
var override: Array[Ability] = []

func set_override(abilities: Array[Ability]) -> void:
	override = abilities
	loadout_changed.emit()

func equip(ability: Ability, slot_index: int) -> void:
	if ability == null or slot_index < 0 or slot_index >= SLOT_COUNT * 2:
		return
	slots[slot_index] = ability
	loadout_changed.emit()

## Convenience for AbilitiesScreen's click-to-equip - any ability can go
## in any slot, so there's no "correct" slot to route to.
func equip_first_open(ability: Ability, page2: bool = false) -> void:
	var first := SLOT_COUNT if page2 else 0
	for i in range(first, first + SLOT_COUNT):
		if slots[i] == null:
			equip(ability, i)
			return
	equip(ability, first)

func unequip(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= SLOT_COUNT * 2:
		return
	slots[slot_index] = null
	loadout_changed.emit()

func get_equipped(slot_index: int) -> Ability:
	if not override.is_empty():
		return override[slot_index] if slot_index >= 0 and slot_index < override.size() else null
	return slots[slot_index] if slot_index >= 0 and slot_index < SLOT_COUNT else null

func get_page2(slot_index: int) -> Ability:
	return slots[SLOT_COUNT + slot_index] if slot_index >= 0 and slot_index < SLOT_COUNT else null

## Per-slot resource_path ("" for empty) - order matters here (slot index
## = ability_N hotkey), so this stays a fixed-length array, not compacted.
func get_all_paths() -> Array[String]:
	var paths: Array[String] = []
	for slot in slots:
		paths.append(slot.resource_path if slot else "")
	return paths
