extends Area3D
class_name LootPickup
## A drop on the ground. Gear, jewels and Slates wait to be looked at and
## picked up with Interact (LootPicker on the Player, card on the HUD);
## currency, Maw Fragments, Figments, Tomes and ammo are collected on touch.
## Spawned by Enemy.gd on death with its content already assigned: one of
## `item`, `slate` or `currency_id`. Gear, Slates, Lenses and Skill Tomes lie
## on the floor as their model; everything else is a rotating,
## bobbing sphere in the rarity colour. Every drop gets a thin rarity beam from the floor.

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

## Everything lies flat (blade face up, guns on their side, armour front up)
## at a random heading, resting on the floor.
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
	elif slate or item is Lens or item is SkillTome:
		model = build_slate(slate) if slate else build_lens(item as Lens) if item is Lens else build_tome(item as SkillTome)
		if model == null:
			return null
		var family := "slate" if slate else "lens" if item is Lens else "tome"
		tilt = Basis.IDENTITY.scaled(Vector3.ONE * float(ITEM_DROP_SCALE[family]))
	else:
		var entry := _equipment_entry(item)
		if entry.is_empty():
			return null
		model = (load(entry["file"]) as PackedScene).instantiate()
		# Body armour lies on its back, front up; accessories are authored flat.
		tilt = Basis(Vector3.RIGHT, -PI * 0.5) if entry["family"] == "body_armour" else Basis.IDENTITY
		tilt = tilt.scaled(Vector3.ONE * float(EQUIPMENT_DROP_SCALE.get(entry["family"], 1.0)))
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
	if _name_tag:
		_name_tag.position.y = maxf(_name_tag.position.y, bounds.size.y - DEFAULT_HOVER + 0.25)
	return holder

## Body armour, rings, belts and amulets (tools/blender), Godot-native: +Y up,
## front +Z. Accessories are scaled up to be seen.
const EQUIPMENT_MANIFEST := "res://assets/models/equipment/equipment_manifest.json"
const EQUIPMENT_DROP_SCALE := {"ring": 5.0, "amulet": 3.0, "belt": 1.0, "body_armour": 1.0}
## Base item id -> manifest key where the name doesn't follow <kind>_ring /
## <kind>_belt.
const EQUIPMENT_BY_BASE := {
	"agility_pendant": "amulet_agility", "intellect_pendant": "amulet_intellect",
	"vital_pendant": "amulet_vital", "vitality_pendant": "amulet_strength",
	"resonant_pendant": "amulet_resonant", "convergence_pendant": "amulet_convergence",
	"aetheric_conduit": "amulet_aetheric_conduit", "padded_coat": "body_padded",
}

static var _equipment: Dictionary = {}
static var _equipment_by_line: Dictionary = {}

## Body armour matches by base line; accessories by the base item id (rolled
## ids are "<base id>_rolled_<n>").
static func _equipment_entry(it: Item) -> Dictionary:
	if it == null:
		return {}
	if _equipment.is_empty() and ResourceLoader.exists(EQUIPMENT_MANIFEST):
		var data: Variant = (load(EQUIPMENT_MANIFEST) as JSON).data
		if data is Dictionary:
			_equipment = data
			for entry: Dictionary in _equipment.values():
				if entry.has("base"):
					_equipment_by_line[entry["base"]] = entry
	var e: Dictionary = _equipment_by_line.get(it.base_line_id, {}) if it.base_line_id != "" else {}
	if e.is_empty():
		var cut := it.item_id.find("_rolled_")
		var base_id := it.item_id.substr(0, cut) if cut != -1 else it.item_id
		var key: String = EQUIPMENT_BY_BASE.get(base_id, "")
		if key == "":
			for kind in ["ring", "belt"]:
				if base_id.ends_with("_" + kind):
					key = kind + "_" + base_id.trim_suffix("_" + kind)
		e = _equipment.get(key, {})
	return e if not e.is_empty() and ResourceLoader.exists(e["file"]) else {}

