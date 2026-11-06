extends Node
class_name PerkEffects
## Runs the Monster Infrequent perks on the player's equipped gear
## (PerkCatalog). Player refreshes it on equipment change. Two copies of a
## perk don't stack: the best roll counts.

const OPENING_STRIKE_SECONDS := 2.0
const NEARBY_RADIUS := 6.0
const SHOCKWAVE_RADIUS := 4.0
const SHOCKWAVE_KNOCKBACK := 9.0
const HEAVY_KNOCKBACK := 6.0
const LANDING_RADIUS := 3.5
const LANDING_MIN_AIR := 0.45
const EMBER_RADIUS := 2.5
const EMBER_INTERVAL := 0.5
const EMBER_MIN_SPEED := 4.0
const BIG_HIT_SHARE := 0.2
const BURST_RADIUS := 4.0
const ERUPT_RADIUS := 3.5
const MARK_SECONDS := 6.0
const SPELL_WINDOW_MSEC := 2500
const CONTROL_AILMENTS := ["chill", "shock", "electrocute", "unraveling", "pallid"]
const ELEMENTS := [Constants.DamageType.FIRE, Constants.DamageType.COLD, Constants.DamageType.LIGHTNING]
## Boss perks (Vestige crafts).
const SUN_COOLDOWN := 8.0
const SUN_RADIUS := 4.0
const WHEEL_HITS := 5
const WHEEL_RADIUS := 5.0
const WHEEL_KNOCKBACK := 8.0
const MAW_COOLDOWN := 4.0
const MAW_RADIUS := 8.0
const MAW_PULL := 10.0
const RIPOSTE_SECONDS := 3.0
const STENCH_RADIUS := 3.0
const STENCH_INTERVAL := 0.5
const LONG_SHOT_DISTANCE := 15.0
const PIN_SECONDS := 1.5
const PIN_COOLDOWN_MSEC := 4000
const FURY_LIFE_SHARE := 0.5
const FURY_SECONDS := 6.0
const FURY_COOLDOWN := 20.0
const FURY_RADIUS := 5.0
const FURY_KNOCKBACK := 8.0
const ROAR_STUN := 2.0
const LAST_ROUND_RADIUS := 3.5
const LANDING_COOLDOWN := 1.0
## "Strongest recent hit": the biggest direct hit, halving every
## RECENT_HIT_HALF_LIFE seconds, but never below the latest hit. Perks that
## used to read Life or Armour scale off it, so they keep pace with monsters.
const RECENT_HIT_HALF_LIFE := 5.0
const STOMP_COOLDOWN := 10.0
const STOMP_RADIUS := 4.0
const STOMP_KNOCKBACK := 8.0
const AILMENT_OF :={Constants.DamageType.FIRE: "ignite", Constants.DamageType.COLD: "chill", Constants.DamageType.LIGHTNING: "shock"}

var perks: Dictionary = {}  # StringName -> best value

var _player: Player
var _in_extra := false
var _last_hit_msec: int = -100000
var _last_element: int = -1
var _casts := 0
var _air_time := 0.0
var _ember_timer := 0.0
var _last_cast_msec: int = -100000
var _last_weapon_msec: int = -100000
var _sun_ready_msec: int = 0
var _wheel_hits := 0
var _maw_ready_msec: int = 0
var _riposte_until_msec: int = 0
var _stench_timer := 0.0
var _stomp_ready_msec: int = 0
var _fury_ready_msec: int = 0
var _was_low_life := false
var _last_round_spent := false
var _landing_ready_msec: int = 0
var _peak_hit := 0.0
var _latest_hit := 0.0
var _peak_hit_msec: int = 0

func _ready() -> void:
	_player = get_parent() as Player
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.hit_blocked.connect(_on_hit_blocked)
	EventBus.ability_cast.connect(_on_ability_cast)
	EventBus.ammo_changed.connect(func(_t, _r): _last_weapon_msec = Time.get_ticks_msec())
	EventBus.melee_attack_executed.connect(func(_s, _d, _t, _m): _last_weapon_msec = Time.get_ticks_msec())

func refresh(items: Array[Item]) -> void:
	perks = {}
	for item in items:
		for id in item.perks:
			var key := StringName(id)
			perks[key] = maxf(perks.get(key, 0.0), float(item.perks[id]))

func has(id: StringName) -> bool:
	return perks.has(id)

func value(id: StringName) -> float:
	return perks.get(id, 0.0)

## ---- Outgoing damage ---------------------------------------------------

