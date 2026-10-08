extends Node
class_name BossBrain
## Runs a boss's abilities and phases. A child of the boss Enemy (which then
## stands still while `casting`, see Enemy.is_attack_locked()). Between its
## ordinary attacks the boss casts a ready ability that fits the player's
## distance; crossing a health threshold starts the next phase: a short
## invulnerable roar, faster cooldowns from then on, and the phase's opening
## ability if it has one.

signal phase_changed(phase: int)

## Seconds between two abilities, and before the first.
const GLOBAL_GAP := 1.4
const OPENING_GAP := 2.5
const ENGAGE_RANGE := 30.0
const PHASE_TRANSITION_SEC := 1.6
const HAZARD_TICK := 0.5
## Hazards deal this share of an ability hit per tick.
const HAZARD_TICK_SHARE := 0.25
const CHARGE_SPEED := 16.0
const CHARGE_HIT_RADIUS := 1.6
const SUMMON_CAP := 6
const BLAST_STAGGER := 0.3
## Pulls stop this far from the boss.
const PULL_STOP_DISTANCE := 2.5

var abilities: Array[BossAbility] = []
## Health fractions that start phase 2, 3, ... (descending).
var phase_thresholds: Array[float] = []
## Phase number -> ability id cast as the phase opens.
var phase_openers: Dictionary = {}
## Cooldown speed per phase (index 0 = phase 1).
var phase_cooldown_scale: Array[float] = [1.0, 0.85, 0.7]

var phase: int = 1
var casting: bool = false

var _boss: Enemy
var _player: Player
var _cooldowns: Dictionary = {}
var _gap: float = OPENING_GAP
var _hazards: Array[Dictionary] = []
var _summoned: Array[Node] = []

func _ready() -> void:
	_boss = get_parent() as Enemy
	_boss.boss_brain = self

func _physics_process(delta: float) -> void:
	if _boss == null or not _boss.health.is_alive():
		_clear_hazards()
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	_tick_hazards(delta)
	_check_phase()
	var speed: float = 1.0 / _cooldown_scale()
	for key in _cooldowns:
		_cooldowns[key] = maxf(_cooldowns[key] - delta * speed, 0.0)
	if casting or _player == null or _boss.status_effects.is_stunned():
		return
	_gap -= delta
	if _gap > 0.0 or _boss.is_attack_locked():
		return
	var dist := _flat_distance(_boss.global_position, _player.global_position)
	if dist > ENGAGE_RANGE:
		return
	var ability := _pick(dist)
	if ability:
		cast(ability)

func _cooldown_scale() -> float:
	return phase_cooldown_scale[clampi(phase - 1, 0, phase_cooldown_scale.size() - 1)]

func is_ready(ability: BossAbility) -> bool:
	return _cooldowns.get(ability.id, 0.0) <= 0.0

func _pick(dist: float) -> BossAbility:
	var ready: Array[BossAbility] = []
	var total := 0.0
	for a in abilities:
		if a.min_phase <= phase and is_ready(a) and dist >= a.min_range and dist <= a.max_range:
			ready.append(a)
			total += a.weight
	var roll := randf() * total
	for a in ready:
		roll -= a.weight
		if roll < 0.0:
			return a
	return null

func find(id: String) -> BossAbility:
	for a in abilities:
		if a.id == id:
			return a
	return null

## ---- Phases --------------------------------------------------------------

func _check_phase() -> void:
	var max_health := _boss.health.max_health
	if max_health <= 0.0 or casting:
		return
	var fraction := _boss.health.current_health / max_health
	if phase - 1 < phase_thresholds.size() and fraction <= phase_thresholds[phase - 1]:
		_enter_phase(phase + 1)

func _enter_phase(new_phase: int) -> void:
	phase = new_phase
	phase_changed.emit(phase)
	EventBus.boss_phase_changed.emit(_boss, phase)
	casting = true
	_boss.invulnerable = true
	_boss.begin_attack_telegraph(PHASE_TRANSITION_SEC)
	BossTelegraph.circle(_scene(), _boss.global_position, 3.0, PHASE_TRANSITION_SEC, Color(1.0, 0.85, 0.4))
	await get_tree().create_timer(PHASE_TRANSITION_SEC).timeout
	if not _alive():
		return
	_boss.invulnerable = false
	casting = false
	var opener := find(phase_openers.get(phase, ""))
	if opener:
		cast(opener)