## Slates, Lenses, Skill Tomes and gold piles (tools/blender), authored flat,
## +Y up. Small ones are scaled up to be seen on the floor.
const ITEM_MANIFEST := "res://assets/models/items/items_manifest.json"
const ITEM_DROP_SCALE := {"slate": 3.0, "lens": 5.0, "tome": 1.0, "gold": 2.0}
const SLATE_CELL := 0.05

static var _items: Dictionary = {}

## A fresh instance of an items_manifest model, or null if it's missing.
static func item_model(key: String) -> Node3D:
	if _items.is_empty() and ResourceLoader.exists(ITEM_MANIFEST):
		var data: Variant = (load(ITEM_MANIFEST) as JSON).data
		if data is Dictionary:
			_items = data
	var e: Dictionary = _items.get(key, {})
	if e.is_empty() or not ResourceLoader.exists(e["file"]):
		return null
	return (load(e["file"]) as PackedScene).instantiate()

## Overrides every surface whose material name starts with `prefix`.
static func _recolor(model: Node3D, prefix: String, mat: Material) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m and m.resource_name.begins_with(prefix):
				mi.set_surface_override_material(i, mat)

## One tile per shape cell, centred; rune inlays glow in the Slate's tag
## (hybrids checkerboard the secondary), edges take the rarity colour, and
## the first `sockets` cells carry a socket with its Lens.
static func build_slate(s: Slate) -> Node3D:
	var probe := item_model("slate_tile")
	if probe == null:
		return null
	probe.free()
	var root := Node3D.new()
	var edge := WeaponModelLibrary._flat(Constants.SLATE_RARITY_COLOR.get(s.rarity, Color.WHITE), 0.6, 0.2)
	var glows := [WeaponModelLibrary._glow(Constants.DAMAGE_TYPE_COLOR.get(s.tag, Color.WHITE)),
		WeaponModelLibrary._glow(Constants.DAMAGE_TYPE_COLOR.get(s.secondary_tag, Color.WHITE))]
	var middle := Vector2.ZERO
	for cell in s.shape_cells:
		middle += Vector2(cell)
	middle /= maxf(s.shape_cells.size(), 1.0)
	for i in s.shape_cells.size():
		var cell := s.shape_cells[i]
		var pos := Vector3((cell.x - middle.x) * SLATE_CELL, 0, (cell.y - middle.y) * SLATE_CELL)
		var tile := item_model("slate_tile")
		tile.position = pos
		root.add_child(tile)
		_recolor(tile, "slate_tag", glows[(cell.x + cell.y) % 2] if s.is_hybrid else glows[0])
		_recolor(tile, "slate_rarity", edge)
		if i < s.sockets:
			var socket := item_model("slate_socket")
			if socket:
				socket.position = pos
				root.add_child(socket)
			if i < s.lenses.size() and s.lenses[i]:
				var lens := build_lens(s.lenses[i], "lens_small")
				if lens:
					lens.position = pos
					root.add_child(lens)
	return root

## Small/Medium/Large by radius; the glass takes the radius tag's colour.
static func build_lens(lens: Lens, key: String = "") -> Node3D:
	if key == "":
		key = "lens_" + String(Lens.SIZE_NAMES.get(lens.radius, "Small")).to_lower()
	var model := item_model(key)
	if model and lens.radius_tag >= 0:
		var color: Color = Constants.DAMAGE_TYPE_COLOR.get(lens.radius_tag, Color.WHITE)
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
				if m and m.resource_name.begins_with("glow_lens"):
					var tinted := m.duplicate() as StandardMaterial3D
					tinted.albedo_color = Color(color, m.albedo_color.a)
					tinted.emission = color
					mi.set_surface_override_material(i, tinted)
	return model

## The tome for the ability's damage type; tome_neutral when it deals none.
static func build_tome(tome: SkillTome) -> Node3D:
	var ability: Ability = load(tome.ability_path) as Ability if ResourceLoader.exists(tome.ability_path) else null
	var kind := "neutral"
	if ability and ability.deals_damage():
		kind = String(Constants.DamageType.keys()[ability.damage_type]).to_lower()
	var model := item_model("tome_" + kind)
	return model if model else item_model("tome_neutral")

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