## "More" multiplier on a weapon or spell hit of damage_type (StatSheet).
func damage_multiplier(damage_type: int) -> float:
	if perks.is_empty():
		return 1.0
	var mult := 1.0
	if has(&"opening_strike") and Time.get_ticks_msec() - _last_hit_msec >= OPENING_STRIKE_SECONDS * 1000.0:
		mult *= 1.0 + value(&"opening_strike") / 100.0
	if has(&"element_shift") and ELEMENTS.has(damage_type) and _last_element != -1 and _last_element != damage_type:
		mult *= 1.0 + value(&"element_shift") / 100.0
	return mult

## The strongest recent hit (see RECENT_HIT_HALF_LIFE).
func recent_hit() -> float:
	var decay := pow(0.5, (Time.get_ticks_msec() - _peak_hit_msec) / (RECENT_HIT_HALF_LIFE * 1000.0))
	return maxf(_latest_hit, _peak_hit * decay)

func _note_hit(amount: float) -> void:
	_peak_hit = maxf(amount, recent_hit())
	_peak_hit_msec = Time.get_ticks_msec()
	_latest_hit = amount

## Perk damage that shouldn't count as a hit for other perks or the
## strongest recent hit.
func _perk_damage(enemy: Enemy, amount: float, damage_type: int, flag: bool = false) -> void:
	var was := _in_extra
	_in_extra = true
	enemy.take_damage(amount, damage_type, flag)
	_in_extra = was

## Extra multiplier on a melee swing (PlayerMeleeAttack, once per target hit);
## heavy = not a jab.
func melee_multiplier(heavy: bool) -> float:
	var mult := 1.0 + value(&"heavy_knockback") / 100.0 if heavy and has(&"heavy_knockback") else 1.0
	var now := Time.get_ticks_msec()
	if has(&"riposte") and now < _riposte_until_msec:
		mult *= 1.0 + value(&"riposte") / 100.0
		# Spent by this swing: other targets of the same cleave still get it.
		_riposte_until_msec = mini(_riposte_until_msec, now + 200)
	return mult

func on_melee_hit(target: Enemy, heavy: bool) -> void:
	if heavy and has(&"heavy_knockback") and is_instance_valid(target) and target.health.is_alive():
		target.apply_knockback(_away(target) * HEAVY_KNOCKBACK)

## Faerie Dragon's Phase Shift: whether this spell hit is avoided (Player.take_damage).
func avoids_spell_hit() -> bool:
	return has(&"phase_shift") and randf() * 100.0 < value(&"phase_shift")

func _on_damage_dealt(source: Node, target: Node, amount: float, damage_type: int, _more: bool, _crit: bool) -> void:
	if source != _player or not target is Enemy:
		return
	var now := Time.get_ticks_msec()
	_last_hit_msec = now
	if ELEMENTS.has(damage_type):
		_last_element = damage_type
	if not _in_extra and not StatusEffectComponent.emitting_dot and amount > 0.0:
		_note_hit(amount)
	if _in_extra or perks.is_empty():
		return
	var enemy := target as Enemy
	_in_extra = true
	var weapon := _player.get_active_weapon()
	var is_spell := now - _last_cast_msec <= SPELL_WINDOW_MSEC and _last_cast_msec > _last_weapon_msec
	if has(&"adjudicator_mark") and is_instance_valid(enemy):
		var marked_until: int = enemy.get_meta("perk_mark", 0)
		if is_spell and marked_until > now:
			enemy.remove_meta("perk_mark")
			if enemy.health.is_alive():
				enemy.take_damage(amount * value(&"adjudicator_mark") / 100.0, damage_type, true)
		elif not is_spell:
			enemy.set_meta("perk_mark", now + int(MARK_SECONDS * 1000.0))
	if has(&"ricochet") and weapon and weapon.is_throwing() and not is_spell:
		var other := _nearest_other(enemy)
		if other:
			other.take_damage(amount * value(&"ricochet") / 100.0, damage_type)
	if has(&"ignite_spread") and weapon and not weapon.is_ranged and not weapon.is_conduit and not is_spell \
			and is_instance_valid(enemy) and enemy.status_effects and enemy.status_effects.has_effect("ignite"):
		var other := _nearest_other(enemy)
		if other and other.status_effects:
			other.status_effects.apply_effect("ignite", _player, amount * value(&"ignite_spread") / 100.0)
	_new_hit_perks(enemy, amount, damage_type, is_spell, now)
	_boss_hit_perks(enemy, amount, damage_type, is_spell, now)
	if has(&"ignite_erupt") and damage_type == Constants.DamageType.FIRE and is_instance_valid(enemy) \
			and enemy.status_effects and enemy.status_effects.has_effect("ignite"):
		var at := enemy.global_position
		for other in _enemies_near(at, ERUPT_RADIUS):
			if other != enemy:
				other.take_damage(amount * value(&"ignite_erupt") / 100.0, Constants.DamageType.FIRE, true)
		SpellFx.burst(enemy.get_parent(), at + Vector3.UP * 0.6, Color(1.0, 0.45, 0.1), 14, Vector2(0.3, 0.8), 0.6, Vector2(0.05, 0.1), 40.0, 0.6)
	_in_extra = false

