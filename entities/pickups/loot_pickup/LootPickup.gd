extends Area3D
class_name LootPickup
## A drop on the ground. Gear, jewels and Slates wait to be looked at and
## picked up with Interact (LootPicker on the Player, card on the HUD);
## currency, Maw Fragments, Figments, Tomes and ammo are collected on touch.
## Spawned by Enemy.gd on death with its content already assigned: one of
## `item`, `slate` or `currency_id`. Weapons and shields lie on the floor as
## their first-person model; everything else is a rotating, bobbing sphere in
## the rarity colour. Every drop gets a thin rarity beam from the floor.

const ROTATE_SPEED := 1.5
const BOB_SPEED := 2.0
const BOB_HEIGHT := 0.15

@export var item: Item
## Slate doesn't extend Item (it's a Fate Board placement, not equippable
## gear - see Slate.gd), so it needs its own field rather than reusing
## `item`. Set exactly one of `item`/`slate` per pickup.
@export var slate: Slate
## Crafting currency (Orb/Brand/Edict id) and how many; set instead of item/slate.
@export var currency_id: StringName = &""
@export var currency_count: int = 1

@onready var mesh: MeshInstance3D = $MeshInstance3D

var _time: float = 0.0

## Extra reach for things collected on touch (currency, fragments, ammo...).
const AUTO_PICKUP_REACH := 1.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if not auto_pickup():
		add_to_group(LOOK_GROUP)
		_add_name_tag()
	else:
		# Collected on touch from a little further away (gear keeps its small
		# shape, which the look-to-pick-up ray aims at).
		var shape := $CollisionShape3D as CollisionShape3D
		var sphere := (shape.shape as SphereShape3D).duplicate() as SphereShape3D
		sphere.radius += AUTO_PICKUP_REACH
		shape.shape = sphere
	_ground = Node3D.new()
	_ground.name = "Ground"
	_ground.position.y = -DEFAULT_HOVER
	add_child(_ground)
	var color := rarity_color() if currency_id == &"" else InventoryGridView.CURRENCY_COLOR
	_model = _build_model()
	if _model:
		mesh.visible = false
	else:
		_apply_color(color)
	_add_beam(color)

## Spawners put drops this far above the floor; the real floor is found on
## the first frame, once the spawner has set the position.
const DEFAULT_HOVER := 0.35
const FLOOR_PROBE := 1.5

var _ground: Node3D
var _model: Node3D
var _settled := false
## Beam spot: the middle of a lying model, not its grip.
var _center := Vector3.ZERO

## Weapons and shields lie flat (blade face up, guns on their side) at a
## random heading, resting on the floor.
func _build_model() -> Node3D:
	var model: Node3D
	var tilt: Basis
	if item is Weapon and WeaponModelLibrary.FAMILY.has((item as Weapon).weapon_type):
		model = WeaponModelLibrary.build(item as Weapon)
		var family := WeaponModelLibrary.get_family((item as Weapon).weapon_type)
		tilt = Basis(Vector3.BACK, PI * 0.5) if family in [&"pistol", &"rifle"] else Basis(Vector3.RIGHT, -PI * 0.5)
	elif item is Weapon or item is Shield:
		model = WeaponModelLibrary.build_offhand(item)
		tilt = Basis(Vector3.RIGHT, PI * 0.5)
	else:
		return null
	var holder := Node3D.new()
	holder.name = "Model"
	holder.rotation.y = randf() * TAU
	_ground.add_child(holder)
	model.basis = tilt
	holder.add_child(model)
	var bounds := AABB()
	var first := true
	var to_holder := holder.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var box := (to_holder * mi.global_transform) * mi.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	model.position.y = -bounds.position.y
	_center = holder.basis * bounds.get_center()
	_center.y = 0.0
	return holder

## A thin column from the floor so every drop shows its rarity across a field.
const BEAM_HEIGHT := 2.4
const BEAM_RADIUS := 0.018

