extends Area3D
class_name Projectile
## Straight-line moving projectile - no gravity/arc. Spawned by
## PlayerRangedAttack or EnemyRangedAttack, which set damage_amount/
## damage_type/source/speed BEFORE add_child() so _ready() sees them,
## then align global_transform to the muzzle after.
##
## Damage is computed once at fire time by the spawner - a weapon swap
## mid-flight can't retroactively change an already-fired shot.
##
## `source` decides what it can hurt: a Player-fired shot damages the
## first Enemy it touches, an Enemy-fired shot damages the Player (and
## can be parried, same as EnemyMeleeAttack's Strike).

@export var speed: float = 25.0
@export var lifetime: float = 3.0

var damage_amount: float = 0.0
var damage_type: Constants.DamageType = Constants.DamageType.KINETIC
var source: Node
var is_critical: bool = false  # set by PlayerRangedAttack._fire() - enemy-fired shots leave this false

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Constants.DAMAGE_TYPE_COLOR.get(damage_type, Color.WHITE)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = mat

func _physics_process(delta: float) -> void:
	global_position += -global_transform.basis.z * speed * delta

func _on_body_entered(body: Node3D) -> void:
	if source is Player:
		_hit_enemy(body as Enemy)
	else:
		_hit_player(body as Player)
	queue_free()

func _hit_enemy(enemy: Enemy) -> void:
	if enemy == null:
		return
	enemy.take_damage(damage_amount, damage_type)
	if enemy.stance:
		enemy.stance.apply_attack_stance_damage(damage_amount, damage_type)
	EventBus.damage_dealt.emit(source, enemy, damage_amount, damage_type, false, is_critical)

func _hit_player(player: Player) -> void:
	if player == null:
		return
	var parried: bool = player.parry_handler and player.parry_handler.attempt_parry(source, player.ward)
	if not parried:
		player.take_damage(damage_amount, damage_type, source)
	EventBus.enemy_attack_resolved.emit(source, player, true, parried)