## ---- Events ------------------------------------------------------------

func _on_enemy_died(node: Node) -> void:
	if perks.is_empty() or _player == null or not _player.health.is_alive() or not node is Enemy:
		return
	var enemy := node as Enemy
	if has(&"reload_on_kill") and randf() * 100.0 < value(&"reload_on_kill"):
		var weapon := _player.get_active_weapon()
		if weapon and weapon.is_ranged and weapon.magazine_size > 0:
			weapon.current_magazine = weapon.magazine_size
			EventBus.ammo_changed.emit(weapon.ammo_type, AmmoInventory.get_reserve(weapon.ammo_type))
	if has(&"elite_battle_cry") and enemy.rarity_component and enemy.rarity_component.rarity != Constants.EnemyRarity.NORMAL:
		for other in _enemies_near(enemy.global_position, value(&"elite_battle_cry")):
			if other != enemy and other.is_rank_and_file() and other.status_effects:
				other.interrupt_attack()
				other.status_effects.apply_timed_effect("stun", ROAR_STUN)
		SpellFx.shockwave(enemy.get_parent(), enemy.global_position + Vector3.UP * 0.1, value(&"elite_battle_cry"), Color(0.95, 0.75, 0.4))
	if has(&"airborne_mana") and not _player.is_on_floor():
		_player.mana.restore(value(&"airborne_mana"))
	if has(&"hollow_life"):
		_player.health.heal(_player.health.max_health * value(&"hollow_life") / 100.0)
	if has(&"herald_maw") and Time.get_ticks_msec() >= _maw_ready_msec:
		_maw_ready_msec = Time.get_ticks_msec() + int(MAW_COOLDOWN * 1000.0)
		_open_maw(enemy)
	var at := enemy.global_position
	if has(&"curse_spread") and enemy.status_effects:
		var curses := enemy.status_effects.get_curses()
		var other := _nearest_other(enemy)
		if other and other.status_effects:
			for curse in curses:
				other.status_effects.apply_curse(curse, _player, 6.0, enemy.status_effects.get_magnitude(curse) * value(&"curse_spread") / 100.0)
	if has(&"control_burst") and enemy.status_effects and CONTROL_AILMENTS.any(func(id: String) -> bool: return enemy.status_effects.has_effect(id)):
		var dmg := enemy.health.max_health * value(&"control_burst") / 100.0
		for other in _enemies_near(at, BURST_RADIUS):
			if other != enemy:
				other.take_damage(dmg, Constants.DamageType.AETHERIC, true)
		SpellFx.burst(enemy.get_parent(), at + Vector3.UP * 0.8, Color(0.6, 0.4, 1.0), 18, Vector2(0.4, 1.0), 0.7, Vector2(0.05, 0.12), 45.0, 0.7)
	if has(&"sand_burst"):
		for other in _enemies_near(at, value(&"sand_burst")):
			if other != enemy and other.status_effects:
				other.status_effects.apply_effect("chill", _player, _player.health.max_health * 0.1)
		SpellFx.burst(enemy.get_parent(), at + Vector3.UP * 0.4, Color(0.85, 0.75, 0.5), 20, Vector2(0.3, 0.9), 0.8, Vector2(0.05, 0.12), 30.0, 0.8)

func _on_hit_blocked(defender: Node) -> void:
	if defender != _player:
		return
	if has(&"riposte"):
		_riposte_until_msec = Time.get_ticks_msec() + int(RIPOSTE_SECONDS * 1000.0)
	if not has(&"block_shockwave"):
		return
	var dmg := recent_hit() * value(&"block_shockwave") / 100.0
	for enemy in _enemies_near(_player.global_position, SHOCKWAVE_RADIUS):
		enemy.apply_knockback(_away(enemy) * SHOCKWAVE_KNOCKBACK)
		if dmg > 0.0:
			_perk_damage(enemy, dmg, Constants.DamageType.KINETIC)
	SpellFx.burst(_player.get_parent(), _player.global_position + Vector3.UP * 0.8, Color(0.9, 0.85, 0.7), 16, Vector2(0.3, 0.8), 0.5, Vector2(0.05, 0.1), 50.0, 0.5)

