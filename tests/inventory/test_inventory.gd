extends Node
## Headless checks for GridInventory, Stash and crafting from the stash.
## Run: Godot --headless --path . res://tests/inventory/test_inventory.tscn
## Exits 0 when every check passes.

var _checks := 0
var _failures := 0
## Bumped as the last line of each test function, so a script error that
## aborts one midway shows up as a failure.
var _finished := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _run() -> void:
	_test_footprints()
	_test_placement()
	_test_no_rotation()
	_test_stacks()
	_test_special_tabs()
	_test_stash_crafting()
	_test_brand_activation()
	_test_save_round_trip()
	_test_debug_screen()
	_check(_finished == 9, "every test function ran to the end (%d/9)" % _finished)
	print("inventory tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _weapon(type: String) -> Weapon:
	var w := Weapon.new()
	w.weapon_type = type
	w.display_name = type
	w.tolerance = 100
	return w

func _slot_item(slot: Constants.EquipmentSlot) -> Item:
	var item := Item.new()
	item.equip_slot = slot
	return item

func _test_footprints() -> void:
	_check(GridInventory.footprint_of(_weapon("Greatsword")) == Vector2i(2, 4), "greatsword 4 tall x 2 wide")
	_check(GridInventory.footprint_of(_weapon("Lever Action Rifle")) == Vector2i(2, 3), "lever action rifle 3x2")
	_check(GridInventory.footprint_of(_weapon("Service Pistol")) == Vector2i(2, 2), "service pistol 2x2")
	_check(GridInventory.footprint_of(_slot_item(Constants.EquipmentSlot.BELT)) == Vector2i(2, 1), "belt 1 tall x 2 wide")
	_check(GridInventory.footprint_of(_slot_item(Constants.EquipmentSlot.RING)) == Vector2i.ONE, "ring 1x1")
	_check(GridInventory.footprint_of(_slot_item(Constants.EquipmentSlot.BODY_ARMOUR)) == Vector2i(2, 3), "body armour 3x2")
	_check(GridInventory.footprint_of(Slate.new()) == Vector2i.ONE, "slate 1x1")
	_check(GridInventory.footprint_of(&"quickening") == Vector2i.ONE, "currency 1x1")
	var kite := Shield.new()
	kite.base_line_id = "kite_shield_line2"
	_check(GridInventory.footprint_of(kite) == Vector2i(2, 3), "kite shield 3x2")

	# Every shipped weapon and shield base resolves to a table entry.
	var table := FootprintTable.get_instance()
	var missing := {}
	for dir in ["res://data/weapons/instances/", "res://data/shields/instances/", "res://data/armor/instances/"]:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".tres"):
				continue
			var item := load(dir + file) as Item
			if item and not table.footprints.has(String(item.get_item_type())):
				missing[String(item.get_item_type())] = true
	_check(missing.is_empty(), "every base type has a footprint (missing: %s)" % ", ".join(missing.keys()))
	_finished += 1

func _test_placement() -> void:
	var inv := GridInventory.new()
	_check(inv.width == Constants.INVENTORY_SIZE.x and inv.height == Constants.INVENTORY_SIZE.y, "default size from Constants")
	var sword := _weapon("Greatsword")
	_check(inv.place(sword, Vector2i(0, 0)) == 0, "place greatsword")
	_check(inv.entry_at(Vector2i(1, 3)) != null and inv.entry_at(Vector2i(1, 3)).content == sword, "greatsword covers its footprint")
	_check(inv.entry_at(Vector2i(2, 0)) == null and inv.entry_at(Vector2i(0, 4)) == null, "greatsword covers nothing more")
	var ring := _slot_item(Constants.EquipmentSlot.RING)
	_check(not inv.can_place(ring, Vector2i(1, 3)), "collision rejected")
	_check(inv.place(ring, Vector2i(1, 3)) == 1, "collided place returns the item")
	_check(inv.can_place(ring, Vector2i(2, 0)), "free cell accepted")
	var rapier_size := GridInventory.footprint_of(_weapon("Rapier"))
	_check(not inv.can_place(_weapon("Rapier"), Vector2i(inv.width - rapier_size.x + 1, 0)), "out of bounds rejected (wide)")
	_check(not inv.can_place(_weapon("Rapier"), Vector2i(0, inv.height - rapier_size.y + 1)), "out of bounds rejected (tall)")
	_check(not inv.can_place(ring, Vector2i(-1, 0)), "negative position rejected")
	var armour := _slot_item(Constants.EquipmentSlot.BODY_ARMOUR)
	_check(inv.add(armour) == 0 and inv.entry_at(Vector2i(2, 0)).content == armour, "find_space is first fit from top-left")
	_check(inv.find_space(Vector2i(2, 4)) == Vector2i(4, 0), "find_space skips occupied columns")
	var entry := inv.entry_at(Vector2i(2, 0))
	_check(not inv.move(entry, Vector2i(1, 0)), "move into a collision rejected")
	_check(inv.move(entry, Vector2i(10, 3)) and entry.position == Vector2i(10, 3), "move to free space")
	_check(inv.move(entry, Vector2i(10, 2)), "move overlapping its own old cells")
	_check(inv.remove_content(sword) and not inv.has_content(sword), "remove item")
	var full := GridInventory.new(4, 4)
	_check(full.add(_weapon("Greatsword")) == 0 and full.add(_weapon("Greatsword")) == 0, "two greatswords fill a 4x4")
	_check(full.add(_weapon("Greatsword")) == 1 and full.find_space(Vector2i.ONE) == GridInventory.NO_SPACE, "full grid rejects pickup")
	_finished += 1

