extends Node
class_name UniqueEffects
## The player's active Unique/Mythic mechanics: every `unique_*` modifier on
## equipped gear (UniqueCatalog), summed by key. Player refreshes it when
## equipment changes and asks it about damage taken and Ward/Life; weapon and
## spell rolls ask damage_multiplier() through StatSheet; on-hit effects run
## off EventBus.damage_dealt.

const ESOTERIC_TO_MANA := "unique_esoteric_to_mana"
const ESOTERIC_OVERFLOW := "unique_esoteric_overflow"
const ESOTERIC_DAMAGE := "unique_esoteric_damage"
const MORE_WARD := "unique_more_ward"
const DEBT := "unique_debt"
const REDUCED_DAMAGE_MOVING := "unique_reduced_damage_moving"
const CRIT_APPLIES_PALLID := "unique_crit_applies_pallid"
const CRIT_VS_PALLID := "unique_crit_vs_pallid"
const NO_WARD_RECOVERY := "unique_no_ward_recovery"
const ESOTERIC_ECHO := "unique_esoteric_echo"
const ECHO_UNRAVELING := "unique_echo_unraveling"
const REDUCED_MAX_LIFE := "unique_reduced_max_life"
const NO_INFUSION := "unique_no_infusion"
const LIFE_ON_KILL := "unique_life_on_kill"
const NO_LIFE_REGEN := "unique_no_life_regen"
const MORE_DAMAGE_MOVING := "unique_more_damage_moving"
const NO_WARD_RECOVERY_MOVING := "unique_no_ward_recovery_moving"
const MORE_FIRE_DAMAGE := "unique_more_fire_damage"
const WARD_ON_BLOCK := "unique_ward_on_block"
const SPELL_DAMAGE_TAKEN := "unique_spell_damage_taken"
const PATIENT_SHOT := "unique_patient_shot"
const DAMAGE_TAKEN := "unique_damage_taken"

const DEBT_MAX_STACKS := 20
const PATIENT_SHOT_SECONDS := 2.0
## Horizontal speed above which the player counts as moving.
const MOVING_SPEED := 0.5

var effects: Dictionary = {}
var debt_stacks: int = 0
var debt_damage: float = 0.0

var _player: Player
var _last_hit_msec: int = -100000
var _in_extra_hit: bool = false

func _ready() -> void:
	_player = get_parent() as Player
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.hit_blocked.connect(_on_hit_blocked)

## Re-reads every equipped item's unique modifiers.
func refresh(items: Array[Item]) -> void:
	effects = {}
	for item in items:
		for affix in item.get_effective_affixes():
			if affix.stat_key.begins_with("unique_"):
				effects[affix.stat_key] = effects.get(affix.stat_key, 0.0) + affix.value
	if not has(DEBT):
		debt_stacks = 0
		debt_damage = 0.0

func has(key: String) -> bool:
	return effects.has(key)

func value(key: String) -> float:
	return effects.get(key, 0.0)

func is_moving() -> bool:
	return _player != null and Vector2(_player.velocity.x, _player.velocity.z).length() > MOVING_SPEED

func _physics_process(_delta: float) -> void:
	if _player and _player.ward:
		_player.ward.recovery_blocked = has(NO_WARD_RECOVERY) or (has(NO_WARD_RECOVERY_MOVING) and is_moving())

## ---- Outgoing damage ---------------------------------------------------

## "More" multiplier on a weapon or spell hit of damage_type.
func damage_multiplier(damage_type: int) -> float:
	var mult := 1.0
	if has(ESOTERIC_DAMAGE) and Constants.DAMAGE_TYPE_CATEGORY.get(damage_type) == Constants.DamageCategory.ESOTERIC:
		mult *= 1.0 + value(ESOTERIC_DAMAGE) / 100.0
	if has(MORE_FIRE_DAMAGE) and damage_type == Constants.DamageType.FIRE:
		mult *= 1.0 + value(MORE_FIRE_DAMAGE) / 100.0
	if is_moving():
		mult *= 1.0 - value(REDUCED_DAMAGE_MOVING) / 100.0
		mult *= 1.0 + value(MORE_DAMAGE_MOVING) / 100.0
	if has(PATIENT_SHOT) and Time.get_ticks_msec() - _last_hit_msec >= PATIENT_SHOT_SECONDS * 1000.0:
		mult *= 1.0 + value(PATIENT_SHOT) / 100.0
	return maxf(mult, 0.0)

