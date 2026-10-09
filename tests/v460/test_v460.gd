extends Node
## Headless checks for the v4.60 batch: stash affinities, the currency and
## Figment tabs, Trash/Favored marks, item comparison, Fate Board removal
## and Lens rules, Slate bracket values, fist weapons, Lens crafting,
## treasure chests, the Spells screen, Tab cycling and the minimap/compass.
## Run: Godot --headless --path . res://tests/v460/test_v460.tscn --quit-after 6000
## Exits 0 when every check passes. Never writes the save file.

const MAP := "res://levels/generated_map/GeneratedMap.tscn"
const HUB := "res://levels/hub/Hub.tscn"

var _checks := 0
var _failures := 0
var _finished := 0
const TEST_COUNT := 11

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	_test_stash_affinity()
	_test_currency_tab()
	_test_marks_and_trash()
	_test_fate_board()
	_test_slate_brackets()
	_test_fists_and_lens_crafting()
	_test_small_helpers()
	await _test_map_chests()
	await _test_hub_screens()
	await _test_compare()
	_test_save_roundtrip()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("v4.60 tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _gear(type_check: Callable) -> Item:
	for i in 400:
		var item := ItemRoller.roll(30, 1.0)
		if item and type_check.call(item):
			return item
	return null

func _test_stash_affinity() -> void:
	var stash := Stash.create_default()
	_check(stash.get_tab(GridInventory.Accepts.FIGMENT) != null, "stash has a Figment tab")
	_check(stash.affinities.get("currency") == stash.tabs.find(stash.get_tab(GridInventory.Accepts.CURRENCY)), "currency affinity on by default")
	_check(stash.affinities.get("uniques") == Stash.UNIQUE_TAB, "unique affinity on by default")
	_check(stash.affinities.has("slates") and stash.affinities.has("figments"), "slate and figment affinities on by default")
	_check(not stash.tab_can_take(stash.tabs.find(stash.get_tab(GridInventory.Accepts.SLATE)), "weapons"), "slate tab can't collect weapons")
	stash.toggle_affinity("weapons", 2)
	_check(stash.affinities.get("weapons") == 2, "weapons affinity set on tab 3")
	GameState.stash = stash
	GameState.inventory = GridInventory.new()
	var screen: StashScreen = load("res://ui/stash/StashScreen.tscn").instantiate() if ResourceLoader.exists("res://ui/stash/StashScreen.tscn") else StashScreen.new()
	add_child(screen)
	var weapon := _gear(func(i): return i is Weapon and i.unique_id == "")
	GameState.inventory.add(weapon)
	var entry: GridInventory.Entry = GameState.inventory.get_entries()[0]
	_check(screen.deposit(entry), "weapon deposited")
	_check(stash.tabs[2].has_content(weapon), "weapon went to its affinity tab (tab 3), not the open tab")
	var figment := FigmentRoller.roll(1)
	GameState.inventory.add(figment)
	screen.deposit(GameState.inventory.get_entries()[0])
	_check(stash.get_tab(GridInventory.Accepts.FIGMENT).has_content(figment), "Figment went to the Figment tab")
	_check(stash.get_figments().has(figment), "stash lists its Figments for the Reality Engine")
	_check(stash.remove_content(figment) and stash.get_figments().is_empty(), "a stashed Figment can be taken out")
	GameState.inventory.add(&"quickening", 30)
	screen.deposit(GameState.inventory.get_entries()[0])
	_check(stash.get_tab(GridInventory.Accepts.CURRENCY).count_of(&"quickening") == 30, "currency went to the Currency tab")
	_check(screen.matches(weapon, weapon.display_name.to_lower()), "search matches an item by name")
	_check(not screen.matches(weapon, "zzqqxx"), "search misses nonsense")
	_check(screen.matches(&"quickening", "quickening"), "search matches currency by name")
	var copied := ItemText.of(weapon)
	_check(copied.begins_with(weapon.display_name) or copied.contains(weapon.display_name), "copied text has the item name")
	_check(copied.contains(ItemText.SEPARATOR), "copied text has section separators")
	screen.open()
	screen._search.text = "zzqqxx"
	screen._apply_search()
	screen.close()
	var restored := Stash.from_dict(JSON.parse_string(JSON.stringify(stash.to_dict())) as Dictionary)
	_check(restored.affinities.get("weapons") == 2, "affinities survive a save")
	var old := stash.to_dict()
	old.erase("affinities")
	(old["tabs"] as Array).pop_back()
	var migrated := Stash.from_dict(old)
	_check(migrated.get_tab(GridInventory.Accepts.FIGMENT) != null and migrated.affinities.has("currency"), "an old save gains the Figment tab and default affinities")
	screen.queue_free()
	_finished += 1

func _test_currency_tab() -> void:
	_check(CurrencyTabView.short_count(4999) == "4999", "4999 shown as is")
	_check(CurrencyTabView.short_count(50000) == "50K", "50000 shown as 50K")
	_check(CurrencyTabView.short_count(40500) == "40.5K", "40500 shown as 40.5K")
	var tab := GameState.stash.get_tab(GridInventory.Accepts.CURRENCY)
	tab.add(&"grafting", 250)
	var view := CurrencyTabView.new()
	add_child(view)
	view.set_inventory(tab)
	_check(view._slots.has(&"grafting") and view._slots[&"grafting"].count == 250, "grafting slot shows the total of every stack (250)")
	_check(view._slots.has(&"brand_fire"), "empty currencies still get a slot")
	view.queue_free()
	var screen := StashScreen.new()
	add_child(screen)
	GameState.inventory = GridInventory.new()
	screen._withdraw_currency(&"grafting", false)
	_check(GameState.inventory.count_of(&"grafting") == Constants.MAX_STACK and tab.count_of(&"grafting") == 150, "a click takes one stack")
	screen._withdraw_currency(&"grafting", true)
	_check(GameState.inventory.count_of(&"grafting") == 250 and tab.count_of(&"grafting") == 0, "shift-click takes the rest")
	screen.queue_free()
	_finished += 1

func _test_marks_and_trash() -> void:
	GameState.inventory = GridInventory.new()
	var trash := _gear(func(i): return i.is_equipment() and not i is Jewel)
	var kept := _gear(func(i): return i.is_equipment() and not i is Jewel)
	var favored := _gear(func(i): return i.is_equipment() and not i is Jewel)
	trash.mark = Item.Mark.TRASH
	favored.mark = Item.Mark.FAVORED
	for item in [trash, kept, favored]:
		GameState.inventory.add(item)
	var copy := ItemSerializer.from_dict(ItemSerializer.to_dict(favored))
	_check(copy.mark == Item.Mark.FAVORED, "mark survives a save")
	GameState.gold = 0
	var sold := GearShop.sell_trash()
	_check(sold.x == 1 and GameState.gold == GearShop.sell_price(trash), "only the Trash item auto-sold (%d)" % sold.x)
	_check(not GameState.inventory.has_content(trash) and GameState.inventory.has_content(kept) and GameState.inventory.has_content(favored), "the rest stays")
	_finished += 1

func _slate(cells: Array[Vector2i]) -> Slate:
	var s := Slate.new()
	s.slate_id = "test_%d" % randi()
	s.display_name = "Test Slate"
	s.tag = Constants.DamageType.FIRE
	s.aether_cost = 1
	s.shape_cells = cells
	return s

func _test_fate_board() -> void:
	var board := FateBoard.new()
	board.aether_capacity = 100
	var a := board.ANCHOR_CELL
	var near := board.place_slate(_slate([Vector2i.ZERO]), a + Vector2i(1, 0))
	var mid := board.place_slate(_slate([Vector2i.ZERO]), a + Vector2i(2, 0))
	var far := board.place_slate(_slate([Vector2i.ZERO]), a + Vector2i(3, 0))
	_check(near != "" and mid != "" and far != "", "three Slates placed in a line")
	_check(board.removal_breaks_chain(mid), "the middle Slate can't come out")
	_check(board.removal_breaks_chain(near), "the one by the center can't come out")
	_check(not board.removal_breaks_chain(far), "the outer Slate can")
	var socketed := _slate([Vector2i.ZERO, Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 2)])
	socketed.sockets = 1
	var host := board.place_slate(socketed, a + Vector2i(-2, 0))
	var lens := LensRoller.roll(10)
	_check(board.socket_lens(host, lens) == "", "a Lens goes into a placed Slate's socket")
	_check(board.placements[host].slate.lenses.has(lens), "the placed Slate holds the Lens")
	_check(board.socket_lens(host, LensRoller.roll(10)) == "no_free_socket", "no second Lens without a free socket")
	_check(board.socket_lens(near, LensRoller.roll(10)) == "no_sockets", "socketless Slate refuses")
	_finished += 1

