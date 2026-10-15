class_name Dev
## The one switch for testing conveniences: cut Pinnacle Life, free Pinnacle
## entry, the Spell Testing Shop, the Currency Exchange, the Gear Shop's
## Unique test stock and the Level 90 Test character.
## Hidden toggle: Ctrl+Shift+D on the title screen, remembered in
## settings.cfg. Until it's been toggled once: on in the editor and debug
## exports, off in release exports unless the preset has the "dev" custom
## feature. Tests may set it directly.

const SECTION := "dev"
const KEY := "enabled"

static var enabled: bool = OS.is_debug_build() or OS.has_feature("dev"):
	set(on):
		enabled = on
		Pinnacle.free_entry = on

static func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(GameSettings.PATH) == OK and cfg.has_section_key(SECTION, KEY):
		enabled = bool(cfg.get_value(SECTION, KEY))

## Flips the switch and writes it into settings.cfg beside the options.
static func toggle() -> void:
	enabled = not enabled
	var cfg := ConfigFile.new()
	cfg.load(GameSettings.PATH)
	cfg.set_value(SECTION, KEY, enabled)
	cfg.save(GameSettings.PATH)
