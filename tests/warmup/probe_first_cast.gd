extends Node
## Windowed probe: the worst frame time after the first cast of several
## spells, with or without SpellWarmup ("warm" user arg).
## Run: Godot --path . res://tests/warmup/probe_first_cast.tscn -- [warm]

const MAP := "res://levels/generated_map/GeneratedMap.tscn"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_to_defaults()
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = "dungeon_cellblock"
	GameState.active_map = figment
	add_child(load(MAP).instantiate())
	for i in 90:
		await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player") as Player
	if OS.get_cmdline_user_args().has("warm"):
		SpellWarmup.done = false
		await SpellWarmup.run(get_tree())
		for i in 30:
			await get_tree().process_frame
	var worst := 0.0
	for id in ["inferno", "black_hole", "comet", "flame_wall", "tornado", "thunder_javelin"]:
		var a := load("res://data/abilities/instances/%s.tres" % id) as Ability
		var spot := player.global_position - player.camera.global_transform.basis.z * 6.0
		var t0 := Time.get_ticks_usec()
		player.ability_cast._cast(a, spot)
		await get_tree().process_frame
		await get_tree().process_frame
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("%s first cast: %.1f ms over 2 frames" % [id, ms])
		worst = maxf(worst, ms)
		for i in 20:
			await get_tree().process_frame
	print("PROBE worst %.1f ms (%s)" % [worst, "warm" if OS.get_cmdline_user_args().has("warm") else "cold"])
	get_tree().quit()