func _on_ability_cast(caster: Node, ability: Ability) -> void:
	if caster != _player:
		return
	_last_cast_msec = Time.get_ticks_msec()
	if not has(&"free_spell") or ability == null:
		return
	_casts += 1
	if _casts >= maxi(int(value(&"free_spell")), 2):
		_casts = 0
		_player.mana.restore(ability.get_mana_cost(_player.stat_sheet))

## A hit that got past mitigation (Player.take_damage).
func on_damage_taken(amount: float) -> void:
	if has(&"big_hit_ward") and _player.ward and amount > _player.health.max_health * BIG_HIT_SHARE:
		_player.ward.restore(amount * value(&"big_hit_ward") / 100.0)

func _physics_process(delta: float) -> void:
	if _player == null or perks.is_empty():
		return
	if not _player.is_on_floor():
		_air_time += delta
	else:
		var now := Time.get_ticks_msec()
		if _air_time >= LANDING_MIN_AIR and has(&"landing_strike") and now >= _landing_ready_msec:
			_landing_ready_msec = now + int(LANDING_COOLDOWN * 1000.0)
			var dmg := recent_hit() * value(&"landing_strike") / 100.0
			for enemy in _enemies_near(_player.global_position, LANDING_RADIUS):
				_perk_damage(enemy, dmg, Constants.DamageType.KINETIC)
			SpellFx.burst(_player.get_parent(), _player.global_position + Vector3.UP * 0.2, Color(0.75, 0.7, 0.6), 18, Vector2(0.3, 0.9), 0.5, Vector2(0.05, 0.1), 40.0, 0.5)
		_air_time = 0.0
	if has(&"stench_aura"):
		_stench_timer -= delta
		if _stench_timer <= 0.0:
			_stench_timer = STENCH_INTERVAL
			var tick := recent_hit() * value(&"stench_aura") / 100.0 * STENCH_INTERVAL
			for enemy in _enemies_near(_player.global_position, STENCH_RADIUS + Enemy.MAX_BODY_RADIUS):
				if tick > 0.0 and enemy.distance_to_body(_player.global_position) <= STENCH_RADIUS:
					_perk_damage(enemy, tick, Constants.DamageType.ENTROPIC, true)
	if has(&"ember_trail"):
		_ember_timer -= delta
		var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
		if _ember_timer <= 0.0 and Input.is_action_pressed("sprint") and speed >= EMBER_MIN_SPEED and _player.is_on_floor():
			_ember_timer = EMBER_INTERVAL
			var hit := recent_hit() * value(&"ember_trail") / 100.0
			for enemy in _enemies_near(_player.global_position, EMBER_RADIUS):
				if enemy.status_effects and hit > 0.0:
					enemy.status_effects.apply_effect("ignite", _player, hit)
	if has(&"low_life_fury"):
		var low := _player.health.current_health < _player.health.max_health * FURY_LIFE_SHARE
		if low and not _was_low_life and Time.get_ticks_msec() >= _fury_ready_msec and _player.health.is_alive():
			_fury_ready_msec = Time.get_ticks_msec() + int(FURY_COOLDOWN * 1000.0)
			_berserker_roar()
		_was_low_life = low
	if _last_round_spent:
		var weapon := _player.get_active_weapon()
		if weapon == null or weapon.get_current_magazine() > 0:
			_last_round_spent = false

func _berserker_roar() -> void:
	var origin := _player.global_position
	for enemy in _enemies_near(origin, FURY_RADIUS):
		enemy.apply_knockback(_away(enemy) * FURY_KNOCKBACK)
	_player.unique_effects.add_timed_more(&"perk_berserker_fury", value(&"low_life_fury"), FURY_SECONDS)
	SpellFx.shockwave(_player.get_parent(), origin + Vector3.UP * 0.1, FURY_RADIUS, Color(0.9, 0.2, 0.15))

## ---- Hit perks (runs inside _on_damage_dealt) ----------------------------

