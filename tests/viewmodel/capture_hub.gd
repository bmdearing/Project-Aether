extends Node
## Saves a full-resolution gameplay shot of the Hub with a chosen weapon.
## Run windowed: Godot --path . res://tests/viewmodel/capture_hub.tscn --resolution 1920x1080 -- <out.png> [WeaponType] [yaw_deg]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	GameState.reset_to_defaults()
	var hub: Node = load("res://levels/hub/Hub.tscn").instantiate()
	get_tree().root.add_child(hub)
	await get_tree().create_timer(1.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Player
	if args.size() > 2:
		player.rotation.y = deg_to_rad(float(args[2]))
	if args.size() > 1:
		var weapon := Weapon.new()
		weapon.weapon_type = args[1]
		weapon.is_two_handed = true
		player.equipment.primary_weapon = weapon
		player.equipment.equipment_changed.emit()
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "user://hub.png")
	get_tree().quit()