func _test_slate_brackets() -> void:
	var slate := _slate([Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)])
	var mod := SlateModifier.new()
	mod.stat_key = "flat_strength"
	mod.value = 6.0
	mod.description = "+6.0 Strength (Main Stat)"
	slate.modifiers.append(mod)
	var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
	add_child(card)
	card.slate_amplifier = 1.5
	_check(card._slate_mod_text(mod, slate) == "+6.0 Strength (+9.0 Strength)", "placed: bracket shows the chain value (%s)" % card._slate_mod_text(mod, slate))
	card.slate_amplifier = -1.0
	_check(card._slate_mod_text(mod, slate).ends_with("(+6.3 Strength)"), "unplaced: its own 5-tile chain (%s)" % card._slate_mod_text(mod, slate))
	card.queue_free()
	_finished += 1

func _test_fists_and_lens_crafting() -> void:
	var fist := Weapon.new()
	fist.weapon_type = "Pressure Fist"
	_check(fist.is_two_handed, "Pressure Fist is two-handed")
	fist.weapon_type = "Spell Gauntlet"
	_check(fist.is_two_handed, "Spell Gauntlet is two-handed")
	fist.weapon_type = "Shortsword"
	_check(not fist.is_two_handed, "Shortsword stays one-handed")
	var resolver := CraftingResolver.create_default()
	var lens := LensRoller.roll(30)
	lens.rarity = Constants.ItemRarity.COMMON
	lens.affixes.clear()
	var result := resolver.apply(lens, &"quickening")
	_check(result.success, "Quickening works on a common Lens (%s)" % ("" if result.success else result.get_message()))
	var inv := GridInventory.new()
	inv.add(lens)
	var jewel := JewelRoller.roll(30)
	jewel.rarity = Constants.ItemRarity.COMMON
	jewel.affixes.clear()
	var jr := resolver.apply(jewel, &"quickening")
	_check(jr.success, "Quickening works on a common Jewel (%s)" % ("" if jr.success else jr.get_message()))
	_finished += 1

