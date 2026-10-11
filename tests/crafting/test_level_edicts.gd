extends Node
## v4.83: the new top gear tier, the item-level Edicts (61/72/83), old-save
## tier migration, and the stash's Crafting Bench and currency tab layout.
## Run: Godot --headless --path . res://tests/crafting/test_level_edicts.tscn --quit-after 6000

var _checks := 0
var _failures := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _run() -> void:
	GameState.game_started = false
	_test_ladder()
	_test_edicts()
	_test_migration()
	_check(ImplicitPool.pool_for_type(&"amulet").any(func(a: ItemAffix): return a.stat_key == "additional_curses"), "an amulet can corrupt to +1 additional Curse")
	_check(not ImplicitPool.pool_for_type(&"ring").any(func(a: ItemAffix): return a.stat_key == "additional_curses"), "only amulets")
	await _test_bench()
	print("level edict tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

## A blank, craftable piece of real gear (not a weapon) at item_level.
func _gear(item_level: int) -> Item:
	for i in 200:
		var item := ItemRoller.roll(item_level)
		if item != null and not item is Weapon and not item is Jewel and item.is_equipment() and item.rarity < Constants.ItemRarity.UNIQUE:
			item = item.duplicate(true) as Item
			item.affixes = item.affixes.filter(func(a: ItemAffix): return a.is_implicit)
			item.rarity = Constants.ItemRarity.COMMON
			item.item_level = item_level
			item.tolerance = 1000
			item.tolerance_max = 1000
			item.is_corrupted = false
			return item
	return null

func _resolver() -> CraftingResolver:
	var r := CraftingResolver.create_default()
	var bag := CurrencyBag.new()
	for id in Constants.ORB_IDS:
		bag.add_currency(id, 100)
	for id in r.edict_defs:
		bag.add_currency(id, 100)
	r.currency = bag
	return r

func _explicits(item: Item) -> Array[ItemAffix]:
	var out: Array[ItemAffix] = []
	for a in item.affixes:
		if not a.is_implicit:
			out.append(a)
	return out

func _test_ladder() -> void:
	_check(ItemRoller.TIER_COUNT == 6, "gear has 6 tiers")
	_check([1, 2, 3, 4, 5, 6].map(func(t): return ItemRoller.tier_min_level(t)) == [83, 72, 61, 40, 21, 1], "tiers open at 83/72/61/40/21/1")
	_check(ItemRoller._tier_range(16.0, 20.0, 2).is_equal_approx(Vector2(16.0, 20.0)), "the authored range is Tier 2")
	_check(ItemRoller._tier_range(16.0, 20.0, 1).is_equal_approx(Vector2(20.0, 25.0)), "Tier 1 is a decay step above it")
	_check(ItemRoller.best_tier_for_level(82) == 2 and ItemRoller.best_tier_for_level(83) == 1, "Tier 1 needs item level 83")
	_check(ItemRoller.levelled_table("local_increased_weapon_damage")[0][0] == 83, "% weapon damage has an 83 tier")
	_check(JewelModifierPool.TIER_COUNT == 3 and ItemRoller.tier_min_level(1, JewelModifierPool.TIER_COUNT) == 80, "jewels keep their own ladder")

func _test_edicts() -> void:
	var r := _resolver()
	for level in [61, 72, 83]:
		var id := StringName("edict_level_%d" % level)
		_check(r.edict_defs.has(id) and Constants.CURRENCY_DROP_WEIGHTS.has(id) and CurrencyText.name_of(id) != String(id), "%s exists, drops and has a name" % id)
		var bad_adds := 0
		var adds := 0
		for i in 12:
			var item := _gear(90)
			_check(r.apply(item, &"quickening").success, "quickening a fresh item")
			_check(r.apply_edict(item, id).success, "%s placed" % id)
			var before := _explicits(item).size()
			var result := r.apply(item, &"grafting")
			if not result.success:
				continue
			for a in result.added:
				adds += 1
				if ItemRoller.affix_tier_level(a) < level:
					bad_adds += 1
			_check(_explicits(item).size() == before + 1 and item.active_edict == null, "the Edict is used up by the craft")
		_check(adds > 0 and bad_adds == 0, "%s only adds tiers needing %d+ (%d added, %d below)" % [id, level, adds, bad_adds])
	# Removal leaves modifiers at or above the level alone.
	var protected_ok := true
	var removed_any := false
	for i in 30:
		var item := _gear(90)
		r.apply(item, &"forging")
		var high := _explicits(item).filter(func(a: ItemAffix): return ItemRoller.affix_tier_level(a) >= 61)
		var low := _explicits(item).filter(func(a: ItemAffix): return ItemRoller.affix_tier_level(a) < 61)
		r.apply_edict(item, &"edict_level_61")
		var result := r.apply(item, &"severance")
		if high.size() > 0 and low.is_empty():
			protected_ok = protected_ok and not result.success and result.error == CraftResult.CraftError.NOTHING_TO_REMOVE
		elif result.success:
			removed_any = true
			protected_ok = protected_ok and result.removed.all(func(a: ItemAffix): return ItemRoller.affix_tier_level(a) < 61)
	_check(protected_ok and removed_any, "Edict of 61 Severance only removes tiers below 61")
	# Nothing qualifies on a lower-level item: refused at no cost.
	var low_item := _gear(70)
	r.apply(low_item, &"quickening")
	r.apply_edict(low_item, &"edict_level_83")
	var grafts: int = r.currency.count_of(&"grafting")
	var refused := r.apply(low_item, &"grafting")
	_check(not refused.success and int(r.currency.count_of(&"grafting")) == grafts, "Edict of 83 on an item level 70 item adds nothing and costs nothing")
	var jewel := JewelRoller.roll(80, 1.0)
	_check(jewel == null or not r.apply_edict(jewel, &"edict_level_72").success, "level Edicts are gear only")

func _test_migration() -> void:
	var item := _gear(90)
	var affix := ItemAffix.new()
	affix.stat_key = "flat_life"
	affix.tier = 1
	affix.value = 100.0
	affix.description = "+100 to Life (Tier 1)"
	item.affixes.append(affix)
	var d := ItemSerializer.to_dict(item)
	d.erase("tier_ladder")
	var old := ItemSerializer.from_dict(d)
	var moved: ItemAffix = old.affixes.filter(func(a: ItemAffix): return a.stat_key == "flat_life")[0]
	_check(moved.tier == 2 and moved.description.ends_with("(Tier 2)"), "an old save's Tier 1 becomes Tier 2 (%d)" % moved.tier)
	var again := ItemSerializer.from_dict(ItemSerializer.to_dict(old))
	_check(again.affixes.filter(func(a: ItemAffix): return a.stat_key == "flat_life")[0].tier == 2, "a new save isn't shifted again")

func _test_bench() -> void:
	var view := CurrencyTabView.new()
	add_child(view)
	view.set_inventory(GameState.stash.get_tab(GridInventory.Accepts.CURRENCY))
	var rects: Array[Rect2] = []
	for id in view._slots:
		rects.append(Rect2(view._slots[id].position, view._slots[id].size))
	rects.append(Rect2(view._bench.position, view._bench.size))
	var overlaps := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				overlaps += 1
	_check(overlaps == 0, "no currency slots overlap (%d)" % overlaps)
	_check(view.custom_minimum_size.x <= StashScreen.PAGE_SIZE.x and view.custom_minimum_size.y <= StashScreen.PAGE_SIZE.y, "the tab fits the stash page (%s)" % view.custom_minimum_size)
	_check(view._slots.has(&"edict_level_83"), "the new Edicts have slots")
	view.queue_free()

	var tab := GameState.stash.get_tab(GridInventory.Accepts.CURRENCY)
	tab.add(&"quickening", 5)
	GameState.inventory = GridInventory.new()
	var item := _gear(90)
	GameState.inventory.add(item)
	var screen := StashScreen.new()
	add_child(screen)
	screen.open()
	await get_tree().process_frame
	var entry: GridInventory.Entry = GameState.inventory.get_entries()[0]
	screen._on_bench_dropped({"grid_entry": entry, "view": screen._carried_view})
	_check(GameState.stash.bench == item and GameState.inventory.get_entries().is_empty(), "an item dropped on the bench leaves the inventory")
	_check(screen._bench_preview(&"quickening") != null and screen._bench_preview(&"quickening").is_valid(), "hovering an Orb previews it on the bench item")
	screen._use_on_bench(&"quickening")
	_check(_explicits(item).size() > 0 and tab.count_of(&"quickening") == 4, "right-clicking an Orb crafts the bench item with stash currency")
	var restored := Stash.from_dict(GameState.stash.to_dict())
	_check(restored.bench is Item and _explicits(restored.bench).size() == _explicits(item).size(), "the bench item is saved with the stash")
	screen._take_from_bench()
	_check(GameState.stash.bench == null and GameState.inventory.get_entries().size() == 1, "clicking the bench takes the item back")
	screen.queue_free()
