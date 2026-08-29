extends Node
class_name PlayerAbilityCast
## Casts AbilityLoadoutComponent's equipped abilities on ability_1..4
## input, checking/consuming ManaComponent + cooldown per Ability.
##
## Execution is deliberately generic for every ability right now: consume
## resource_cost, start cooldown, deal damage to every Enemy within the
## ability's own radius (a self-centered nova). Not each ability's actual
## described mechanic (Comet/Winter's Eye/Frost Armor are distinct real
## mechanics) - a first pass so the ability bar's readouts aren't inert UI.

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
	# Section 12: Instinct -> "+1% Attack/Cast speed per point" - divides
	# the authored cooldown, same treatment PlayerMeleeAttack/
	# PlayerRangedAttack give their own timings.
	_cooldowns[ability] = ability.get_effective_cooldown() / _player.get_action_speed_multiplier()
	_cast(ability)

## Each enemy rolls its own crit independently (roll_damage() per-target,
## not once and reused) - a shared roll would make them all crit together.
func _cast(ability: Ability) -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if _player.global_position.distance_to(enemy.global_position) > ability.radius:
			continue
		var hit := ability.roll_damage(_player.stat_sheet)
		var damage: float = hit["final_damage"]
		var is_critical: bool = hit["is_critical"]
		enemy.take_damage(damage, ability.damage_type)
		if enemy.stance:
			enemy.stance.apply_attack_stance_damage(damage, ability.damage_type)
		EventBus.damage_dealt.emit(_player, enemy, damage, ability.damage_type, false, is_critical)

	_play_range_effect(ability)
	EventBus.ability_cast.emit(_player, ability)

func _play_range_effect(ability: Ability) -> void:
	var effect: AbilityRangeEffect = RANGE_EFFECT_SCENE.instantiate()
	_player.get_tree().current_scene.add_child(effect)
	effect.global_position = _player.global_position
	effect.play(ability.radius, Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE))
