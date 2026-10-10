extends Node
## Screenshots a spell from the player's own camera in a real generated map,
## cast at three stationary dummies ahead.
## Run windowed: Godot --path . res://tests/ui_capture/capture_spell.tscn --resolution 1600x900 -- <out_prefix> <ability_id> <times,csv> [style_id] [distance] [twist]
## Writes <out_prefix>_<time>.png per time (seconds after the cast).

const ABILITY_DIR := "res://data/abilities/instances/"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var ability_id: String = args[1]
	var times: PackedStringArray = args[2].split(",")
	var style: String = args[3] if args.size() > 3 else "dungeon_cellblock"
	var distance: float = float(args[4]) if args.size() > 4 else 8.0
	GameState.reset_to_defaults()
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = style
	GameState.active_map = figment
	GameState.portal_map_state = {"seed": 7, "tileset_id": style}
	GameState.returning_through_portal = false
	var map: GeneratedMap = load("res://levels/generated_map/GeneratedMap.tscn").instantiate()
	get_tree().root.add_child(map)
	await get_tree().create_timer(1.5).timeout
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	var player := get_tree().get_first_node_in_group("player") as Player
	player.set_physics_process(false)
	# The boss room is the largest open space; stand back from its altar.
	var vault := map._cell_to_world(map.graph.vault_cell)
	var to_altar := map.boss_portal_point - vault
	to_altar.y = 0.0
	var fwd := to_altar.normalized() if to_altar.length() > 0.1 else Vector3.FORWARD
	player.global_position = vault - fwd * 6.0 + Vector3.UP * 0.1
	player.look_at(player.global_position + fwd, Vector3.UP)
	var right := fwd.cross(Vector3.UP)
	var target := player.global_position + fwd * distance
	for offset in [-1.6, 0.0, 1.6]:
		_dummy(map, target + right * offset + fwd * absf(offset) * 0.4)
	var eye := player.camera.global_position
	player.head.rotation.x = -atan2(eye.y - (target.y + 0.8), eye.distance_to(Vector3(target.x, eye.y, target.z)))
	await get_tree().create_timer(0.5).timeout

	var ability := load(ABILITY_DIR + ability_id + ".tres") as Ability
	ability.level = 5
	if args.size() > 5:
		ability.web_points = {args[5]: 1}
	var started := Time.get_ticks_msec()
	player.ability_cast._cast(ability, target)
	for t in times:
		while (Time.get_ticks_msec() - started) / 1000.0 < float(t):
			await get_tree().process_frame
		_hide_hud()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, t])
	print("CAPTURE_DONE")
	get_tree().quit()

func _hide_hud() -> void:
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false

func _dummy(parent: Node, pos: Vector3) -> void:
	var e := EnemyRoster.create_unit("unchartered_brigand")
	parent.add_child(e)
	e.global_position = pos
	e.move_speed = 0.0
	e.health.max_health = 1.0e6
	e.health.current_health = 1.0e6
	var melee := e.get_node_or_null("MeleeAttack")
	if melee:
		melee.set_physics_process(false)
