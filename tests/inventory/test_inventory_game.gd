extends Node
## Scene-level checks for the grid inventory inside the real Hub: pickups,
## equip/unequip through InventoryScreen, Fate Board Slates, shop refunds
## and legacy save migration.
## Run: Godot --headless --path . res://tests/inventory/test_inventory_game.tscn
## Exits 0 when every check passes. Never writes the save file.

const HUB := "res://levels/hub/Hub.tscn"
const LOOT_PICKUP := "res://entities/pickups/loot_pickup/LootPickup.tscn"

var _checks := 0
var _failures := 0
var _finished := 0
var _hub: Node
var _player: Player
var _equipment: EquipmentComponent
var _screen: InventoryScreen
var _full_signals := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false  # keeps SaveManager.save_game() a no-op
	_hub = load(HUB).instantiate()
	add_child(_hub)
	await _frames(5)
	_player = get_tree().get_first_node_in_group("player") as Player
	_equipment = GameState.player_equipment
	_screen = _hub.get_node("InventoryScreen")
	EventBus.inventory_full.connect(func(_c): _full_signals += 1)

	_test_new_game_state()
	await _test_pickups()
	_test_equip_unequip()
	_test_swap_revert()
	_test_fate_board()
	_test_shop_refund()
	_test_migration()
	_check(_finished == 7, "every test function ran to the end (%d/7)" % _finished)
	print("inventory game tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _armor(slot: Constants.EquipmentSlot, name: String) -> Armor:
	var a := Armor.new()
	a.equip_slot = slot
	a.display_name = name
	a.item_id = name.to_snake_case()
	return a

func _weapon(type: String, two_handed: bool) -> Weapon:
	var w := Weapon.new()
	w.weapon_type = type
	w.display_name = type
	w.is_two_handed = two_handed
	return w

func _entry_for(content) -> GridInventory.Entry:
	for e in GameState.inventory.get_entries():
		if not e.is_currency() and e.content == content:
			return e
	return null

func _doll_row(slot: Constants.EquipmentSlot) -> Dictionary:
	for row in _screen._doll_rows:
		if row["slot"] == slot:
			return row
	return {}

func _test_new_game_state() -> void:
	_check(GameState.inventory.get_entries().is_empty(), "new game starts with an empty grid (no base-item catalogue)")
	_check(_equipment.get_equipped(Constants.EquipmentSlot.BODY_ARMOUR) != null, "starting armour still equipped")
	_finished += 1

func _test_pickups() -> void:
	var helmet := _armor(Constants.EquipmentSlot.HELMET, "Test Helm")
	var pickup: LootPickup = load(LOOT_PICKUP).instantiate()
	pickup.item = helmet
	_hub.add_child(pickup)
	pickup._on_body_entered(_player)
	_check(GameState.inventory.has_content(helmet) and pickup.is_queued_for_deletion(), "pickup goes into the grid")

	var slate := Slate.new()
	var slate_pickup: LootPickup = load(LOOT_PICKUP).instantiate()
	slate_pickup.slate = slate
	_hub.add_child(slate_pickup)
	slate_pickup._on_body_entered(_player)
	_check(GameState.inventory.has_content(slate), "slate pickup goes into the grid")
	GameState.remove_from_inventory(slate)

	var saved := GameState.inventory
	GameState.inventory = GridInventory.new(1, 1)
	GameState.inventory.add(&"quickening")
	var blocked: LootPickup = load(LOOT_PICKUP).instantiate()
	blocked.item = _armor(Constants.EquipmentSlot.GLOVES, "Test Gloves")
	_hub.add_child(blocked)
	_full_signals = 0
	blocked._on_body_entered(_player)
	_check(not blocked.is_queued_for_deletion() and _full_signals == 1, "full inventory leaves the pickup on the ground")
	GameState.inventory = saved
	blocked._on_body_entered(_player)
	_check(blocked.is_queued_for_deletion() and GameState.inventory.has_content(blocked.item), "pickup succeeds once there's room")
	await _frames(1)
	_finished += 1

func _test_equip_unequip() -> void:
	_screen.open()
	_check(not get_tree().paused, "inventory doesn't pause")
	var helmet: Item = GameState.get_inventory_items().filter(func(i): return i.display_name == "Test Helm")[0]
	_screen._on_entry_right_clicked(_screen.inventory_grid, _entry_for(helmet))
	_check(_equipment.get_equipped(Constants.EquipmentSlot.HELMET) == helmet and not GameState.inventory.has_content(helmet), "click equips and removes from grid")

	var old_body := _equipment.get_equipped(Constants.EquipmentSlot.BODY_ARMOUR)
	var body := _armor(Constants.EquipmentSlot.BODY_ARMOUR, "Test Plate")
	GameState.inventory.add(body)
	_screen._on_entry_right_clicked(_screen.inventory_grid, _entry_for(body))
	_check(_equipment.get_equipped(Constants.EquipmentSlot.BODY_ARMOUR) == body, "body armour swapped in")
	var returned := GameState.get_inventory_items().filter(func(i): return i is Armor and i.display_name == old_body.display_name)
	_check(returned.size() == 1, "displaced armour returns to the grid")
	_check(returned.size() == 1 and returned[0] != old_body and returned[0].resource_path == "", "hand-authored base returns as its own copy")

	_screen._on_doll_slot_pressed(_doll_row(Constants.EquipmentSlot.HELMET))
	_check(_equipment.get_equipped(Constants.EquipmentSlot.HELMET) == null and GameState.inventory.has_content(helmet), "doll click unequips into the grid")

	var saved := GameState.inventory
	GameState.inventory = GridInventory.new(1, 1)
	GameState.inventory.add(&"quickening")
	_screen._on_doll_slot_pressed(_doll_row(Constants.EquipmentSlot.BODY_ARMOUR))
	_check(_equipment.get_equipped(Constants.EquipmentSlot.BODY_ARMOUR) == body, "unequip refused when the grid is full")
	GameState.inventory = saved

	var refs_have_body := GameState.equipment_refs.any(func(r): return r is Dictionary and r.get("display_name", "") == "Test Plate")
	_check(refs_have_body, "equipment refs synced after equip")
	_screen.close()
	_finished += 1

func _test_swap_revert() -> void:
	var saber := _weapon("Saber", false)
	var shield := Shield.new()
	shield.equip_slot = Constants.EquipmentSlot.OFFHAND
	shield.base_line_id = "kite_shield_line1"
	shield.display_name = "Test Kite"
	_equipment.equip(saber, true)
	_equipment.equip(shield, true)
	var saved := GameState.inventory
	GameState.inventory = GridInventory.new(2, 4)
	var greatsword := _weapon("Greatsword", true)
	GameState.inventory.add(greatsword)
	_screen.open()
	_screen._on_entry_right_clicked(_screen.inventory_grid, _entry_for(greatsword))
	_check(_equipment.get_equipped(Constants.EquipmentSlot.PRIMARY_WEAPON) == saber and _equipment.get_equipped(Constants.EquipmentSlot.OFFHAND) == shield, "swap reverted when displaced items don't fit")
	_check(GameState.inventory.has_content(greatsword) and GameState.inventory.get_entries().size() == 1, "grid unchanged after a reverted swap")

	GameState.inventory = GridInventory.new(4, 4)
	GameState.inventory.add(greatsword)
	_screen._on_entry_right_clicked(_screen.inventory_grid, _entry_for(greatsword))
	_check(_equipment.get_equipped(Constants.EquipmentSlot.PRIMARY_WEAPON) == greatsword and _equipment.get_equipped(Constants.EquipmentSlot.OFFHAND) == null, "two-hander equipped when there's room")
	_check(GameState.inventory.has_content(saber) and GameState.inventory.has_content(shield), "two-hander puts both displaced items in the grid")
	_screen.close()
	GameState.inventory = saved
	_finished += 1

func _test_fate_board() -> void:
	var editor: FateBoardEditor = _hub.get_node("FateBoardEditor")
	var slate := Slate.new()
	slate.display_name = "Test Slate"
	slate.aether_cost = 1
	GameState.inventory.add(slate)
	editor.open()
	var palette_slates := editor.palette_list.get_children().filter(func(b): return not b.is_queued_for_deletion() and b.slate == slate)
	_check(palette_slates.size() == 1, "palette lists carried slates")
	editor._selected_slate = slate
	editor._on_cell_clicked(FateBoard.ANCHOR_CELL, MOUSE_BUTTON_LEFT)
	_check(GameState.fate_board.placements.size() == 1 and not GameState.inventory.has_content(slate), "placing moves the slate out of the grid")
	_check(GameState.fate_board_placements.size() == 1 and GameState.fate_board_placements[0]["slate_ref"] is Dictionary, "placed rolled slate saved as full data")
	editor._on_cell_clicked(FateBoard.ANCHOR_CELL, MOUSE_BUTTON_RIGHT)
	_check(GameState.fate_board.placements.is_empty() and GameState.inventory.has_content(slate), "removing returns the slate to the grid")

	editor._selected_slate = slate
	editor._on_cell_clicked(FateBoard.ANCHOR_CELL, MOUSE_BUTTON_LEFT)
	var saved := GameState.inventory
	GameState.inventory = GridInventory.new(1, 1)
	GameState.inventory.add(&"quickening")
	editor._on_cell_clicked(FateBoard.ANCHOR_CELL, MOUSE_BUTTON_RIGHT)
	_check(GameState.fate_board.placements.size() == 1, "removal refused when the grid is full")
	GameState.inventory = saved
	editor._on_cell_clicked(FateBoard.ANCHOR_CELL, MOUSE_BUTTON_RIGHT)
	editor.close()
	_finished += 1

func _test_shop_refund() -> void:
	var shop: ShopScreen = _hub.get_node("ShopScreen")
	var gear_shop: GearShop = _hub.get_node("GearShop")
	var saved := GameState.inventory
	GameState.inventory = GridInventory.new(1, 1)
	GameState.inventory.add(&"quickening")
	var gold := GameState.gold
	var item := _weapon("Dagger", false)
	var label := Label.new()
	var button := Button.new()
	shop._on_buy_pressed({"cost": 50, "on_buy": func(): return gear_shop._buy(item)}, button, label)
	_check(GameState.gold == gold and label.text == "No room" and not button.disabled, "purchase with no room is refunded")
	GameState.inventory = saved
	shop._on_buy_pressed({"cost": 50, "on_buy": func(): return gear_shop._buy(item)}, button, label)
	_check(GameState.gold == gold - 50 and GameState.inventory.has_content(item), "purchase lands in the grid")
	label.free()
	button.free()
	_finished += 1

func _test_migration() -> void:
	var equipped := _armor(Constants.EquipmentSlot.HELMET, "Old Equipped Helm")
	var loose := _armor(Constants.EquipmentSlot.GLOVES, "Old Loose Gloves")
	var old_equipped := ItemSerializer.to_dict(equipped)
	var old_loose := ItemSerializer.to_dict(loose)
	for d in [old_equipped, old_loose]:
		for key in ["tolerance", "tolerance_max", "sockets", "sockets_rolled", "quality", "active_edict"]:
			d.erase(key)
	var placed_slate := Slate.new()
	placed_slate.display_name = "Old Placed Slate"
	var loose_slate := Slate.new()
	loose_slate.display_name = "Old Loose Slate"
	var parsed := {
		"owned_loot": [old_equipped.duplicate(true), old_loose],
		"owned_slates": [SlateSerializer.to_dict(loose_slate), SlateSerializer.to_dict(placed_slate)],
	}
	for d in parsed["owned_slates"]:
		for key in ["tolerance", "tolerance_max", "explicits", "is_corrupted", "active_edict"]:
			d.erase(key)
	GameState.inventory = GridInventory.new()
	GameState.stash = Stash.create_default()
	GameState.equipment_refs = [old_equipped]
	GameState.weapon_set_refs = [[], []]
	GameState.fate_board_placements = [{"slate_ref": 1.0, "origin": [75, 75], "rotation_steps": 0, "flipped": false, "designated_ability_id": ""}]
	SaveManager._migrate_legacy_inventory(parsed)
	var names := GameState.get_inventory_items().map(func(i): return i.display_name)
	_check(names.has("Old Loose Gloves") and not names.has("Old Equipped Helm"), "migration keeps loose loot and skips equipped copies")
	_check(names.has("Old Loose Slate") and not names.has("Old Placed Slate"), "migration moves unplaced slates into the grid")
	var ref = GameState.fate_board_placements[0]["slate_ref"]
	_check(ref is Dictionary and ref.get("display_name", "") == "Old Placed Slate", "placed slate index converted to full data")
	_check(GameState.get_inventory_items().all(func(i): return (i.tolerance > 0) == (i is Slate)), "migrated slates get tolerance, gear does not")

	var crowded := {"owned_loot": []}
	for i in 30:
		crowded["owned_loot"].append(ItemSerializer.to_dict(_armor(Constants.EquipmentSlot.BODY_ARMOUR, "Bulk %d" % i)))
	GameState.inventory = GridInventory.new()
	GameState.equipment_refs = []
	GameState.fate_board_placements = []
	SaveManager._migrate_legacy_inventory(crowded)
	var in_stash := 0
	for tab in GameState.stash.tabs:
		in_stash += tab.get_entries().size()
	var fits := int(Constants.INVENTORY_SIZE.x / 2.0) * int(Constants.INVENTORY_SIZE.y / 3.0)  # 2x3 body armours
	_check(GameState.inventory.get_entries().size() == fits and GameState.inventory.get_entries().size() + in_stash == 30, "migration overflow goes to the stash")
	_finished += 1
