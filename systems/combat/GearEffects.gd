extends Node
class_name GearEffects
## Gear modifiers that react to a hit or a kill rather than adding to a
## total: "increased damage vs Chilled / full Life / ... enemies", "while
## moving", "at range", vs Staggered / unaware enemies, after a melee hit;
## Stagger and explosion procs; Life/Ward/Mana gained on hit, kill or ailment.
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
## Seconds after a melee hit that "damage after melee" lasts.
const AFTER_MELEE_SECONDS := 4.0
## Explosive hits' Bleed zone: radius, and how many seconds of its per-second
## damage the Bleed carries.
const EXPLOSION_BLEED_RADIUS := 2.5
const EXPLOSION_BLEED_SECONDS := 2.0
const STUN_SECONDS := 1.0
## Hollow corruption: your hits drain your own Ward by this share of the damage.
const HOLLOW_WARD_DRAIN := 0.1

## Ailment application -> resource it grants.
const ON_AILMENT := {
	"ignite": ["mana_on_ignite", "mana"],
	"electrocute": ["mana_on_electrocute", "mana"],
	"chill": ["ward_on_chill", "ward"],
	"pallid": ["ward_on_pallid", "ward"],
}

var _player: Player
var _in_extra_hit := false
var _last_melee_msec: int = -100000

## The player's gear bonus for `key` (StatKeys canonical), 0 without a player.
static func player_bonus(tree: SceneTree, key: String) -> float:
	var player := tree.get_first_node_in_group("player") as Player if tree else null
	return player.stat_sheet.get_misc_bonus(key) if player and player.stat_sheet else 0.0

## PlayerMeleeAttack calls this on every melee hit (damage after melee).
func note_melee_hit() -> void:
	_last_melee_msec = Time.get_ticks_msec()

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
	if enemy.is_staggered():
		total += _bonus("damage_vs_staggered")
	if enemy.last_hit_was_unaware:
		total += _bonus("damage_vs_unaware")
	if Time.get_ticks_msec() - _last_melee_msec <= AFTER_MELEE_SECONDS * 1000.0:
		total += _bonus("damage_after_melee")
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
	if _bonus("hollow_damage_ward_drain") > 0.0:
		_player.ward.drain(amount * HOLLOW_WARD_DRAIN)
	if _bonus("stagger_chance") > 0.0 and randf() < _bonus("stagger_chance") / 100.0:
		enemy.interrupt_attack()
	if damage_type == Constants.DamageType.EXPLOSIVE:
		_explosion_effects(enemy, amount)
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

## Explosive hits: a chance to Stun, and a Bleed on everything near the blast.
func _explosion_effects(enemy: Enemy, amount: float) -> void:
	if _bonus("explosion_stun_chance") > 0.0 and randf() < _bonus("explosion_stun_chance") / 100.0 and enemy.status_effects:
		enemy.interrupt_attack()
		enemy.status_effects.apply_timed_effect("stun", STUN_SECONDS)
	var bleed := _bonus("explosion_bleed")
	if bleed <= 0.0:
		return
	for node in get_tree().get_nodes_in_group("enemy"):
		var other := node as Enemy
		if other and other.status_effects and other.health.is_alive() and other.global_position.distance_to(enemy.global_position) <= EXPLOSION_BLEED_RADIUS:
			other.status_effects.apply_effect("bleed", _player, amount * bleed / 100.0 * EXPLOSION_BLEED_SECONDS)
