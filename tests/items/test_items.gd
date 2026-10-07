extends Node
## Non-gear item tagging (Figments/tomes were read as Helmets), crafting
## stones as stackable currency (incl. old saves holding them as Items),
## and selling to the Gear Shop.
## Run: Godot --headless --path . res://tests/items/test_items.tscn --quit-after 3000

var _checks := 0
var _failures := 0

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _old_item(id: String) -> Item:
	var item := Item.new()
	item.item_id = id
	item.display_name = id
	return item

func _ready() -> void:
	GameState.reset_to_defaults()
	var card: Node = load("res://ui/item_card/ItemCard.tscn").instantiate()
	var fig := FigmentRoller.roll(1)
	_check(GridInventory.footprint_of(fig) == Vector2i.ONE, "figments take 1x1")
	_check(not card._item_type_line(fig).contains("Helmet"), "figments aren't labelled Helmet")
	var tome := SkillTome.new()
	_check(card._item_type_line(tome) == "Skill Tome", "skill tomes are labelled Skill Tome")
	var ring := Item.new()
	ring.equip_slot = Constants.EquipmentSlot.RING
	_check(ring.is_equipment() and ring.get_item_type() == &"ring", "rings are still equipment")
	var helm := Armor.new()
	helm.equip_slot = Constants.EquipmentSlot.HELMET
	_check(helm.get_item_type() == &"helmet" and GridInventory.footprint_of(helm) == Vector2i(2, 2), "real helmets are still 2x2 helmets")
	card.free()

	# Crafting stones are currency stacks.
	var inv := GridInventory.new()
	for id in Constants.CRAFTING_CONSUMABLE_IDS:
		_check(CurrencyText.name_of(StringName(id)) != id, "%s has a display name" % id)
		_check(CurrencyText.description_of(StringName(id)) != "", "%s has a description" % id)
	inv.add(&"shard_of_tharsis", 3)
	inv.add(_old_item("shard_of_tharsis"))
	_check(inv.count_of(&"shard_of_tharsis") == 4, "an old Item shard joins the currency stack")
	_check(inv.get_entries().size() == 1, "shards share one 1x1 stack")
	# An old save with shards stored as separate Items loads as one stack.
	var old_save := {"width": 12, "height": 5, "entries": [
		{"x": 0, "y": 0, "count": 1, "item": ItemSerializer.to_dict(_old_item("shard_of_tharsis"))},
		{"x": 2, "y": 0, "count": 1, "item": ItemSerializer.to_dict(_old_item("shard_of_tharsis"))},
		{"x": 4, "y": 0, "count": 1, "item": ItemSerializer.to_dict(_old_item("infusion_stone"))},
	]}
	var loaded := GridInventory.from_dict(old_save)
	_check(loaded.count_of(&"shard_of_tharsis") == 2 and loaded.count_of(&"infusion_stone") == 1, "old saved stones load as currency")
	_check(loaded.get_entries().all(func(e): return e.is_currency()), "no stone stays an Item after loading")

	# A saved shield keeps its base line (and so its 2x2 size), also from
	# saves written before the line was saved.
	var buckler := (load("res://data/shields/instances/gen_buckler_crude_buckler.tres") as Item).duplicate(true)
	buckler.item_id = "gen_buckler_crude_buckler_rolled_42"
	var sd := ItemSerializer.to_dict(buckler)
	_check(GridInventory.footprint_of(ItemSerializer.from_dict(sd)) == Vector2i(2, 2), "a reloaded buckler is 2x2")
	for key in ["base_line_id", "item_level", "evasion_value"]:
		sd.erase(key)
	var old_buckler := ItemSerializer.from_dict(sd)
	_check(GridInventory.footprint_of(old_buckler) == Vector2i(2, 2), "a buckler from an old save is 2x2")
	_check(old_buckler.evasion_value == buckler.evasion_value and old_buckler.stat_requirement_value == buckler.stat_requirement_value, "old-save shields get their base evasion and requirements back")
	var small := GridInventory.from_dict({"width": 12, "height": 6, "entries": []})
	small.grow_to(Constants.INVENTORY_SIZE)
	_check(small.width == 14 and small.height == 7, "old 12x6 inventories grow to 14x7")

	# Selling
	var sold := Item.new()
	sold.item_id = "test_ring"
	sold.display_name = "Test Ring"
	sold.equip_slot = Constants.EquipmentSlot.RING
	sold.rarity = Constants.ItemRarity.RARE
	_check(GameState.add_to_inventory(sold), "ring goes in the inventory")
	var gold_before := GameState.gold
	var screen: ShopScreen = load("res://ui/shop/ShopScreen.tscn").instantiate()
	add_child(screen)
	var entry := {"label": sold.display_name, "price": GearShop.sell_price(sold), "item": sold,
		"on_sell": func(): return GameState.remove_from_inventory(sold)}
	screen.open_with("Test", [], {}, [entry])
	var sell_button: Button = null
	for row in screen.list.get_children():
		if row is HBoxContainer and (row.get_child(2) as Button).text == "Sell":
			sell_button = row.get_child(2)
	_check(sell_button != null, "shop lists inventory items to sell")
	if sell_button:
		sell_button.pressed.emit()
	_check(not GameState.get_inventory_items().has(sold), "selling removes the item")
	_check(GameState.gold == gold_before + GearShop.sell_price(sold), "selling pays gold")
	if sell_button:
		sell_button.pressed.emit()
	_check(GameState.gold == gold_before + GearShop.sell_price(sold), "a sold row can't be sold twice")
	screen.close()

	print("item tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