func _test_small_helpers() -> void:
	_check(is_equal_approx(Compass.heading_of(0.0), 0.0), "yaw 0 faces north")
	_check(is_equal_approx(Compass.heading_of(-PI / 2.0), 90.0), "turning right faces east (%.1f)" % Compass.heading_of(-PI / 2.0))
	var yaw := GeneratedMap.facing_away(Vector3.ZERO, Vector3(0, 0, -2), 1.0)
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	_check(forward.dot(Vector3(0, 0, -1)) > 0.99, "facing away from a portal behind you")
	_check(MenuTabStrip.SCREENS.size() == 5, "five screens in the Tab cycle")
	_check(InputMap.has_action("open_menu") and InputMap.has_action("mark_trash") and InputMap.has_action("mark_favored"), "new input actions exist")
	var k_bound := false
	for e in InputMap.action_get_events("open_abilities"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_K:
			k_bound = true
	_check(k_bound, "Spells screen is on K")
	var wiki := LensWiki.new()
	add_child(wiki)
	_check(wiki.shown.size() == LensRoller.RADIUS_MODS.size(), "Lens wiki lists every radius modifier")
	_check(Wiki.PAGES.has("Lenses"), "Wiki has a Lenses tab")
	wiki.queue_free()
	_finished += 1

func _test_map_chests() -> void:
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = "dungeon_crypt" if MapTileset.all_ids().has("dungeon_crypt") else MapTileset.all_ids()[0]
	GameState.active_map = figment
	var map: GeneratedMap = load(MAP).instantiate()
	add_child(map)
	await _frames(6)
	var chests := get_tree().get_nodes_in_group("treasure_chest")
	_check(chests.size() >= 2, "a Figment has treasure chests (%d)" % chests.size())
	var hud_minimap := map.find_children("*", "Minimap", true, false)
	_check(not hud_minimap.is_empty(), "the HUD has a minimap")
	_check(not map.find_children("*", "Compass", true, false).is_empty(), "the HUD has a compass")
	if chests.size() > 0:
		var chest: TreasureChest = chests[0]
		var pickups_before := map.get_children().filter(func(c): return c is LootPickup or c is GoldPickup).size()
		chest.open()
		await _frames(2)
		var pickups_after := map.get_children().filter(func(c): return c is LootPickup or c is GoldPickup).size()
		_check(pickups_after > pickups_before, "opening a chest drops loot (%d -> %d)" % [pickups_before, pickups_after])
		_check(chest.is_opened(), "chest is open")
		var floor_y := chest.global_position.y
		_check(absf(floor_y) < 3.0, "chest sits near the floor (y %.2f)" % floor_y)
		var state := map.capture_state()
		_check((state["chests_opened"] as Array).has(0), "opened chest saved in the map state")
	map.queue_free()
	await _frames(2)
	GameState.active_map = null
	_finished += 1

func _test_hub_screens() -> void:
	GameState.owned_ability_ids = ["spark", "blink"]
	var hub: Node = load(HUB).instantiate()
	add_child(hub)
	await _frames(4)
	var spells := get_tree().get_first_node_in_group("abilities_screen") as AbilitiesScreen
	spells.open()
	await _frames(2)
	_check(spells._grid.get_child_count() == 2, "the Spells grid shows owned spells (%d)" % spells._grid.get_child_count())
	var spark: Ability = spells._owned_abilities.filter(func(a): return a.ability_id == "spark")[0]
	spells._open_assign(spark)
	spells._assign_to(AbilityLoadoutComponent.SLOT_COUNT + 1)
	var player := get_tree().get_first_node_in_group("player") as Player
	_check(player.ability_loadout.slots[AbilityLoadoutComponent.SLOT_COUNT + 1] == spark, "right-click assign put Spark on Stance Page slot 2")
	spells._open_assign(spark)
	spells._assign_to(AbilityLoadoutComponent.SLOT_COUNT + 3)
	_check(player.ability_loadout.slots[AbilityLoadoutComponent.SLOT_COUNT + 1] == null, "a page never holds the same spell twice")
	spells._open_web(spark)
	_check(spells._web_page.visible and not spells._library.visible, "left-click opens the spell's page")
	spells.close()
	var pause := get_tree().get_first_node_in_group("full_screen_menu") as PauseMenu
	var tab := InputEventAction.new()
	tab.action = "open_menu"
	tab.pressed = true
	pause._input(tab)
	await _frames(1)
	_check(MenuTabStrip.open_index(get_tree()) == 0, "Tab opens the Inventory first")
	pause._input(tab)
	await _frames(1)
	_check(MenuTabStrip.open_index(get_tree()) == 1, "Tab again moves to the Character screen")
	var strip := hub.find_children("*", "MenuTabStrip", true, false)
	_check(not strip.is_empty() and (strip[0] as CanvasLayer).visible, "tab strip shows over the screen")
	for menu in get_tree().get_nodes_in_group("blocking_menu"):
		if menu.is_open():
			menu.close()
	hub.queue_free()
	await _frames(2)
	_finished += 1

func _test_compare() -> void:
	var map: GeneratedMap = load(MAP).instantiate()
	add_child(map)
	await _frames(4)
	var equipment := GameState.player_equipment as EquipmentComponent
	var helmet := _gear(func(i): return i.equip_slot == Constants.EquipmentSlot.HELMET)
	var other := _gear(func(i): return i.equip_slot == Constants.EquipmentSlot.HELMET and i != helmet)
	equipment.equip(helmet, true)
	var worn := ItemCompare.equipped_for(other)
	_check(worn.size() == 1 and worn[0] == helmet, "a helmet compares with the worn helmet")
	_check(ItemCompare.equipped_for(helmet).is_empty(), "the worn helmet compares with nothing")
	var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
	card.compare_against = ItemCompare.equipped_for(other)
	card.display_item(other)
	var wrapped := ItemCompare.wrap(card, other)
	_check(wrapped is HBoxContainer and wrapped.get_child_count() == 2, "hover card shows the equipped item beside it")
	var a := Armor.new()
	a.armor_value = 50.0
	var b := Armor.new()
	b.armor_value = 20.0
	var lines := ItemCompare.diff_lines(a, b)
	_check(lines.size() == 1 and lines[0]["gain"] and lines[0]["text"] == "+30 Armour", "armour diff reads +30 Armour (%s)" % str(lines))
	wrapped.free()
	map.queue_free()
	await _frames(2)
	_finished += 1

func _test_save_roundtrip() -> void:
	var d := GameState.stash.to_dict()
	_check(d.has("affinities"), "stash save has affinities")
	_finished += 1
