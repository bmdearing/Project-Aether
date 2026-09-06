extends Node3D
class_name BrandShop
## Hub interactable (dev/testing convenience, Implementation Brief v3.8c) -
## every real Brand purchasable for Gold, unlimited quantity. Same
## proximity+E pattern as GearShop/SpellTestShop, reuses the same shared
## ShopScreen via open_with() rather than building a second shop UI.
##
## Sources its brand list from Constants.BRAND_RARITIES directly (26 real
## ids, one per data/brands/instances/*.tres) rather than a hardcoded list -
## Facsimile/Amalgam/Imbue are cut from this project entirely (see Brand.
## gd's own header, no BrandRarity.LEGENDARY entries currently exist), so
## there's nothing to accidentally offer that can't actually be granted.
## Price scales by Constants.BrandRarity tier, not doc-sourced (no shop
## economy exists for Brands anywhere in the source material) - loosely
## following the same "common cheap, rare expensive" shape GearShop's own
## invented COST_BY_RARITY already uses.

const PRICE_BY_RARITY := {
	Constants.BrandRarity.COMMON: 50,
	Constants.BrandRarity.UNCOMMON: 200,
	Constants.BrandRarity.RARE: 800,
	Constants.BrandRarity.LEGENDARY: 5000,
}

const BRAND_DIR := "res://data/brands/instances/"

@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: bool = false
var _shop_screen: ShopScreen

func _ready() -> void:
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false

## Looked up lazily, not cached at _ready() - same declaration-order
## reasoning as GearShop._get_shop_screen().
func _get_shop_screen() -> ShopScreen:
	if not is_instance_valid(_shop_screen):
		_shop_screen = get_tree().get_first_node_in_group("shop_screen")
	return _shop_screen

func _unhandled_input(event: InputEvent) -> void:
	var shop_screen := _get_shop_screen()
	if _player_in_range and event.is_action_pressed("interact") and shop_screen and not shop_screen.is_open():
		get_viewport().set_input_as_handled()
		_open_shop()

## Grouped by rarity tier (cheapest first) since ShopScreen's list has no
## section headers of its own - sorted order is the only way to keep
## Common/Uncommon/Rare visually together.
func _open_shop() -> void:
	var brand_ids: Array = Constants.BRAND_RARITIES.keys()
	brand_ids.sort_custom(func(a, b): return Constants.BRAND_RARITIES[a] < Constants.BRAND_RARITIES[b])

	var entries: Array = []
	for brand_id in brand_ids:
		var brand: Brand = load(BRAND_DIR + brand_id + ".tres")
		if brand == null:
			continue
		var price: int = PRICE_BY_RARITY.get(Constants.BRAND_RARITIES[brand_id], 50)
		entries.append({
			"label": brand.display_name,
			"cost": price,
			"color": Constants.ITEM_RARITY_COLOR.get(brand.rarity, Color.WHITE),
			"item": brand,
			"repeatable": true,
			"on_buy": func(): _buy(brand_id, price),
		})
	_get_shop_screen().open_with("Brand Shop", entries)

## Duplicated, not the cached load()'d Resource itself - two purchases of
## the same Brand must be independent inventory instances, same reasoning
## ItemRoller.roll() duplicates its own picked base item.
func _buy(brand_id: String, price: int) -> void:
	var brand: Brand = (load(BRAND_DIR + brand_id + ".tres") as Brand).duplicate(true)
	GameState.owned_loot.append(brand)
	EventBus.gold_spent.emit(price)
	EventBus.brand_purchased.emit(brand_id)

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false
