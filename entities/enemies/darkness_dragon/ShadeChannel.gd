extends Node
class_name ShadeChannel
## Added to each Shade the Darkness Dragon raises at Nightfall
## (DarknessDragon.on_unit_summoned()). It walks the unit to a lit Lightwell
## instead of fighting and smothers it: after SNUFF_SEC beside the well the
## flame goes out, and the Shade moves on to the next lit one. Killing it
## stops it; with no lit well left it fights normally until one is relit.

const SNUFF_RANGE := 2.6
const SNUFF_SEC := 4.0
const RETARGET_SEC := 1.0

var arena: DarkArena
var well: Lightwell
var progress := 0.0
var _unit: Enemy
var _saved_stop := 0.0
var _hunting := false
var _retarget_in := 0.0

func _ready() -> void:
	add_to_group("shade_channel")
	_unit = get_parent() as Enemy
	_saved_stop = _unit.stop_distance
	_unit.health.died.connect(_on_died)

func _physics_process(delta: float) -> void:
	if _unit == null or not _unit.health.is_alive() or not is_instance_valid(arena):
		return
	if not is_instance_valid(well) or not well.lit:
		_retarget_in -= delta
		if _retarget_in <= 0.0:
			_retarget_in = RETARGET_SEC
			_pick_well()
		return
	var offset := well.global_position - _unit.global_position
	offset.y = 0.0
	if offset.length() > SNUFF_RANGE + 0.6:
		return
	progress += delta / SNUFF_SEC
	well.strain = maxf(well.strain, progress)
	if progress >= 1.0:
		well.set_lit(false)
		well = null
		progress = 0.0

func _pick_well() -> void:
	if is_instance_valid(well):
		well.strain = 0.0
	progress = 0.0
	well = arena.well_for_shade(_unit.global_position)
	_set_hunting(well != null)

## Hunting a well: walk to it and don't attack. Otherwise fight as usual.
func _set_hunting(on: bool) -> void:
	_hunting = on
	_unit.move_target = well if on else null
	_unit.stop_distance = SNUFF_RANGE - 0.8 if on else _saved_stop
	for path in ["MeleeAttack", "RangedAttack"]:
		var attack := _unit.get_node_or_null(path)
		if attack:
			attack.set_physics_process(not on)

func _on_died() -> void:
	if is_instance_valid(well):
		well.strain = 0.0
