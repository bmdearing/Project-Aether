extends Node3D
class_name CurrencyShop
## Hub interactable (proximity + E, like GearShop) opening a VendorScreen with
## infinite stock: Tempering and the Shard of Tharsis at PRICE Gold each
## (shift + right-click buys VendorScreen.INFINITE_BULK), plus a residue grant
## for testing the Siphon. Dev builds only.

const PRICE := 1

@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: bool = false
var _stock := GridInventory.new(10, 5)

func _ready() -> void:
	if not Dev.enabled:
		queue_free()
		return
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false
	for id in currency_ids():
		_stock.add(id, 1)

## Residue each regular pool gets from the "+500 residue" action.
const RESIDUE_GRANT := 500

static func currency_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in Constants.CRAFTING_CONSUMABLE_IDS:
		ids.append(StringName(id))
	return ids

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact") and not get_tree().paused:
		get_viewport().set_input_as_handled()
		open()

func open() -> VendorScreen:
	return VendorScreen.open_for(get_tree(), {
		"title": "Currency Exchange",
		"stock": _stock,
		"infinite": true,
		"buy_price": func(_content) -> int: return PRICE,
		"sell_price": func(_content) -> int: return 0,
		"action": {"label": "+%d to each residue pool" % RESIDUE_GRANT, "cost": 0, "on_action": _grant_residue},
	})

func _grant_residue() -> void:
	for pool in Residue.REGULAR:
		Residue.add(pool, RESIDUE_GRANT)
	open()

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		GameSettings.refresh_interact_prompt(prompt_label)
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false
