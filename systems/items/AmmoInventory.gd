extends Node
## Autoload. Ammo reserves per Constants.AmmoType. Since v5.12 every reserve
## is unlimited: magazines and reloads are the only limit, so there are no
## ammo drops and no Ammo Store. The API stays so magazine code reads the
## same for every weapon.
## (No class_name: an autoload's script can't share its own singleton's name.)

const INFINITE_RESERVE := 9999

func reset() -> void:
	pass

func get_capacity(_ammo_type: Constants.AmmoType) -> int:
	return INFINITE_RESERVE

func get_reserve(_ammo_type: Constants.AmmoType) -> int:
	return INFINITE_RESERVE

func consume(_ammo_type: Constants.AmmoType, _amount: int = 1) -> bool:
	return true

func add(_ammo_type: Constants.AmmoType, _amount: int) -> int:
	return 0

func is_full(_ammo_type: Constants.AmmoType) -> bool:
	return true
