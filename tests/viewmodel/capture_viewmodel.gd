extends Node
## Renders a contact sheet of the first-person viewmodel: one row per weapon
## type, columns sampled across an attack. Needs a real window (not --headless).
## Run: Godot --path . res://tests/viewmodel/capture_viewmodel.tscn -- <out.png> [Type,Type,...] [jab|thrust|charged|fire|walk|cast]

const DEFAULT_TYPES := ["Greatsword", "Dagger", "Rapier", "Spear", "Mace", "Bow", "Service Pistol", "Staff", "Wand", "Pressure Fist"]
var SAMPLE_TIMES := [0.0, 0.12, 0.25, 0.4, 0.6, 0.85]
var THUMB := Vector2i(384, 216)

var _player: Player

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://viewmodel.png"
	var types: Array = Array(args[1].split(",")) if args.size() > 1 else DEFAULT_TYPES
	var mode: String = args[2] if args.size() > 2 else "thrust"
	if mode == "idle":
		SAMPLE_TIMES = [0.0]
	if args.size() > 3:
		THUMB = Vector2i(int(args[3]), int(args[3]) * 9 / 16)
	GameState.reset_to_defaults()
	_build_arena()
	_player = load("res://entities/player/Player.tscn").instantiate()
	add_child(_player)
	_player.global_position = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _frames(10)
	var grid_cols := 4 if mode == "idle" else 1
	var sheet := Image.create(THUMB.x * SAMPLE_TIMES.size() * grid_cols, THUMB.y * ceili(types.size() / float(grid_cols)), false, Image.FORMAT_RGB8)
	for row in types.size():
		var weapon := Weapon.new()
		var parts: PackedStringArray = String(types[row]).split("|")
		weapon.weapon_type = parts[0]
		weapon.base_damage_min = 1.0
		weapon.base_damage_max = 1.0
		weapon.is_ranged = ["Bow", "Longbow", "Shortbow", "Crossbow", "Service Pistol", "Revolver", "Machine Pistol", "Submachine Gun", "Battle Rifle", "Bolt Action Rifle", "Lever Action Rifle", "Machine Gun", "Pump Action Shotgun", "Loaded Shotgun"].has(weapon.weapon_type)
		weapon.is_two_handed = ["Greatsword", "Claymore", "Halberd", "Spear", "Staff", "War Pick", "Shock Lance", "Longbow", "Bow", "Crossbow", "Battle Rifle", "Bolt Action Rifle", "Lever Action Rifle", "Machine Gun", "Pump Action Shotgun", "Loaded Shotgun", "Submachine Gun"].has(weapon.weapon_type)
		weapon.equip_slot = Constants.EquipmentSlot.PRIMARY_WEAPON
		_player.equipment.primary_weapon = weapon
		_player.equipment.offhand = _make_offhand(parts[1]) if parts.size() > 1 else null
		_player.equipment.equipment_changed.emit()
		await _seconds(1.2)
		var start := Time.get_ticks_msec()
		_trigger(mode, weapon)
		for col in SAMPLE_TIMES.size():
			var target_ms := start + int(SAMPLE_TIMES[col] * 1000.0 * _time_scale(weapon))
			while Time.get_ticks_msec() < target_ms:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, THUMB), Vector2i((col + row % grid_cols) * THUMB.x, (row / grid_cols) * THUMB.y))
		_release(mode)
		await _seconds(1.5)
	sheet.save_png(out_path)
	print("saved ", out_path)
	get_tree().quit()

func _time_scale(weapon: Weapon) -> float:
	return 2.0 if ["Greatsword", "Claymore"].has(weapon.weapon_type) else 1.0

func _trigger(mode: String, weapon: Weapon) -> void:
	match mode:
		"idle":
			pass
		"jab":
			_player.melee_attack.try_light_jab()
		"charged":
			_player.weapon_stance._enter_stance()
			_player.melee_attack.try_charged_thrust()
		"reload":
			weapon.reload_time = 1.0
			EventBus.reload_started.emit(weapon)
		"fire":
			_player.ranged_attack._fire(weapon)
		"walk":
			Input.action_press("move_forward")
		"cast":
			EventBus.ability_cast.emit(_player, null)
		_:
			if weapon.is_ranged:
				_player.ranged_attack._fire(weapon)
			else:
				_player.melee_attack.try_standard_thrust()

func _release(mode: String) -> void:
	if mode == "walk":
		Input.action_release("move_forward")
	if mode == "charged":
		_player.weapon_stance._exit_stance()

func _build_arena() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.55, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	mesh.position.y = -0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.33, 0.3)
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
	var pillar := MeshInstance3D.new()
	pillar.mesh = BoxMesh.new()
	pillar.mesh.size = Vector3(1, 3, 1)
	pillar.position = Vector3(1.5, 1.5, -6)
	add_child(pillar)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _make_offhand(kind: String) -> Item:
	if ["Rod", "Tome", "Grimoire", "Fetish", "Talisman"].has(kind):
		var focus := Weapon.new()
		focus.weapon_type = kind
		focus.is_offhand = true
		return focus
	var shield := Shield.new()
	shield.base_line_id = kind + "_line1"
	return shield
