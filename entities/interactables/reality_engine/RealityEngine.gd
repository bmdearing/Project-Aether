extends Node3D
class_name RealityEngine
## The Reality Engine (map device). Interacting lists every carried
## or stashed Figment (via ShopScreen) plus a free run (the next Depth while
## levelling, Tier 1 after). Choosing one
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
	for figment in GameState.stash.get_figments():
		entries.append(_entry_for(figment, true))
	entries.append_array(_pinnacle_entries())
	# The free run: the next uncleared Depth while levelling, Tier 1 after.
	var free_label := "Enter a Free Tier %d Figment (Area Level %d)" % [FREE_TIER, AreaLevel.ENDGAME_BASE + FREE_TIER]
	var free_roll := func(): return FigmentRoller.roll(FREE_TIER)
	if not FigmentProgress.levelling_complete():
		var depth := FigmentProgress.max_drop_depth()
		free_label = "Enter a Free Depth %d Figment (Area Level %d)" % [depth, depth * AreaLevel.LEVELS_PER_DEPTH - (AreaLevel.LEVELS_PER_DEPTH - 1)]
		free_roll = func(): return FigmentRoller.roll_depth(depth)
	_get_shop_screen().open_with("Reality Engine", entries, {
		"label": free_label,
		"cost": 0,
		"on_action": func(): _enter(free_roll.call()),
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

func _entry_for(figment: FigmentItem, in_stash: bool = false) -> Dictionary:
	return {
		"label": _label_for(figment) + (" - Stash" if in_stash else ""),
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
	if owned and not GameState.remove_from_inventory(figment):
		GameState.stash.remove_content(figment)
	GameState.active_map = figment
	SaveManager.save_game()
	get_tree().paused = false
	LoadingScreen.change_scene(GameState.MAP_SCENE)

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		GameSettings.refresh_interact_prompt(prompt_label)
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false

func _label_for(figment: FigmentItem) -> String:
	if figment.is_levelling():
		return "Depth %d %s (Area Level %d, %d mods)" % [figment.depth, figment.display_name, figment.area_level(), figment.affixes.size()]
	return "T%d %s (Area Level %d, %s, %d mods)%s" % [figment.tier, figment.display_name, figment.area_level(), FigmentMods.band_name(figment.tier),
		figment.affixes.size(), "" if FigmentProgress.is_band_completed(figment.tileset_id, figment.band()) else " - New (+1 point)"]