## ---- Casting -------------------------------------------------------------

func cast(a: BossAbility) -> void:
	casting = true
	match a.kind:
		BossAbility.Kind.SLAM:
			await _slam(a)
		BossAbility.Kind.BLAST:
			await _blast(a)
		BossAbility.Kind.HAZARD:
			await _hazard(a)
		BossAbility.Kind.CHARGE:
			await _charge(a)
		BossAbility.Kind.VOLLEY:
			await _volley(a)
		BossAbility.Kind.SUMMON:
			await _summon(a)
		BossAbility.Kind.PULL:
			await _pull(a)
	if not _alive():
		return
	casting = false
	_cooldowns[a.id] = a.cooldown
	_gap = GLOBAL_GAP * _cooldown_scale()

func _slam(a: BossAbility) -> void:
	var center := _boss.global_position
	_boss.begin_attack_telegraph(a.telegraph)
	BossTelegraph.circle(_scene(), center, a.radius, a.telegraph, _tint(a))
	await _wait(a.telegraph)
	if _alive():
		_hit_circle(center, a.radius, a)

func _blast(a: BossAbility) -> void:
	_boss.begin_attack_telegraph(a.telegraph)
	for i in a.count:
		if not _alive() or _player == null:
			return
		var spot := _player.global_position
		if i > 0:
			var angle := randf() * TAU
			spot += Vector3(cos(angle), 0, sin(angle)) * randf_range(a.radius, a.radius * 2.5)
		_delayed_circle(spot, a)
		if i < a.count - 1:
			await _wait(BLAST_STAGGER)
	await _wait(a.telegraph)

func _delayed_circle(spot: Vector3, a: BossAbility) -> void:
	BossTelegraph.circle(_scene(), spot, a.radius, a.telegraph, _tint(a))
	await _wait(a.telegraph)
	if _alive():
		_hit_circle(spot, a.radius, a)

func _hazard(a: BossAbility) -> void:
	var spot := _player.global_position
	_boss.begin_attack_telegraph(a.telegraph)
	BossTelegraph.circle(_scene(), spot, a.radius, a.telegraph, _tint(a))
	await _wait(a.telegraph)
	if not _alive():
		return
	var marker := BossTelegraph.circle(_scene(), spot, a.radius, 0.01, _tint(a))
	marker.persist = true
	_hazards.append({"node": marker, "center": spot, "ability": a, "left": a.duration, "tick": 0.0})

func _tick_hazards(delta: float) -> void:
	for h in _hazards.duplicate():
		h["left"] -= delta
		h["tick"] -= delta
		if h["tick"] <= 0.0:
			h["tick"] = HAZARD_TICK
			var a: BossAbility = h["ability"]
			_hit_circle(h["center"], a.radius, a, HAZARD_TICK_SHARE)
		if h["left"] <= 0.0:
			if is_instance_valid(h["node"]):
				h["node"].queue_free()
			_hazards.erase(h)

func _clear_hazards() -> void:
	for h in _hazards:
		if is_instance_valid(h["node"]):
			h["node"].queue_free()
	_hazards.clear()

func _charge(a: BossAbility) -> void:
	var to_player := _player.global_position - _boss.global_position
	to_player.y = 0.0
	var dir := to_player.normalized() if to_player.length() > 0.1 else -_boss.global_transform.basis.z
	var length := clampf(to_player.length() + 2.0, 4.0, a.max_range + 2.0)
	_boss.begin_attack_telegraph(a.telegraph)
	BossTelegraph.line(_scene(), _boss.global_position, dir, length, CHARGE_HIT_RADIUS * 2.0, a.telegraph, _tint(a))
	await _wait(a.telegraph)
	var travelled := 0.0
	var hit := false
	while _alive() and travelled < length:
		await get_tree().physics_frame
		if not _alive():
			return
		var step := CHARGE_SPEED * get_physics_process_delta_time()
		_boss._pull = dir * CHARGE_SPEED
		travelled += step
		if not hit and _player and _flat_distance(_boss.global_position, _player.global_position) <= CHARGE_HIT_RADIUS:
			hit = true
			_damage_player(a)
			_player.apply_impulse(dir * 9.0)

