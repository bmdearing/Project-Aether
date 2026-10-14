extends Node
## The Hub's Currency Exchange: every Orb and crafting consumable for 1 Gold.
## Run: Godot --headless --path . res://tests/hub/test_currency_shop.tscn
## Exits 0 when every check passes.

var _checks := 0
var _failures := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _owned(id: StringName) -> int:
	var tab := GameState.stash.get_tab(GridInventory.Accepts.CURRENCY)
	return (tab.count_of(id) if tab else 0) + GameState.inventory.count_of(id)

func _run() -> void:
	SaveManager.slot_prefix = "user://test_currency_shop_slot"
	GameState.reset_to_defaults()
	GameState.game_started = false
	var hub: Node = load("res://levels/hub/Hub.tscn").instantiate()
	add_child(hub)
	for i in 10:
		await get_tree().process_frame
	var shop := hub.get_node("CurrencyShop") as CurrencyShop
	_check(shop != null, "the Hub has a Currency Exchange")
	var ids := CurrencyShop.currency_ids()
	_check(ids.size() == Constants.ORB_IDS.size() + Constants.CRAFTING_CONSUMABLE_IDS.size() + 25 + 7, "it sells every Orb, consumable, Brand and Edict (%d)" % ids.size())
	_check(ids.has(&"brand_fire") and ids.has(&"edict_level_83"), "Brands and Edicts are in stock")
	GameState.gold = 200
	var vendor := shop.open()
	var stock: GridInventory = vendor.config["stock"]
	_check(vendor._is_open and ids.all(func(id): return stock.count_of(id) == 1), "the stock shows every currency")
	var edict: StringName = &"edict_prefix"
	var before := _owned(edict)
	var entry: GridInventory.Entry = stock.get_entries().filter(func(e): return e.content == edict)[0]
	vendor.buy(entry)
	vendor.buy(entry)
	_check(GameState.gold == 198 and _owned(edict) == before + 2, "each costs 1 Gold")
	_check(stock.count_of(edict) == 1, "buying never draws the stock down")
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.pressed = true
	Input.parse_input_event(shift)
	await get_tree().process_frame
	if Input.is_key_pressed(KEY_SHIFT):
		vendor.buy(entry)
		_check(GameState.gold == 198 - VendorScreen.INFINITE_BULK and _owned(edict) == before + 2 + VendorScreen.INFINITE_BULK, "shift buys ten")
	_check(vendor.price_to_sell(edict) == 0, "the exchange doesn't buy")
	vendor.close()
	print("currency shop tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
