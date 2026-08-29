extends Node
## Single JSON save file at user://savegame.json. Loads at boot (its own
## _ready(), before MainMenu ever shows) and populates GameState's
## fields directly; MainMenu's Continue button is then just "GameState is
## already what it should be, go to the Hub" - no separate load step.
##
## Deliberately NOT a periodic-timer autosave - instead saves at every
## meaningful transition point (every change_scene_to_file() away from
## gameplay, every quit). There are only a handful of such call sites in
## this whole project (PauseMenu, DeathScreen, MainMenu, MapDevice), few
## enough to enumerate and guard directly with save_game() calls, which is
## simpler and more deterministic than reasoning about a timer interval.
##
## Scope, deliberately limited for a first pass (see GameState.gd's
## header for the fields actually saved): equipment loadout, ability
## loadout + ranks, and settings. NOT saved: Fate Board layout (no
## serialize/deserialize path built for FateBoard.placements yet),
## current Health/Ward/Mana or player position (you always resume the
## Hub at full - there's no "resume mid-map" concept since maps aren't
## persistent either), GameState.active_map (irrelevant once you've left
## a map). A player who quits mid-map and reloads starts back in the Hub,
## not where they were.

const SAVE_PATH := "user://savegame.json"

func _ready() -> void:
	load_game()

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	if not GameState.game_started:
		return
	var data := {
		"game_started": GameState.game_started,
		"mouse_sensitivity": GameState.mouse_sensitivity,
		"master_volume": GameState.master_volume,
		"fullscreen": GameState.fullscreen,
		"equipment_paths": GameState.equipment_paths,
		"ability_loadout_paths": GameState.ability_loadout_paths,
		"ability_ranks": GameState.ability_ranks,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: failed to open %s for writing (error %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data))
	file.close()

func load_game() -> void:
	if not has_save():
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: failed to open %s for reading (error %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: %s did not contain a valid JSON object, ignoring" % SAVE_PATH)
		return

	GameState.game_started = parsed.get("game_started", GameState.game_started)
	GameState.mouse_sensitivity = parsed.get("mouse_sensitivity", GameState.mouse_sensitivity)
	GameState.master_volume = parsed.get("master_volume", GameState.master_volume)
	GameState.fullscreen = parsed.get("fullscreen", GameState.fullscreen)
	GameState.equipment_paths = _to_string_array(parsed.get("equipment_paths"), GameState.equipment_paths)
	GameState.ability_loadout_paths = _to_string_array(parsed.get("ability_loadout_paths"), GameState.ability_loadout_paths)
	var ranks = parsed.get("ability_ranks", {})
	if typeof(ranks) == TYPE_DICTIONARY:
		GameState.ability_ranks = ranks

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

func _to_string_array(value, fallback: Array[String]) -> Array[String]:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var result: Array[String] = []
	for v in value:
		result.append(str(v))
	return result
