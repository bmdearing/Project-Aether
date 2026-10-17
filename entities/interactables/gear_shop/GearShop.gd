extends Node3D
class_name GearShop
## Hub interactable, same proximity+E pattern as RealityEngine, opens the
## VendorScreen. Stock is ItemRoller.roll()'d and kept (GameState.shop_stock,
## saved) until the player levels up or RESTOCK_SECONDS of play pass, or
## rerolled on demand via "Reroll Stock" (REROLL_COST Gold).
##
## Gold is an invented currency, no doc-sourced economy exists.
## COST_BY_RARITY/REROLL_COST are loosely modeled after ItemRoller/
## FigmentRoller's own invented tuning.

const STOCK_SIZE := 6
const REROLL_COST := 15
## Four hours of play.
const RESTOCK_SECONDS := 4.0 * 3600.0
const COST_BY_RARITY := {
	0: 20,   # Constants.ItemRarity.COMMON
	1: 50,   # UNCOMMON
	2: 120,  # RARE
}
## Selling pays a fraction of what that rarity would cost to buy.
const SELL_PRICE_BY_RARITY := {
	0: 5,    # COMMON
	1: 12,   # UNCOMMON
	2: 30,   # RARE
	3: 75,   # UNIQUE
	4: 150,  # MYTHIC
}

@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: bool = false
## The stock as a grid (STOCK_GRID cells), shown by the VendorScreen.
var _stock: GridInventory
const STOCK_GRID := Vector2i(12, 8)

func _ready() -> void:
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false
	_refresh_stock()

## No Map-tier context in the Hub - player level stands in instead, floored
## at MIN_SHOP_ITEM_LEVEL so a level-1/standalone session (Hub launched
## directly, no save) still gets a full pool instead of 0-2 items. Matches
## GameState.initialize_standalone()'s player_level so standalone-shop
## items are never above what the player can actually equip.
const MIN_SHOP_ITEM_LEVEL := 5
## UniqueCatalog ids kept in stock at TEST_STOCK_COST when Dev.enabled (just Arkanus;
## the Unique Catalogue has them all).
const TEST_STOCK := ["arkanus"]
const TEST_STOCK_COST := 1

## The saved stock, rerolled once the player has levelled or enough play time passed.
func _refresh_stock() -> void:
	var stale := GameState.shop_stock == null or GameState.shop_stock_level != GameState.player_level \
		or GameState.play_time - GameState.shop_stock_time >= RESTOCK_SECONDS
	if stale:
		_roll_stock()
	else:
		_stock = GameState.shop_stock

func _roll_stock() -> void:
	_stock = GridInventory.new(STOCK_GRID.x, STOCK_GRID.y)
	var shop_item_level := maxi(GameState.player_level, MIN_SHOP_ITEM_LEVEL)
	for i in range(STOCK_SIZE):
		var item := ItemRoller.roll(shop_item_level, 1.0)
		if item:
			_stock.add(item)
	for id in (TEST_STOCK if Dev.enabled else []):
		for def in UniqueCatalog.DEFS:
			if def["id"] == id:
				_stock.add(UniqueRoller.build(def, shop_item_level))
	GameState.shop_stock = _stock
	GameState.shop_stock_level = GameState.player_level
	GameState.shop_stock_time = GameState.play_time

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact") and not get_tree().paused:
		get_viewport().set_input_as_handled()
		_open_shop()

func _open_shop() -> void:
	_refresh_stock()
	var sold := sell_trash()
	VendorScreen.open_for(get_tree(), {
		"title": "Gear Shop",
		"stock": _stock,
		"buy_price": buy_price,
		"sell_price": func(content) -> int: return sell_price(content) if content is Item else 0,
		"action": {"label": "Reroll Stock", "cost": REROLL_COST, "on_action": _reroll_and_reopen},
		"notice": "Sold %d Trash item%s for %d Gold." % [sold.x, "" if sold.x == 1 else "s", sold.y] if sold.x > 0 else "",
	})

func buy_price(content) -> int:
	var item := content as Item
	if item == null:
		return 0
	return TEST_STOCK_COST if TEST_STOCK.has(item.unique_id) else COST_BY_RARITY.get(item.rarity, 20)

## Sells every carried item marked Trash. Returns (items sold, Gold gained).
static func sell_trash() -> Vector2i:
	var sold := Vector2i.ZERO
	for content in GameState.get_inventory_items():
		var item := content as Item
		if item and item.mark == Item.Mark.TRASH and GameState.remove_from_inventory(item):
			sold += Vector2i(1, sell_price(item))
	GameState.gold += sold.y
	return sold

static func sell_price(item: Item) -> int:
	return SELL_PRICE_BY_RARITY.get(item.rarity, 5)

## A fresh stock grid, reopened so the screen shows it.
func _reroll_and_reopen() -> void:
	_roll_stock()
	_open_shop()

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		GameSettings.refresh_interact_prompt(prompt_label)
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false
