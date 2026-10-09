extends Node
## Repro for Hub motes rendering as big squares: Hub -> map -> Hub, screenshots.
func _ready() -> void:
	_run.call_deferred()
func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	GameState.reset_to_defaults()
	var hub: Node = load("res://levels/hub/Hub.tscn").instantiate()
	get_tree().root.add_child(hub)
	await get_tree().create_timer(3.0).timeout
	await _shot(out + "_1.png")
	hub.queue_free()
	await get_tree().create_timer(0.5).timeout
	var map: Node = load("res://levels/generated_map/GeneratedMap.tscn").instantiate()
	get_tree().root.add_child(map)
	await get_tree().create_timer(3.0).timeout
	map.queue_free()
	await get_tree().create_timer(0.5).timeout
	hub = load("res://levels/hub/Hub.tscn").instantiate()
	get_tree().root.add_child(hub)
	await get_tree().create_timer(3.0).timeout
	await _shot(out + "_2.png")
	get_tree().quit()
