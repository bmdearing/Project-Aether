extends Node
## Autoload. Thin access point to the SoundLibrary resource so call sites
## don't each load it: `SoundLib.library.swing_blade`, or the helpers below.
## (No class_name: autoload singleton; SoundLibrary is the resource class.)

## An empty library (silence) when the real one fails to load, e.g. sounds
## added but not yet imported, so no gameplay code trips over a null.
var library: SoundLibrary = _load_library()

static func _load_library() -> SoundLibrary:
	var lib := load("res://data/sound/sound_library.tres") as SoundLibrary
	if lib == null:
		push_error("SoundLib: sound_library.tres failed to load (unimported sounds?); playing silent")
		return SoundLibrary.new()
	return lib

func pick_random(arr: Array[AudioStream]) -> AudioStream:
	return library.pick_random(arr) if library else null

func get_fire_sound(ammo_type: Constants.AmmoType) -> AudioStream:
	return library.get_fire_sound(ammo_type) if library else null

func get_reload_sound(ammo_type: Constants.AmmoType) -> AudioStream:
	return library.get_reload_sound(ammo_type) if library else null

func get_impact_sound(surface: String) -> AudioStream:
	return library.get_impact_sound(surface) if library else null