func _test_no_rotation() -> void:
	var inv := GridInventory.new()
	for method in ["rotate", "rotate_entry", "flip", "flip_entry", "set_rotation", "place_rotated"]:
		_check(not inv.has_method(method), "no %s API" % method)
	var info := inv.get_method_list().map(func(m): return m["name"])
	_check(not info.any(func(n: String): return n.contains("rotat") or n.contains("flip")), "no rotation-related method at all")
	inv.add(_weapon("Greatsword"))
	var entry := inv.get_entries()[0]
	_check(not ("rotation" in entry) and not ("flipped" in entry), "entries carry no orientation")
	_finished += 1

func _test_stacks() -> void:
	var inv := GridInventory.new()
	_check(inv.add(&"quickening", 150) == 0, "pickup 150 orbs")
	var stacks := inv.get_entries().filter(func(e): return e.content == &"quickening")
	_check(stacks.size() == 2 and stacks.any(func(e): return e.count == 100) and stacks.any(func(e): return e.count == 50), "stack caps at 100 and overflows into a new cell")
	_check(inv.add(&"quickening", 60) == 0, "pickup 60 more")
	_check(inv.count_of(&"quickening") == 210 and inv.get_entries().size() == 3, "pickup tops up existing stack first")
	var small: GridInventory.Entry = inv.get_entries().filter(func(e): return e.count == 10)[0]
	var leftover := inv.place(&"quickening", small.position, 95)
	_check(leftover == 0 and small.count == 100 and inv.count_of(&"quickening") == 305 and inv.get_entries().size() == 4, "drop merges into a stack and overflows")
	_check(inv.place(&"severance", small.position, 5) == 5, "drop on a different stack rejected")
	inv.add(&"severance", 5)
	var sev: GridInventory.Entry = inv.get_entries().filter(func(e): return e.content == &"severance")[0]
	_check(not inv.move(sev, small.position), "moving onto a different stack rejected")
	var partial := GridInventory.new()
	partial.add(&"grafting", 30)
	partial.place(&"grafting", Vector2i(5, 5), 90)
	var a := partial.entry_at(Vector2i(0, 0))
	var b := partial.entry_at(Vector2i(5, 5))
	_check(partial.move(b, a.position) and a.count == 100 and b.count == 20 and partial.get_entries().size() == 2, "moving a stack onto a stack merges, remainder stays")
	_check(partial.remove_currency(&"grafting", 30) and partial.count_of(&"grafting") == 90 and partial.get_entries().size() == 1, "remove_currency drains the smallest stack first")
	_check(not partial.remove_currency(&"grafting", 91), "remove_currency refuses more than owned")
	var tiny := GridInventory.new(2, 1)
	_check(tiny.add(&"opening", 250) == 50 and tiny.count_of(&"opening") == 200, "pickup leftover when full")
	_finished += 1

func _test_special_tabs() -> void:
	var stash := Stash.create_default()
	_check(stash.tabs.size() == Constants.STASH_TAB_COUNT + 3, "stash has general + 3 special tabs")
	var currency := stash.get_tab(GridInventory.Accepts.CURRENCY)
	var slates := stash.get_tab(GridInventory.Accepts.SLATE)
	_check(currency.width == Constants.STASH_CURRENCY_TAB_SIZE.x and slates.height == Constants.STASH_SLATE_TAB_SIZE.y, "special tab sizes from Constants")
	_check(currency.add(&"brand_fire", 3) == 0, "currency tab accepts currency")
	_check(currency.add(_weapon("Dagger")) == 1 and currency.add(Slate.new()) == 1, "currency tab rejects gear and slates")
	_check(currency.place(_weapon("Dagger"), Vector2i(5, 5)) == 1, "currency tab rejects placed gear")
	_check(slates.add(Slate.new()) == 0, "slate tab accepts slates")
	_check(slates.add(&"quickening") == 1 and slates.add(_weapon("Dagger")) == 1, "slate tab rejects currency and gear")
	var general: GridInventory = stash.tabs[0]
	_check(general.add(_weapon("Dagger")) == 0 and general.add(&"quickening") == 0 and general.add(Slate.new()) == 0, "general tab accepts anything")
	var carried := GridInventory.new()
	carried.add(_weapon("Mace"))
	var entry := carried.get_entries()[0]
	_check(not carried.transfer(entry, currency, Vector2i(6, 6)) and carried.has_content(entry.content), "transfer of gear to currency tab rejected")
	_check(carried.transfer(entry, general, Vector2i(6, 6)) and not carried.has_content(entry.content) and general.has_content(entry.content), "transfer to a general tab")
	_finished += 1

