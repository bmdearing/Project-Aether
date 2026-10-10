extends Node
## Single JSON save at user://savegame.json, loaded at boot straight into
## GameState. Saved on scene transitions and quit, not on a timer.
## Not saved: current Health/Ward/Mana, player position, active_map.

const SAVE_PATH := "user://savegame.json"
const TEMP_PATH := SAVE_PATH + ".tmp"
const BACKUP_PATH := SAVE_PATH + ".bak"
## 2: loot moved from owned_loot/owned_slates into the footprint grid.
const INVENTORY_VERSION := 2

func _ready() -> void:
	load_game()
	GameSettings.load_and_apply()

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BACKUP_PATH)

func save_game() -> void:
	if not GameState.game_started:
		return
	var data := {
		"game_started": GameState.game_started,
		"mouse_sensitivity": GameState.mouse_sensitivity,
		"master_volume": GameState.master_volume,
		"fullscreen": GameState.fullscreen,
		"equipment_refs": GameState.equipment_refs,
		"weapon_set_refs": GameState.weapon_set_refs,
		"active_weapon_set": GameState.active_weapon_set,
		"ability_loadout_paths": GameState.ability_loadout_paths,
		"ability_levels": GameState.ability_levels,
		"player_level": GameState.player_level,
		"player_xp": GameState.player_xp,
		"gold": GameState.gold,
		"shield_on_rmb": GameState.shield_on_rmb,
		"stance_page": GameState.stance_page,
		"owned_ability_ids": GameState.owned_ability_ids,
		"fate_board_placements": GameState.fate_board_placements,
		"ammo_reserves": AmmoInventory.serialize(),
		"inventory_version": INVENTORY_VERSION,
		"grid_inventory": GameState.inventory.to_dict(),
		"stash": GameState.stash.to_dict(),
		"portal_map_state": GameState.portal_map_state,
		"portals_opened": GameState.portals_opened,
		"player_name": GameState.player_name,
		"game_mode": GameState.game_mode,
		"deaths": GameState.deaths,
		"kills": GameState.kills,
		"pinnacle_clears": GameState.pinnacle_clears,
	}
	_write_atomic(JSON.stringify(data))

## Writes to a temp file, then swaps it in; the previous save becomes the
## backup, so a crash mid-save never leaves only a truncated file.
func _write_atomic(text: String) -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: failed to open %s for writing (error %d)" % [TEMP_PATH, FileAccess.get_open_error()])
		return
	var ok := file.store_string(text)
	file.close()
	if not ok:
		push_warning("SaveManager: failed to write %s" % TEMP_PATH)
		return
	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(BACKUP_PATH):
			DirAccess.remove_absolute(BACKUP_PATH)
		DirAccess.rename_absolute(SAVE_PATH, BACKUP_PATH)
	var err := DirAccess.rename_absolute(TEMP_PATH, SAVE_PATH)
	if err != OK:
		push_warning("SaveManager: failed to move %s into place (error %d)" % [TEMP_PATH, err])

func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: %s is missing or corrupt" % path)
		return {}
	return parsed

