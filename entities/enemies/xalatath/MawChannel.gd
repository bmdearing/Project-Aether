extends Node
class_name MawChannel
## Added to a Mindbender the Herald of the Maw summons (Xalatath.
## on_unit_summoned()). It walks the unit to an Anchor pylon instead of
## fighting, then channels a beam at it; after CHANNEL_SEC the pylon
## shatters. Killing the Mindbender stops it. If no pylon is left standing,
## the unit goes back to fighting normally.

const CHANNEL_RANGE := 4.0
const CHANNEL_SEC := 8.0
const BEAM_COLOR := Color(0.6, 0.25, 0.95)

var arena: MawArena
var pylon: MawPylon
var progress := 0.0
var _unit: Enemy
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _saved_stop := 0.0
var _saved_retreat := 0.0

func _ready() -> void:
	add_to_group("maw_channel")
	_unit = get_parent() as Enemy
	_saved_stop = _unit.stop_distance
	_saved_retreat = _unit.retreat_distance
	_unit.stop_distance = CHANNEL_RANGE - 1.0
	_unit.retreat_distance = 0.0
	_set_attacks(false)
	_unit.health.died.connect(_release)
	_retarget()

func _physics_process(delta: float) -> void:
	if _unit == null or not _unit.health.is_alive():
		return
	if not is_instance_valid(pylon) or not pylon.alive:
		_clear_strain()
		_retarget()
		return
	var offset := pylon.global_position - _unit.global_position
	offset.y = 0.0
	if offset.length() > CHANNEL_RANGE + MawPylon.RADIUS:
		_show_beam(false)
		return
	progress += delta / CHANNEL_SEC
	pylon.strain = maxf(pylon.strain, progress)
	_show_beam(true)
	if progress >= 1.0:
		progress = 0.0
		pylon.shatter()

func is_channeling() -> bool:
	return _beam != null and _beam.visible

## Picks the next standing pylon, or lets the unit fight if none is left.
func _retarget() -> void:
	pylon = arena.pylon_for_channeler(_unit.global_position) if is_instance_valid(arena) else null
	progress = 0.0
	if pylon == null:
		_release()
		queue_free()
		return
	_unit.move_target = pylon

func _release() -> void:
	_clear_strain()
	_show_beam(false)
	if not is_instance_valid(_unit):
		return
	_unit.move_target = null
	_unit.stop_distance = _saved_stop
	_unit.retreat_distance = _saved_retreat
	_set_attacks(true)

## The pylon's strain shows the furthest channel on it; a released channel
## stops counting.
func _clear_strain() -> void:
	if not is_instance_valid(pylon):
		return
	var others := get_tree().get_nodes_in_group("maw_channel").filter(func(c): return c != self and c.pylon == pylon)
	pylon.strain = others.reduce(func(m, c): return maxf(m, c.progress), 0.0)

func _set_attacks(enabled: bool) -> void:
	for path in ["MeleeAttack", "RangedAttack"]:
		var attack := _unit.get_node_or_null(path)
		if attack:
			attack.set_physics_process(enabled)

func _show_beam(visible_now: bool) -> void:
	if not visible_now:
		if _beam:
			_beam.visible = false
		return
	if _beam == null:
		_beam_mat = MawPylon._glow_material(BEAM_COLOR, 2.5)
		_beam = MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.06
		cylinder.bottom_radius = 0.06
		cylinder.height = 1.0
		cylinder.radial_segments = 6
		_beam.mesh = cylinder
		_beam.material_override = _beam_mat
		_beam.top_level = true
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_beam)
	_beam.visible = true
	var from := _unit.get_cast_origin() + Vector3(0, 0.4, 0)
	var to := pylon.global_position + Vector3(0, MawPylon.CRYSTAL_HEIGHT, 0)
	var span := to - from
	var width := 1.0 + progress * 3.0
	# The cylinder's Y axis runs along the beam.
	var axis := span.normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.99 else Vector3.RIGHT).normalized()
	_beam.global_transform = Transform3D(Basis(side * width, axis * span.length(), side.cross(axis) * width), from + span / 2.0)
	_beam_mat.emission_energy_multiplier = 2.0 + progress * 4.0
