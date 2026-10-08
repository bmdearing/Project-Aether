extends Node3D
class_name GearShop
## Hub interactable, same proximity+E pattern as RealityEngine, opens
## ShopScreen. Stock is ItemRoller.roll()'d fresh once per Hub visit, or
## on demand via "Reroll Stock" (REROLL_COST Gold) - browsing never rerolls.
##
## Gold is an invented currency, no doc-sourced economy exists.
## COST_BY_RARITY/REROLL_COST are loosely modeled after ItemRoller/
## FigmentRoller's own invented tuning.

const STOCK_SIZE := 6
const REROLL_COST := 15
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
var _shop_screen: ShopScreen
var _stock: Array[Item] = []

func _ready() -> void:
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false
	_roll_stock()

## Looked up lazily, not cached at _ready() - GearShop is declared before
## ShopScreen in Hub.tscn and siblings ready in declaration order, so a
## _ready()-time group lookup would find nothing.
func _get_shop_screen() -> ShopScreen:
	if not is_instance_valid(_shop_screen):
		_shop_screen = get_tree().get_first_node_in_group("shop_screen")
	return _shop_screen

## No Map-tier context in the Hub - player level stands in instead, floored
## at MIN_SHOP_ITEM_LEVEL so a level-1/standalone session (Hub launched
## directly, no save) still gets a full pool instead of 0-2 items. Matches
## GameState.initialize_standalone()'s player_level so standalone-shop
## items are never above what the player can actually equip.
const MIN_SHOP_ITEM_LEVEL := 5

func _roll_stock() -> void:
	_stock = []
	var shop_item_level := maxi(GameState.player_level, MIN_SHOP_ITEM_LEVEL)
	for i in range(STOCK_SIZE):
		var item := ItemRoller.roll(shop_item_level, 1.0)
		if item:
			_stock.append(item)

func _unhandled_input(event: InputEvent) -> void:
	var shop_screen := _get_shop_screen()
	if _player_in_range and event.is_action_pressed("interact") and shop_screen and not shop_screen.is_open():
		get_viewport().set_input_as_handled()
		_open_shop()

func _open_shop() -> void:
	var entries: Array = []
	for item in _stock:
		entries.append({
			"label": item.display_name,
			"cost": COST_BY_RARITY.get(item.rarity, 20),
			"color": _item_color(item),
			"item": item,
			"on_buy": func(): _buy(item),
		})
	var sell_entries: Array = []
	for content in GameState.get_inventory_items():
		var item := content as Item
		if item == null:
			continue
		sell_entries.append({
			"label": item.display_name,
			"price": sell_price(item),
			"color": _item_color(item),
			"item": item,
			"on_sell": func(): return GameState.remove_from_inventory(item),
		})
	_get_shop_screen().open_with("Gear Shop", entries, {
		"label": "Reroll Stock",
		"cost": REROLL_COST,
		"on_action": func(): _reroll_and_reopen(),
	}, sell_entries)

static func sell_price(item: Item) -> int:
	return SELL_PRICE_BY_RARITY.get(item.rarity, 5)

func _buy(item: Item) -> bool:
	if not GameState.add_to_inventory(item):
		return false
	_stock.erase(item)
	return true

## Re-opens rather than refreshes, so stock/button/Gold label all update
## through the same open_with() path a normal open uses.
func _reroll_and_reopen() -> void:
	_roll_stock()
	_open_shop()

## Rarity color, same as InventoryScreen._item_color().
func _item_color(item: Item) -> Color:
	return Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE)

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false
