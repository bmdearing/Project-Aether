extends Node3D
class_name CurrencyShop
## Hub interactable (proximity + E, like GearShop) opening a VendorScreen:
## every Orb and crafting consumable at PRICE Gold each, unlimited (a stack
## of each, refilled on every purchase). "Buy BULK of each" sends them to the
## stash's Currency tab, or the inventory when it's full.

const PRICE := 1
const BULK := 10

@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: bool = false
var _stock := GridInventory.new(8, 2)

func _ready() -> void:
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false
	for id in currency_ids():
		_stock.add(id, Constants.MAX_STACK)

static func currency_ids() -> Array[StringName]:
	var ids: Array[StringName] = Constants.ORB_IDS.duplicate()
	for id in Constants.CRAFTING_CONSUMABLE_IDS:
		ids.append(StringName(id))
	return ids

## Adds `count` of `id`; returns how many didn't fit anywhere.
static func deliver(id: StringName, count: int) -> int:
	var tab := GameState.stash.get_tab(GridInventory.Accepts.CURRENCY)
	var left := tab.add(id, count) if tab else count
	if left > 0:
		left = GameState.inventory.add(id, left)
	return left

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact") and not get_tree().paused:
		get_viewport().set_input_as_handled()
		open()

func open() -> VendorScreen:
	var ids := currency_ids()
	return VendorScreen.open_for(get_tree(), {
		"title": "Currency Exchange",
		"stock": _stock,
		"buy_price": func(_content) -> int: return PRICE,
		"sell_price": func(_content) -> int: return 0,
		"on_bought": func(content) -> void: _stock.add(content, 1),
		"action": {"label": "Buy %d of each" % BULK, "cost": PRICE * BULK * ids.size(), "on_action": func() -> void:
			var refund := 0
			for id in ids:
				refund += deliver(id, BULK) * PRICE
			GameState.gold += refund},
	})

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		GameSettings.refresh_interact_prompt(prompt_label)
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false