func _on_damage_dealt(source: Node, target: Node, amount: float, damage_type: int, _more: bool, is_critical: bool) -> void:
	if _in_extra_hit or source != _player or not target is Enemy or effects.is_empty():
		_note_hit(source, target)
		return
	_note_hit(source, target)
	var enemy := target as Enemy
	_in_extra_hit = true
	if is_critical and has(CRIT_VS_PALLID) and enemy.status_effects and enemy.status_effects.has_effect("pallid"):
		enemy.take_damage(amount * value(CRIT_VS_PALLID) / 100.0, damage_type)
	if is_critical and has(CRIT_APPLIES_PALLID) and enemy.status_effects:
		enemy.status_effects.apply_effect("pallid", _player, amount)
	if has(ESOTERIC_ECHO) and (damage_type == Constants.DamageType.AETHERIC or damage_type == Constants.DamageType.ENTROPIC):
		var echo_type := Constants.DamageType.ENTROPIC if damage_type == Constants.DamageType.AETHERIC else Constants.DamageType.AETHERIC
		var echo := amount * value(ESOTERIC_ECHO) / 100.0
		enemy.take_damage(echo, echo_type, true)
		if has(ECHO_UNRAVELING) and enemy.status_effects:
			enemy.status_effects.apply_effect("enhanced:unraveling", _player, echo)
	if debt_stacks > 0 and not is_moving() and is_instance_valid(enemy) and enemy.health.is_alive():
		enemy.take_damage(debt_damage * value(DEBT) / 100.0 * debt_stacks, Constants.DamageType.KINETIC, false, false, false, true)
		debt_stacks = 0
		debt_damage = 0.0
	_in_extra_hit = false

func _note_hit(source: Node, target: Node) -> void:
	if source == _player and target is Enemy:
		_last_hit_msec = Time.get_ticks_msec()

func _on_enemy_died(_enemy: Node) -> void:
	if has(LIFE_ON_KILL) and _player and _player.health.is_alive():
		_player.health.heal(_player.health.max_health * value(LIFE_ON_KILL) / 100.0)

func _on_hit_blocked(defender: Node) -> void:
	if defender == _player and has(WARD_ON_BLOCK):
		_player.ward.restore(_player.ward.max_ward * value(WARD_ON_BLOCK) / 100.0)

## ---- Incoming damage ---------------------------------------------------

## Multiplier on an incoming hit before mitigation.
func damage_taken_multiplier(is_spell: bool) -> float:
	var mult := 1.0 + value(DAMAGE_TAKEN) / 100.0
	if is_spell:
		mult *= 1.0 + value(SPELL_DAMAGE_TAKEN) / 100.0
	return mult

## A hit that got past mitigation: Grevane's Debt records it.
func record_damage_taken(amount: float) -> void:
	if has(DEBT) and amount > 0.0:
		debt_stacks = mini(debt_stacks + 1, DEBT_MAX_STACKS)
		debt_damage += amount

## The Hollowed King's Mantle: Esoteric damage comes out of Mana first.
## Returns what's left for Ward/Life, which is 0 when the Mantle took it.
func absorb_esoteric(amount: float, damage_type: int) -> float:
	if not has(ESOTERIC_TO_MANA) or Constants.DAMAGE_TYPE_CATEGORY.get(damage_type) != Constants.DamageCategory.ESOTERIC:
		return amount
	var mana := _player.mana
	var drained: float = minf(amount, mana.current_mana)
	mana.spend(drained)
	var overflow := amount - drained
	if overflow > 0.0:
		_player.health.apply_damage(overflow * value(ESOTERIC_OVERFLOW) / 100.0)
	return 0.0

func max_life_multiplier() -> float:
	return maxf(1.0 - value(REDUCED_MAX_LIFE) / 100.0, 0.05)

func ward_multiplier() -> float:
	return 1.0 + value(MORE_WARD) / 100.0
