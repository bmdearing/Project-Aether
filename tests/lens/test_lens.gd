extends Node
## Lenses and the Fate Board placement rules: rolling, saving, the tag
## connection rule (and saved boards keeping their Slates), distance cost,
## and each radius modifier - bridge, free placement, cheap, amplify - plus
## the Lens's own jewel modifiers; socketing in the inventory.
## Run: Godot --headless --path . res://tests/lens/test_lens.tscn
## Exits 0 when every check passes. Never writes the save file.

const HUB := "res://levels/hub/Hub.tscn"
const TEST_COUNT := 6
const A := FateBoard.ANCHOR_CELL

var _checks := 0
var _failures := 0
var _finished := 0

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
	GameState.game_started = false
	_test_roll()
	_test_save()
	_test_rules()
	_test_lens_effects()
	_test_amplify()
	await _test_inventory()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("lens tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

## A 1x2 Slate of `tag` (two tiles side by side).
func _slate(tag: int, cost: int = 1) -> Slate:
	var s := Slate.new()
	s.slate_id = "test_%d" % randi()
	s.display_name = "%s Slate" % Constants.DAMAGE_TYPE_NAME.get(tag, "?")
	s.tag = tag
	var shape: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	s.shape_cells = shape
	s.aether_cost = cost
	return s

func _lens(mod: String, radius: int = 3, tag: int = -1, value: float = 0.0) -> Lens:
	var l := Lens.new()
	l.radius = radius
	l.radius_mod = mod
	l.radius_tag = tag
	l.radius_value = value
	l.display_name = "Test Lens"
	return l

func _board() -> FateBoard:
	var b := FateBoard.new()
	b.aether_capacity = 100
	return b

func _test_roll() -> void:
	var radii := {}
	var mods := {}
	for i in 300:
		var lens := LensRoller.roll(60, 3.0)
		radii[lens.radius] = true
		mods[lens.radius_mod] = true
		_check(lens.affixes.size() <= 2 and lens.radius_text() != "", "a Lens has a radius modifier and at most 2 jewel modifiers")
		if lens.affixes.size() > 2 or lens.radius_text() == "":
			break
	_check(radii.has(2) and radii.has(3) and radii.has(4), "Lenses roll Small, Medium and Large radii")
	_check(mods.size() == LensRoller.RADIUS_MODS.size(), "every radius modifier can roll")
	var sockets := {}
	for i in 200:
		var s := SlateRoller.roll(30)
		sockets[s.sockets] = true
		if s.get_size() < 5 and s.sockets > 0:
			_check(false, "small Slates have no sockets")
	_check(sockets.has(0) and sockets.has(1) and sockets.has(2), "Slates roll 0-2 Lens sockets")
	_check(LensRoller.roll(10).get_item_type() == &"lens", "a Lens is its own item type")
	_finished += 1

func _test_save() -> void:
	var slate := _slate(Constants.DamageType.FIRE)
	slate.sockets = 2
	slate.lenses.append(_lens("amplify_tag", 4, Constants.DamageType.FIRE, 30.0))
	var copy := SlateSerializer.from_dict(JSON.parse_string(JSON.stringify(SlateSerializer.to_dict(slate))))
	_check(copy.sockets == 2 and copy.lenses.size() == 1 and copy.lenses[0].radius == 4 and copy.lenses[0].radius_mod == "amplify_tag" and is_equal_approx(copy.lenses[0].radius_value, 30.0), "Slate sockets and their Lenses survive a save")
	var loose := ItemSerializer.from_dict(JSON.parse_string(JSON.stringify(ItemSerializer.to_dict(_lens("cheap", 2)))))
	_check(loose is Lens and (loose as Lens).radius_mod == "cheap", "a loose Lens loads as a Lens")
	_finished += 1

func _test_rules() -> void:
	var board := _board()
	var fire := _slate(Constants.DamageType.FIRE)
	_check(board.place_slate(fire, A + Vector2i(1, 0)) != "", "a Slate next to the anchor places")
	var cold := _slate(Constants.DamageType.COLD)
	_check(board._placement_failure_reason(cold, A + Vector2i(3, 0), 0, false) == "tag_not_connected", "a Cold Slate can't hang off only a Fire Slate")
	var fire2 := _slate(Constants.DamageType.FIRE)
	_check(board.place_slate(fire2, A + Vector2i(3, 0)) != "", "a Fire Slate can")
	var hybrid := _slate(Constants.DamageType.FIRE)
	hybrid.is_hybrid = true
	hybrid.secondary_tag = Constants.DamageType.COLD
	_check(board.place_slate(hybrid, A + Vector2i(5, 0)) != "", "a Fire/Cold Hybrid joins the Fire chain")
	_check(board.place_slate(_slate(Constants.DamageType.COLD), A + Vector2i(7, 0)) != "", "...and a Cold Slate can hang off the Hybrid")
	# Saved boards keep Slates placed before the rule.
	var old := _board()
	_check(old.place_slate(_slate(Constants.DamageType.PALE), A + Vector2i(1, 0)) != "" and old.place_slate(_slate(Constants.DamageType.COLD), A + Vector2i(3, 0), 0, false, "", true) != "", "restoring a save skips the rule")
	_check(old._placement_failure_reason(_slate(Constants.DamageType.FIRE), A + Vector2i(5, 0), 0, false) == "tag_not_connected", "new placements still follow it")
	# Distance cost.
	var near := board.placement_cost(_slate(Constants.DamageType.FIRE, 2), [A + Vector2i(1, 0)])
	var far := board.placement_cost(_slate(Constants.DamageType.FIRE, 2), [A + Vector2i(12, 0)])
	_check(near == 2 and far == 2 + 12 / FateBoard.AETHER_RING_SIZE, "Slates cost +1 Aether per %d tiles from the anchor (%d, %d)" % [FateBoard.AETHER_RING_SIZE, near, far])
	var used_before := board.aether_used
	var id := board.place_slate(_slate(Constants.DamageType.COLD), A + Vector2i(9, 0))
	var paid: int = board.placements[id].aether_paid
	board.remove_slate(id)
	_check(board.aether_used == used_before and paid >= 2, "removal refunds what the Slate paid")
	_finished += 1

func _test_lens_effects() -> void:
	var board := _board()
	var host := _slate(Constants.DamageType.FIRE)
	host.sockets = 2
	host.lenses.append(_lens("bridge_tag", 3, Constants.DamageType.COLD))
	board.place_slate(host, A + Vector2i(1, 0))
	_check(board.place_slate(_slate(Constants.DamageType.COLD), A + Vector2i(3, 0)) != "", "a bridging Lens lets a Cold Slate hang off Fire")
	var chains := ChainCalculator.compute_chains(board)
	_check(chains.any(func(c): return c.tag == Constants.DamageType.COLD and c.tile_count == 4), "the bridged Slate joins the Cold chain")
	var far_cell := A + Vector2i(30, 0)
	_check(board.lens_effects_at([far_cell]).is_empty(), "effects stop at the radius")
	var free_board := _board()
	var free_host := _slate(Constants.DamageType.FIRE)
	free_host.lenses.append(_lens("free_placement", 3))
	free_board.place_slate(free_host, A + Vector2i(1, 0))
	_check(free_board._placement_failure_reason(_slate(Constants.DamageType.PALE), A + Vector2i(3, 0), 0, false) == "", "a free-placement Lens waives the connection rule")
	var cheap_host := _slate(Constants.DamageType.FIRE)
	cheap_host.lenses.append(_lens("cheap", 4, -1, 1.0))
	var cheap_board := _board()
	cheap_board.place_slate(cheap_host, A + Vector2i(1, 0))
	_check(cheap_board.placement_cost(_slate(Constants.DamageType.FIRE, 3), [A + Vector2i(3, 0), A + Vector2i(4, 0)]) == 2, "a cheap Lens takes 1 off the cost")
	_check(cheap_board.placement_cost(_slate(Constants.DamageType.FIRE, 1), [A + Vector2i(3, 0)]) == 1, "never below 1")
	_finished += 1

func _test_amplify() -> void:
	var board := _board()
	var host := _slate(Constants.DamageType.FIRE)
	var dmg := ItemAffix.new()
	dmg.stat_key = "fire_increased_damage"
	dmg.value = 20.0
	host.explicits.append(dmg)
	board.place_slate(host, A + Vector2i(1, 0))
	_check(ChainCalculator.slate_misc_bonuses(board).get("increased_fire_damage", 0.0) == 20.0, "plain Slate modifier")
	host.lenses.append(_lens("amplify_tag", 2, Constants.DamageType.FIRE, 50.0))
	_check(is_equal_approx(ChainCalculator.slate_misc_bonuses(board).get("increased_fire_damage", 0.0), 30.0), "a Fire amplify Lens makes Fire Slates in radius 50% stronger")
	host.lenses[0].radius_tag = Constants.DamageType.COLD
	_check(ChainCalculator.slate_misc_bonuses(board).get("increased_fire_damage", 0.0) == 20.0, "...but only Slates of its tag")
	host.lenses.clear()
	var stat_line := SlateModifier.new()
	stat_line.stat_key = "flat_strength"
	stat_line.value = 10.0
	host.modifiers.append(stat_line)
	var plain_str: float = ChainCalculator.slate_stat_bonuses(board, ChainCalculator.compute_chains(board)).get(Constants.Stat.STRENGTH, 0.0)
	host.lenses.append(_lens("amplify_attributes", 2, -1, 40.0))
	var boosted_str: float = ChainCalculator.slate_stat_bonuses(board, ChainCalculator.compute_chains(board)).get(Constants.Stat.STRENGTH, 0.0)
	_check(is_equal_approx(boosted_str, plain_str * 1.4), "an attribute Lens makes attribute lines 40% stronger")
	var own := ItemAffix.new()
	own.stat_key = "cast_speed"
	own.value = 7.0
	host.lenses[0].affixes.append(own)
	_check(ChainCalculator.slate_misc_bonuses(board).get("cast_speed", 0.0) == 7.0, "a Lens's own modifiers count while its Slate is placed")
	_finished += 1

func _test_inventory() -> void:
	var hub: Node = load(HUB).instantiate()
	add_child(hub)
	await _frames(5)
	var screen := get_tree().get_first_node_in_group("inventory_screen") as InventoryScreen
	if screen == null:
		screen = hub.find_children("*", "InventoryScreen", true, false).front()
	screen.open()
	var slate := _slate(Constants.DamageType.FIRE)
	slate.sockets = 1
	var lens := _lens("cheap", 2, -1, 1.0)
	GameState.add_to_inventory(slate)
	GameState.add_to_inventory(lens)
	var entries := GameState.inventory.get_entries()
	var lens_entry: GridInventory.Entry = entries.filter(func(e): return e.content == lens)[0]
	var slate_entry: GridInventory.Entry = entries.filter(func(e): return e.content == slate)[0]
	screen._on_entry_right_clicked(screen.inventory_grid, lens_entry)
	screen._on_entry_clicked(screen.inventory_grid, slate_entry)
	_check(slate.lenses == [lens] and not GameState.inventory.has_content(lens), "a Lens sockets into a Slate")
	var gear := Item.new()
	gear.equip_slot = Constants.EquipmentSlot.RING
	gear.sockets = 1
	gear.max_sockets = 1
	screen._held_jewel = LensRoller.roll(10)
	screen._socket_into(gear)
	_check(gear.socketed.is_empty(), "Lenses don't go into gear")
	screen._release_jewel()
	screen._take_lenses_out(slate)
	_check(slate.lenses.is_empty() and GameState.inventory.has_content(lens), "Lenses come back out freely")
	GameState.remove_from_inventory(slate)
	GameState.remove_from_inventory(lens)
	screen.close()
	hub.queue_free()
	await _frames(1)
	_finished += 1
