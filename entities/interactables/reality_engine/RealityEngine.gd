extends Node3D
class_name RealityEngine
## The Reality Engine (map device). Interacting lists every carried
## or stashed Figment (RealityEngineScreen) plus a free run (the next Depth
## while levelling, Tier 1 after). Choosing one
## consumes it and loads GameState.MAP_SCENE with its modifiers. A full set
## of Maw Fragments opens a Pinnacle boss instead (Pinnacle.enter()).

const FREE_TIER := 1
const NEW_COLOR := Color(0.55, 0.95, 0.7)

@onready var prompt_label: Label3D = $PromptLabel
@onready var fx: RealityEngineFx = get_node_or_null("Fx")

var _player_in_range: bool = false

func _ready() -> void:
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact") and not AetherStyle.menu_open(get_tree()):
		get_viewport().set_input_as_handled()
		_open_selection()

func _open_selection() -> void:
	var carried: Array = []
	for item in GameState.get_inventory_items():
		if item is FigmentItem:
			carried.append(_entry_for(item as FigmentItem))
	var stashed: Array = []
	for figment in GameState.stash.get_figments():
		stashed.append(_entry_for(figment, true))
	if fx:
		fx.surge()
	RealityEngineScreen.open_for(get_tree(), [
		{"title": "Free Run", "entries": [_free_entry()]},
		{"title": "Carried Figments", "entries": carried},
		{"title": "In the Stash", "entries": stashed},
		{"title": "Pinnacle", "entries": _pinnacle_entries()},
	])

## The free run, rolled now so its card can be shown: the next uncleared
## Depth while levelling, Tier 1 after.
func _free_entry() -> Dictionary:
	var free: FigmentItem
	if FigmentProgress.levelling_complete():
		free = FigmentRoller.roll(FREE_TIER)
	else:
		free = FigmentRoller.roll_depth(FigmentProgress.max_drop_depth())
	var entry := _entry_for(free)
	entry["tag"] = "FREE"
	entry["tag_color"] = AetherStyle.AETHER
	entry["on_buy"] = func(): _enter(free)
	return entry

## One entry per Pinnacle boss; each needs a full set of Maw Fragments.
func _pinnacle_entries() -> Array:
	var have := Pinnacle.FRAGMENT_IDS.size() - Pinnacle.missing_fragments(GameState.inventory).size()
	var entries: Array = []
	for id in Pinnacle.offered_bosses():
		var boss_id: String = id
		var cost_text := "Free (testing)" if Pinnacle.free_entry else "%d/%d Fragments" % [have, Pinnacle.FRAGMENT_IDS.size()]
		entries.append({
			"name": Pinnacle.BOSSES[boss_id]["name"],
			"subtitle": "Pinnacle encounter",
			"description": "Feed the Engine a full set of Maw Fragments to open %s's arena. One of each Fragment is spent." % Pinnacle.BOSSES[boss_id]["name"],
			"icon": Pinnacle.FRAGMENT_IDS[0],
			"fragments": true,
			"tag": cost_text,
			"cost_text": cost_text,
			"fail_text": "Need all 4 Maw Fragments",
			"button_label": "Open the Arena",
			"color": Constants.ITEM_RARITY_COLOR[Constants.ItemRarity.UNIQUE],
			"on_buy": func(): return Pinnacle.enter(get_tree(), boss_id),
		})
	return entries

func _entry_for(figment: FigmentItem, in_stash: bool = false) -> Dictionary:
	var entry := {
		"name": figment.display_name,
		"subtitle": _subtitle_for(figment),
		"button_label": "Enter Figment",
		"color": Constants.ITEM_RARITY_COLOR.get(figment.rarity, Color.WHITE),
		"icon": figment,
		"item": figment,
		"on_buy": func(): _enter(figment, true),
	}
	if not figment.is_levelling() and not FigmentProgress.is_band_completed(figment.tileset_id, figment.band()):
		entry["tag"] = "NEW +1"
		entry["tag_color"] = NEW_COLOR
	elif in_stash:
		entry["tag"] = "STASH"
		entry["tag_color"] = AetherStyle.TEXT_DIM
	return entry

## get_tree().paused must be cleared before changing scenes, otherwise it
## carries over and leaves the Map's Player/enemies frozen (the selection
## screen pauses the tree like every other menu).
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
		if fx:
			fx.awake = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false
		if fx:
			fx.awake = false

func _subtitle_for(figment: FigmentItem) -> String:
	var mods := "%d mod%s" % [figment.affixes.size(), "" if figment.affixes.size() == 1 else "s"]
	if figment.is_levelling():
		return "Depth %d  ·  Area Level %d  ·  %s" % [figment.depth, figment.area_level(), mods]
	return "Tier %d  ·  Area Level %d  ·  %s Band  ·  %s" % [figment.tier, figment.area_level(), FigmentMods.band_name(figment.tier), mods]
