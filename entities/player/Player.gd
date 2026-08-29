extends CharacterBody3D
class_name Player
## First-person controller. Camera lives in Head; WeaponSocket under the
## camera holds the placeholder blade. Melee weight (Pillar 2) reads
## through camera shake/swing/hitstop, not a visible body.

@export var move_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var crouch_speed: float = 3.0
## 7.0 (was 4.5) - needed to clear the Vault's jump gap + platform rise;
## matches Enemy.jump_velocity, tuned the same way.
@export var jump_velocity: float = 7.0
@export var mouse_sensitivity: float = 0.0035
@export var max_look_up_deg: float = 89.0
@export var stat_sheet: StatSheet

@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_socket: Node3D = $Head/Camera3D/WeaponSocket
@onready var weapon_mesh: MeshInstance3D = $Head/Camera3D/WeaponSocket/WeaponMesh
@onready var attack_hitbox: Area3D = $Head/Camera3D/WeaponSocket/WeaponMesh/AttackHitbox
@onready var sidearm_mesh: MeshInstance3D = $Head/Camera3D/WeaponSocket/SidearmMesh
@onready var shield_mesh: MeshInstance3D = $Head/Camera3D/ShieldSocket/ShieldMesh
@onready var health: HealthComponent = $HealthComponent
@onready var ward: WardComponent = $WardComponent
@onready var mana: ManaComponent = $ManaComponent
@onready var parry_handler: ParryRiposteHandler = $ParryRiposteHandler
@onready var equipment: EquipmentComponent = $EquipmentComponent
@onready var ability_loadout: AbilityLoadoutComponent = $AbilityLoadoutComponent
@onready var melee_attack: PlayerMeleeAttack = $PlayerMeleeAttack
@onready var ranged_attack: PlayerRangedAttack = $PlayerRangedAttack
@onready var ability_cast: PlayerAbilityCast = $PlayerAbilityCast
@onready var experience: ExperienceComponent = $ExperienceComponent

var fate_board: FateBoard
var _active_weapon_slot: Constants.EquipmentSlot = Constants.EquipmentSlot.PRIMARY_WEAPON
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _base_max_health: float = 0.0
var _base_max_mana: float = 0.0
var _base_mana_regen: float = 0.0

## Crouch/slide: fully invented, no doc-sourced design. Capsule shrinks
## from STANDING to CROUCH height anchored at the feet (not centered),
## head lowers to match. No headroom check standing up - nothing low
## enough to clip into yet.
const STANDING_CAPSULE_HEIGHT := 1.8
const CROUCH_CAPSULE_HEIGHT := 1.0
const STANDING_HEAD_Y := 1.6
const CROUCH_HEAD_Y := 0.8
const CROUCH_TRANSITION_SPEED := 6.0

## Slide: tap Crouch while sprinting + moving, on the floor. Launches
## along the move direction at SLIDE_SPEED (or current sprint speed if
## faster), decelerating to crouch speed. Jumping/leaving the floor
## cancels it; ends into a crouch if Crouch is still held.
const SLIDE_SPEED := 12.0
const SLIDE_DURATION := 0.5
const SLIDE_DECELERATION := 14.0

var _is_crouching: bool = false
var _is_sliding: bool = false
var _slide_timer: float = 0.0
var _slide_direction: Vector3 = Vector3.ZERO
var _slide_speed_current: float = 0.0

## Section 12: Instinct -> Action Speed, split by type ("1% Attack/Cast |
## 0.7% Dodge | 0.5% Move" per point). No Dodge mechanic exists yet.
const INSTINCT_MOVE_SPEED_PCT := 0.005
const INSTINCT_ACTION_SPEED_PCT := 0.01

func _ready() -> void:
	if stat_sheet == null:
		# Fallback only - Player.tscn assigns player_baseline.tres normally.
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
	mouse_sensitivity = GameState.mouse_sensitivity
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	health.died.connect(_on_died)
	# Captured before any gear bonus applies - the .tscn's static values
	# are the class baseline Vitality/Intellect add on top of.
	_base_max_health = health.max_health
	_base_max_mana = mana.max_mana
	_base_mana_regen = mana.regen_per_second
	if collision_shape.shape:
		collision_shape.shape = collision_shape.shape.duplicate()
	equipment.equipment_changed.connect(_on_equipment_changed)
	_apply_saved_loadout()
	_apply_saved_experience()
	_on_equipment_changed()  # applies stat bonuses + visuals for whatever _apply_saved_loadout() just equipped

