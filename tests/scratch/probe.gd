extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_to_defaults()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)
	var player: Player = load("res://entities/player/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0, 0)
	for i in 3: await get_tree().physics_frame
	player.set_physics_process(false)
	for id in ["synod_warden_golem", "unchartered_brigand"]:
		var e := EnemyRoster.create_unit(id)
		add_child(e)
		e.global_position = Vector3(0, 0, -3)
		e.set_physics_process(false)
		for i in 3: await get_tree().physics_frame
		print(id, " groups=", e.get_groups(), " hp=", e.health.current_health, " ward=", e._ward_current, " pos=", e.global_position)
		var ab: Ability = load("res://data/abilities/instances/entropic_decay.tres")
		player.ability_cast._cast(ab, player.global_position)
		await get_tree().create_timer(1.0).timeout
		print(id, " after hp=", e.health.current_health, " ward=", e._ward_current, " pos=", e.global_position)
		e.queue_free()
		await get_tree().physics_frame
	get_tree().quit(0)
