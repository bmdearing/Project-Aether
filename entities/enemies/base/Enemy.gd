extends CharacterBody3D
class_name Enemy
## Base enemy per the Trinity Rule (Section 21) - archetype is a combination
## of at most two of {Fast, Lethal, Tanky}. Archetype-specific subclasses
## (GlassCannon, MobileBruiser, HeavyHitter) should extend this and tune
## exported values rather than duplicate component wiring.
##
## Chase movement lives here (shared by every archetype); actually
## threatening the player is still an optional child component
## (EnemyMeleeAttack and/or EnemyRangedAttack, see systems/combat/), which
## drives begin_attack_telegraph()/end_attack_telegraph() below. Chasing
## and attacking are deliberately decoupled - this node doesn't know or
## care which attack component (if any) a given archetype has attached,
## same compositional pattern as Player's melee/ranged attack nodes.

@export var archetype: Constants.EnemyArchetype
@export var move_speed: float = 3.0
## Distance at which this enemy notices the player and starts moving.
@export var chase_range: float = 15.0
## Distance the enemy tries to close to and then holds - for melee
## archetypes this should sit at/inside their attack component's
## attack_range so Idle's own proximity check can trigger once movement
## stops; for a ranged archetype it's a stand-off distance instead.
@export var stop_distance: float = 2.3
## >0 makes the enemy back away once the player is closer than this
## (kiting) - 0 disables retreat entirely (melee archetypes just hold at
## stop_distance).
@export var retreat_distance: float = 0.0

const TELEGRAPH_COLOR := Color(1.0, 0.95, 0.2)

@onready var health: HealthComponent = $HealthComponent
@onready var stance: StanceComponent = $StanceComponent
@onready var composure: ComposureComponent = $ComposureComponent
@onready var attack_hitbox: Area3D = $AttackHitbox

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _base_color: Color = Color.WHITE
var _player: Player

func _ready() -> void:
	health.died.connect(_on_died)
	add_to_group("enemy")
	# Same group-lookup pattern EnemyMeleeAttack already uses successfully -
	# safe here (unlike reading another node's @onready var) because this
	# is Enemy's own _ready(), and Player's subtree finishes readying
	# before any Enemy's does (Player is declared first in TestArena.tscn).
	_player = get_tree().get_first_node_in_group("player") as Player

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_chase()
	move_and_slide()

## Pure translation, no facing/rotation - the capsule placeholder mesh is
## rotationally symmetric so there's nothing to see yet; revisit once
## enemy art exists to actually show a facing direction.
func _update_chase() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if not is_instance_valid(_player) or not health.is_alive():
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if dist > chase_range or dist < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var dir := to_player / dist
	if retreat_distance > 0.0 and dist < retreat_distance:
		velocity.x = -dir.x * move_speed
		velocity.z = -dir.z * move_speed
	elif dist > stop_distance:
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

func _on_died() -> void:
	queue_free()

func take_damage(amount: float, damage_type: Constants.DamageType, is_spell: bool = false) -> void:
	var multiplier := composure.get_damage_multiplier(is_spell) if composure else 1.0
	health.apply_damage(amount * multiplier)

func _set_placeholder_color(c: Color) -> void:
	_base_color = c
	_apply_mesh_color(c)

## Visual stand-in for a telegraph animation until enemy art/animation
## exists: flash the capsule to a warning color, then ease it back to the
## base color over the telegraph so the color's RETURN - not just its
## appearance - is the "the hit is coming now" cue.
func begin_attack_telegraph() -> void:
	_apply_mesh_color(TELEGRAPH_COLOR)

## progress: 0.0 (just telegraphed) -> 1.0 (about to strike).
func update_attack_telegraph(progress: float) -> void:
	_apply_mesh_color(TELEGRAPH_COLOR.lerp(_base_color, clamp(progress, 0.0, 1.0)))

func end_attack_telegraph() -> void:
	_apply_mesh_color(_base_color)

func _apply_mesh_color(c: Color) -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mesh.set_surface_override_material(0, mat)
