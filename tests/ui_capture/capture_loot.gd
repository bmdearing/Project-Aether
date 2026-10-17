extends Node
## Screenshot of ground drops: weapon/shield models lying flat, orbs for the
## rest, a rarity beam on each. Needs a real window (not --headless).
## Run: Godot --path . res://tests/ui_capture/capture_loot.tscn -- <out.png>

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://loot.png"
	_build_arena()
	var drops: Array = [
		_weapon("Greatsword", Constants.ItemRarity.COMMON),
		_weapon("Dagger", Constants.ItemRarity.UNCOMMON),
		_weapon("Service Pistol", Constants.ItemRarity.RARE),
		_weapon("Battle Rifle", Constants.ItemRarity.UNIQUE),
		_weapon("Bow", Constants.ItemRarity.MYTHIC),
		_weapon("Halberd", Constants.ItemRarity.RARE),
		_weapon("Pressure Fist", Constants.ItemRarity.UNCOMMON),
		_shield(),
		_ring(),
	]
	for i in drops.size():
		var pickup: LootPickup = load("res://entities/pickups/loot_pickup/LootPickup.tscn").instantiate()
		pickup.item = drops[i]
		add_child(pickup)
		pickup.global_position = Vector3((i % 5 - 2) * 1.4, Enemy.DROP_HOVER, -2.0 - (i / 5) * 1.6)
	var currency: LootPickup = load("res://entities/pickups/loot_pickup/LootPickup.tscn").instantiate()
	currency.currency_id = Constants.roll_currency_drop(1)
	add_child(currency)
	currency.global_position = Vector3(2.8, Enemy.DROP_HOVER, -3.6)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 2.6, 2.2)
	cam.look_at(Vector3(0, 0, -2.6))
	cam.current = true
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("saved ", out_path)
	get_tree().quit()

func _weapon(t: String, rarity: int) -> Weapon:
	var w := Weapon.new()
	w.weapon_type = t
	w.display_name = t
	w.rarity = rarity
	return w

func _shield() -> Shield:
	var s := Shield.new()
	s.base_line_id = "kite_line1"
	s.display_name = "Kite Shield"
	s.rarity = Constants.ItemRarity.RARE
	s.equip_slot = Constants.EquipmentSlot.OFFHAND
	return s

func _ring() -> Item:
	var r := Item.new()
	r.display_name = "Ring"
	r.rarity = Constants.ItemRarity.UNCOMMON
	r.equip_slot = Constants.EquipmentSlot.RING
	return r

func _build_arena() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.45, 0.5)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	mesh.position.y = -0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.28, 0.26)
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
