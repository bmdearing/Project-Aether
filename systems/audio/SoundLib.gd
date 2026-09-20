extends Node
## Autoload. Thin access point to the SoundLibrary resource so call sites
## don't each load it: `SoundLib.library.swing_blade`, or the helpers below.
## (No class_name: autoload singleton; SoundLibrary is the resource class.)

var library: SoundLibrary = load("res://data/sound/sound_library.tres")

func pick_random(arr: Array[AudioStream]) -> AudioStream:
	return library.pick_random(arr) if library else null

func get_fire_sound(ammo_type: Constants.AmmoType) -> AudioStream:
	return library.get_fire_sound(ammo_type) if library else null

func get_reload_sound(ammo_type: Constants.AmmoType) -> AudioStream:
	return library.get_reload_sound(ammo_type) if library else null

func get_impact_sound(surface: String) -> AudioStream:
	return library.get_impact_sound(surface) if library else null
