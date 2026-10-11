extends Control
## Life/Mana globes large at several fill levels, and an enemy bar mid-hit.
## Run windowed: Godot --path . res://tests/ui_capture/capture_orbs.tscn --resolution 1600x500 -- <out.png> [seconds]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://orbs.png"
	var wait: float = float(args[1]) if args.size() > 1 else 2.0
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var specs := [[1.0, Color(0.85, 0.12, 0.12), "LIFE"], [0.6, Color(0.85, 0.12, 0.12), "LIFE"], [0.25, Color(0.85, 0.12, 0.12), "LIFE"],
		[0.0, Color(0.85, 0.12, 0.12), "LIFE"], [0.7, Color(0.15, 0.35, 0.95), "MANA"]]
	for i in specs.size():
		var orb := StatOrb.new()
		orb.radius = 130.0
		orb.fill_color = specs[i][1]
		orb.label_prefix = specs[i][2]
		orb.position = Vector2(10 + i * 318, 40)
		add_child(orb)
		orb.set_value(specs[i][0] * 200.0, 200.0)
	# An enemy bar just hit for 40% (the white chunk), scaled up.
	var bar := EnemyHealthBar.new()
	bar.position = Vector2(60, 470)
	bar.scale = Vector2(4, 4)
	add_child(bar)
	bar.set_enemy_name("Training Dummy")
	bar.set_health(100.0, 100.0)
	await get_tree().create_timer(wait).timeout
	bar.set_health(60.0, 100.0)
	await get_tree().create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