func load_game() -> void:
	var parsed := _read_save(SAVE_PATH)
	if parsed.is_empty():
		parsed = _read_save(BACKUP_PATH)
	if parsed.is_empty():
		return

	GameState.game_started = parsed.get("game_started", GameState.game_started)
	GameState.mouse_sensitivity = parsed.get("mouse_sensitivity", GameState.mouse_sensitivity)
	GameState.master_volume = parsed.get("master_volume", GameState.master_volume)
	GameState.fullscreen = parsed.get("fullscreen", GameState.fullscreen)
	GameState.equipment_refs = _to_ref_array(parsed.get("equipment_refs"), GameState.equipment_refs)
	var weapon_sets_raw = parsed.get("weapon_set_refs")
	if typeof(weapon_sets_raw) == TYPE_ARRAY and weapon_sets_raw.size() == 2:
		GameState.weapon_set_refs = [
			_to_ref_array(weapon_sets_raw[0], GameState.weapon_set_refs[0]),
			_to_ref_array(weapon_sets_raw[1], GameState.weapon_set_refs[1]),
		]
	GameState.active_weapon_set = int(parsed.get("active_weapon_set", GameState.active_weapon_set))
	GameState.ability_loadout_paths = _to_string_array(parsed.get("ability_loadout_paths"), GameState.ability_loadout_paths)
	var levels = parsed.get("ability_levels", null)
	if typeof(levels) == TYPE_DICTIONARY:
		GameState.ability_levels = levels
	else:
		# Pre-level saves stored ranks 0-5; rank N becomes level N + 1.
		var ranks = parsed.get("ability_ranks", {})
		GameState.ability_levels = {}
		if typeof(ranks) == TYPE_DICTIONARY:
			for id in ranks:
				GameState.ability_levels[id] = int(ranks[id]) + 1
	GameState.player_level = int(parsed.get("player_level", GameState.player_level))
	GameState.player_xp = float(parsed.get("player_xp", GameState.player_xp))
	GameState.gold = int(parsed.get("gold", GameState.gold))
	GameState.shield_on_rmb = bool(parsed.get("shield_on_rmb", true))
	GameState.stance_page = clampi(int(parsed.get("stance_page", 0)), 0, 1)
	var ids = parsed.get("owned_ability_ids", [])
	if typeof(ids) == TYPE_ARRAY:
		var typed_ids: Array[String] = []
		for id in ids:
			typed_ids.append(str(id))
		GameState.owned_ability_ids = typed_ids

	var grid_raw = parsed.get("grid_inventory")
	if typeof(grid_raw) == TYPE_DICTIONARY:
		GameState.inventory = GridInventory.from_dict(grid_raw)
		# Saves from before the inventory grew (v4.23: 12x6 -> 14x7).
		GameState.inventory.grow_to(Constants.INVENTORY_SIZE)
	var portal_raw = parsed.get("portal_map_state")
	GameState.portal_map_state = portal_raw if typeof(portal_raw) == TYPE_DICTIONARY else {}
	GameState.portals_opened = int(parsed.get("portals_opened", 0))
	GameState.player_name = str(parsed.get("player_name", ""))
	GameState.game_mode = int(parsed.get("game_mode", GameState.GameMode.FRAGMENTED_REALITY)) as GameState.GameMode
	GameState.deaths = int(parsed.get("deaths", 0))
	GameState.kills = int(parsed.get("kills", 0))
	GameState.pinnacle_clears = {}
	var clears: Variant = parsed.get("pinnacle_clears", {})
	if clears is Dictionary:
		for boss_id in clears:
			GameState.pinnacle_clears[str(boss_id)] = int(clears[boss_id])
	var stash_raw = parsed.get("stash")
	if typeof(stash_raw) == TYPE_DICTIONARY:
		GameState.stash = Stash.from_dict(stash_raw)

	var ammo_raw = parsed.get("ammo_reserves")
	if typeof(ammo_raw) == TYPE_DICTIONARY:
		AmmoInventory.deserialize(ammo_raw)

	var placements_raw = parsed.get("fate_board_placements", [])
	if typeof(placements_raw) == TYPE_ARRAY:
		var placements := []
		for entry in placements_raw:
			if typeof(entry) == TYPE_DICTIONARY:
				placements.append(entry)
		GameState.fate_board_placements = placements

	if int(parsed.get("inventory_version", 1)) < INVENTORY_VERSION:
		_migrate_legacy_inventory(parsed)

func delete_save() -> void:
	for path in [SAVE_PATH, BACKUP_PATH, TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

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

## Moves a pre-grid save's owned_loot/owned_slates into the grid (overflow
## goes to the stash). Equipped items used to sit in owned_loot as well;
## they're matched against the equipment refs and skipped. Placed Slates
## were saved as owned_slates indices and now carry their full data.
func _migrate_legacy_inventory(parsed: Dictionary) -> void:
	var equipped_keys := []
	var refs: Array = GameState.equipment_refs.duplicate()
	for set_refs in GameState.weapon_set_refs:
		refs.append_array(set_refs)
	for ref in refs:
		if ref is Dictionary:
			equipped_keys.append(_legacy_key(ref))
	for entry in parsed.get("owned_loot", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var key := _legacy_key(entry)
		if equipped_keys.has(key):
			equipped_keys.erase(key)
			continue
		if ItemSerializer.is_legacy_brand(entry):
			var currency := ItemSerializer.legacy_brand_currency(entry)
			if currency != &"":
				_store_migrated(currency)
			continue
		var item := ItemSerializer.from_dict(entry)
		if item:
			_store_migrated(item)

	var slates: Array[Slate] = []
	for entry in parsed.get("owned_slates", []):
		if typeof(entry) == TYPE_DICTIONARY:
			slates.append(SlateSerializer.from_dict(entry))
	var placed := {}
	for placement in GameState.fate_board_placements:
		var ref = placement.get("slate_ref")
		if ref is float or ref is int:
			var idx := int(ref)
			if idx >= 0 and idx < slates.size():
				placement["slate_ref"] = SlateSerializer.to_dict(slates[idx])
				placed[idx] = true
	for i in slates.size():
		if not placed.has(i):
			_store_migrated(slates[i])

## Item data with the fields a load may fill in randomly removed, so a
## loot entry and its equipment ref compare equal.
func _legacy_key(d: Dictionary) -> Dictionary:
	var key := ItemSerializer.to_dict(ItemSerializer.from_dict(d))
	key.erase("tolerance")
	key.erase("tolerance_max")
	return key

func _store_migrated(content) -> void:
	if GameState.inventory.add(content) == 0:
		return
	for tab in GameState.stash.tabs:
		if tab.add(content) == 0:
			return
	push_warning("SaveManager: no room to migrate %s" % (content if content is StringName else content.display_name))
