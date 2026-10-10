extends Node3D
class_name SparkCrawler
## Spark ground crawler. Re-targets the nearest enemy every frame and turns
## toward it at TURN_SPEED; wanders when nothing is within SEEK_RADIUS. Can
## hit the same enemy repeatedly, at most once per HIT_INTERVAL - shared by
## every crawler (HitCooldown), so a cast's sparks can't stack on one enemy.
##
## straight = true (Booming Blade): no seeking or wandering, it runs flat
## along its heading at speed for range metres, stops at walls, and uses
## its own hit_key / hit_interval.

const MOVE_SPEED := 5.0
const TURN_SPEED := 3.0  # rad/s
const SEEK_RADIUS := 12.0
const LIFETIME := 4.0
const HIT_INTERVAL := 0.15
const HIT_RADIUS := 0.7
const WANDER_INTERVAL := 0.4
const WANDER_TURN_RANGE := 1.2  # max radians of random turn per wander tick

var heading: Vector3 = Vector3.FORWARD
var ability: Ability
var stat_sheet: StatSheet
var source: Node
var damage_multiplier: float = 1.0
var straight: bool = false
var speed: float = MOVE_SPEED
var lifetime: float = LIFETIME
var range_m: float = 0.0
var hit_key: StringName = &"spark"
var hit_interval: float = HIT_INTERVAL
var _travelled: float = 0.0

var _wander_timer: float = 0.0
var _wander_target: Vector3 = Vector3.FORWARD

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	if not straight:
		get_tree().create_timer(lifetime).timeout.connect(queue_free)
	if mesh and ability:
		_build_visuals(Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE))

func _physics_process(delta: float) -> void:
	_crackle(delta)
	if straight:
		if not _advance_straight(delta):
			return
	else:
		_advance_seeking(delta)
	_hit_enemies_in_reach()

func _advance_seeking(delta: float) -> void:
	var target := _find_nearest_enemy()
	var desired: Vector3 = heading
	if target:
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() > 0.05:
			desired = to_target.normalized()
	else:
		desired = _tick_wander(delta)
	heading = heading.lerp(desired, TURN_SPEED * delta).normalized()

	global_position += heading * MOVE_SPEED * delta
	if heading.length() > 0.01:
		look_at(global_position + heading, Vector3.UP)

## False once it has hit a wall or run its range (and freed itself).
func _advance_straight(delta: float) -> bool:
	var step := heading * speed * delta
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3, global_position + Vector3.UP * 0.3 + step, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit["collider"] is StaticBody3D and absf(hit["normal"].y) < 0.6:
		queue_free()
		return false
	global_position += step
	look_at(global_position + heading, Vector3.UP)
	_travelled += step.length()
	if range_m > 0.0 and _travelled >= range_m:
		queue_free()
		return false
	return true

func _hit_enemies_in_reach() -> void:
	if ability == null or stat_sheet == null:
		return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if enemy.distance_to_body(global_position) > HIT_RADIUS:
			continue
		if not HitCooldown.try_hit(hit_key, enemy, hit_interval):
			continue
		var hit := ability.roll_damage(stat_sheet)
		var damage: float = hit["final_damage"] * damage_multiplier
		enemy.take_damage(damage, ability.damage_type)
		if enemy.stance:
			enemy.stance.apply_attack_stance_damage(damage, ability.damage_type)
		EventBus.damage_dealt.emit(source, enemy, damage, ability.damage_type, false, hit["is_critical"])
		ability.apply_statuses(enemy, source, damage)

func _find_nearest_enemy() -> Enemy:
	var nearest: Enemy = null
	var nearest_dist := SEEK_RADIUS
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest

## Picks a new random heading every WANDER_INTERVAL.
func _tick_wander(delta: float) -> Vector3:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = WANDER_INTERVAL
		var turn := randf_range(-WANDER_TURN_RANGE, WANDER_TURN_RANGE)
		_wander_target = heading.rotated(Vector3.UP, turn).normalized()
	return _wander_target

## ---- Visuals -----------------------------------------------------------------

const ARC_INTERVAL := 0.11
const ARC_REACH := 0.7
const ORB_HEIGHT := 0.3

var _color: Color = Color.WHITE
var _arc_timer: float = 0.0
var _light: OmniLight3D

## A crackling ball of light skittering along the floor: glow, a spray of
## sparks, a flickering light, and little arcs jumping down to the ground.
func _build_visuals(color: Color) -> void:
	_color = color
	mesh.visible = false
	for layer in [[0.75, Color(color, 0.55)], [0.28, Color(1.0, 0.98, 0.85, 1.0)]]:
		var glow := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * float(layer[0])
		glow.mesh = quad
		var mat := SpellFx.glow_material(layer[1], true, BaseMaterial3D.BILLBOARD_ENABLED)
		mat.vertex_color_use_as_albedo = false
		glow.material_override = mat
		glow.position.y = ORB_HEIGHT
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(glow)
	var sparks := SpellFx.emitter(self, 24, 0.25)
	sparks.local_coords = false
	sparks.position.y = ORB_HEIGHT
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 1.5
	sparks.initial_velocity_max = 3.5
	sparks.gravity = Vector3(0, -6.0, 0)
	sparks.scale_amount_min = 0.03
	sparks.scale_amount_max = 0.06
	sparks.color_ramp = SpellFx.ramp(Color(1.0, 1.0, 0.9, 1.0), Color(color, 1.0), 0.2)
	sparks.mesh = SpellFx.glow_quad()
	sparks.emitting = true
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 2.5
	_light.position.y = ORB_HEIGHT
	add_child(_light)

func _crackle(delta: float) -> void:
	if _light == null:
		return
	_light.light_energy = randf_range(0.8, 1.6)
	_arc_timer -= delta
	if _arc_timer > 0.0:
		return
	_arc_timer = ARC_INTERVAL
	var from := global_position + Vector3.UP * ORB_HEIGHT
	var angle := randf() * TAU
	var to := global_position + Vector3(cos(angle), 0.02, sin(angle)) * randf_range(0.25, ARC_REACH)
	LightningArc.spawn(get_parent(), from, to, _color, 0.25, false, 0)
