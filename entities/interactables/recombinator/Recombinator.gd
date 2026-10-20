extends Node3D
class_name Recombinator
## Hub station for Slate splitting and recombining (SlateRecombinator).
## Lists carried Slates in the ShopScreen: one Split row per Slate that can
## be split, one Recombine row per pair of same-kind Slates.

@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: bool = false

func _ready() -> void:
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false

func _shop_screen() -> ShopScreen:
	return get_tree().get_first_node_in_group("shop_screen")

func _unhandled_input(event: InputEvent) -> void:
	var screen := _shop_screen()
	if _player_in_range and event.is_action_pressed("interact") and screen and not screen.is_open() and not get_tree().paused:
		get_viewport().set_input_as_handled()
		_open()

func _open() -> void:
	var slates: Array[Slate] = []
	for content in GameState.get_inventory_items():
		if content is Slate:
			slates.append(content)
	var entries: Array = []
	for slate in slates:
		var error := SlateRecombinator.split_error(slate)
		if error == "":
			entries.append(_row("Split: %s" % slate.display_name, slate, SlateRecombinator.SPLIT_COST, "Split", _do_split.bind(slate)))
	for i in slates.size():
		for j in range(i + 1, slates.size()):
			if SlateRecombinator.recombine_error(slates[i], slates[j]) == "":
				entries.append(_row("Recombine: %s (%s + %s)" % [slates[i].display_name, _mods_text(slates[i]), _mods_text(slates[j])], slates[i],
					SlateRecombinator.RECOMBINE_COST, "Recombine", _do_recombine.bind(slates[i], slates[j])))
	_shop_screen().open_with("Recombinator", entries)
	_shop_screen().set_notice("Split a Slate with 2+ crafted modifiers into two, or merge two Slates of the same kind. Lenses must come out first; split Slates can't be split again.")

func _row(label: String, slate: Slate, cost: int, button: String, on_buy: Callable) -> Dictionary:
	return {
		"label": label,
		"slate": slate,
		"cost": cost,
		"button_label": button,
		"fail_text": "No room",
		"color": Constants.SLATE_RARITY_COLOR.get(slate.rarity, Color.WHITE),
		"on_buy": on_buy,
	}

func _mods_text(slate: Slate) -> String:
	return "%d mod%s" % [slate.explicits.size(), "" if slate.explicits.size() == 1 else "s"]

func _do_split(slate: Slate) -> bool:
	if not GameState.remove_from_inventory(slate):
		return false
	var halves := SlateRecombinator.split(slate)
	if not GameState.add_to_inventory(halves[0]) or not GameState.add_to_inventory(halves[1]):
		GameState.remove_from_inventory(halves[0])
		GameState.add_to_inventory(slate)
		return false
	_reopen.call_deferred()
	return true

func _do_recombine(a: Slate, b: Slate) -> bool:
	var result := SlateRecombinator.recombine(a, b)
	GameState.remove_from_inventory(a)
	GameState.remove_from_inventory(b)
	if not GameState.add_to_inventory(result):
		GameState.add_to_inventory(a)
		GameState.add_to_inventory(b)
		return false
	_reopen.call_deferred()
	return true

## Rebuilds the list so used Slates drop off and new ones appear.
func _reopen() -> void:
	var screen := _shop_screen()
	if screen and screen.is_open():
		screen.close()
		_open()

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		GameSettings.refresh_interact_prompt(prompt_label)
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false