func _volley(a: BossAbility) -> void:
	_boss.begin_attack_telegraph(a.telegraph)
	await _wait(a.telegraph)
	if not _alive() or _player == null:
		return
	var origin := _boss.global_position + Vector3(0, 1.2, 0)
	var aim := (_player.global_position + Vector3(0, 0.9, 0) - origin).normalized()
	for i in a.count:
		var t := 0.0 if a.count == 1 else float(i) / (a.count - 1) - 0.5
		var dir := aim.rotated(Vector3.UP, deg_to_rad(a.spread_degrees) * t)
		var projectile: Projectile = EnemyRangedAttack.PROJECTILE_SCENE.instantiate()
		projectile.damage_amount = _damage(a)
		projectile.damage_type = _type(a)
		projectile.source = _boss
		projectile.speed = 16.0
		_scene().add_child(projectile)
		projectile.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), origin + dir * 1.2)

func _summon(a: BossAbility) -> void:
	_summoned = _summoned.filter(func(n): return is_instance_valid(n) and n.health.is_alive())
	_boss.begin_attack_telegraph(a.telegraph)
	BossTelegraph.circle(_scene(), _boss.global_position, 3.0, a.telegraph, _tint(a))
	await _wait(a.telegraph)
	if not _alive():
		return
	for i in mini(a.count, SUMMON_CAP - _summoned.size()):
		var unit := EnemyRoster.create_unit(a.unit_id)
		var angle := TAU * i / maxf(a.count, 1)
		_boss.get_parent().add_child(unit)
		unit.global_position = _boss.global_position + Vector3(cos(angle), 0.1, sin(angle)) * 3.0
		_summoned.append(unit)

func _pull(a: BossAbility) -> void:
	_boss.begin_attack_telegraph(a.telegraph + 0.8)
	BossTelegraph.circle(_scene(), _boss.global_position, a.max_range, a.telegraph, Color(0.6, 0.3, 0.9))
	await _wait(a.telegraph)
	if not _alive() or _player == null:
		return
	var to_boss := _boss.global_position - _player.global_position
	to_boss.y = 0.0
	var distance := to_boss.length() - PULL_STOP_DISTANCE
	if distance > 0.0 and to_boss.length() <= a.max_range:
		# An impulse decays at Player.IMPULSE_FRICTION, travelling v^2 / 2f.
		_player.apply_impulse(to_boss.normalized() * sqrt(2.0 * Player.IMPULSE_FRICTION * distance))
	var center := _boss.global_position
	BossTelegraph.circle(_scene(), center, a.radius, 0.8, _tint(a))
	await _wait(0.8)
	if _alive():
		_hit_circle(center, a.radius, a)

## ---- Damage --------------------------------------------------------------

func _hit_circle(center: Vector3, radius: float, a: BossAbility, share: float = 1.0) -> void:
	if _player == null or not _player.health.is_alive():
		return
	if absf(_player.global_position.y - center.y) > 3.0:
		return
	if _flat_distance(center, _player.global_position) <= radius + 0.4:
		_damage_player(a, share)

func _damage_player(a: BossAbility, share: float = 1.0) -> void:
	var amount := _damage(a) * share
	_player.take_damage(amount, _type(a), _boss, Player.HitKind.SPELL)
	if a.status != "" and _player.status_effects:
		_player.status_effects.apply_effect(a.status, _boss, amount)

func _damage(a: BossAbility) -> float:
	return _boss.get_ability_base_damage() * a.damage_mult

func _type(a: BossAbility) -> int:
	return a.damage_type if a.damage_type >= 0 else _boss.get_ability_damage_type()

func _tint(a: BossAbility) -> Color:
	return Constants.DAMAGE_TYPE_COLOR.get(_type(a), Color(1.0, 0.25, 0.15))

## ---- Helpers -------------------------------------------------------------

func _alive() -> bool:
	return is_instance_valid(self) and is_instance_valid(_boss) and _boss.health.is_alive() and is_inside_tree()

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout

func _scene() -> Node:
	return _boss.get_parent()

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
