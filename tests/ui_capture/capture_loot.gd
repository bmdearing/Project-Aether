extends Node
## Screenshot of ground drops: weapon/shield models lying flat, orbs for the
## rest, a rarity beam on each. Needs a real window (not --headless).
## Run: Godot --path . res://tests/ui_capture/capture_loot.tscn -- <out.png> [equipment|items]

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
	if args.size() > 1 and args[1] == "equipment":
		drops = EQUIPMENT.map(func(path: String) -> Item: return _rolled(path))
	if args.size() > 1 and args[1] == "items":
		_spawn_items()
		drops = []
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
	var close := args.size() > 1 and args[1] == "items"
	cam.global_position = Vector3(0, 1.3, 0.3) if close else Vector3(0, 2.6, 2.2)
	cam.look_at(Vector3(0, 0, -2.3) if close else Vector3(0, 0, -2.6))
	cam.current = true
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("saved ", out_path)
	get_tree().quit()

## Slates, Lenses, Skill Tomes and gold piles, back row to front.
func _spawn_items() -> void:
	var slates: Array[Slate] = [
		_slate([Vector2i(0, 0)], Constants.DamageType.FIRE, -1, Constants.SlateRarity.COMMON, 0),
		_slate([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)], Constants.DamageType.COLD, -1, Constants.SlateRarity.UNCOMMON, 0),
		_slate([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], Constants.DamageType.LIGHTNING, Constants.DamageType.ENTROPIC, Constants.SlateRarity.RARE, 2),
	]
	for i in slates.size():
		_drop_at(func(p: LootPickup) -> void: p.slate = slates[i], Vector3((i - 1) * 0.8, 0, -3.3))
	for i in 3:
		var lens := Lens.new()
		lens.radius = 2 + i
		lens.radius_tag = [-1, Constants.DamageType.FIRE, Constants.DamageType.AETHERIC][i]
		lens.display_name = "Lens %d" % lens.radius
		_drop_at(func(p: LootPickup) -> void: p.item = lens, Vector3((i - 1) * 0.8, 0, -2.6))
	for i in 3:
		var tome := SkillTome.new()
		tome.ability_path = ["res://data/abilities/instances/inferno.tres", "res://data/abilities/instances/ice_pulse.tres", "res://data/abilities/instances/blink.tres"][i]
		tome.display_name = tome.ability_path.get_file()
		_drop_at(func(p: LootPickup) -> void: p.item = tome, Vector3((i - 1) * 0.8, 0, -1.9))
	for i in 4:
		var gold: GoldPickup = load("res://entities/pickups/gold_pickup/GoldPickup.tscn").instantiate()
		gold.amount = [5, 30, 120, 500][i]
		add_child(gold)
		gold.global_position = Vector3((i - 1.5) * 0.6, Enemy.DROP_HOVER, -1.3)

func _drop_at(fill: Callable, pos: Vector3) -> void:
	var pickup: LootPickup = load("res://entities/pickups/loot_pickup/LootPickup.tscn").instantiate()
	fill.call(pickup)
	add_child(pickup)
	pickup.global_position = pos + Vector3.UP * Enemy.DROP_HOVER

func _slate(cells: Array[Vector2i], tag: int, secondary: int, rarity: int, sockets: int) -> Slate:
	var s := Slate.new()
	s.display_name = "Slate"
	s.shape_cells = cells
	s.tag = tag
	s.is_hybrid = secondary >= 0
	s.secondary_tag = maxi(secondary, 0)
	s.rarity = rarity
	s.sockets = sockets
	if sockets > 0:
		var lens := Lens.new()
		lens.radius_tag = Constants.DamageType.FIRE
		s.lenses = [lens]
	return s

const EQUIPMENT := [
	"res://data/armor/instances/gen_body_armour_aegis_plate.tres",
	"res://data/armor/instances/gen_body_armour_aetherial_coat.tres",
	"res://data/armor/instances/padded_coat.tres",
	"res://data/items/instances/iron_belt.tres",
	"res://data/items/instances/leather_belt.tres",
	"res://data/items/instances/ember_ring.tres",
	"res://data/items/instances/void_ring.tres",
	"res://data/items/instances/vitality_pendant.tres",
	"res://data/items/instances/aetheric_conduit.tres",
]

## A copy named the way ItemRoller names rolled items.
func _rolled(path: String) -> Item:
	var it := (load(path) as Item).duplicate(true) as Item
	it.item_id = "%s_rolled_%d" % [it.item_id, 7]
	it.rarity = Constants.ItemRarity.UNCOMMON
	return it

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
