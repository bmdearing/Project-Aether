extends Node3D
class_name TreasureChest
## A treasure chest in a Figment: walk up and press E to open it. It spills
## gold and a handful of drops (gear, currency, now and then a Jewel, Slate
## or Figment) around itself, scaled by Item Quantity/Rarity like enemy
## drops. Built in code; GeneratedMap places them and remembers which were
## opened across a portal trip.

signal opened_chest

## Placeholder numbers: drop rolls per chest before Item Quantity, and the
## chance each roll picks a category (in order; gear otherwise).
const BASE_ROLLS := 3.0
const CURRENCY_CHANCE := 0.4
const JEWEL_CHANCE := 0.06
const SLATE_CHANCE := 0.05
const FIGMENT_CHANCE := 0.04
const GOLD_RANGE := Vector2i(20, 60)
const DROP_RADIUS := 1.8
const SIZE := Vector3(1.1, 0.7, 0.7)
const WOOD := Color(0.36, 0.22, 0.1)
const BRASS := Color(0.85, 0.66, 0.3)

const LOOT_PICKUP_SCENE := preload("res://entities/pickups/loot_pickup/LootPickup.tscn")
const GOLD_PICKUP_SCENE := preload("res://entities/pickups/gold_pickup/GoldPickup.tscn")

var _opened := false
var _player_in_range := false
var _lid: Node3D
var _prompt: Label3D
var _glow: OmniLight3D
var _body: StaticBody3D

func _ready() -> void:
	add_to_group("treasure_chest")
	var body := StaticBody3D.new()
	_body = body
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	shape.shape = box
	shape.position.y = SIZE.y / 2.0
	body.add_child(shape)
	body.add_child(_box(Vector3(SIZE.x, SIZE.y * 0.62, SIZE.z), Vector3(0, SIZE.y * 0.31, 0), WOOD))
	body.add_child(_box(Vector3(SIZE.x + 0.04, 0.08, SIZE.z + 0.04), Vector3(0, SIZE.y * 0.55, 0), BRASS))
	# The lid hinges along the back edge.
	_lid = Node3D.new()
	_lid.position = Vector3(0, SIZE.y * 0.62, -SIZE.z / 2.0)
	body.add_child(_lid)
	_lid.add_child(_box(Vector3(SIZE.x, SIZE.y * 0.38, SIZE.z), Vector3(0, SIZE.y * 0.19, SIZE.z / 2.0), WOOD.lightened(0.08)))
	_lid.add_child(_box(Vector3(0.14, 0.16, 0.06), Vector3(0, 0.08, SIZE.z + 0.02), BRASS))

	_glow = OmniLight3D.new()
	_glow.light_color = BRASS
	_glow.light_energy = 1.2
	_glow.omni_range = 3.0
	_glow.position.y = 1.0
	add_child(_glow)

	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 40
	_prompt.outline_size = 8
	_prompt.position.y = SIZE.y + 0.6
	_prompt.text = "Press E to open"
	_prompt.visible = false
	add_child(_prompt)

	var area := Area3D.new()
	area.monitorable = false
	var reach := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.4
	reach.shape = sphere
	reach.position.y = 1.0
	area.add_child(reach)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mesh.material_override = mat
	return mesh

## Drops the chest onto the floor under it (its own collider ignored).
func settle() -> void:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 3.0, global_position + Vector3.DOWN * 6.0, 1)
	query.collision_mask = 1
	query.exclude = [_body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		global_position.y = hit["position"].y

func is_opened() -> bool:
	return _opened

func _on_body_entered(body: Node3D) -> void:
	if body is Player and not _opened:
		_player_in_range = true
		GameSettings.refresh_interact_prompt(_prompt)
		_prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		_prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and not _opened and event.is_action_pressed("interact") and not AetherStyle.menu_open(get_tree()):
		get_viewport().set_input_as_handled()
		open()

## Opens the chest and drops its loot.
func open() -> void:
	if _opened:
		return
	set_opened()
	opened_chest.emit()
	_spill_loot()

## Shows the chest as already open, without dropping anything (a restored map).
func set_opened() -> void:
	_opened = true
	_prompt.visible = false
	_glow.visible = false
	create_tween().tween_property(_lid, "rotation_degrees:x", -105.0, 0.35).set_trans(Tween.TRANS_BACK)

func _spill_loot() -> void:
	var mods := Loot.multipliers()
	var gold: GoldPickup = GOLD_PICKUP_SCENE.instantiate()
	gold.amount = roundi(randi_range(GOLD_RANGE.x, GOLD_RANGE.y) * (1.0 + (_tier() - 1) * 0.2))
	_place(gold)
	for i in Loot.roll_count(BASE_ROLLS * mods["quantity"] * (1.0 + FigmentTree.effect("chest_quantity") / 100.0)):
		_roll_drop(mods["rarity"])

func _roll_drop(rarity_mult: float) -> void:
	var item_level := _tier()
	var pickup: LootPickup = LOOT_PICKUP_SCENE.instantiate()
	var roll := randf()
	if roll < CURRENCY_CHANCE:
		pickup.currency_id = Constants.roll_currency_drop()
	elif roll < CURRENCY_CHANCE + JEWEL_CHANCE:
		pickup.item = JewelRoller.roll(item_level, rarity_mult)
	elif roll < CURRENCY_CHANCE + JEWEL_CHANCE + SLATE_CHANCE:
		pickup.slate = SlateRoller.roll(item_level, rarity_mult)
	elif roll < CURRENCY_CHANCE + JEWEL_CHANCE + SLATE_CHANCE + FIGMENT_CHANCE:
		pickup.item = FigmentRoller.roll_for_drop(item_level)
	else:
		pickup.item = ItemRoller.roll(item_level, rarity_mult)
	if pickup.currency_id == &"" and pickup.item == null and pickup.slate == null:
		pickup.free()
		return
	_place(pickup)

func _tier() -> int:
	return GameState.active_map.tier if GameState.active_map else maxi(GameState.player_level, 1)

## Drops a pickup on the floor in a ring in front of the chest.
func _place(pickup: Node3D) -> void:
	get_parent().add_child(pickup)
	var angle := randf() * TAU
	var spot := global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(1.0, DROP_RADIUS)
	var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 2.0, spot + Vector3.DOWN * 4.0, 1)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	spot.y = (hit["position"].y if hit else global_position.y) + 0.4
	pickup.global_position = spot
