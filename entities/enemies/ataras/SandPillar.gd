extends StaticBody3D
class_name SandPillar
## Ataras's Sand Pillar: marked under the player, it bursts up out of the
## ground DELAY seconds later and stays standing as solid cover. Standing
## behind one (from the arena's centre) shelters you from his Fiery Sun;
## it also stops his Mirage stones. The Sun's blast brings them all down.

const BossFx := preload("res://entities/effects/boss_fx/BossFx.gd")
const DELAY := 3.0
const RADIUS := 1.3
const HEIGHT := 6.0
const HIT_RADIUS := 1.9
const RISE_SEC := 0.18
const KNOCK_UP_HEIGHT := 1.4
const SAND := Color(0.86, 0.68, 0.42)
const STONE := Color(0.72, 0.58, 0.38)

var damage := 10.0
var source: Enemy
var standing := false

var _body: Node3D
var _shape: CollisionShape3D

## Marks `spot` (floor height) now; the pillar erupts there after DELAY.
static func raise(parent: Node, spot: Vector3, hit: float, from: Enemy) -> SandPillar:
	var pillar := SandPillar.new()
	pillar.damage = hit
	pillar.source = from
	parent.add_child(pillar)
	pillar.global_position = spot
	return pillar

func _ready() -> void:
	add_to_group("ataras_pillar")
	collision_layer = 1
	collision_mask = 0
	_build()
	_shape.disabled = true
	_body.visible = false
	BossTelegraph.circle(get_parent(), global_position, HIT_RADIUS, DELAY, Color(1.0, 0.6, 0.25))
	var dust := SpellFx.emitter(self, 40, 0.9)
	dust.position.y = 0.1
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = HIT_RADIUS * 0.8
	dust.direction = Vector3.UP
	dust.spread = 20.0
	dust.initial_velocity_min = 0.4
	dust.initial_velocity_max = 1.6
	dust.scale_amount_min = 0.1
	dust.scale_amount_max = 0.25
	dust.color_ramp = SpellFx.ramp(Color(SAND, 0.0), Color(SAND, 0.7), 0.3)
	dust.mesh = SpellFx.glow_quad(false)
	dust.emitting = true
	SpellFx.free_after(dust, DELAY + 0.2)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_sand), global_position, -6.0, 0.7)
	await get_tree().create_timer(DELAY, false).timeout
	if is_inside_tree():
		_erupt()

func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STONE
	mat.roughness = 1.0
	var column := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = RADIUS * 0.8
	cylinder.bottom_radius = RADIUS
	cylinder.height = HEIGHT
	cylinder.radial_segments = 10
	column.mesh = cylinder
	column.material_override = mat
	column.position.y = HEIGHT * 0.5
	_body.add_child(column)
	# Two rough bands of darker stone.
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = STONE.darkened(0.25)
	band_mat.roughness = 1.0
	for y in [HEIGHT * 0.3, HEIGHT * 0.78]:
		var band := MeshInstance3D.new()
		var ring := CylinderMesh.new()
		ring.top_radius = RADIUS * 1.08
		ring.bottom_radius = RADIUS * 1.12
		ring.height = 0.35
		ring.radial_segments = 10
		band.mesh = ring
		band.material_override = band_mat
		band.position.y = y
		_body.add_child(band)
	_shape = CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	_shape.shape = shape
	_shape.position.y = HEIGHT * 0.5
	add_child(_shape)

func _erupt() -> void:
	_push_out_bodies()
	standing = true
	_shape.disabled = false
	_body.visible = true
	_body.position.y = -HEIGHT
	var rise := create_tween()
	rise.tween_property(_body, "position:y", 0.0, RISE_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var parent := get_parent()
	SpellFx.burst(parent, global_position + Vector3.UP * 0.5, SAND, 40, Vector2(4, 9), 0.7, Vector2(0.1, 0.25), 70.0, -9.0)
	SmokePuff.spawn(parent, global_position, 1.4, Color(0.8, 0.66, 0.44))
	SpellFx.shockwave(parent, global_position + Vector3.UP * 0.05, HIT_RADIUS + 1.0, SAND, 0.3)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_heavy_impact), global_position, 2.0, 1.1)

## Anything standing where the pillar comes up is thrown clear; the player
## also takes the hit.
func _push_out_bodies() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if is_instance_valid(player) and player.health.is_alive() and _flat_distance(player.global_position) <= HIT_RADIUS:
		_place_outside(player)
		player.take_damage(damage, Constants.DamageType.KINETIC, source, Player.HitKind.SPELL)
		player.knock_up(KNOCK_UP_HEIGHT)
	if is_instance_valid(source) and _flat_distance(source.global_position) <= RADIUS + 0.8:
		_place_outside(source)

func _place_outside(body: Node3D) -> void:
	var away := body.global_position - global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD
	body.global_position = Vector3(global_position.x, body.global_position.y, global_position.z) + away * (RADIUS + 0.9)

func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()

## True when this pillar stands between `from` and `point` (on the floor plane).
func shelters(from: Vector3, point: Vector3) -> bool:
	if not standing:
		return false
	var to_point := Vector2(point.x - from.x, point.z - from.z)
	var to_pillar := Vector2(global_position.x - from.x, global_position.z - from.z)
	var reach := to_point.length()
	if reach < 0.01:
		return false
	var along := to_pillar.dot(to_point / reach)
	if along <= 0.0 or along >= reach:
		return false
	return absf(to_point.normalized().cross(to_pillar)) <= RADIUS

## Brought down by the Sun's blast: sinks into a cloud of sand.
func crumble() -> void:
	standing = false
	if _shape:
		_shape.set_deferred("disabled", true)
	SpellFx.burst(get_parent(), global_position + Vector3.UP * HEIGHT * 0.5, SAND, 30, Vector2(2, 5), 0.9, Vector2(0.12, 0.3), 180.0, -6.0)
	SmokePuff.spawn(get_parent(), global_position, 1.6, Color(0.8, 0.66, 0.44))
	var sink := create_tween()
	sink.tween_property(_body, "position:y", -HEIGHT, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	sink.tween_callback(queue_free)
