extends Node
## Jewels and sockets: rolling, crafting, stats from socketed jewels, saving,
## socketing through the inventory, the item card, the socket overlay, and
## the enemy animation LOD added alongside them.
## Run: Godot --headless --path . res://tests/jewels/test_jewels.tscn
## Exits 0 when every check passes. Never writes the save file.

const HUB := "res://levels/hub/Hub.tscn"
const ITEM_CARD := "res://ui/item_card/ItemCard.tscn"
const TEST_COUNT := 8

var _checks := 0
var _failures := 0
var _finished := 0
var _hub: Node
var _equipment: EquipmentComponent
var _screen: InventoryScreen

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
	_hub = load(HUB).instantiate()
	add_child(_hub)
	await _frames(5)
	_equipment = GameState.player_equipment
	_screen = _hub.get_node("InventoryScreen")

	_test_rolls()
	_test_crafting()
	_test_stats()
	_test_saving()
	_test_socketing()
	_test_card()
	await _test_overlay()
	await _test_animation_lod()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("jewel tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _jewel(stats: Dictionary, rarity: int = Constants.ItemRarity.RARE) -> Jewel:
	var jewel := Jewel.new()
	jewel.display_name = Jewel.DISPLAY_NAME
	jewel.item_id = "jewel_rolled_test"
	jewel.rarity = rarity
	for key in stats:
		var affix := ItemAffix.new()
		affix.stat_key = key
		affix.value = stats[key]
		affix.value_min = stats[key] - 1.0
		affix.value_max = stats[key] + 1.0
		affix.tier = 1
		affix.description = ItemRoller.format_desc(CraftingResolver._template_for(affix), affix.value) + " (Tier 1)"
		jewel.affixes.append(affix)
	return jewel

func _armor(sockets: int, strength: float = 0.0) -> Armor:
	var a := Armor.new()
	a.equip_slot = Constants.EquipmentSlot.GLOVES
	a.display_name = "Socket Gloves"
	a.item_id = "socket_gloves"
	a.max_sockets = sockets
	a.sockets = sockets
	if strength > 0.0:
		a.rarity = Constants.ItemRarity.UNCOMMON
		var affix := ItemAffix.new()
		affix.stat_key = "flat_strength"
		affix.value = strength
		affix.description = "+%d Strength (Tier 2)" % strength
		a.affixes.append(affix)
	return a

func _test_rolls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var limits_ok := true
	var values_ok := true
	var rare_counts_ok := true
	var saw_rare := false
	for i in 300:
		var rolled := JewelRoller.roll(10, 2.0, rng)
		var prefixes := rolled.affixes.filter(func(a: ItemAffix): return a.is_prefix).size()
		var suffixes := rolled.affixes.size() - prefixes
		var limits := rolled.get_affix_limits()
		limits_ok = limits_ok and prefixes <= limits.x and suffixes <= limits.y
		if rolled.rarity == Constants.ItemRarity.RARE:
			saw_rare = true
			rare_counts_ok = rare_counts_ok and rolled.affixes.size() >= 3 and rolled.affixes.size() <= 4
		for a in rolled.affixes:
			var in_pool := JewelModifierPool.STAT_KEYS.has(a.stat_key) and a.tier >= 1 and a.tier <= JewelModifierPool.TIER_COUNT
			values_ok = values_ok and in_pool and a.value >= a.value_min - 0.001 and a.value <= a.value_max + 0.001
	_check(limits_ok, "rolled jewels keep within 2 prefixes / 2 suffixes")
	_check(saw_rare and rare_counts_ok, "rare jewels roll 3-4 modifiers")
	_check(values_ok, "jewel modifiers come from the jewel pool with in-range values")
	var level1 := JewelModifierPool.defs_for(JewelRoller.roll(1, 2.0, rng))
	_check(level1.all(func(d: ModifierDef): return d.tiers.size() == 1 and d.tiers[0].tier == 3), "item level 1 jewels only reach Tier 3")

	var jewel := Jewel.new()
	jewel.item_level = 80  # Tier 1 needs item level 80
	var defs := JewelModifierPool.defs_for(jewel)
	_check(defs.size() == JewelModifierPool.STAT_KEYS.size(), "every jewel stat key exists in the affix pool (%d/%d)" % [defs.size(), JewelModifierPool.STAT_KEYS.size()])
	_check(defs.any(func(d): return d.affix_type == ModifierDef.AffixType.PREFIX) and defs.any(func(d): return d.affix_type == ModifierDef.AffixType.SUFFIX), "the pool has both prefixes and suffixes")
	var strength: ModifierDef = defs.filter(func(d): return d.stat_key == "flat_strength")[0]
	var gear_t1 := ItemRoller._tier_range(20.0, 25.0, 1)
	var gear_worst := ItemRoller._tier_range(20.0, 25.0, ItemRoller.TIER_COUNT)
	_check(strength.tiers.size() == 3, "jewel modifiers have three tiers")
	_check(strength.tiers[0].value_max < gear_t1.y and strength.tiers[2].value_min > gear_worst.x, "jewel bands sit inside gear's: below its best, above its worst")
	_check(jewel.get_item_type() == &"jewel" and not jewel.is_equipment(), "a jewel is its own type and can't be equipped")
	_finished += 1

func _test_crafting() -> void:
	var resolver := CraftingResolver.create_default()
	var jewel := Jewel.new()
	jewel.item_level = 80  # Tier 1 needs item level 80
	var r := resolver.apply(jewel, &"quickening")
	_check(r.success and jewel.rarity == Constants.ItemRarity.UNCOMMON and jewel.affixes.size() == 1, "Quickening makes an Uncommon jewel with one modifier")
	_check(jewel.affixes.all(func(a): return JewelModifierPool.STAT_KEYS.has(a.stat_key)), "Orbs roll from the jewel pool")
	var forged := Jewel.new()
	forged.item_level = 50
	r = resolver.apply(forged, &"forging")
	var prefixes := forged.affixes.filter(func(a: ItemAffix): return a.is_prefix).size()
	_check(r.success and forged.rarity == Constants.ItemRarity.RARE and forged.affixes.size() == 4 and prefixes == 2, "Forging fills a jewel to 2 prefixes + 2 suffixes")
	r = resolver.apply(forged, &"ascendant")
	_check(not r.success, "a full jewel takes no more modifiers")
	r = resolver.apply(Jewel.new(), &"opening")
	_check(not r.success, "jewels have no sockets to open")
	_finished += 1

func _test_stats() -> void:
	var gloves := _armor(2)
	gloves.socketed.append(_jewel({"flat_strength": 10.0}))
	_check(gloves.get_effective_affixes().size() == 1 and gloves.affixes.is_empty(), "socketed jewel modifiers count as the item's, without being added to it")
	var old := _equipment.get_equipped(Constants.EquipmentSlot.GLOVES)
	_equipment.equip(gloves, true)
	var bonus: float = _equipment.compute_stat_bonuses().get(Constants.Stat.STRENGTH, 0.0)
	_check(is_equal_approx(bonus, 10.0), "a socketed jewel feeds the stat totals (%.1f)" % bonus)
	gloves.sockets = 0
	bonus = _equipment.compute_stat_bonuses().get(Constants.Stat.STRENGTH, 0.0)
	_check(is_equal_approx(bonus, 0.0), "a jewel without a socket gives nothing")
	gloves.sockets = 2
	if old:
		_equipment.equip(old, true)
	else:
		_equipment.unequip(Constants.EquipmentSlot.GLOVES)
	_finished += 1

func _test_saving() -> void:
	var gloves := _armor(2)
	gloves.socketed.append(_jewel({"flat_strength": 10.0, "max_life": 8.0}))
	var copy := ItemSerializer.from_dict(JSON.parse_string(JSON.stringify(ItemSerializer.to_dict(gloves))))
	_check(copy.socketed.size() == 1 and copy.socketed[0] is Jewel, "socketed jewels survive a save as Jewels")
	_check(copy.socketed.size() == 1 and copy.socketed[0].affixes.size() == 2 and is_equal_approx(copy.socketed[0].affixes[0].value, 10.0), "jewel modifiers survive a save")
	var loose := ItemSerializer.from_dict(ItemSerializer.to_dict(_jewel({"cast_speed": 3.0})))
	_check(loose is Jewel and loose.get_item_type() == &"jewel", "a loose jewel loads as a Jewel")
	_finished += 1

func _test_socketing() -> void:
	_screen.open()
	var gloves := _armor(1)
	var jewel := _jewel({"flat_strength": 6.0})
	var spare := _jewel({"flat_agility": 6.0})
	GameState.inventory.add(gloves)
	GameState.inventory.add(jewel)
	GameState.inventory.add(spare)
	_screen._on_entry_right_clicked(_screen.inventory_grid, _entry_for(jewel))
	_check(_screen._held_jewel == jewel, "right-clicking a jewel picks it up")
	_screen._on_entry_clicked(_screen.inventory_grid, _entry_for(gloves))
	_check(gloves.socketed == [jewel] and not GameState.inventory.has_content(jewel), "clicking an item sets the jewel and takes it out of the grid")
	_screen._on_entry_right_clicked(_screen.inventory_grid, _entry_for(spare))
	_screen._on_entry_clicked(_screen.inventory_grid, _entry_for(gloves))
	_check(gloves.socketed.size() == 1 and GameState.inventory.has_content(spare), "a full item refuses another jewel")
	_screen._release_jewel()
	_screen._unsocket_all(gloves)
	_check(gloves.socketed.is_empty() and GameState.inventory.has_content(jewel), "unsocketing returns jewels to the grid")

	# Into equipped gear, through the paper doll.
	var worn := _armor(2)
	var old := _equipment.get_equipped(Constants.EquipmentSlot.GLOVES)
	_equipment.equip(worn, true)
	var before: float = _equipment.compute_stat_bonuses().get(Constants.Stat.STRENGTH, 0.0)
	_screen._on_entry_right_clicked(_screen.inventory_grid, _entry_for(jewel))
	_screen._on_doll_slot_pressed(_doll_row(Constants.EquipmentSlot.GLOVES))
	var after: float = _equipment.compute_stat_bonuses().get(Constants.Stat.STRENGTH, 0.0)
	_check(worn.socketed == [jewel] and is_equal_approx(after - before, 6.0), "a jewel set into worn gear raises its stats")
	_check(_equipment.get_equipped(Constants.EquipmentSlot.GLOVES) == worn, "socketing a worn item doesn't unequip it")
	_screen._unsocket_all(worn)
	if old:
		_equipment.equip(old, true)
	_screen.close()
	for item in [gloves, jewel, spare]:
		GameState.remove_from_inventory(item)
	_finished += 1

func _test_card() -> void:
	var gloves := _armor(2, 5.0)
	var card: ItemCard = load(ITEM_CARD).instantiate()
	add_child(card)
	card.display_item(gloves)
	_check(not _has_socket_row(card), "no socket row while nothing is socketed")
	gloves.socketed.append(_jewel({"flat_strength": 10.0, "max_life": 8.0}))
	card.display_item(gloves)
	var text := _card_text(card)
	_check(_has_socket_row(card), "socket row shows once a jewel is set")
	_check(text.contains("+15 Strength") and text.contains("+8 to Life") and not text.contains("Socketed"), "main card folds jewel modifiers into the explicits")
	card._showing_alt = true
	card._render_alt_info()
	text = _card_text(card)
	_check(text.contains("+5 Strength") and text.contains("Socketed (1/2)") and text.contains("+10(9-11) Strength"), "Alt splits socket modifiers into their own section")
	card.display_item(_jewel({"cast_speed": 4.0}))
	_check(_card_text(card).contains(ItemCard.JEWEL_HINT), "a jewel's card says how to socket it")
	card.queue_free()
	_finished += 1

func _test_overlay() -> void:
	var saved_setting := GameState.always_show_sockets
	GameState.always_show_sockets = false  # the player's own settings.cfg may have it on
	var button := Button.new()
	button.size = Vector2(72, 108)
	add_child(button)
	var overlay := SocketOverlay.new()
	button.add_child(overlay)
	overlay.item = _armor(3)
	await _frames(1)
	_check(overlay.size == button.size, "the overlay covers the item art")
	_check(not overlay.visible, "sockets are hidden until hovered")
	button.mouse_entered.emit()
	_check(overlay.visible, "hovering shows the sockets")
	button.mouse_exited.emit()
	GameState.always_show_sockets = true
	EventBus.settings_changed.emit()
	_check(overlay.visible, "the setting keeps them shown")
	GameState.always_show_sockets = false
	EventBus.settings_changed.emit()
	_check(not overlay.visible, "turning the setting off hides them again")
	var jewel := _jewel({"cast_speed": 4.0})
	overlay.item = jewel
	_check(not overlay.visible, "a socketless jewel leaves the overlay hidden")
	_check(IconArt.key_of(jewel) == &"jewel", "a jewel draws as a gem icon")
	GameState.always_show_sockets = saved_setting
	button.queue_free()
	await _frames(1)
	_finished += 1

func _test_animation_lod() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = Vector3(0, 1.6, 200)
	camera.look_at(Vector3(0, 1.6, 0))
	camera.make_current()
	var enemy := EnemyRoster.create_unit("hollowed_shambler")
	add_child(enemy)
	enemy.set_physics_process(false)
	await _frames(2)
	var anim: EnemyAnimationController = enemy._anim_controller
	_check(anim != null and anim._tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "enemy animation is advanced by the LOD, not every frame")
	if anim:
		var steps := {}
		for z in [190.0, 165.0, 150.0, 60.0, 260.0]:
			enemy.global_position = Vector3(0, 0, z)
			steps[z] = anim.lod_step()
		_check(steps[190.0] == 1, "full rate near the camera (%d)" % steps[190.0])
		_check(steps[165.0] == EnemyAnimationController.MID_STEP, "every other frame at mid range (%d)" % steps[165.0])
		_check(steps[150.0] == EnemyAnimationController.FAR_STEP, "every few frames far away (%d)" % steps[150.0])
		_check(steps[60.0] == 0, "frozen past the draw distance (%d)" % steps[60.0])
		_check(steps[260.0] == 0, "frozen behind the camera (%d)" % steps[260.0])
		enemy.global_position = Vector3(0, 0, 150)
		anim._pulse("attack_triggered")
		_check(anim.lod_step() == 1, "a pending trigger runs at full rate")
	var geometry := enemy.find_children("*", "GeometryInstance3D", true, false)
	_check(not geometry.is_empty() and geometry.any(func(g): return g.visibility_range_end == DrawDistance.ACTOR_RANGE), "enemy models have a draw distance")
	enemy.queue_free()
	camera.queue_free()
	await _frames(1)
	_finished += 1

func _has_socket_row(card: Node) -> bool:
	for child in card.find_children("*", "", true, false):
		if child is ItemCard.SocketRow:
			return true
	return false

func _card_text(node: Node) -> String:
	var out := ""
	for child in node.find_children("*", "", true, false):
		if child is Label:
			out += child.text + "\n"
		elif child is RichTextLabel:
			out += child.get_parsed_text() + "\n"
		elif child is ItemCard.LeaderRow:
			out += "%s: %s\n" % [child.label, child.value]
	return out

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
