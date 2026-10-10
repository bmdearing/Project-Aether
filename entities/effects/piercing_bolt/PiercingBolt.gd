extends Area3D
class_name PiercingBolt
## Straight-line bolt that pierces, hitting each enemy once (_hit_enemies).
## Player-cast only.

@export var speed: float = 22.0
@export var lifetime: float = 2.0

var damage_amount: float = 0.0
var damage_type: Constants.DamageType = Constants.DamageType.KINETIC
var source: Node
var is_critical: bool = false
var ability: Ability  # rolls its statuses on each enemy hit

## Thunder Sweep: travels flat along the ground, riding over slopes and
## stopping only at walls; max_distance > 0 ends the bolt after that far.
var follow_ground: bool = false
var max_distance: float = 0.0

var _hit_enemies: Array[Enemy] = []
var _travelled: float = 0.0

const GROUND_OFFSET := 0.3
const WALL_NORMAL_Y := 0.6

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	if mesh:
		_build_visuals()

## Moves by ray-checked steps: enemies along the step are hit (so a fast
## bolt can't skip past one between frames), walls and floors stop it.
func _physics_process(delta: float) -> void:
	var step := -global_transform.basis.z * speed * delta
	if follow_ground:
		step.y = 0.0
	var space := get_world_3d().direct_space_state
	var from := global_position
	var exclude: Array[RID] = []
	if not is_instance_valid(source):
		source = null  # the shooter left (scene change, death); hits still land, unattributed
	if source is CollisionObject3D:
		exclude.append(source.get_rid())
	for i in 8:
		var query := PhysicsRayQueryParameters3D.create(from, from + step, 1)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit["collider"]
		if collider is Enemy:
			_hit(collider)
		elif collider is StaticBody3D and not (follow_ground and hit["normal"].y > WALL_NORMAL_Y):
			_impact(hit["position"])
			queue_free()
			return
		exclude.append(hit["rid"])
	global_position = from + step
	if follow_ground:
		_snap_to_ground(space)
	_travelled += step.length()
	if max_distance > 0.0 and _travelled >= max_distance:
		queue_free()

func _snap_to_ground(space: PhysicsDirectSpaceState3D) -> void:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, global_position + Vector3.DOWN * 3.0, 1)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit and hit["collider"] is StaticBody3D:
		global_position.y = hit["position"].y + GROUND_OFFSET

func _on_body_entered(body: Node3D) -> void:
	var enemy := body as Enemy
	if enemy:
		_hit(enemy)

func _hit(enemy: Enemy) -> void:
	if _hit_enemies.has(enemy) or not enemy.health.is_alive():
		return
	_hit_enemies.append(enemy)
	enemy.take_damage(damage_amount, damage_type)
	if enemy.stance:
		enemy.stance.apply_attack_stance_damage(damage_amount, damage_type)
	EventBus.damage_dealt.emit(source, enemy, damage_amount, damage_type, false, is_critical)
	if ability:
		ability.apply_statuses(enemy, source, damage_amount)

## ---- Visuals -----------------------------------------------------------------

const STREAK_SHADER := preload("res://shaders/spell_streak.gdshader")
const FIRE_CORE := Color(1.0, 0.7, 0.3)
const FIRE_GLOW := Color(1.0, 0.4, 0.08)
const SPARK_CORE := Color(1.0, 0.97, 0.75)

var _glow: Color = Color.WHITE

## A hot core with a halo, a motion streak (parented, so it never lags at
## 40 m/s), a trail of embers or sparks and a small travelling light.
func _build_visuals() -> void:
	var fire := damage_type == Constants.DamageType.FIRE
	var lightning := damage_type == Constants.DamageType.LIGHTNING
	var base: Color = Constants.DAMAGE_TYPE_COLOR.get(damage_type, Color.WHITE)
	_glow = FIRE_GLOW if fire else base.lightened(0.2)
	var core_color := FIRE_CORE if fire else (SPARK_CORE if lightning else base.lightened(0.5))
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.albedo_color = core_color
	mesh.material_override = core
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (0.9 if lightning else 1.1)
	halo.mesh = quad
	var halo_mat := SpellFx.glow_material(Color(_glow, 0.85), true, BaseMaterial3D.BILLBOARD_ENABLED)
	halo_mat.vertex_color_use_as_albedo = false
	halo.material_override = halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position.z = -0.6
	add_child(halo)

	var length := 2.2 if lightning else 1.6
	var streak := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.01
	cone.bottom_radius = 0.13
	cone.height = length
	cone.radial_segments = 10
	cone.rings = 1
	streak.mesh = cone
	var streak_mat := ShaderMaterial.new()
	streak_mat.shader = STREAK_SHADER
	streak_mat.set_shader_parameter("color", _glow)
	streak_mat.set_shader_parameter("length", length)
	streak.material_override = streak_mat
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streak.rotation.x = PI * 0.5  # narrow tail (+Y) trails behind (+Z)
	streak.position.z = -0.6 + length * 0.5
	add_child(streak)

	var trail := SpellFx.emitter(self, 36, 0.45 if fire else 0.2)
	trail.local_coords = false
	trail.position.z = -0.4
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.08
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 0.2 if fire else 1.5
	trail.initial_velocity_max = 0.8 if fire else 4.0
	trail.gravity = Vector3(0, 1.2, 0) if fire else Vector3.ZERO
	trail.scale_amount_min = 0.05
	trail.scale_amount_max = 0.14 if fire else 0.07
	trail.scale_amount_curve = SpellFx.curve(1.0, 0.2)
	trail.color_ramp = SpellFx.ramp(Color(core_color, 1.0), Color(_glow, 0.9), 0.2)
	trail.mesh = SpellFx.glow_quad()
	trail.emitting = true

	var light := OmniLight3D.new()
	light.light_color = _glow
	light.light_energy = 1.4
	light.omni_range = 3.5
	light.position.z = -0.6
	add_child(light)

func _impact(at: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene:
		SpellFx.burst(scene, at, _glow, 14, Vector2(2.0, 5.0), 0.35, Vector2(0.04, 0.1), 90.0, -6.0)
		SpellFx.flash(scene, at, Color(_glow, 0.8), 1.2, 0.15)
