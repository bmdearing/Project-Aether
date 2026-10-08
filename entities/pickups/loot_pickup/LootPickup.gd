extends Area3D
class_name LootPickup
## Auto-pickup on touch - a judgment call, not requested verbatim. Fits
## genre convention for gear that drops constantly during combat better
## than adding a whole proximity-prompt + keypress flow (like
## RealityEngine's) for something this frequent. Spawned by Enemy.gd on death
## with one ItemRoller-rolled Item (or, since the Slate-system expansion,
## a SlateRoller-rolled Slate - see the `slate` field) already assigned.
## Placeholder visual (a colored, rotating/bobbing sphere) keyed by rarity
## (Constants.ITEM_RARITY_COLOR / Constants.SLATE_RARITY_COLOR) - same
## color language ItemSlotButton and the Player's weapon/shield meshes
## already use.

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

var _base_y: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	_base_y = position.y
	body_entered.connect(_on_body_entered)
	if item:
		_apply_color(Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE))
		if item.rarity >= Constants.ItemRarity.RARE:
			_add_beam(Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE))
	elif currency_id != &"":
		_apply_color(InventoryGridView.CURRENCY_COLOR)
	elif slate:
		_apply_color(Constants.SLATE_RARITY_COLOR.get(slate.rarity, Color.WHITE))

## A tall faint light column so Rare and better drops stand out across a field.
const BEAM_HEIGHT := 5.0

func _add_beam(color: Color) -> void:
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.03
	cylinder.bottom_radius = 0.09
	cylinder.height = BEAM_HEIGHT
	beam.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color, 0.45)
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(0, BEAM_HEIGHT / 2.0, 0)
	add_child(beam)

func _apply_color(color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat

func _process(delta: float) -> void:
	_time += delta
	rotate_y(ROTATE_SPEED * delta)
	position.y = _base_y + sin(_time * BOB_SPEED) * BOB_HEIGHT

func _on_body_entered(body: Node3D) -> void:
	if not (body is Player):
		return
	if currency_id != &"":
		var leftover := GameState.inventory.add(currency_id, currency_count)
		if leftover > 0:
			currency_count = leftover
			EventBus.inventory_full.emit(null)
			return
		queue_free()
		return
	if slate:
		if not GameState.add_to_inventory(slate):
			EventBus.inventory_full.emit(slate)
			return
		EventBus.slate_picked_up.emit(slate)
		queue_free()
		return
	if item == null:
		return
	if item is AmmoPack:
		var pack := item as AmmoPack
		AmmoInventory.add(pack.ammo_type, pack.amount)
		queue_free()
		return
	if item is SkillTome:
		var tome := item as SkillTome
		if not GameState.owned_ability_ids.has(tome.ability_id):
			GameState.owned_ability_ids.append(tome.ability_id)
		EventBus.tome_picked_up.emit(tome)
	else:
		if not GameState.add_to_inventory(item):
			EventBus.inventory_full.emit(item)
			return
		EventBus.loot_picked_up.emit(item)
	queue_free()
