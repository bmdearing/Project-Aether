extends Node
## Non-gear item tagging (currency/Figments/tomes were read as Helmets),
## inventory footprints, and selling to the Gear Shop.
## Run: Godot --headless --path . res://tests/items/test_items.tscn --quit-after 3000

var _checks := 0
var _failures := 0

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _ready() -> void:
	GameState.reset_to_defaults()
	var card: Node = load("res://ui/item_card/ItemCard.tscn").instantiate()
	for id in Constants.CRAFTING_CONSUMABLE_IDS:
		var c := load("res://data/consumables/instances/%s.tres" % id) as Item
		_check(not c.is_equipment(), "%s is not equipment" % id)
		_check(c.get_item_type() == &"currency", "%s is typed currency" % id)
		_check(GridInventory.footprint_of(c) == Vector2i.ONE, "%s takes 1x1" % id)
		_check(card._item_type_line(c) == "Currency", "%s is labelled Currency" % id)
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

	# Selling
	var shard := (load("res://data/consumables/instances/shard_of_tharsis.tres") as Item).duplicate()
	_check(GameState.add_to_inventory(shard), "shard goes in the inventory")
	var gold_before := GameState.gold
	var screen: ShopScreen = load("res://ui/shop/ShopScreen.tscn").instantiate()
	add_child(screen)
	var entry := {"label": shard.display_name, "price": GearShop.sell_price(shard), "item": shard,
		"on_sell": func(): return GameState.remove_from_inventory(shard)}
	screen.open_with("Test", [], {}, [entry])
	var sell_button: Button = null
	for row in screen.list.get_children():
		if row is HBoxContainer and (row.get_child(2) as Button).text == "Sell":
			sell_button = row.get_child(2)
	_check(sell_button != null, "shop lists inventory items to sell")
	if sell_button:
		sell_button.pressed.emit()
	_check(not GameState.get_inventory_items().has(shard), "selling removes the item")
	_check(GameState.gold == gold_before + GearShop.sell_price(shard), "selling pays gold")
	if sell_button:
		sell_button.pressed.emit()
	_check(GameState.gold == gold_before + GearShop.sell_price(shard), "a sold row can't be sold twice")
	screen.close()

	print("item tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
