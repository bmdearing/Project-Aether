extends Node3D
class_name FlameWallField
## Flame Wall: Ignites each enemy once per pass through it
## (_ignited_this_pass), and separately hits everything inside every tick.
## Oriented perpendicular to the caster; width comes from the radius.

const DURATION := 6.0
const TICK_INTERVAL := 0.5
const SCORCH_CHANCE_PER_TICK := 0.35
const TICK_DAMAGE_PERCENT := 0.25
const WALL_HEIGHT := 2.2
const WALL_THICKNESS := 0.6

var _half_width: float = 2.5
var _ability: Ability
var _stat_sheet: StatSheet
var _source: Node
var _elapsed: float = 0.0
var _ticker: float = 0.0
var _inside: Array[Enemy] = []

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var area: Area3D = $Area3D

var _duration: float = DURATION

func play(radius: float, color: Color, ability: Ability, stat_sheet: StatSheet, source: Node, caster_position: Vector3) -> void:
	_duration = DURATION * ability.get_duration_multiplier(stat_sheet)
	_half_width = max(radius, 1.5)
	_ability = ability
	_stat_sheet = stat_sheet
	_source = source

	# look_at() points local -Z at the target, which puts local X (the
	# box's WIDTH axis) perpendicular to the caster direction - exactly
	# the "wall standing between caster and target" orientation wanted.
	var flat_caster_pos := Vector3(caster_position.x, global_position.y, caster_position.z)
	if global_position.distance_to(flat_caster_pos) > 0.01:
		look_at(flat_caster_pos, Vector3.UP)

	var box := mesh.mesh as BoxMesh
	box.size = Vector3(_half_width * 2.0, WALL_HEIGHT, WALL_THICKNESS)
	mesh.position = Vector3(0, WALL_HEIGHT * 0.5, 0)
	var shape := (area.get_node("CollisionShape3D").shape as BoxShape3D)
	shape.size = box.size
	area.get_node("CollisionShape3D").position = mesh.position

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c := color
	c.a = 0.55
	mat.albedo_color = c
	mesh.material_override = mat

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	area.monitoring = true

func _on_body_entered(body: Node3D) -> void:
	var enemy := body as Enemy
	if enemy == null or _inside.has(enemy):
		return
	_inside.append(enemy)
	# Ignite's burn is a share of the hit that caused it, so roll one.
	var hit := _ability.roll_damage(_stat_sheet)
	_ability.apply_statuses(enemy, _source, hit["final_damage"])

func _on_body_exited(body: Node3D) -> void:
	var enemy := body as Enemy
	if enemy:
		_inside.erase(enemy)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		queue_free()
		return
	_ticker -= delta
	if _ticker > 0.0:
		return
	_ticker += TICK_INTERVAL
	if _ability == null or _stat_sheet == null:
		return
	for enemy in _inside.duplicate():
		if not is_instance_valid(enemy):
			_inside.erase(enemy)
			continue
		var hit := _ability.roll_damage(_stat_sheet)
		var damage: float = hit["final_damage"] * TICK_DAMAGE_PERCENT
		enemy.take_damage(damage, _ability.damage_type)
		EventBus.damage_dealt.emit(_source, enemy, damage, _ability.damage_type, false, hit["is_critical"])
		# Standing in the fire builds Scorch.
		enemy.status_effects.try_apply("scorch", _source, 0.0, SCORCH_CHANCE_PER_TICK)
