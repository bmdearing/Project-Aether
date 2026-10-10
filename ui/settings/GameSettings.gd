extends RefCounted
class_name GameSettings
## Player options, kept in their own file so New Game (which deletes the
## save) doesn't reset them. Values live on GameState; this loads, saves
## and applies them. Control bindings are saved here too (section
## "controls"), one key or mouse button per remappable action.

const PATH := "user://settings.cfg"
const SECTION := "settings"
const CONTROLS := "controls"

## Remappable actions in the order the Controls tab lists them.
const REMAPPABLE := [
	["move_forward", "Move Forward"], ["move_backward", "Move Back"],
	["move_left", "Move Left"], ["move_right", "Move Right"],
	["jump", "Jump"], ["sprint", "Sprint / Dash"], ["crouch", "Crouch / Slide"],
	["attack", "Attack"], ["stance", "Stance / Aim / Shield"], ["parry", "Parry"],
	["reload", "Reload"], ["weapon_swap", "Swap Weapons / Stance Page"],
	["ability_1", "Spell 1"], ["ability_2", "Spell 2"], ["ability_3", "Spell 3"], ["ability_4", "Spell 4"],
	["interact", "Interact / Pick Up"], ["return_to_hub", "Portal to Hub"],
	["open_inventory", "Inventory"], ["open_character", "Character"], ["open_abilities", "Abilities"],
	["open_fate_board", "Fate Board"], ["open_map", "Map"], ["open_figment_tree", "Figment Tree"], ["open_menu", "Menu (cycle screens)"],
	["mark_trash", "Mark Item as Trash"], ["mark_favored", "Mark Item as Favored"],
	["fate_board_rotate", "Rotate Slate"], ["fate_board_flip", "Flip Slate"],
]

static func load_and_apply() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		GameState.mouse_sensitivity = float(cfg.get_value(SECTION, "mouse_sensitivity", GameState.mouse_sensitivity))
		GameState.master_volume = float(cfg.get_value(SECTION, "master_volume", GameState.master_volume))
		GameState.fullscreen = bool(cfg.get_value(SECTION, "fullscreen", GameState.fullscreen))
		GameState.field_of_view = float(cfg.get_value(SECTION, "field_of_view", GameState.field_of_view))
		GameState.vsync = bool(cfg.get_value(SECTION, "vsync", GameState.vsync))
		GameState.always_show_sockets = bool(cfg.get_value(SECTION, "always_show_sockets", GameState.always_show_sockets))
		for entry in REMAPPABLE:
			var saved: Variant = cfg.get_value(CONTROLS, entry[0]) if cfg.has_section_key(CONTROLS, entry[0]) else null
			if saved is Dictionary:
				var event := event_from_dict(saved)
				if event:
					bind(entry[0], event)
	apply()

static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "mouse_sensitivity", GameState.mouse_sensitivity)
	cfg.set_value(SECTION, "master_volume", GameState.master_volume)
	cfg.set_value(SECTION, "fullscreen", GameState.fullscreen)
	cfg.set_value(SECTION, "field_of_view", GameState.field_of_view)
	cfg.set_value(SECTION, "vsync", GameState.vsync)
	cfg.set_value(SECTION, "always_show_sockets", GameState.always_show_sockets)
	for entry in REMAPPABLE:
		var event := current_event(entry[0])
		if event and not _is_default(entry[0], event):
			cfg.set_value(CONTROLS, entry[0], event_to_dict(event))
	cfg.save(PATH)

static func apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(GameState.master_volume, 0.0001)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if GameState.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if GameState.vsync else DisplayServer.VSYNC_DISABLED)
	EventBus.settings_changed.emit()

## ---- Controls ------------------------------------------------------------

## Makes event the action's only binding. Another action already on that
## key loses it (gets the old key instead), so two actions never share one.
static func bind(action: String, event: InputEvent) -> void:
	var previous := current_event(action)
	for entry in REMAPPABLE:
		var other: String = entry[0]
		if other != action and InputMap.action_has_event(other, event) and previous:
			InputMap.action_erase_events(other)
			InputMap.action_add_event(other, previous)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)

static func reset_controls() -> void:
	for entry in REMAPPABLE:
		InputMap.action_erase_events(entry[0])
		for event in default_events(entry[0]):
			InputMap.action_add_event(entry[0], event)

static func current_event(action: String) -> InputEvent:
	var events := InputMap.action_get_events(action)
	return events[0] if not events.is_empty() else null

static func default_events(action: String) -> Array:
	var setting: Variant = ProjectSettings.get_setting("input/" + action)
	return setting.get("events", []) if setting is Dictionary else []

static func _is_default(action: String, event: InputEvent) -> bool:
	var defaults := default_events(action)
	return defaults.size() == 1 and (defaults[0] as InputEvent).is_match(event)

## "E", "Left Mouse"... for prompts and the Controls tab.
static func key_name(action: String) -> String:
	return event_name(current_event(action))

static func event_name(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if key.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
			code = DisplayServer.keyboard_get_keycode_from_physical(code)  # the label on this keyboard layout
		return OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Left Mouse"
			MOUSE_BUTTON_RIGHT: return "Right Mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
			var other: return "Mouse %d" % other
	return "Unbound"

static func event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {"type": "key", "physical": int(key.physical_keycode), "keycode": int(key.keycode)}
	if event is InputEventMouseButton:
		return {"type": "mouse", "button": int((event as InputEventMouseButton).button_index)}
	return {}

static func event_from_dict(d: Dictionary) -> InputEvent:
	match d.get("type", ""):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(d.get("physical", 0)) as Key
			key.keycode = int(d.get("keycode", 0)) as Key
			return key
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(d.get("button", 1)) as MouseButton
			return mouse
	return null

## Rewrites a 3D "Press E ..." prompt for the current Interact key. The
## scene's original text is kept as the template, so later rebinds show too.
static func refresh_interact_prompt(label: Label3D) -> void:
	if not label.has_meta(&"prompt_template"):
		label.set_meta(&"prompt_template", label.text)
	label.text = String(label.get_meta(&"prompt_template")).replace("Press E", "Press " + key_name("interact"))
