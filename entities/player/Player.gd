extends CharacterBody3D
class_name Player
## True first-person controller. Camera lives in the Head node; a
## WeaponSocket under the camera holds a placeholder blade mesh (real
## viewmodel once art exists). Melee weight (Pillar 2) is communicated
## through camera shake / swing motion / hitstop on the viewmodel, NOT
## through seeing the player's body swing - there isn't one, by design.
## See systems/combat/PlayerMeleeAttack.gd for the actual attack.

@export var move_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0035
@export var max_look_up_deg: float = 89.0
@export var stat_sheet: StatSheet

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_socket: Node3D = $Head/Camera3D/WeaponSocket
@onready var weapon_mesh: MeshInstance3D = $Head/Camera3D/WeaponSocket/WeaponMesh
@onready var attack_hitbox: Area3D = $Head/Camera3D/WeaponSocket/WeaponMesh/AttackHitbox
@onready var sidearm_mesh: MeshInstance3D = $Head/Camera3D/WeaponSocket/SidearmMesh
@onready var shield_mesh: MeshInstance3D = $Head/Camera3D/ShieldSocket/ShieldMesh
@onready var health: HealthComponent = $HealthComponent
@onready var ward: WardComponent = $WardComponent
@onready var parry_handler: ParryRiposteHandler = $ParryRiposteHandler
@onready var equipment: EquipmentComponent = $EquipmentComponent
@onready var melee_attack: PlayerMeleeAttack = $PlayerMeleeAttack
@onready var ranged_attack: PlayerRangedAttack = $PlayerRangedAttack

var fate_board: FateBoard
var _active_weapon_slot: Constants.EquipmentSlot = Constants.EquipmentSlot.PRIMARY_WEAPON
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	if stat_sheet == null:
		# Fallback only - Player.tscn assigns data/stats/instances/
		# player_baseline.tres as the real default. Matches those same
		# values so nothing silently breaks if a future scene forgets to
		# assign one.
		stat_sheet = StatSheet.new()
		stat_sheet.vitality = 10.0
		stat_sheet.strength = 10.0
		stat_sheet.instinct = 10.0
		stat_sheet.arcane = 10.0
		stat_sheet.enigma = 10.0
		stat_sheet.intellect = 10.0
	fate_board = FateBoard.new()
	GameState.player_stat_sheet = stat_sheet
	GameState.fate_board = fate_board
	GameState.player_equipment = equipment
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	health.died.connect(_on_died)
	_update_shield_mesh()
	_update_active_weapon_visual()

## DamageCalculator.calculate() multiplies base_weapon_damage by
## stat_value * scale, so a zero-stat StatSheet made every player hit
## (melee and ranged) resolve to exactly 0 final_damage - this was the
## actual bug, not just missing flavor. See player_baseline.tres.
func _on_died() -> void:
	EventBus.player_died.emit()

## Placeholder blade colored by the equipped weapon's damage type (same
## Constants.DAMAGE_TYPE_COLOR language used for the Fate Board grid).
## Unshaded + material_override (not set_surface_override_material) so the
## color reads correctly regardless of scene lighting - a lit placeholder
## sitting right against the camera can end up looking flat/dark depending
## on ambient light, which made it hard to pick out. Re-run on ready and on
## every weapon swap; EquipmentComponent still has no "equipped changed"
## signal, so re-equipping the *same* slot via the Inventory UI mid-game
## won't re-color until that's added.
func _update_weapon_mesh_color() -> void:
	_color_mesh_for_weapon(weapon_mesh, equipment.primary_weapon)

## Same treatment for the Sidearm slot's placeholder mesh - a distinct
## shape from the blade, not a recolor of it, so swapping weapons (V)
## visibly reads as "different weapon" rather than just a color change.
func _update_sidearm_mesh_color() -> void:
	_color_mesh_for_weapon(sidearm_mesh, equipment.sidearm_weapon)

func _color_mesh_for_weapon(target_mesh: MeshInstance3D, weapon: Weapon) -> void:
	if target_mesh == null:
		return
	if weapon == null:
		target_mesh.visible = false
		return
	target_mesh.material_override = _unshaded_material(Constants.DAMAGE_TYPE_COLOR.get(weapon.native_damage_type, Color.WHITE))

## Shows whichever of weapon_mesh/sidearm_mesh matches _active_weapon_slot
## (and only if that slot actually has a weapon equipped) - swap_weapon (V)
## calls this after toggling the slot.
func _update_active_weapon_visual() -> void:
	_update_weapon_mesh_color()
	_update_sidearm_mesh_color()
	var primary_active := _active_weapon_slot == Constants.EquipmentSlot.PRIMARY_WEAPON
	if weapon_mesh:
		weapon_mesh.visible = primary_active and equipment.primary_weapon != null
	if sidearm_mesh:
		sidearm_mesh.visible = not primary_active and equipment.sidearm_weapon != null

## Same treatment as the weapon blade, colored by Section 18's rarity
## palette (Constants.ITEM_RARITY_COLOR) since Shield has no damage-type
## identity of its own to key a color off of. Hidden whenever
## EquipmentComponent.offhand is empty (no shield, or a two-handed weapon
## cleared it).
func _update_shield_mesh() -> void:
	if shield_mesh == null:
		return
	var shield := equipment.offhand
	if shield == null:
		shield_mesh.visible = false
		return
	shield_mesh.visible = true
	shield_mesh.material_override = _unshaded_material(Constants.ITEM_RARITY_COLOR.get(shield.rarity, Color.WHITE))

func _unshaded_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

## Toggles between Primary (melee) and Sidearm (ranged) - the only two
## weapon slots with an actual attack behind them so far.
func _swap_active_weapon() -> void:
	_active_weapon_slot = Constants.EquipmentSlot.SIDEARM_WEAPON if _active_weapon_slot == Constants.EquipmentSlot.PRIMARY_WEAPON else Constants.EquipmentSlot.PRIMARY_WEAPON
	_update_active_weapon_visual()

## Physical hits are mitigated by equipped Armor first (Section 16), then
## Ward absorbs the Esoteric portion of what's left (WardComponent.absorb),
## remainder overflows to Health - mirrors Enemy.take_damage's shape.
func take_damage(amount: float, damage_type: Constants.DamageType, source: Node = null) -> void:
	var mitigated := amount
	if Constants.DAMAGE_TYPE_CATEGORY.get(damage_type) == Constants.DamageCategory.PHYSICAL:
		var armor := equipment.get_total_armor() if equipment else 0.0
		mitigated = amount * (1.0 - DamageCalculator.physical_mitigation(armor, amount))
	var overflow := ward.absorb(mitigated, damage_type)
	health.apply_damage(overflow)
	EventBus.damage_dealt.emit(source, self, mitigated, damage_type, false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		var clamped_x: float = clamp(head.rotation.x, deg_to_rad(-max_look_up_deg), deg_to_rad(max_look_up_deg))
		head.rotation.x = clamped_x

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var speed := sprint_speed if Input.is_action_pressed("sprint") else move_speed
	# Movement is relative to where the body (not the camera pitch) is facing,
	# so looking up/down doesn't tilt movement into the floor or sky.
	var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

	move_and_slide()

	if Input.is_action_just_pressed("parry"):
		parry_handler.start_parry_window()

	if Input.is_action_just_pressed("swap_weapon"):
		_swap_active_weapon()

	if Input.is_action_just_pressed("attack"):
		if _active_weapon_slot == Constants.EquipmentSlot.SIDEARM_WEAPON:
			ranged_attack.try_attack()
		else:
			melee_attack.try_attack()
