extends Node
class_name GearEffects
## Gear modifiers that react to a hit or a kill rather than adding to a
## total: "increased damage vs Chilled / full Life / ... enemies", "while
## moving", "at range", and Life/Ward/Mana gained on hit, kill or ailment.
## Lives on the Player and reads its StatSheet (StatKeys canonical keys).
## Conditional damage is dealt as an extra hit of the same type for that
## share of the hit; damage-over-time ticks don't count as hits.

## Status id each "damage_vs_<status>" key checks for.
const VS_STATUS := {
	"damage_vs_chilled": "chill",
	"damage_vs_ignited": "ignite",
	"damage_vs_shocked": "shock",
	"damage_vs_pallid": "pallid",
	"damage_vs_unraveling": "unraveling",
	"damage_vs_aetherburn": "aetherburn",
}
## Below this share of max Life an enemy counts as low ("below 35% health").
const LOW_LIFE := 0.35
## Further than this from the player counts as "outside melee range".
const RANGED_DISTANCE := 4.5
## Ailment application -> resource it grants.
const ON_AILMENT := {
	"ignite": ["mana_on_ignite", "mana"],
	"electrocute": ["mana_on_electrocute", "mana"],
	"chill": ["ward_on_chill", "ward"],
	"pallid": ["ward_on_pallid", "ward"],
}

var _player: Player
var _in_extra_hit := false

func _ready() -> void:
	_player = get_parent() as Player
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.status_effect_applied.connect(_on_status_applied)

func _bonus(key: String) -> float:
	return _player.stat_sheet.get_misc_bonus(key) if _player and _player.stat_sheet else 0.0

## % increased damage the hit earns against `enemy` (amount already dealt).
func conditional_percent(enemy: Enemy, amount: float) -> float:
	var total := 0.0
	if enemy.status_effects:
		for key in VS_STATUS:
			if _bonus(key) > 0.0 and enemy.status_effects.has_effect(VS_STATUS[key]):
				total += _bonus(key)
	var life := enemy.health.current_health
	var max_life := maxf(enemy.health.max_health, 1.0)
	if life > 0.0 and life / max_life < LOW_LIFE:
		total += _bonus("damage_vs_low_life")
	if life + amount >= max_life * 0.999:
		total += _bonus("damage_vs_full_life")
	if Vector2(_player.velocity.x, _player.velocity.z).length() > UniqueEffects.MOVING_SPEED:
		total += _bonus("damage_while_moving")
	if _player.global_position.distance_to(enemy.global_position) > RANGED_DISTANCE:
		total += _bonus("damage_at_range")
	return total

func _on_damage_dealt(source: Node, target: Node, amount: float, damage_type: int, _more: bool, _is_critical: bool) -> void:
	if _in_extra_hit or source != _player or not target is Enemy or StatusEffectComponent.emitting_dot:
		return
	var enemy := target as Enemy
	if _bonus("life_on_hit") > 0.0:
		_player.health.heal(_bonus("life_on_hit"))
	if _bonus("ward_on_hit") > 0.0:
		_player.ward.restore(_bonus("ward_on_hit"))
	if _bonus("ward_drain_on_hit") > 0.0 and enemy.get_ward() > 0.0:
		_player.ward.restore(enemy.drain_ward(enemy.get_ward_max() * _bonus("ward_drain_on_hit") / 100.0))
	if not enemy.health.is_alive():
		return
	var percent := conditional_percent(enemy, amount)
	if percent > 0.0:
		_in_extra_hit = true
		enemy.take_damage(amount * percent / 100.0, damage_type, false, false, false, true)
		_in_extra_hit = false

func _on_enemy_died(_enemy: Node) -> void:
	if _player == null or not _player.health.is_alive():
		return
	if _bonus("mana_on_kill") > 0.0:
		_player.mana.restore(_bonus("mana_on_kill"))
	var ward := _bonus("ward_on_kill") + _player.ward.max_ward * _bonus("ward_percent_on_kill") / 100.0
	if ward > 0.0:
		_player.ward.restore(ward)

func _on_status_applied(target: Node, effect_id: String, _stacks: int) -> void:
	if not target is Enemy or _player == null:
		return
	var entry: Array = ON_AILMENT.get(effect_id.trim_prefix("enhanced:"), [])
	if entry.is_empty() or _bonus(entry[0]) <= 0.0:
		return
	if entry[1] == "mana":
		_player.mana.restore(_bonus(entry[0]))
	else:
		_player.ward.restore(_bonus(entry[0]))
