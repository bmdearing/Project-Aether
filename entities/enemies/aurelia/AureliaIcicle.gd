extends Node3D
class_name AureliaIcicle
## One of Aurelia's Ice Spears: a long icicle flying flat at chest height.
## Upgraded, it turns softly toward the player for HOMING_SEC.

const SPEED := 14.0
const MAX_DISTANCE := 46.0
const HIT_RADIUS := 0.8
const HEIGHT := 1.1
const HOMING_DEG_PER_SEC := 38.0
const HOMING_SEC := 2.4
const ICE := Color(0.72, 0.92, 1.0)

var direction := Vector3.FORWARD
var damage := 10.0
var source: Enemy
var homing := false

var _travelled := 0.0
var _age := 0.0
var _player: Player

## Fires one from `origin` (at floor height) along `dir`.
static func fire(parent: Node, origin: Vector3, dir: Vector3, hit: float, from: Enemy, track: bool) -> AureliaIcicle:
	var icicle := AureliaIcicle.new()
	icicle.direction = Vector3(dir.x, 0.0, dir.z).normalized()
	icicle.damage = hit
	icicle.source = from
	icicle.homing = track
	parent.add_child(icicle)
	icicle.global_position = origin + Vector3.UP * HEIGHT + icicle.direction * 1.2
	icicle._face()
	return icicle

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	# The spear: a long faceted cone, point first (-Z).
	var spear := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.13
	cone.height = 1.5
	cone.radial_segments = 6
	cone.rings = 1
	spear.mesh = cone
	spear.rotation.x = -PI / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.95, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.6
	mat.metallic = 0.2
	mat.roughness = 0.1
	spear.material_override = mat
	spear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spear)
	var glow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.9
	glow.mesh = quad
	var gmat := SpellFx.glow_material(Color(0.5, 0.8, 1.0, 0.8), true, BaseMaterial3D.BILLBOARD_ENABLED)
	gmat.vertex_color_use_as_albedo = false
	glow.material_override = gmat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position.z = 0.3
	add_child(glow)
	# A frost trail left hanging in the air behind it.
	var trail := SpellFx.emitter(self, 36, 0.5)
	trail.local_coords = false
	trail.position.z = 0.7
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.5
	trail.scale_amount_min = 0.08
	trail.scale_amount_max = 0.2
	trail.scale_amount_curve = SpellFx.curve(1.0, 0.2)
	trail.color_ramp = SpellFx.ramp(Color(0.9, 0.97, 1.0, 0.9), Color(0.5, 0.8, 1.0, 0.6), 0.2)
	trail.mesh = SpellFx.glow_quad()
	trail.emitting = true

func _physics_process(delta: float) -> void:
	_age += delta
	if homing and _age < HOMING_SEC and is_instance_valid(_player):
		var to := _player.global_position - global_position
		to.y = 0.0
		if to.length() > 0.5:
			var want := to.normalized()
			var angle := direction.signed_angle_to(want, Vector3.UP)
			var step := deg_to_rad(HOMING_DEG_PER_SEC) * delta
			direction = direction.rotated(Vector3.UP, clampf(angle, -step, step))
	var move := SPEED * delta
	global_position += direction * move
	_travelled += move
	_face()
	if is_instance_valid(_player) and _player.health.is_alive():
		var chest := _player.global_position + Vector3.UP * 0.9
		if global_position.distance_to(chest) <= HIT_RADIUS + 0.35:
			AureliaAilments.hit(_player, damage, Constants.DamageType.COLD, source)
			if _player.status_effects:
				_player.status_effects.apply_effect("chill", source, damage)
			_shatter(true)
			return
	if _travelled >= MAX_DISTANCE:
		_shatter(false)

func _face() -> void:
	if direction.length() > 0.01:
		look_at(global_position + direction, Vector3.UP)

func _shatter(hit: bool) -> void:
	var parent := get_parent()
	SpellFx.shards(parent, global_position, ICE, 12 if hit else 6, Vector2(2, 5), Vector2(0.05, 0.13), 0.6, 80.0)
	if hit:
		SpellFx.flash(parent, global_position, Color(0.6, 0.85, 1.0), 1.6, 0.18)
		AureliaSfx.play("spears_hit", global_position, 0.0)
	queue_free()