func _add_beam(color: Color) -> void:
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = BEAM_RADIUS * 0.4
	cylinder.bottom_radius = BEAM_RADIUS
	cylinder.height = BEAM_HEIGHT
	cylinder.radial_segments = 8
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	beam.mesh = cylinder
	beam.material_override = _additive(Color(color, 0.85))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = _center + Vector3(0, BEAM_HEIGHT / 2.0, 0)
	_ground.add_child(beam)
	var flare := MeshInstance3D.new()
	flare.name = "Flare"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.13
	disc.bottom_radius = 0.13
	disc.height = 0.002
	disc.radial_segments = 16
	flare.mesh = disc
	flare.material_override = _additive(Color(color, 0.18))
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flare.position = _center + Vector3(0, 0.01, 0)
	_ground.add_child(flare)

static func _additive(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	return mat

func _apply_color(color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat

## Only the sphere spins and bobs; the pickup itself stays where it was put.
func _process(delta: float) -> void:
	if not _settled:
		_settled = true
		_settle_on_floor()
	if _model:
		return
	_time += delta
	mesh.rotate_y(ROTATE_SPEED * delta)
	mesh.position.y = sin(_time * BOB_SPEED) * BOB_HEIGHT

func _settle_on_floor() -> void:
	var from := global_position + Vector3.UP * 0.1
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * FLOOR_PROBE, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		_ground.global_position.y = (hit["position"] as Vector3).y

const LOOK_GROUP := &"loot_look"
const NAME_TAG_RANGE := 14.0
const TARGETED_SCALE := 1.35

var _name_tag: Label3D

## Collected on touch, not by looking at it and pressing Interact.
func auto_pickup() -> bool:
	if currency_id != &"":
		return true
	return item is AmmoPack or item is SkillTome or item is FigmentItem

func display_name() -> String:
	if slate:
		return slate.display_name
	return item.display_name if item else ""

func rarity_color() -> Color:
	if slate:
		return Constants.SLATE_RARITY_COLOR.get(slate.rarity, Color.WHITE)
	return Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE) if item else Color.WHITE

## Name above the drop, so you can find the one to look at.
func _add_name_tag() -> void:
	_name_tag = Label3D.new()
	_name_tag.name = "NameTag"
	_name_tag.text = display_name()
	_name_tag.modulate = rarity_color()
	_name_tag.outline_modulate = Color(0, 0, 0, 0.85)
	_name_tag.outline_size = 8
	_name_tag.font_size = 40
	_name_tag.pixel_size = 0.0035
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.fixed_size = false
	_name_tag.position.y = 0.55
	_name_tag.visibility_range_end = NAME_TAG_RANGE
	_name_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_name_tag)

## LootPicker: grows the drop and brightens its name while it's the target.
func set_targeted(on: bool) -> void:
	mesh.scale = Vector3.ONE * (TARGETED_SCALE if on else 1.0)
	if _model:
		_model.scale = mesh.scale
	if _name_tag:
		_name_tag.font_size = 52 if on else 40
		_name_tag.outline_modulate = Color(rarity_color().darkened(0.7), 0.95) if on else Color(0, 0, 0, 0.85)

func _on_body_entered(body: Node3D) -> void:
	if body is Player and auto_pickup():
		try_pickup()

## Moves the content into the inventory and frees the drop. False (and the
## drop stays) when there's no room.
func try_pickup() -> bool:
	if is_queued_for_deletion():
		return false
	if currency_id != &"":
		var leftover := GameState.inventory.add(currency_id, currency_count)
		if leftover > 0:
			currency_count = leftover
			EventBus.inventory_full.emit(null)
			return false
		queue_free()
		return true
	if slate:
		if not GameState.add_to_inventory(slate):
			EventBus.inventory_full.emit(slate)
			return false
		EventBus.slate_picked_up.emit(slate)
		queue_free()
		return true
	if item == null:
		return false
	if item is AmmoPack:
		var pack := item as AmmoPack
		if AmmoInventory.is_full(pack.ammo_type):
			return false  # at capacity: it stays on the ground
		AmmoInventory.add(pack.ammo_type, pack.amount)
		queue_free()
		return true
	if item is SkillTome:
		var tome := item as SkillTome
		if not GameState.owned_ability_ids.has(tome.ability_id):
			GameState.owned_ability_ids.append(tome.ability_id)
		EventBus.tome_picked_up.emit(tome)
	else:
		if not GameState.add_to_inventory(item):
			EventBus.inventory_full.emit(item)
			return false
		EventBus.loot_picked_up.emit(item)
	queue_free()
	return true