func _new_hit_perks(enemy: Enemy, amount: float, damage_type: int, is_spell: bool, now: int) -> void:
	if not is_instance_valid(enemy) or StatusEffectComponent.emitting_dot:
		return
	var weapon := _player.get_active_weapon()
	var melee := weapon != null and not weapon.is_ranged and not weapon.is_conduit and not weapon.is_throwing() and not is_spell
	var shot := weapon != null and (weapon.is_ranged or weapon.is_throwing()) and not weapon.is_conduit and not is_spell
	if has(&"cursed_extra") and enemy.health.is_alive() and enemy.status_effects and not enemy.status_effects.get_curses().is_empty():
		enemy.take_damage(amount * value(&"cursed_extra") / 100.0, damage_type, true)
	if has(&"melee_leech") and melee:
		_player.health.heal(amount * value(&"melee_leech") / 100.0)
	if has(&"web_chill") and shot and enemy.health.is_alive() and enemy.status_effects:
		enemy.status_effects.apply_effect("chill", _player, amount * value(&"web_chill") / 100.0)
	if has(&"long_shot") and shot and weapon.is_ranged and enemy.health.is_alive() and enemy.is_rank_and_file() \
			and enemy.global_position.distance_to(_player.global_position) > LONG_SHOT_DISTANCE \
			and now >= int(enemy.get_meta("perk_pin_ready", 0)) and randf() * 100.0 < value(&"long_shot"):
		enemy.set_meta("perk_pin_ready", now + PIN_COOLDOWN_MSEC)
		enemy.interrupt_attack()
		enemy.status_effects.apply_timed_effect("stun", PIN_SECONDS)
	if has(&"last_round") and shot and weapon.is_ranged and weapon.magazine_size > 0 \
			and weapon.get_current_magazine() == 0 and not _last_round_spent:
		_last_round_spent = true
		var at := enemy.global_position
		for other in _enemies_near(at, LAST_ROUND_RADIUS):
			if other != enemy:
				other.take_damage(amount * value(&"last_round") / 100.0, damage_type, true)
		SpellFx.burst(enemy.get_parent(), at + Vector3.UP * 0.8, Color(1.0, 0.7, 0.3), 18, Vector2(0.4, 1.0), 0.5, Vector2(0.05, 0.12), 50.0, 0.5)
		SpellFx.shockwave(enemy.get_parent(), at + Vector3.UP * 0.1, LAST_ROUND_RADIUS, Color(1.0, 0.65, 0.25))
	if has(&"war_stomp") and melee and now >= _stomp_ready_msec:
		_stomp_ready_msec = now + int(STOMP_COOLDOWN * 1000.0)
		var origin := _player.global_position
		for other in _enemies_near(origin, STOMP_RADIUS):
			other.apply_knockback(_away(other) * STOMP_KNOCKBACK)
			other.take_damage(amount * value(&"war_stomp") / 100.0, Constants.DamageType.KINETIC, true)
		SpellFx.shockwave(_player.get_parent(), origin + Vector3.UP * 0.1, STOMP_RADIUS, Color(1.0, 0.5, 0.2))
		SpellFx.burst(_player.get_parent(), origin + Vector3.UP * 0.2, Color(0.7, 0.45, 0.3), 20, Vector2(1.5, 4.0), 0.5, Vector2(0.06, 0.14), 20.0, -6.0)

## ---- Boss perks ----------------------------------------------------------

