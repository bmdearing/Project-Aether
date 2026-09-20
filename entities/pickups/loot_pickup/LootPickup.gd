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

@onready var mesh: MeshInstance3D = $MeshInstance3D

var _base_y: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	_base_y = position.y
	body_entered.connect(_on_body_entered)
	if item:
		_apply_color(Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE))
	elif slate:
		_apply_color(Constants.SLATE_RARITY_COLOR.get(slate.rarity, Color.WHITE))

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
	if slate:
		GameState.owned_slates.append(slate)
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
		GameState.owned_loot.append(item)
		EventBus.loot_picked_up.emit(item)
	queue_free()
