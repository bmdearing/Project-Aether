extends Node
class_name CharacterScreen
## The character sheet (C) is the left half of InventoryScreen; this stands in
## for it so the Tab menu and C key have a screen to open. Open alone, the
## sheet shows by itself; with the inventory (B) up, both halves show.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("character_screen")

func _inventory() -> InventoryScreen:
	return get_tree().get_first_node_in_group("inventory_screen") as InventoryScreen

func is_open() -> bool:
	var inv := _inventory()
	return inv != null and inv.is_showing_stats()

func open() -> void:
	var inv := _inventory()
	if inv:
		inv.set_panels(true, inv.is_showing_items())

func close() -> void:
	var inv := _inventory()
	if inv and inv.is_open():
		inv.set_panels(false, inv.is_showing_items())
