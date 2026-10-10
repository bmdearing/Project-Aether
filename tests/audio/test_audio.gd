extends Node
## Sound library and ambience: every slot that should have sounds has them,
## they all load, loops loop, and maps play their style's ambience.
## Run: Godot --headless --path . res://tests/audio/test_audio.tscn --quit-after 3000

var _checks := 0
var _failures := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _run() -> void:
	var lib: SoundLibrary = SoundLib.library
	_check(lib != null, "the sound library loads")
	for slot in ["pistol_fire", "revolver_fire", "shotgun_fire", "rifle_fire", "automatic_fire", "impact_flesh", "impact_stone",
			"hit_flesh", "shield_block", "hit_critical", "explosion", "enemy_death", "item_drop"]:
		var streams: Array = lib.get(slot)
		_check(not streams.is_empty() and streams.all(func(s): return s is AudioStream), "%s has sounds (%d)" % [slot, streams.size()])
	for slot in ["dry_click", "rifle_reload", "item_pickup", "craft_apply", "ui_click"]:
		_check(lib.get(slot) is AudioStream, "%s has a sound" % slot)
	for id in Ambience.LOOPS:
		var loop := Ambience.load_loop(id) as AudioStreamOggVorbis
		_check(loop != null and loop.loop and loop.get_length() > 30.0, "%s loads as a loop" % id)
	_check(Ambience.random_thunder() != null, "thunder loads")
	for id in MapTileset.all_ids():
		var style := MapTileset.load_style(id)
		for layer in style.ambience_id.split(",", false):
			_check(Ambience.LOOPS.has(layer.split(":")[0]), "%s's ambience %s exists" % [id, layer])
	AudioManager.play_ambience("wind_gusts")
	await get_tree().create_timer(1.2).timeout
	_check(AudioManager.ambience_id() == "wind_gusts", "play_ambience starts the loop")
	AudioManager.play_ambience("river:-9,forest")
	await get_tree().create_timer(0.2).timeout
	_check(AudioManager.ambience_id() == "river:-9,forest" and AudioManager._ambience.size() == 2, "layered ambience plays both loops")
	AudioManager.play_ambience("")
	await get_tree().create_timer(1.2).timeout
	_check(AudioManager.ambience_id() == "", "an empty id fades it out")
	AudioManager.play_at(lib.hit_flesh[0], Vector3.ZERO)
	AudioManager.play_at(lib.hit_flesh[0], Vector3.ZERO)
	var playing := 0
	for child in AudioManager.get_children():
		if child is AudioStreamPlayer3D and child.playing:
			playing += 1
	_check(playing == 1, "the same sound twice in one frame plays once (%d)" % playing)
	print("audio tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
