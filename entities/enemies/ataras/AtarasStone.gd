extends Node3D
class_name AtarasStone
## A shard of stone a Mirage clone hurls at the player. Flies straight at
## chest height; Sand Pillars stop it.

const BossFx := preload("res://entities/effects/boss_fx/BossFx.gd")
const SPEED := 24.0
const MAX_DISTANCE := 50.0
const HIT_RADIUS := 0.7
const HEIGHT := 1.2
const STONE := Color(0.72, 0.58, 0.38)

var direction := Vector3.FORWARD
var damage := 10.0
var source: Enemy

var _travelled := 0.0
var _player: Player
var _spin := Vector3(7.0, 4.0, 0.0)
var _rock: MeshInstance3D

## Fires one from `origin` (floor height) along `dir`.
static func fire(parent: Node, origin: Vector3, dir: Vector3, hit: float, from: Enemy) -> AtarasStone:
	var stone := AtarasStone.new()
	stone.direction = Vector3(dir.x, 0.0, dir.z).normalized()
	stone.damage = hit
	stone.source = from
	parent.add_child(stone)
	stone.global_position = origin + Vector3.UP * HEIGHT + stone.direction * 1.0
	return stone

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	_rock = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.32
	mesh.height = 0.5
	mesh.radial_segments = 6
	mesh.rings = 3
	_rock.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STONE
	mat.roughness = 1.0
	_rock.material_override = mat
	_rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rock)
	var trail := SpellFx.emitter(self, 30, 0.45)
	trail.local_coords = false
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.4
	trail.scale_amount_min = 0.1
	trail.scale_amount_max = 0.22
	trail.scale_amount_curve = SpellFx.curve(1.0, 0.2)
	trail.color_ramp = SpellFx.ramp(Color(0.9, 0.78, 0.55, 0.7), Color(0.8, 0.65, 0.42, 0.4), 0.2)
	trail.mesh = SpellFx.glow_quad(false)
	trail.emitting = true

func _physics_process(delta: float) -> void:
	var move := SPEED * delta
	global_position += direction * move
	_travelled += move
	_rock.rotation += _spin * delta
	for pillar in get_tree().get_nodes_in_group("ataras_pillar"):
		var p := pillar as SandPillar
		if p and p.standing and Vector2(global_position.x - p.global_position.x, global_position.z - p.global_position.z).length() <= SandPillar.RADIUS + 0.2:
			_shatter(false)
			return
	if is_instance_valid(_player) and _player.health.is_alive():
		var chest := _player.global_position + Vector3.UP * 0.9
		if global_position.distance_to(chest) <= HIT_RADIUS + 0.35:
			_player.take_damage(damage, Constants.DamageType.KINETIC, source, Player.HitKind.ATTACK)
			_shatter(true)
			return
	if _travelled >= MAX_DISTANCE:
		_shatter(false)

func _shatter(hit: bool) -> void:
	var parent := get_parent()
	SpellFx.shards(parent, global_position, STONE, 14 if hit else 8, Vector2(2, 5), Vector2(0.06, 0.15), 0.6, 120.0, false)
	SmokePuff.spawn(parent, global_position, 0.5, Color(0.8, 0.66, 0.44))
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_heavy_impact), global_position, -4.0 if hit else -8.0, 1.4)
	queue_free()
