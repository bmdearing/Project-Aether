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

## No Map-tier context in the Hub - player level stands in instead.
func _roll_stock() -> void:
	_stock = []
	for i in range(STOCK_SIZE):
		var item := ItemRoller.roll(GameState.player_level, 1.0)
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
	_get_shop_screen().open_with("Gear Shop", entries, {
		"label": "Reroll Stock",
		"cost": REROLL_COST,
		"on_action": func(): _reroll_and_reopen(),
	})

func _buy(item: Item) -> void:
	GameState.owned_loot.append(item)
	_stock.erase(item)

## Re-opens rather than refreshes, so stock/button/Gold label all update
## through the same open_with() path a normal open uses.
func _reroll_and_reopen() -> void:
	_roll_stock()
	_open_shop()

## Mirrors InventoryScreen._item_color() - rarity for every item type
## (Patch v3.8b: dropped weapons' damage-type exception).
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
