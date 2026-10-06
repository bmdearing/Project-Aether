extends Node3D
class_name SpellTestShop
## Hub interactable for testing: lists every ability under
## data/abilities/instances/ at 0 cost, same proximity+E pattern as
## RealityEngine/GearShop. Bypasses the normal SkillTome-drop acquisition path.

const ABILITY_DIR := "res://data/abilities/instances/"

@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: bool = false
var _shop_screen: ShopScreen

func _ready() -> void:
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false

## Looked up lazily, not cached at _ready() - this node is declared
## before ShopScreen in Hub.tscn and siblings ready in declaration order,
## so a _ready()-time group lookup would find nothing.
func _get_shop_screen() -> ShopScreen:
	if not is_instance_valid(_shop_screen):
		_shop_screen = get_tree().get_first_node_in_group("shop_screen")
	return _shop_screen

func _unhandled_input(event: InputEvent) -> void:
	var shop_screen := _get_shop_screen()
	if _player_in_range and event.is_action_pressed("interact") and shop_screen and not shop_screen.is_open():
		get_viewport().set_input_as_handled()
		_open_shop()

func _open_shop() -> void:
	var entries: Array = []
	var dir := DirAccess.open(ABILITY_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next().trim_suffix(".remap")
		while file_name != "":
			if file_name.ends_with(".tres"):
				var ability: Ability = load(ABILITY_DIR + file_name) as Ability
				if ability:
					entries.append({
						"label": ability.display_name,
						"cost": 0,
						"color": Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE),
						"ability": ability,
						"on_buy": func(): _grant(ability.ability_id),
					})
			file_name = dir.get_next().trim_suffix(".remap")
		dir.list_dir_end()
	_get_shop_screen().open_with("Spell Testing Shop (Free - Debug)", entries)

func _grant(ability_id: String) -> void:
	if not GameState.owned_ability_ids.has(ability_id):
		GameState.owned_ability_ids.append(ability_id)

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false