## Fires on every equip()/unequip(), not just at spawn - also covers a
## shield/weapon equipped into a previously-empty slot.
func _on_equipment_changed() -> void:
	stat_sheet.set_equipment_bonus(equipment.compute_stat_bonuses())
	_apply_derived_stats()
	_update_shield_mesh()
	_update_active_weapon_visual()

## Section 12 per-point values. DoT mitigation/Debuff effectiveness are
## deferred - no supporting system exists yet.
const VITALITY_LIFE_PER_POINT := 2.0
const VITALITY_LIFE_REGEN_PER_POINT := 0.1
const INTELLECT_MANA_PER_POINT := 2.0
const INTELLECT_MANA_REGEN_PER_POINT := 0.1

func _apply_derived_stats() -> void:
	var vitality := stat_sheet.get_stat(Constants.Stat.VITALITY)
	var intellect := stat_sheet.get_stat(Constants.Stat.INTELLECT)
	health.set_max_health(_base_max_health + vitality * VITALITY_LIFE_PER_POINT)
	health.regen_per_second = vitality * VITALITY_LIFE_REGEN_PER_POINT
	mana.max_mana = _base_max_mana + intellect * INTELLECT_MANA_PER_POINT
	mana.regen_per_second = _base_mana_regen + intellect * INTELLECT_MANA_REGEN_PER_POINT

func _apply_saved_experience() -> void:
	experience.level = GameState.player_level
	experience.xp = GameState.player_xp
	experience.leveled_up.connect(_on_leveled_up)
	experience.xp_changed.connect(_on_xp_changed)

## Section 12: leveling grants no stat points (gear-only). Level itself
## just feeds GearShop's stock-quality signal.
func _on_leveled_up(new_level: int) -> void:
	GameState.player_level = new_level
	EventBus.player_leveled_up.emit(new_level)

func _on_xp_changed(current: float, _needed: float) -> void:
	GameState.player_xp = current

func _on_died() -> void:
	EventBus.player_died.emit()

## Re-applies GameState's equipment/ability loadout - Player is a fresh
## instance every scene load, so this runs every time, not just at boot.
func _apply_saved_loadout() -> void:
	for ref in GameState.equipment_refs:
		var item: Item = load(ref) if ref is String and ref != "" else (ItemSerializer.from_dict(ref) if ref is Dictionary else null)
		if item:
			equipment.equip(item)
	for i in range(GameState.ability_loadout_paths.size()):
		var path: String = GameState.ability_loadout_paths[i]
		if path != "":
			var ability: Ability = load(path)
			if ability:
				ability_loadout.equip(ability, i)
	_apply_saved_ability_ranks()

func _apply_saved_ability_ranks() -> void:
	if GameState.ability_ranks.is_empty():
		return
	var dir_path := "res://data/abilities/instances/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var ability: Ability = load(dir_path + file_name) as Ability
			if ability and GameState.ability_ranks.has(ability.ability_id):
				ability.rank = GameState.ability_ranks[ability.ability_id]
		file_name = dir.get_next()
	dir.list_dir_end()

func _update_weapon_mesh_color() -> void:
	_color_mesh_for_weapon(weapon_mesh, equipment.primary_weapon)

func _update_sidearm_mesh_color() -> void:
	_color_mesh_for_weapon(sidearm_mesh, equipment.sidearm_weapon)

func _color_mesh_for_weapon(target_mesh: MeshInstance3D, weapon: Weapon) -> void:
	if target_mesh == null:
		return
	if weapon == null:
		target_mesh.visible = false
		return
	target_mesh.material_override = _unshaded_material(Constants.DAMAGE_TYPE_COLOR.get(weapon.native_damage_type, Color.WHITE))

func _update_active_weapon_visual() -> void:
	_update_weapon_mesh_color()
	_update_sidearm_mesh_color()
	var primary_active := _active_weapon_slot == Constants.EquipmentSlot.PRIMARY_WEAPON
	if weapon_mesh:
		weapon_mesh.visible = primary_active and equipment.primary_weapon != null
	if sidearm_mesh:
		sidearm_mesh.visible = not primary_active and equipment.sidearm_weapon != null

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

