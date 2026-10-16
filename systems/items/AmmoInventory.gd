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
## Carry capacity per type: this multiple of the starting ammo, raised +25%
## of it per tier bought at the Hub's Ammo Store, each type on its own track.
const BASE_CAPACITY_SHARE := 2.0
const CAPACITY_STEP := 0.25
const MAX_CAPACITY_TIER := 5
## A type's first tier costs this much Gold per Gold-per-round of that ammo
## (Constants.AMMO_ROUND_COST); each tier after costs double.
const UPGRADE_BASE_COST := 250

var _capacity_tiers: Dictionary = {}  # AmmoType -> tiers bought

var _reserves: Dictionary = {}   # AmmoType -> int

func _ready() -> void:
	reset()

func reset() -> void:
	_reserves = STARTING_AMMO.duplicate()
	_capacity_tiers = {}

func get_capacity(ammo_type: Constants.AmmoType) -> int:
	if ammo_type == Constants.AmmoType.ARROW:
		return INFINITE_RESERVE
	var base: float = STARTING_AMMO.get(ammo_type, 30) * BASE_CAPACITY_SHARE
	return roundi(base * (1.0 + CAPACITY_STEP * get_capacity_tier(ammo_type)))

func get_capacity_tier(ammo_type: Constants.AmmoType) -> int:
	return int(_capacity_tiers.get(ammo_type, 0))

## Gold for the next tier, or -1 at the top.
func get_upgrade_cost(ammo_type: Constants.AmmoType) -> int:
	var tier := get_capacity_tier(ammo_type)
	if tier >= MAX_CAPACITY_TIER:
		return -1
	return UPGRADE_BASE_COST * int(Constants.AMMO_ROUND_COST.get(ammo_type, 1)) * int(pow(2, tier))

## Spends the Gold for one more tier. False when maxed or short on Gold.
func buy_capacity_tier(ammo_type: Constants.AmmoType) -> bool:
	var cost := get_upgrade_cost(ammo_type)
	if cost < 0 or GameState.gold < cost:
		return false
	GameState.gold -= cost
	_capacity_tiers[ammo_type] = get_capacity_tier(ammo_type) + 1
	EventBus.ammo_changed.emit(ammo_type, get_reserve(ammo_type))
	return true

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

## Adds up to the type's capacity; returns how many rounds went in.
func add(ammo_type: Constants.AmmoType, amount: int) -> int:
	if ammo_type == Constants.AmmoType.ARROW:
		return 0
	var current: int = _reserves.get(ammo_type, 0)
	var added := clampi(get_capacity(ammo_type) - current, 0, amount)
	_reserves[ammo_type] = current + added
	EventBus.ammo_changed.emit(ammo_type, _reserves[ammo_type])
	return added

func is_full(ammo_type: Constants.AmmoType) -> bool:
	return get_reserve(ammo_type) >= get_capacity(ammo_type)

func serialize() -> Dictionary:
	return _reserves.duplicate()

func serialize_capacity() -> Dictionary:
	return _capacity_tiers.duplicate()

func deserialize_capacity(data: Dictionary) -> void:
	_capacity_tiers = {}
	for key in data:
		if STARTING_AMMO.has(int(key)):
			_capacity_tiers[int(key)] = clampi(int(data[key]), 0, MAX_CAPACITY_TIER)

## JSON turns the int enum keys into strings, so they're converted back;
## a type missing from an older save keeps its starting amount.
func deserialize(data: Dictionary) -> void:
	reset()
	for key in data:
		var ammo_type := int(key)
		if STARTING_AMMO.has(ammo_type):
			_reserves[ammo_type] = maxi(0, int(data[key]))