func _test_stash_crafting() -> void:
	var stash := Stash.create_default()
	var carried := GridInventory.new()
	carried.add(&"tempering", 2)
	carried.add(&"opening", 1)
	var resolver := CraftingResolver.create_default()
	resolver.currency = carried
	var item := _weapon("Saber")
	item.max_sockets = 3
	stash.tabs[1].add(item)
	var r := resolver.apply(item, &"tempering")
	_check(r.success and item.quality >= 2 and stash.tabs[1].has_content(item), "tempering works on a stash item")
	_check(carried.count_of(&"tempering") == 1, "orb taken from carried inventory")
	_check(resolver.apply(item, &"opening").success and item.sockets_rolled and carried.count_of(&"opening") == 0, "opening works on a stash item")
	_check(resolver.apply(item, &"opening").error == CraftResult.CraftError.SOCKETS_ALREADY_ROLLED, "stash item keeps its crafting state")
	var slate := Slate.new()
	slate.tolerance = 100
	stash.get_tab(GridInventory.Accepts.SLATE).add(slate)
	carried.add(&"edict_spell")
	_check(resolver.apply_edict(slate, &"edict_spell").success and slate.active_edict != null, "edict applied to a stashed slate")
	_finished += 1

func _test_brand_activation() -> void:
	var stash := Stash.create_default()
	var carried := GridInventory.new()
	stash.get_tab(GridInventory.Accepts.CURRENCY).add(&"brand_fire", 5)
	var active := ActiveBrands.new(carried)
	_check(not active.activate(&"brand_fire") and not active.is_active(&"brand_fire"), "brand in the stash can't be activated")
	var stack: GridInventory.Entry = stash.get_tab(GridInventory.Accepts.CURRENCY).get_entries()[0]
	_check(stash.get_tab(GridInventory.Accepts.CURRENCY).transfer(stack, carried, Vector2i.ZERO), "brand moved to carried inventory")
	_check(active.activate(&"brand_fire"), "carried brand can be activated")
	active.consume(&"brand_fire")
	_check(carried.count_of(&"brand_fire") == 4 and not active.is_active(&"brand_fire"), "consuming takes one from the carried stack")
	_finished += 1

func _test_save_round_trip() -> void:
	var inv := GridInventory.new()
	var sword := _weapon("Greatsword")
	sword.quality = 7
	inv.place(sword, Vector2i(3, 1))
	inv.add(&"quickening", 130)
	var slate := Slate.new()
	slate.display_name = "Test Slate"
	inv.place(slate, Vector2i(11, 5))
	var json: Dictionary = JSON.parse_string(JSON.stringify(inv.to_dict()))
	var copy := GridInventory.from_dict(json)
	_check(copy.get_entries().size() == 4 and copy.count_of(&"quickening") == 130, "round trip keeps entries and counts")
	var copied_sword = copy.entry_at(Vector2i(4, 4)).content
	_check(copied_sword is Weapon and copied_sword.quality == 7 and copy.entry_at(Vector2i(3, 1)).position == Vector2i(3, 1), "round trip keeps gear position and state")
	_check(copy.entry_at(Vector2i(11, 5)).content is Slate, "round trip keeps slates")
	var stash := Stash.create_default()
	stash.get_tab(GridInventory.Accepts.CURRENCY).add(&"brand_cold", 7)
	var stash_copy := Stash.from_dict(JSON.parse_string(JSON.stringify(stash.to_dict())))
	_check(stash_copy.tabs.size() == stash.tabs.size() and stash_copy.get_tab(GridInventory.Accepts.CURRENCY).count_of(&"brand_cold") == 7, "stash round trip keeps tab types and contents")
	_finished += 1

func _test_debug_screen() -> void:
	var screen = load("res://ui/debug/inventory_debug/InventoryDebugScreen.tscn").instantiate()
	add_child(screen)
	GameState.inventory = GridInventory.new()
	screen.open()
	_check(not get_tree().paused, "opening the inventory doesn't pause")
	screen._add_currency()
	screen._add_gear()
	_check(GameState.inventory.count_of(&"quickening") == 20, "debug screen adds currency")
	screen.close()
	var inventory_screen = load("res://ui/inventory/InventoryScreen.gd")
	_check(FileAccess.get_file_as_string(inventory_screen.resource_path).contains("paused = true"), "inventory screen pauses the game")
	_finished += 1