## Runs inside _on_damage_dealt (so extra damage here doesn't retrigger).
func _boss_hit_perks(enemy: Enemy, amount: float, damage_type: int, is_spell: bool, now: int) -> void:
	# Ailment ticks report as the player's damage too; they aren't hits.
	if not is_instance_valid(enemy) or StatusEffectComponent.emitting_dot:
		return
	if has(&"convergence") and AILMENT_OF.has(damage_type) and enemy.status_effects and enemy.health.is_alive():
		for type in AILMENT_OF:
			if type != damage_type:
				enemy.status_effects.apply_effect(AILMENT_OF[type], _player, amount * value(&"convergence") / 100.0)
	if has(&"falling_sun") and now >= _sun_ready_msec:
		_sun_ready_msec = now + int(SUN_COOLDOWN * 1000.0)
		var at := enemy.global_position
		for other in _enemies_near(at, SUN_RADIUS):
			other.take_damage(amount * value(&"falling_sun") / 100.0, Constants.DamageType.FIRE, true)
		SpellFx.burst(enemy.get_parent(), at + Vector3.UP * 0.5, Color(1.0, 0.6, 0.15), 30, Vector2(2.0, 5.0), 0.7, Vector2(0.08, 0.18), 70.0, -3.0)
		SpellFx.shockwave(enemy.get_parent(), at + Vector3.UP * 0.1, SUN_RADIUS, Color(1.0, 0.55, 0.15))
		SpellFx.light_pop(enemy.get_parent(), at + Vector3.UP * 1.5, Color(1.0, 0.7, 0.3), 4.0, SUN_RADIUS * 2.0, 0.4)
	if has(&"earth_wheel") and not is_spell:
		_wheel_hits += 1
		if _wheel_hits >= WHEEL_HITS:
			_wheel_hits = 0
			var origin := _player.global_position
			for other in _enemies_near(origin, WHEEL_RADIUS):
				other.apply_knockback(_away(other) * WHEEL_KNOCKBACK)
				other.take_damage(amount * value(&"earth_wheel") / 100.0, Constants.DamageType.KINETIC)
			SpellFx.shockwave(_player.get_parent(), origin + Vector3.UP * 0.1, WHEEL_RADIUS, Color(0.7, 0.6, 0.45))
			SpellFx.burst(_player.get_parent(), origin + Vector3.UP * 0.2, Color(0.6, 0.5, 0.4), 22, Vector2(2.0, 5.0), 0.5, Vector2(0.06, 0.14), 20.0, -6.0)
	# Last, so the hits above count first.
	if has(&"sealed_verdict") and enemy.health.is_alive() and not _is_boss(enemy) \
			and enemy.health.current_health < enemy.health.max_health * value(&"sealed_verdict") / 100.0:
		_execute.call_deferred(enemy, damage_type)

## The Herald's Maw: nearby enemies are dragged to the corpse and take a share
## of its maximum Life as Entropic damage.
func _open_maw(dead: Enemy) -> void:
	var at := dead.global_position
	var dmg := dead.health.max_health * value(&"herald_maw") / 100.0
	for other in _enemies_near(at, MAW_RADIUS):
		if other == dead:
			continue
		var pull := at - other.global_position
		pull.y = 0.0
		if pull.length() > 0.5:
			other.apply_knockback(pull.normalized() * minf(MAW_PULL, pull.length() * 2.0))
		other.take_damage(dmg, Constants.DamageType.ENTROPIC, true)
	SpellFx.burst(dead.get_parent(), at + Vector3.UP * 0.8, Color(0.35, 0.1, 0.5), 28, Vector2(-4.0, -1.5), 0.6, Vector2(0.06, 0.14), 180.0, 0.0)
	SpellFx.shockwave(dead.get_parent(), at + Vector3.UP * 0.1, MAW_RADIUS, Color(0.45, 0.15, 0.65))

## ---- Helpers -----------------------------------------------------------

func _enemies_near(at: Vector3, radius: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy and enemy.health and enemy.health.is_alive() and enemy.global_position.distance_to(at) <= radius:
			result.append(enemy)
	return result

func _nearest_other(enemy: Enemy) -> Enemy:
	if not is_instance_valid(enemy):
		return null
	var best: Enemy = null
	var best_d := NEARBY_RADIUS
	for other in _enemies_near(enemy.global_position, NEARBY_RADIUS):
		var d := other.global_position.distance_to(enemy.global_position)
		if other != enemy and d < best_d:
			best = other
			best_d = d
	return best

func _away(enemy: Enemy) -> Vector3:
	var away := enemy.global_position - _player.global_position
	away.y = 0.0
	return away.normalized() if away.length() > 0.1 else -_player.global_transform.basis.z

## The Sealed King's Verdict, after the hit that set it up has finished.
func _execute(enemy: Enemy, damage_type: int) -> void:
	if not is_instance_valid(enemy) or not enemy.health.is_alive():
		return
	SpellFx.burst(enemy.get_parent(), enemy.global_position + Vector3.UP * 1.0, Color(0.95, 0.9, 1.0), 16, Vector2(1.0, 3.0), 0.5, Vector2(0.05, 0.12), 180.0, 0.0)
	enemy.take_damage(enemy.health.current_health + 1.0, damage_type, true, false, false, true)

## Pinnacle and Figment bosses (their brains have phases); Ascendants cast
## spells through a phaseless brain and count as ordinary enemies here.
func _is_boss(enemy: Enemy) -> bool:
	return enemy.rank == Constants.EnemyRank.BOSS or (enemy.boss_brain != null and not enemy.boss_brain.phase_thresholds.is_empty())
