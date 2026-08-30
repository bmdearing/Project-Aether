extends Area3D
class_name PiercingBolt
## Straight-line traveling bolt that PIERCES - unlike entities/projectile/
## Projectile.gd (which queue_free()s on its first hit, shared with
## ordinary ranged weapon fire), this keeps traveling through its whole
## lifetime, damaging every NEW enemy it touches once each (tracked in
## _hit_enemies so a wide/slow bolt can't tick the same enemy twice while
## overlapping it). User request (2026-08-30): Cinder Lance and Thunder
## Javelin both "should pierce" / "work like Cinder Lance."
##
## Player-only for now (no enemy caster uses this) - source is always the
## casting Player, aimed from the camera along its forward direction.

@export var speed: float = 22.0
@export var lifetime: float = 2.0

var damage_amount: float = 0.0
var damage_type: Constants.DamageType = Constants.DamageType.KINETIC
var source: Node
var is_critical: bool = false
var applies_status_effects: Array[String] = []

var _hit_enemies: Array[Enemy] = []

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
	var enemy := body as Enemy
	if enemy == null or _hit_enemies.has(enemy):
		return
	_hit_enemies.append(enemy)
	enemy.take_damage(damage_amount, damage_type)
	if enemy.stance:
		enemy.stance.apply_attack_stance_damage(damage_amount, damage_type)
	EventBus.damage_dealt.emit(source, enemy, damage_amount, damage_type, false, is_critical)
	for effect_id in applies_status_effects:
		enemy.status_effects.apply_effect(effect_id, source, damage_amount)
