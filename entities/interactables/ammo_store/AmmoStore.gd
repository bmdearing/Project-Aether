extends Node3D
class_name AmmoStore
## Hub interactable, same proximity+E pattern as GearShop but with no menu:
## one press buys a full resupply - every reserve (except infinite ARROW)
## topped up to AmmoInventory.STARTING_AMMO and every magazine in both
## weapon sets filled - priced per round by Constants.AMMO_ROUND_COST.
## All or nothing: short on Gold buys nothing.

const MESSAGE_SEC := 2.0

@onready var prompt_label: Label3D = $PromptLabel

var _player: Player
var _message_until_msec: int = 0

func _ready() -> void:
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false

func _process(_delta: float) -> void:
	if _player and Time.get_ticks_msec() >= _message_until_msec:
		prompt_label.text = "Press E to Resupply: %d Gold" % get_resupply_cost(_player)

func _unhandled_input(event: InputEvent) -> void:
	if _player and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_show_message(resupply(_player))

## Returns the message to show: "Fully stocked", "Not enough Gold (cost X)"
## or "Resupplied (-X Gold)".
func resupply(player: Player) -> String:
	var missing := get_missing(player)
	var cost := _cost_of(missing)
	if cost == 0:
		return "Fully stocked"
	if GameState.gold < cost:
		return "Not enough Gold (cost %d)" % cost
	GameState.gold -= cost
	var reserves: Dictionary = missing["reserves"]
	for ammo_type in reserves:
		AmmoInventory.add(ammo_type, reserves[ammo_type])
	for weapon: Weapon in missing["magazines"]:
		weapon.current_magazine = weapon.magazine_size
		player.ranged_attack.cancel_reload(weapon)
		# The HUD re-reads the magazine on ammo_changed.
		EventBus.ammo_changed.emit(weapon.ammo_type, AmmoInventory.get_reserve(weapon.ammo_type))
	return "Resupplied (-%d Gold)" % cost

func get_resupply_cost(player: Player) -> int:
	return _cost_of(get_missing(player))

## {"reserves": {AmmoType: rounds}, "magazines": {Weapon: rounds}}, missing
## entries only. Reserves above the starting amount are never reduced.
func get_missing(player: Player) -> Dictionary:
	var reserves := {}
	for ammo_type in AmmoInventory.STARTING_AMMO:
		var short: int = maxi(0, AmmoInventory.STARTING_AMMO[ammo_type] - AmmoInventory.get_reserve(ammo_type))
		if short > 0:
			reserves[ammo_type] = short
	var magazines := {}
	for weapon in _magazine_weapons(player):
		var short := weapon.magazine_size - weapon.get_current_magazine()
		if short > 0:
			magazines[weapon] = short
	return {"reserves": reserves, "magazines": magazines}

func _cost_of(missing: Dictionary) -> int:
	var cost := 0
	var reserves: Dictionary = missing["reserves"]
	for ammo_type in reserves:
		cost += reserves[ammo_type] * int(Constants.AMMO_ROUND_COST.get(ammo_type, 1))
	var magazines: Dictionary = missing["magazines"]
	for weapon: Weapon in magazines:
		cost += magazines[weapon] * int(Constants.AMMO_ROUND_COST.get(weapon.ammo_type, 1))
	return cost

## Ranged weapons with a magazine in either weapon set, main hand or offhand.
func _magazine_weapons(player: Player) -> Array[Weapon]:
	var result: Array[Weapon] = []
	var equipment := player.equipment
	var items: Array = []
	items.append_array(equipment.primary_weapons)
	items.append_array(equipment.offhands)
	for item in items:
		var weapon := item as Weapon
		if weapon and weapon.is_ranged and weapon.ammo_type != Constants.AmmoType.ARROW and weapon.magazine_size > 0 and not result.has(weapon):
			result.append(weapon)
	return result

func _show_message(text: String) -> void:
	prompt_label.text = text
	_message_until_msec = Time.get_ticks_msec() + int(MESSAGE_SEC * 1000.0)

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player = body
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player = null
		prompt_label.visible = false
