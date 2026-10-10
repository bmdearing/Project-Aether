extends Node
class_name CastTimeHandler
## Decides when an ability fires: CAST_TIME abilities wait out an
## interruptible windup; INSTANT and CHANNELED fire immediately.
## PlayerAbilityCast runs the actual cast on cast_completed.

signal cast_completed(ability: Ability, cast_position: Vector3)
signal cast_interrupted()

var _casting: bool = false
var _current_ability: Ability = null
var _current_cast_position: Vector3 = Vector3.ZERO
var _cast_timer: float = 0.0

var _player: Player

func _ready() -> void:
	_player = get_parent()

func is_casting() -> bool:
	return _casting

func try_cast(ability: Ability, cast_position: Vector3) -> bool:
	if _casting:
		return false
	match ability.cast_type:
		Ability.CastType.INSTANT:
			_fire_immediately(ability, cast_position)
			return true
		Ability.CastType.CAST_TIME:
			_begin_cast(ability, cast_position)
			return true
		Ability.CastType.CHANNELED:
			_begin_channel(ability, cast_position)
			return true
	return false

func interrupt() -> void:
	if _casting:
		# Tell the player (the AbilityBar flashes); Mana and cooldown are already spent.
		if _current_ability:
			EventBus.ability_cast_failed.emit(_player, _current_ability, "Interrupted")
		_casting = false
		_current_ability = null
		_cast_timer = 0.0
		cast_interrupted.emit()
		EventBus.cast_interrupted.emit()

func _process(delta: float) -> void:
	if not _casting or _current_ability == null:
		return
	_cast_timer -= delta
	if _cast_timer <= 0.0:
		_casting = false
		var ability := _current_ability
		var pos := _current_cast_position
		_current_ability = null
		cast_completed.emit(ability, pos)

func _begin_cast(ability: Ability, cast_position: Vector3) -> void:
	_casting = true
	_current_ability = ability
	_current_cast_position = cast_position
	var cast_time: float = ability.get_cast_time(_player.stat_sheet)
	_cast_timer = cast_time
	EventBus.cast_started.emit(ability, cast_time)

func _fire_immediately(ability: Ability, cast_position: Vector3) -> void:
	cast_completed.emit(ability, cast_position)

## Channeling isn't implemented here yet; behaves like INSTANT.
func _begin_channel(ability: Ability, cast_position: Vector3) -> void:
	cast_completed.emit(ability, cast_position)
