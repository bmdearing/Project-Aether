extends Node
## Autoload. Persistent ammo reserves per Constants.AmmoType - the pool
## magazines reload from. ARROW is infinite: never stored, never consumed.
## (No class_name: an autoload's script can't share its own singleton's name.)

## Starting ammo per type - enough to feel comfortable but not infinite.
const STARTING_AMMO := {
	Constants.AmmoType.PISTOL: 60,
	Constants.AmmoType.REVOLVER: 24,
	Constants.AmmoType.SHOTGUN: 24,
	Constants.AmmoType.RIFLE: 30,
	Constants.AmmoType.AUTOMATIC: 90,
	Constants.AmmoType.CROSSBOW_BOLT: 20,
}
const INFINITE_RESERVE := 9999

var _reserves: Dictionary = {}   # AmmoType -> int

func _ready() -> void:
	reset()

func reset() -> void:
	_reserves = STARTING_AMMO.duplicate()

func get_reserve(ammo_type: Constants.AmmoType) -> int:
	if ammo_type == Constants.AmmoType.ARROW:
		return INFINITE_RESERVE
	return _reserves.get(ammo_type, 0)

func consume(ammo_type: Constants.AmmoType, amount: int = 1) -> bool:
	if ammo_type == Constants.AmmoType.ARROW:
		return true
	var current: int = _reserves.get(ammo_type, 0)
	if current < amount:
		return false
	_reserves[ammo_type] = current - amount
	EventBus.ammo_changed.emit(ammo_type, _reserves[ammo_type])
	return true

func add(ammo_type: Constants.AmmoType, amount: int) -> void:
	if ammo_type == Constants.AmmoType.ARROW:
		return
	_reserves[ammo_type] = _reserves.get(ammo_type, 0) + amount
	EventBus.ammo_changed.emit(ammo_type, _reserves[ammo_type])

func serialize() -> Dictionary:
	return _reserves.duplicate()

## JSON turns the int enum keys into strings, so they're converted back;
## a type missing from an older save keeps its starting amount.
func deserialize(data: Dictionary) -> void:
	reset()
	for key in data:
		var ammo_type := int(key)
		if STARTING_AMMO.has(ammo_type):
			_reserves[ammo_type] = maxi(0, int(data[key]))
