extends Node
## Loot system: Magic Find conversion, how gear/Figment/enemy bonuses add up,
## weighted rarity, drop-roll counts, the new gear modifiers, Item Quantity
## and Rarity actually changing what a kill drops, the character sheet rows,
## the Rare drop beam, look-to-pick-up and the item card's Alt view.
## Run: Godot --headless --path . res://tests/loot/test_loot.tscn
## Exits 0 when every check passes. Never writes the save file.

const HUB := "res://levels/hub/Hub.tscn"
const LOOT_PICKUP := "res://entities/pickups/loot_pickup/LootPickup.tscn"
const TEST_COUNT := 10

var _checks := 0
var _failures := 0
var _finished := 0
var _hub: Node
var _player: Player

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
	_player = get_tree().get_first_node_in_group("player") as Player

	_test_magic_find()
	_test_multipliers()
	_test_rarity_weights()
	_test_roll_counts()
	_test_gear_modifiers()
	_test_character_sheet()
	await _test_kill_drops()
	await _test_rare_beam()
	await _test_look_pickup()
	await _test_card_alt()
	GameState.active_map = null
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("loot tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_magic_find() -> void:
	_check(is_equal_approx(Loot.quantity_percent({"magic_find": 10.0}), 5.0), "10 Magic Find = 5% Item Quantity")
	_check(is_equal_approx(Loot.rarity_percent({"magic_find": 10.0}), 20.0), "10 Magic Find = 20% Item Rarity")
	var both := {"magic_find": 10.0, "item_quantity": 4.0, "item_rarity": 15.0}
	_check(is_equal_approx(Loot.quantity_percent(both), 9.0) and is_equal_approx(Loot.rarity_percent(both), 35.0), "Magic Find adds to Item Quantity/Rarity from other mods")
	_finished += 1

func _test_multipliers() -> void:
	var figment := FigmentItem.new()
	figment.loot_quantity_multiplier = 1.2
	figment.loot_rarity_multiplier = 1.3
	GameState.active_map = figment
	var enemy_rarity := EnemyRarityComponent.new()
	enemy_rarity.rarity = Constants.EnemyRarity.ELITE
	enemy_rarity.affixes.append(load("res://data/enemies/affixes/pack_aggressive.tres") as EnemyAffix)
	var mods := Loot.multipliers(enemy_rarity, {"magic_find": 10.0})
	# Quantity: 20 Figment + 10 affix + 5 Magic Find. Rarity: 30 + 15 + 20.
	_check(is_equal_approx(mods["quantity"], 1.35), "gear, Figment and enemy Item Quantity add up (%.2f)" % mods["quantity"])
	_check(is_equal_approx(mods["rarity"], 1.65), "gear, Figment and enemy Item Rarity add up (%.2f)" % mods["rarity"])
	GameState.active_map = null
	mods = Loot.multipliers(null, {})
	_check(is_equal_approx(mods["quantity"], 1.0) and is_equal_approx(mods["rarity"], 1.0), "no bonuses outside a Figment = x1")
	enemy_rarity.free()
	_finished += 1

func _rarity_shares(multiplier: float, rolls: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var counts := {}
	for i in rolls:
		var r := Loot.roll_rarity(multiplier, rng)
		counts[r] = counts.get(r, 0) + 1
	var shares := {}
	for r in [Constants.ItemRarity.COMMON, Constants.ItemRarity.UNCOMMON, Constants.ItemRarity.RARE]:
		shares[r] = float(counts.get(r, 0)) / rolls
	return shares

func _test_rarity_weights() -> void:
	var base := _rarity_shares(1.0, 20000)
	var boosted := _rarity_shares(3.0, 20000)
	_check(absf(base[Constants.ItemRarity.RARE] - 0.06) < 0.01, "Rares drop without any Item Rarity (%.3f)" % base[Constants.ItemRarity.RARE])
	_check(absf(base[Constants.ItemRarity.UNCOMMON] - 0.22) < 0.015, "base Uncommon share (%.3f)" % base[Constants.ItemRarity.UNCOMMON])
	var w := Loot.rarity_weights(3.0)
	var w_total := 0.0
	for v in w.values():
		w_total += v
	_check(absf(boosted[Constants.ItemRarity.RARE] - w[Constants.ItemRarity.RARE] / w_total) < 0.01, "+200%% Item Rarity roughly doubles the Rare share (%.3f)" % boosted[Constants.ItemRarity.RARE])
	_check(boosted[Constants.ItemRarity.COMMON] < base[Constants.ItemRarity.COMMON] - 0.2, "Item Rarity makes Commons rarer")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var rares_ok := true
	var saw_rare := false
	for i in 400:
		var item := ItemRoller.roll(30)
		if item and item.rarity == Constants.ItemRarity.RARE:
			saw_rare = true
			var explicit := item.affixes.filter(func(a: ItemAffix): return not a.is_implicit).size()
			rares_ok = rares_ok and explicit >= 1
	_check(saw_rare and rares_ok, "plain gear drops include Rares, each with modifiers")
	_finished += 1

func _test_roll_counts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var total := 0
	for i in 10000:
		total += Loot.roll_count(2.3, rng)
	_check(absf(total / 10000.0 - 2.3) < 0.03, "fractional roll counts average out (%.3f)" % (total / 10000.0))
	_check(Loot.roll_count(3.0, rng) == 3, "a whole expected count is exact")
	var ascendant := EnemyRarityComponent.new()
	ascendant.rarity = Constants.EnemyRarity.ASCENDANT
	_check(is_equal_approx(Loot.base_drop_rolls(Constants.EnemyRank.NORMAL), 1.0), "a normal enemy gets one roll")
	_check(is_equal_approx(Loot.base_drop_rolls(Constants.EnemyRank.BOSS), 5.0), "a boss gets five")
	_check(is_equal_approx(Loot.base_drop_rolls(Constants.EnemyRank.NORMAL, ascendant), 4.0), "an Ascendant gets extra rolls")
	ascendant.free()
	_finished += 1

func _pool_keys(item: Item) -> Array:
	return ItemRoller._pool_for(item).map(func(e): return e["stat_key"])

func _test_gear_modifiers() -> void:
	var gloves := Armor.new()
	gloves.equip_slot = Constants.EquipmentSlot.GLOVES
	var amulet := Item.new()
	amulet.equip_slot = Constants.EquipmentSlot.AMULET
	var glove_keys := _pool_keys(gloves)
	var hood := Armor.new()
	hood.equip_slot = Constants.EquipmentSlot.HELMET
	hood.evasion_value = 40.0
	var hood_keys := _pool_keys(hood)
	_check(hood_keys.has("flat_evasion") and hood_keys.has("increased_evasion"), "an Evasion base rolls Evasion mods")
	_check(not hood_keys.has("flat_armor") and not hood_keys.has("increased_armor") and not hood_keys.has("increased_ward"), "an Evasion base never rolls Armour or Ward mods")
	var plate := Armor.new()
	plate.equip_slot = Constants.EquipmentSlot.BODY_ARMOUR
	plate.armor_value = 100.0
	plate.ward_value = 50.0
	var plate_keys := _pool_keys(plate)
	_check(plate_keys.has("increased_armor") and plate_keys.has("flat_ward") and not plate_keys.has("increased_evasion"), "an Armour/Ward base rolls both of those and no Evasion")
	var amulet_keys := _pool_keys(amulet)
	_check(glove_keys.has("item_rarity") and glove_keys.has("magic_find") and not glove_keys.has("item_quantity"), "armour rolls Item Rarity and Magic Find, not Quantity")
	_check(amulet_keys.has("item_quantity") and amulet_keys.has("item_rarity") and amulet_keys.has("magic_find"), "accessories roll all three")
	var sword := load("res://data/weapons/instances/crude_greatsword.tres") as Weapon
	if sword:
		var weapon_keys := []
		for want_prefix in [true, false]:
			for a in ItemRoller._eligible_weapon_affixes(sword, 50, want_prefix):
				weapon_keys.append(a.stat_key)
		_check(not weapon_keys.has("magic_find") and not weapon_keys.has("item_rarity"), "weapons don't roll loot modifiers")
	var jewel := Jewel.new()
	jewel.item_level = 50
	var jewel_keys := JewelModifierPool.defs_for(jewel).map(func(d): return d.stat_key)
	_check(jewel_keys.has("item_rarity") and jewel_keys.has("magic_find"), "jewels can roll Item Rarity and Magic Find")
	_check(GearModifierPool._is_suffix("magic_find") and GearModifierPool._is_suffix("item_rarity") and not GearModifierPool._is_suffix("item_quantity"), "Rarity and Magic Find are suffixes, Quantity a prefix")

	var ring := Item.new()
	ring.equip_slot = Constants.EquipmentSlot.RING
	ring.display_name = "Finder's Band"
	var mf := ItemAffix.new()
	mf.stat_key = "magic_find"
	mf.value = 10.0
	ring.affixes.append(mf)
	var equipment := GameState.player_equipment as EquipmentComponent
	var before := Loot.rarity_percent(Loot.player_bonuses())
	equipment.equip(ring, true)
	var after := Loot.rarity_percent(Loot.player_bonuses())
	_check(is_equal_approx(after - before, 20.0), "equipped Magic Find counts for the player (%.1f)" % (after - before))
	equipment.unequip(Constants.EquipmentSlot.RING, equipment.rings.find(ring))
	_finished += 1

func _test_character_sheet() -> void:
	var lists: Array[VBoxContainer] = [VBoxContainer.new(), VBoxContainer.new(), VBoxContainer.new()]
	for l in lists:
		add_child(l)
	StatSummaryBuilder.refresh(lists[0], lists[1], lists[2], _player)
	var text := ""
	for child in lists[2].find_children("*", "Label", true, false):
		text += (child as Label).text + "\n"
	_check(text.contains("Item Quantity") and text.contains("Item Rarity") and text.contains("Magic Find"), "the character sheet lists Item Quantity, Item Rarity and Magic Find")
	for l in lists:
		l.queue_free()
	_finished += 1

func _count_pickups(parent: Node) -> int:
	return parent.get_children().filter(func(n): return n is LootPickup and not n.is_queued_for_deletion()).size()

func _clear_pickups(parent: Node) -> void:
	for n in parent.get_children():
		if n is LootPickup:
			n.free()

func _test_kill_drops() -> void:
	var arena := Node3D.new()
	add_child(arena)
	arena.global_position = Vector3(500, 0, 500)
	var enemy := EnemyRoster.create_unit("hollowed_shambler")
	arena.add_child(enemy)
	enemy.set_physics_process(false)
	await _frames(2)
	var figment := FigmentItem.new()
	GameState.active_map = figment
	var kills := 60
	seed(21)
	for i in kills:
		enemy._maybe_drop_loot()
	var plain := _count_pickups(arena)
	_clear_pickups(arena)
	figment.loot_quantity_multiplier = 4.0  # +300% Item Quantity
	seed(21)
	for i in kills:
		enemy._maybe_drop_loot()
	var boosted := _count_pickups(arena)
	_check(plain > 0 and boosted > plain * 2.5, "Item Quantity multiplies what kills drop (%d -> %d)" % [plain, boosted])
	var spread := false
	for n in arena.get_children():
		if n is LootPickup and n.global_position.distance_to(enemy.global_position) > 0.05:
			spread = true
	_check(spread, "several drops spread out around the kill")
	_clear_pickups(arena)
	enemy.queue_free()
	arena.queue_free()
	GameState.active_map = null
	await _frames(1)
	_finished += 1

func _test_rare_beam() -> void:
	var rare := Item.new()
	rare.rarity = Constants.ItemRarity.RARE
	var common := Item.new()
	var pickups: Array[LootPickup] = []
	for item in [rare, common]:
		var p: LootPickup = load(LOOT_PICKUP).instantiate()
		p.item = item
		add_child(p)
		p.global_position = Vector3(600, 0, 600)
		pickups.append(p)
	_check(pickups[0].get_node_or_null("Beam") != null, "Rare drops have a light beam")
	_check(pickups[1].get_node_or_null("Beam") == null, "Common drops don't")
	for p in pickups:
		p.queue_free()
	await _frames(1)
	_finished += 1

func _look_pickup(item: Item, offset: Vector3) -> LootPickup:
	var p: LootPickup = load(LOOT_PICKUP).instantiate()
	p.item = item
	_hub.add_child(p)
	var cam := _player.camera
	p.global_position = cam.global_position + cam.global_transform.basis * offset
	p._base_y = p.position.y
	return p

func _test_look_pickup() -> void:
	var currency: LootPickup = load(LOOT_PICKUP).instantiate()
	currency.currency_id = Pinnacle.FRAGMENT_IDS[0]
	_check(currency.auto_pickup(), "currency and fragments are collected on touch")
	currency.free()
	for auto in [AmmoPack.new(), SkillTome.new(), FigmentItem.new()]:
		var p: LootPickup = load(LOOT_PICKUP).instantiate()
		p.item = auto
		_check(p.auto_pickup(), "%s is collected on touch" % auto.get_script().get_global_name())
		p.free()

	var sword := Weapon.new()
	sword.display_name = "Look Test Sword"
	sword.rarity = Constants.ItemRarity.RARE
	var ahead := _look_pickup(sword, Vector3(0, 0, -3))
	var aside := _look_pickup(Item.new(), Vector3(3, 0, 0))
	_check(not ahead.auto_pickup() and ahead.is_in_group(LootPickup.LOOK_GROUP), "gear waits to be picked up")
	_check(ahead.get_node_or_null("NameTag") != null and (ahead.get_node("NameTag") as Label3D).text == "Look Test Sword", "gear drops show their name")
	ahead._on_body_entered(_player)
	_check(not ahead.is_queued_for_deletion(), "walking over gear doesn't pick it up")
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _frames(2)
	var picker := _player.loot_picker
	_check(picker.target == ahead, "the drop in the middle of the view is the target")
	_check(ahead.mesh.scale.x > 1.0 and is_equal_approx(aside.mesh.scale.x, 1.0), "only the target is highlighted")
	var look_card: LootLookCard = _hub.find_children("*", "LootLookCard", true, false)[0] if not _hub.find_children("*", "LootLookCard", true, false).is_empty() else null
	_check(look_card != null and look_card._card.visible and look_card._card._current_item == sword, "the HUD shows the looked-at item's card")
	_check(look_card != null and look_card._prompt.text.begins_with("E "), "the prompt names the Interact key")

	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(2)
	_check((not is_instance_valid(ahead) or ahead.is_queued_for_deletion()) and GameState.inventory.has_content(sword), "Interact picks up the target")
	await get_tree().physics_frame
	await _frames(1)
	_check(picker.target == null and not look_card._card.visible, "nothing targeted afterwards: the card hides")
	var release := InputEventAction.new()
	release.action = &"interact"
	Input.parse_input_event(release)

	var far := _look_pickup(Item.new(), Vector3(0, 0, -(LootPicker.REACH + 2.0)))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(picker.target == null, "drops beyond reach aren't targeted")
	GameState.remove_from_inventory(sword)
	for p in [aside, far]:
		p.queue_free()
	await _frames(1)
	_finished += 1

func _card_texts(card: ItemCard) -> String:
	var texts: Array[String] = []
	for child in card._content().get_children():
		if child is Label and not child.is_queued_for_deletion():
			texts.append((child as Label).text)
	return "\n".join(texts)

func _test_card_alt() -> void:
	var ring := Item.new()
	ring.display_name = "Alt Test Ring"
	ring.equip_slot = Constants.EquipmentSlot.RING
	var own := ItemAffix.new()
	own.stat_key = "flat_strength"
	own.description = "+10 Strength"
	own.value = 10.0
	own.tier = 2
	ring.affixes.append(own)
	ring.sockets = 1
	var jewel := JewelRoller.roll(20)
	ring.socketed.append(jewel)
	var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
	add_child(card)
	card.display_item(ring)
	await _frames(1)
	_check(not _card_texts(card).contains("Socketed ("), "main card folds jewel mods in, no socket section")
	var alt := InputEventKey.new()
	alt.keycode = KEY_ALT
	alt.pressed = true
	Input.parse_input_event(alt)
	await _frames(2)
	var alt_text := _card_texts(card)
	_check(card._showing_alt, "holding Alt switches the card to Alt view")
	_check(alt_text.contains("[Tier 2]") and alt_text.contains("Socketed (1/1)"), "Alt view lists explicits, then the jewel mods in their own section")
	_check(alt_text.find("Strength") < alt_text.find("Socketed ("), "the socket section sits below the explicits")
	var up := InputEventKey.new()
	up.keycode = KEY_ALT
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)
	_check(not card._showing_alt and _card_texts(card).contains("Alt Test Ring"), "releasing Alt swaps back")
	card.queue_free()
	await _frames(1)
	_finished += 1
