extends Node
## Single JSON save file at user://savegame.json. Loads at boot, before
## MainMenu shows, populating GameState directly - Continue is then just
## "go to the Hub", no separate load step.
##
## Saves at every meaningful transition (scene change away from gameplay,
## quit) rather than on a timer - few enough call sites to enumerate
## directly (PauseMenu, DeathScreen, MainMenu, MapDevice).
##
## Saves: equipment loadout (incl. rolled/pathless items via
## ItemSerializer), owned loot, ability loadout + ranks, level/XP, gold,
## owned ability ids, settings. NOT saved: Fate Board layout, current
## Health/Ward/Mana or player position (always resume the Hub at full),
## GameState.active_map.

const SAVE_PATH := "user://savegame.json"

func _ready() -> void:
	load_game()

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	if not GameState.game_started:
		return
	var owned_loot_data := []
	for item in GameState.owned_loot:
		owned_loot_data.append(ItemSerializer.to_dict(item))
	var data := {
		"game_started": GameState.game_started,
		"mouse_sensitivity": GameState.mouse_sensitivity,
		"master_volume": GameState.master_volume,
		"fullscreen": GameState.fullscreen,
		"equipment_refs": GameState.equipment_refs,
		"ability_loadout_paths": GameState.ability_loadout_paths,
		"ability_ranks": GameState.ability_ranks,
		"player_level": GameState.player_level,
		"player_xp": GameState.player_xp,
		"gold": GameState.gold,
		"owned_ability_ids": GameState.owned_ability_ids,
		"owned_loot": owned_loot_data,
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
	GameState.equipment_refs = _to_ref_array(parsed.get("equipment_refs"), GameState.equipment_refs)
	GameState.ability_loadout_paths = _to_string_array(parsed.get("ability_loadout_paths"), GameState.ability_loadout_paths)
	var ranks = parsed.get("ability_ranks", {})
	if typeof(ranks) == TYPE_DICTIONARY:
		GameState.ability_ranks = ranks
	GameState.player_level = int(parsed.get("player_level", GameState.player_level))
	GameState.player_xp = float(parsed.get("player_xp", GameState.player_xp))
	GameState.gold = int(parsed.get("gold", GameState.gold))
	var ids = parsed.get("owned_ability_ids", [])
	if typeof(ids) == TYPE_ARRAY:
		var typed_ids: Array[String] = []
		for id in ids:
			typed_ids.append(str(id))
		GameState.owned_ability_ids = typed_ids

	var loot_raw = parsed.get("owned_loot", [])
	if typeof(loot_raw) == TYPE_ARRAY:
		var loot: Array[Item] = []
		for entry in loot_raw:
			if typeof(entry) == TYPE_DICTIONARY:
				var item := ItemSerializer.from_dict(entry)
				if item:
					loot.append(item)
		GameState.owned_loot = loot

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

## Entries stay whatever type they parsed as (String or Dictionary) rather
## than being coerced with str() - a rolled item's Dictionary data would
## be mangled otherwise. Any other type is dropped.
func _to_ref_array(value, fallback: Array) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var result: Array = []
	for v in value:
		if typeof(v) == TYPE_STRING or typeof(v) == TYPE_DICTIONARY:
			result.append(v)
	return result