## Melee vs ranged attack follows the active Weapon's is_ranged, not
## which slot it's in - see the dispatch in _physics_process().
func _swap_active_weapon() -> void:
	_active_weapon_slot = Constants.EquipmentSlot.SIDEARM_WEAPON if _active_weapon_slot == Constants.EquipmentSlot.PRIMARY_WEAPON else Constants.EquipmentSlot.PRIMARY_WEAPON
	_update_active_weapon_visual()
	EventBus.weapon_swapped.emit(self)

func get_active_weapon() -> Weapon:
	return equipment.sidearm_weapon if _active_weapon_slot == Constants.EquipmentSlot.SIDEARM_WEAPON else equipment.primary_weapon

func take_damage(amount: float, damage_type: Constants.DamageType, source: Node = null) -> void:
	var mitigated := amount
	if Constants.DAMAGE_TYPE_CATEGORY.get(damage_type) == Constants.DamageCategory.PHYSICAL:
		var armor := equipment.get_total_armor() if equipment else 0.0
		mitigated = amount * (1.0 - DamageCalculator.physical_mitigation(armor, amount))
	var overflow := ward.absorb(mitigated, damage_type)
	health.apply_damage(overflow)
	EventBus.damage_dealt.emit(source, self, mitigated, damage_type, false, false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		var clamped_x: float = clamp(head.rotation.x, deg_to_rad(-max_look_up_deg), deg_to_rad(max_look_up_deg))
		head.rotation.x = clamped_x

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
		_is_sliding = false
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		_is_sliding = false

	var crouch_held := Input.is_action_pressed("crouch")
	var sprinting := Input.is_action_pressed("sprint")
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if Input.is_action_just_pressed("crouch") and is_on_floor() and not _is_sliding and sprinting and move_dir.length() > 0.1:
		_start_slide(move_dir)

	if _is_sliding:
		_slide_timer -= delta
		_slide_speed_current = max(_slide_speed_current - SLIDE_DECELERATION * delta, _effective_speed(crouch_speed))
		velocity.x = _slide_direction.x * _slide_speed_current
		velocity.z = _slide_direction.z * _slide_speed_current
		_is_crouching = true
		if _slide_timer <= 0.0 or not is_on_floor():
			_end_slide(crouch_held)
	else:
		_is_crouching = crouch_held
		var speed := _effective_speed(crouch_speed) if _is_crouching else _effective_speed(sprint_speed if sprinting else move_speed)
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed

	_update_crouch_visual(delta)
	move_and_slide()

	if Input.is_action_just_pressed("parry"):
		parry_handler.start_parry_window()

	if Input.is_action_just_pressed("swap_weapon"):
		_swap_active_weapon()

	if Input.is_action_just_pressed("attack"):
		var active_weapon := get_active_weapon()
		if active_weapon and active_weapon.is_ranged:
			ranged_attack.try_attack()
		else:
			melee_attack.try_attack()

func get_move_speed_multiplier() -> float:
	return 1.0 + stat_sheet.get_stat(Constants.Stat.INSTINCT) * INSTINCT_MOVE_SPEED_PCT

func _effective_speed(base: float) -> float:
	return base * get_move_speed_multiplier()

func get_action_speed_multiplier() -> float:
	return 1.0 + stat_sheet.get_stat(Constants.Stat.INSTINCT) * INSTINCT_ACTION_SPEED_PCT

func _start_slide(move_dir: Vector3) -> void:
	_is_sliding = true
	_slide_timer = SLIDE_DURATION
	_slide_direction = move_dir
	_slide_speed_current = max(_effective_speed(sprint_speed), SLIDE_SPEED)

func _end_slide(keep_crouching: bool) -> void:
	_is_sliding = false
	_is_crouching = keep_crouching

func _update_crouch_visual(delta: float) -> void:
	var crouched := _is_crouching or _is_sliding
	var target_height := CROUCH_CAPSULE_HEIGHT if crouched else STANDING_CAPSULE_HEIGHT
	var target_head_y := CROUCH_HEAD_Y if crouched else STANDING_HEAD_Y
	var shape := collision_shape.shape as CapsuleShape3D
	if shape:
		shape.height = move_toward(shape.height, target_height, CROUCH_TRANSITION_SPEED * delta)
		collision_shape.position.y = shape.height / 2.0
	head.position.y = move_toward(head.position.y, target_head_y, CROUCH_TRANSITION_SPEED * delta)
