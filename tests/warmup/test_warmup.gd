extends Node
## SpellWarmup: spawns every spell's effects once in front of the camera,
## then removes them without touching the map, enemies or the player.
## Run: Godot --headless --path . res://tests/warmup/test_warmup.tscn --quit-after 6000

const MAP := "res://levels/generated_map/GeneratedMap.tscn"
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
	GameState.reset_to_defaults()
	GameState.game_started = false
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = "dungeon_cellblock"
	GameState.active_map = figment
	var map: Node = load(MAP).instantiate()
	add_child(map)
	for i in 30:
		await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player") as Player
	player.health.max_health = 1.0e7
	player.health.current_health = 1.0e7
	var enemies := get_tree().get_nodes_in_group("enemy").size()
	var scene := get_tree().current_scene
	var before := scene.get_children().size()
	SpellWarmup.done = false
	var t := Time.get_ticks_msec()
	await SpellWarmup.run(get_tree())
	print("warmup took %d ms" % (Time.get_ticks_msec() - t))
	_check(SpellWarmup.done, "the warmup ran")
	for i in 120:
		await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("enemy").size() == enemies, "no enemy was touched")
	await get_tree().create_timer(12.0).timeout
	_check(scene.get_children().size() <= before + 2, "the warmup effects finish and are gone (%d -> %d)" % [before, scene.get_children().size()])
	_check(player.camera.current, "the player's camera is back")
	_check(player.health.is_alive(), "the player is fine")
	print("warmup tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
