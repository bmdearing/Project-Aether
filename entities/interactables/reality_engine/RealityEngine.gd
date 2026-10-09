extends Node3D
class_name RealityEngine
## The Reality Engine (map device). Interacting lists every carried
## Figment (via ShopScreen) plus an always-free Tier 1 run. Choosing one
## consumes it and loads GameState.MAP_SCENE with its modifiers. A full set
## of Maw Fragments opens a Pinnacle boss instead (Pinnacle.enter()).

const FREE_TIER := 1

@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: bool = false
var _shop_screen: ShopScreen

func _ready() -> void:
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false

## Looked up lazily, not cached at _ready() - same reasoning as GearShop's
## own _get_shop_screen(): declaration order in the scene tree isn't
## guaranteed to put ShopScreen before this interactable.
func _get_shop_screen() -> ShopScreen:
	if not is_instance_valid(_shop_screen):
		_shop_screen = get_tree().get_first_node_in_group("shop_screen")
	return _shop_screen

func _unhandled_input(event: InputEvent) -> void:
	var shop_screen := _get_shop_screen()
	if _player_in_range and event.is_action_pressed("interact") and shop_screen and not shop_screen.is_open():
		get_viewport().set_input_as_handled()
		_open_selection()

func _open_selection() -> void:
	var entries: Array = []
	for item in GameState.get_inventory_items():
		if item is FigmentItem:
			entries.append(_entry_for(item as FigmentItem))
	entries.append_array(_pinnacle_entries())
	_get_shop_screen().open_with("Reality Engine", entries, {
		"label": "Enter a Free Tier %d Figment" % FREE_TIER,
		"cost": 0,
		"on_action": func(): _enter(FigmentRoller.roll(FREE_TIER)),
	})

## One entry per Pinnacle boss; each needs a full set of Maw Fragments.
func _pinnacle_entries() -> Array:
	var have := Pinnacle.FRAGMENT_IDS.size() - Pinnacle.missing_fragments(GameState.inventory).size()
	var entries: Array = []
	for id in Pinnacle.BOSSES:
		var boss_id: String = id
		entries.append({
			"label": "Pinnacle: %s" % Pinnacle.BOSSES[boss_id]["name"],
			"cost_text": "Free (testing)" if Pinnacle.free_entry else "%d/%d Fragments" % [have, Pinnacle.FRAGMENT_IDS.size()],
			"fail_text": "Need all 4",
			"button_label": "Open",
			"color": Constants.ITEM_RARITY_COLOR[Constants.ItemRarity.UNIQUE],
			"repeatable": true,
			"on_buy": func(): return Pinnacle.enter(get_tree(), boss_id),
		})
	return entries

func _entry_for(figment: FigmentItem) -> Dictionary:
	return {
		"label": "%s (%d Aether-warped)" % [figment.display_name, figment.affixes.size()],
		"cost": 0,
		"button_label": "Enter",
		"color": Constants.ITEM_RARITY_COLOR.get(figment.rarity, Color.WHITE),
		"item": figment,
		"on_buy": func(): _enter(figment, true),
	}

## get_tree().paused must be cleared before changing scenes, otherwise it
## carries over and leaves the Map's Player/enemies frozen - the
## selection screen (ShopScreen) paused the tree same as every other menu
## in this project; unlike the old direct roll-and-travel flow, this one
## goes through a paused UI first, so this line is required here in a way
## it never had to be before. Same pattern DeathScreen/MainMenu/PauseMenu
## already follow for their own scene changes.
func _enter(figment: FigmentItem, owned: bool = false) -> void:
	if owned:
		GameState.remove_from_inventory(figment)
	GameState.active_map = figment
	SaveManager.save_game()
	get_tree().paused = false
	get_tree().change_scene_to_file(GameState.MAP_SCENE)

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false
