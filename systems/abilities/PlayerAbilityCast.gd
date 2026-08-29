extends Node
class_name PlayerAbilityCast
## Casts AbilityLoadoutComponent's equipped abilities on ability_1..4
## input, checking/consuming ManaComponent + cooldown per Ability.
##
## Execution is DELIBERATELY GENERIC for every ability right now: consume
## resource_cost, start cooldown, then deal Ability.predict_damage()
## damage to every Enemy within the ability's own radius of the player (a
## self-centered nova, sized per-ability rather than one shared radius).
## This is a first-pass simplification, not each ability's actual
## described mechanic - Comet is supposed to be a targeted drop, Winter's
## Eye a traveling orb that detonates, Frost Armor a melee-retaliation
## trigger rather than something you cast on demand. Building those
## distinct behaviors is real future work; this exists so the ability
## bar's cooldown/cost readouts and the equip/upgrade menu actually mean
## something end to end rather than being inert UI.
##
## Damage is computed via Ability.predict_damage() - the same method the
## stat card uses to show "Predicted Damage" - so what you see on the
## card is guaranteed to match what casting actually deals, not a
## separately-maintained copy of the same formula.

const RANGE_EFFECT_SCENE := preload("res://entities/effects/ability_range_effect/AbilityRangeEffect.tscn")

var _cooldowns: Dictionary = {}  # Ability -> float seconds remaining
var _player: Player

func _ready() -> void:
	_player = get_parent()

func _physics_process(delta: float) -> void:
	for ability in _cooldowns.keys():
		_cooldowns[ability] = max(0.0, _cooldowns[ability] - delta)
	for i in range(AbilityLoadoutComponent.SLOT_COUNT):
		if Input.is_action_just_pressed("ability_%d" % (i + 1)):
			_try_cast(i)

func get_cooldown_remaining(ability: Ability) -> float:
	return _cooldowns.get(ability, 0.0) if ability else 0.0

func _try_cast(slot_index: int) -> void:
	var ability: Ability = _player.ability_loadout.get_equipped(slot_index)
	if ability == null:
		return
	if get_cooldown_remaining(ability) > 0.0:
		EventBus.ability_cast_failed.emit(_player, ability, "On cooldown")
		return
	if _player.mana.current_mana < ability.resource_cost:
		EventBus.ability_cast_failed.emit(_player, ability, "Not enough Mana")
		return
	_player.mana.spend(ability.resource_cost)
	_cooldowns[ability] = ability.get_effective_cooldown()
	_cast(ability)

func _cast(ability: Ability) -> void:
	var damage: float = ability.predict_damage(_player.stat_sheet)

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if _player.global_position.distance_to(enemy.global_position) > ability.radius:
			continue
		enemy.take_damage(damage, ability.damage_type)
		if enemy.stance:
			enemy.stance.apply_attack_stance_damage(damage, ability.damage_type)
		EventBus.damage_dealt.emit(_player, enemy, damage, ability.damage_type, false)

	_play_range_effect(ability)
	EventBus.ability_cast.emit(_player, ability)

func _play_range_effect(ability: Ability) -> void:
	var effect: AbilityRangeEffect = RANGE_EFFECT_SCENE.instantiate()
	_player.get_tree().current_scene.add_child(effect)
	effect.global_position = _player.global_position
	effect.play(ability.radius, Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE))
