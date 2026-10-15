extends Node3D
class_name SecretHoard
## A secret room's hoard: one gilded TreasureChest (MapEncounters.HOARD).
## The chest goes on the map itself (where its spilled loot is saved across
## a portal trip), once this node has been placed.

var chest: TreasureChest
var _opened_on_restore := false

func _ready() -> void:
	_place_chest.call_deferred()

func _place_chest() -> void:
	chest = MapEncounters.make_hoard_chest()
	chest.transform = transform
	get_parent().add_child(chest)
	if _opened_on_restore:
		chest.set_opened()
	await get_tree().physics_frame
	if is_instance_valid(chest):
		chest.settle()

func capture_state() -> Dictionary:
	return {"opened": chest.is_opened() if is_instance_valid(chest) else _opened_on_restore}

func restore_state(state: Dictionary) -> void:
	_opened_on_restore = bool(state.get("opened", false))
	if _opened_on_restore and is_instance_valid(chest):
		chest.set_opened()
