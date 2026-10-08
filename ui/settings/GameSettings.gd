extends RefCounted
class_name GameSettings
## Player options, kept in their own file so New Game (which deletes the
## save) doesn't reset them. Values live on GameState; this loads, saves
## and applies them.

const PATH := "user://settings.cfg"
const SECTION := "settings"

static func load_and_apply() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		GameState.mouse_sensitivity = float(cfg.get_value(SECTION, "mouse_sensitivity", GameState.mouse_sensitivity))
		GameState.master_volume = float(cfg.get_value(SECTION, "master_volume", GameState.master_volume))
		GameState.fullscreen = bool(cfg.get_value(SECTION, "fullscreen", GameState.fullscreen))
		GameState.field_of_view = float(cfg.get_value(SECTION, "field_of_view", GameState.field_of_view))
		GameState.vsync = bool(cfg.get_value(SECTION, "vsync", GameState.vsync))
		GameState.always_show_sockets = bool(cfg.get_value(SECTION, "always_show_sockets", GameState.always_show_sockets))
	apply()

static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "mouse_sensitivity", GameState.mouse_sensitivity)
	cfg.set_value(SECTION, "master_volume", GameState.master_volume)
	cfg.set_value(SECTION, "fullscreen", GameState.fullscreen)
	cfg.set_value(SECTION, "field_of_view", GameState.field_of_view)
	cfg.set_value(SECTION, "vsync", GameState.vsync)
	cfg.set_value(SECTION, "always_show_sockets", GameState.always_show_sockets)
	cfg.save(PATH)

static func apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(GameState.master_volume, 0.0001)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if GameState.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if GameState.vsync else DisplayServer.VSYNC_DISABLED)
	EventBus.settings_changed.emit()
