extends Node3D
class_name UniqueCatalogue
## Dev-only Hub interactable: every Unique, Mythic and Unique Slate in
## UniqueCatalog, free, built fresh on each take (boss-only and
## corrupted-only ones too). Same proximity+E list as SpellTestShop.

@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: bool = false
var _shop_screen: ShopScreen

func _ready() -> void:
	if not Dev.enabled:
		queue_free()
		return
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false

## Looked up lazily: ShopScreen is declared after this node in Hub.tscn.
func _get_shop_screen() -> ShopScreen:
	if not is_instance_valid(_shop_screen):
		_shop_screen = get_tree().get_first_node_in_group("shop_screen")
	return _shop_screen

func _unhandled_input(event: InputEvent) -> void:
	var shop_screen := _get_shop_screen()
	if _player_in_range and event.is_action_pressed("interact") and shop_screen and not shop_screen.is_open():
		get_viewport().set_input_as_handled()
		open()

func open() -> void:
	_get_shop_screen().open_with("Unique Catalogue (Free - Debug)", entries())

## Built at the player's level (at least 1), so the base is the best one
## they could find there.
func entries() -> Array:
	var level := maxi(GameState.player_level, 1)
	var list: Array = []
	for def in UniqueCatalog.DEFS:
		var preview := _build(def, level)
		if preview == null:
			continue
		list.append({
			"label": def["name"],
			"cost": 0,
			"color": Constants.ITEM_RARITY_COLOR.get(def["rarity"], Color.WHITE),
			"item": preview,
			"on_buy": func(): return _give(_build(def, level)),
		})
	for def in UniqueCatalog.SLATE_DEFS:
		list.append({
			"label": def["name"] + " (Slate)",
			"cost": 0,
			"color": Constants.ITEM_RARITY_COLOR[Constants.ItemRarity.UNIQUE],
			"on_buy": func(): return _give(UniqueRoller.build_slate(def)),
		})
	return list

## "any"-base uniques (corrupted-only, made from an existing item) go on a ring.
func _build(def: Dictionary, level: int) -> Item:
	if def["base_type"] == "any":
		return UniqueRoller.build(def, level, UniqueRoller.base_for("ring", level))
	return UniqueRoller.build(def, level)

## False (the row shows "No room") when the inventory can't fit it.
func _give(content) -> bool:
	return content != null and GameState.inventory.add(content) == 0

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		GameSettings.refresh_interact_prompt(prompt_label)
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false
