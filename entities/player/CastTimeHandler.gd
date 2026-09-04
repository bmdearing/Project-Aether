extends Node
class_name CastTimeHandler
## Patch v3.7 Section 2. Gates CAST_TIME abilities behind an interruptible
## windup before they actually fire; INSTANT and CHANNELED abilities fire
## immediately (channeled cast-speed interaction is explicitly deferred -
## several abilities, e.g. Flame Jets, already run their own bespoke
## channel loop in PlayerAbilityCast.gd, untouched by this). PlayerAbilityCast.
## _try_cast() calls try_cast() after its own mana/cooldown checks pass,
## then connects to cast_completed to actually run the ability's real
## cast logic (_cast()) - this only decides WHEN that happens, never what.

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
	var cast_time: float = _player.stat_sheet.get_effective_cast_time(ability.base_cast_time)
	_cast_timer = cast_time
	EventBus.cast_started.emit(ability, cast_time)

func _fire_immediately(ability: Ability, cast_position: Vector3) -> void:
	cast_completed.emit(ability, cast_position)

## Channeled implementation deferred - wire to cast_completed immediately
## for now (matches INSTANT), per the brief's own explicit scope cut.
func _begin_channel(ability: Ability, cast_position: Vector3) -> void:
	cast_completed.emit(ability, cast_position)
