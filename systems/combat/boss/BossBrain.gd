extends Node
class_name BossBrain
## Runs a boss's abilities and phases. A child of the boss Enemy (which then
## stands still while `casting`, see Enemy.is_attack_locked()). Between its
## ordinary attacks the boss casts a ready ability that fits the player's
## distance; crossing a health threshold starts the next phase: a short
## invulnerable roar, faster cooldowns from then on, and the phase's opening
## ability if it has one.

const BossFx := preload("res://entities/effects/boss_fx/BossFx.gd")

signal phase_changed(phase: int)
## A ground ability landed (slams, blasts, pull slams, a hazard appearing).
signal ground_struck(ability: BossAbility, center: Vector3, radius: float)
## A hazard pool ran out.
signal hazard_ended(ability: BossAbility, center: Vector3, radius: float)

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
## Pulls stop this far from the boss, and drag the player at most PULL_MAX_DRAG.
const PULL_STOP_DISTANCE := 3.5
const PULL_MAX_DRAG := 8.0
## The brain wakes once its boss is in combat (the player came inside its
## chase range, or hit it) and keeps the boss chasing until the player is
## past LEASH_RANGE.
const LEASH_RANGE := 40.0
## Range answers: a player the engaged boss can see, staying beyond
## range_answer_distance for RANGE_ANSWER_DELAY seconds, gets the boss's
## next range_answers entry (each boss has its own).
const RANGE_ANSWER_DELAY := 4.0
const RANGE_ANSWER_COOLDOWN := 10.0
const LEAP_HEIGHT := 4.0
## Share of a LEAP's telegraph spent crouching before take-off.
const LEAP_CROUCH := 0.4
const WAVE_STEP_SEC := 0.28
## Metres a LANCE runs on past the player.
const LANCE_OVERSHOOT := 8.0

var abilities: Array[BossAbility] = []
## Health fractions that start phase 2, 3, ... (descending).
var phase_thresholds: Array[float] = []
## Phase number -> ability id cast as the phase opens.
var phase_openers: Dictionary = {}
## Cooldown speed per phase (index 0 = phase 1).
var phase_cooldown_scale: Array[float] = [1.0, 0.85, 0.7]
var global_gap: float = GLOBAL_GAP
var opening_gap: float = OPENING_GAP
## Only casts while its enemy is in combat and can see the player (Ascendants).
var require_sight: bool = false
## Cast in turn at a player keeping their distance; empty for none.
var range_answers: Array[BossAbility] = []
var range_answer_distance: float = 13.0

var phase: int = 1
var casting: bool = false
var engaged: bool = false

var _boss: Enemy
var _player: Player
var _cooldowns: Dictionary = {}
var _gap: float = OPENING_GAP
var _hazards: Array[Dictionary] = []
var _summoned: Array[Node] = []
var _far_time: float = 0.0
var _answer_cooldown: float = 0.0
var _next_answer: int = 0

func _ready() -> void:
	_boss = get_parent() as Enemy
	_boss.boss_brain = self
	_gap = opening_gap
	ground_struck.connect(_on_ground_struck)

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
	if _player == null:
		return
	_update_engaged()
	_tick_range_answer(delta)
	if casting or not engaged or _boss.status_effects.is_stunned():
		return
	if _far_time >= RANGE_ANSWER_DELAY and _answer_cooldown <= 0.0 and not _boss.is_mid_attack():
		cast(_take_range_answer())
		return
	# A follow-up the boss can't let pass (Aurelia burning an Entangled
	# player) skips the gap and its cooldown.
	if not _boss.is_mid_attack():
		var urgent: BossAbility = _boss.urgent_ability(_flat_distance(_boss.global_position, _player.global_position))
		if urgent and urgent.min_phase <= phase:
			cast(urgent)
			return
	_gap -= delta
	if _gap > 0.0 or _boss.is_mid_attack():
		return
	var dist := _flat_distance(_boss.global_position, _player.global_position)
	if dist > ENGAGE_RANGE:
		return
	if require_sight and not (_boss.is_in_combat() and _can_see_player()):
		return
	var ability := _pick(dist)
	if ability:
		cast(ability)

func _update_engaged() -> void:
	if _boss.rank != Constants.EnemyRank.BOSS:
		engaged = _boss.is_in_combat()
		return
	var dist := _flat_distance(_boss.global_position, _player.global_position)
	if engaged and dist > LEASH_RANGE:
		engaged = false
	elif not engaged:
		engaged = _boss.is_in_combat() and dist <= LEASH_RANGE
	if engaged:
		_boss.mark_in_combat()

## Out of sight pauses the timer rather than resetting it, so ducking
## behind a pillar between shots doesn't dodge the answer.
func _tick_range_answer(delta: float) -> void:
	_answer_cooldown = maxf(_answer_cooldown - delta, 0.0)
	if not engaged or range_answers.is_empty() or require_sight:
		_far_time = 0.0
		return
	if _flat_distance(_boss.global_position, _player.global_position) <= range_answer_distance:
		_far_time = 0.0
	elif _can_see_player():
		_far_time += delta

## The next answer in turn, stretched to reach the player where needed.
func _take_range_answer() -> BossAbility:
	_far_time = 0.0
	_answer_cooldown = RANGE_ANSWER_COOLDOWN
	var a := range_answers[_next_answer % range_answers.size()].copy()
	_next_answer += 1
	if a.kind == BossAbility.Kind.PULL:
		a.max_range = maxf(a.max_range, _flat_distance(_boss.get_pull_center(), _player.global_position) + 2.0)
	a.cooldown = 0.0
	return a

func _cooldown_scale() -> float:
	return phase_cooldown_scale[clampi(phase - 1, 0, phase_cooldown_scale.size() - 1)]

func is_ready(ability: BossAbility) -> bool:
	return _cooldowns.get(ability.id, 0.0) <= 0.0

func _pick(dist: float) -> BossAbility:
	var ready: Array[BossAbility] = []
	var total := 0.0
	var summons_full := _living_summons() >= SUMMON_CAP
	for a in abilities:
		# At the cap a summon would only play its cast and bring nobody.
		if a.kind == BossAbility.Kind.SUMMON and summons_full:
			continue
		if a.min_phase <= phase and is_ready(a) and dist >= a.min_range and dist <= a.max_range and _boss.can_use_ability(a):
			ready.append(a)
			total += a.weight * _boss.ability_weight(a)
	var roll := randf() * total
	for a in ready:
		roll -= a.weight * _boss.ability_weight(a)
		if roll < 0.0:
			return a
	return null

func _living_summons() -> int:
	_summoned = _summoned.filter(func(n): return is_instance_valid(n) and n.health.is_alive())
	return _summoned.size()

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
	BossFx.phase_roar(_boss, _boss.get_ability_damage_type(), _boss.roar_sound())
	await _boss.run_phase_transition(phase, PHASE_TRANSITION_SEC)
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
	var s := _scaled(a)
	match a.kind:
		BossAbility.Kind.SLAM:
			await _slam(s)
		BossAbility.Kind.BLAST:
			await _blast(s)
		BossAbility.Kind.HAZARD:
			await _hazard(s)
		BossAbility.Kind.CHARGE:
			await _charge(s)
		BossAbility.Kind.VOLLEY:
			await _volley(s)
		BossAbility.Kind.SUMMON:
			await _summon(s)
		BossAbility.Kind.PULL:
			await _pull(s)
		BossAbility.Kind.CUSTOM:
			await _boss.cast_custom(a)
		BossAbility.Kind.LEAP:
			await _leap(s)
		BossAbility.Kind.BLINK:
			await _blink(s)
		BossAbility.Kind.WAVE:
			await _wave(s)
		BossAbility.Kind.LANCE:
			await _lance(s)
	if not _alive():
		return
	casting = false
	_cooldowns[a.id] = a.cooldown
	_gap = global_gap * _cooldown_scale()

## The ability as this cast runs it: Figment mods scale its radius
## (area), telegraph (cast speed, floored at MIN_TELEGRAPH_SHARE) and volley
## count (extra projectiles). Cooldowns stay keyed by the original's id.
func _scaled(a: BossAbility) -> BossAbility:
	var area := _boss.get_area_multiplier()
	var cast_speed := _boss.get_cast_speed_multiplier()
	var extra := _boss.get_extra_projectiles() if a.kind == BossAbility.Kind.VOLLEY else 0
	if is_equal_approx(area, 1.0) and is_equal_approx(cast_speed, 1.0) and extra == 0:
		return a
	var s := a.copy()
	s.radius *= area
	s.telegraph *= maxf(1.0 / maxf(cast_speed, 0.01), FigmentMods.MIN_TELEGRAPH_SHARE)
	s.count += extra
	return s

## The glow gathering at the hand; after the telegraph has picked the
## element (the Lord's cycle advances there).
func _wind_up(a: BossAbility) -> void:
	var at := _boss.get_cast_origin()
	if _player:
		var ahead := _player.global_position - _boss.global_position
		ahead.y = 0.0
		at += ahead.normalized() * minf(_boss.body_radius + 0.3, ahead.length() * 0.5)
	BossFx.charge(_boss, at, _type(a), a.telegraph)

func _slam(a: BossAbility) -> void:
	var center := _boss.global_position
	_boss.begin_attack_telegraph(a.telegraph)
	_wind_up(a)
	BossTelegraph.circle(_scene(), center, a.radius, a.telegraph, _tint(a))
	_boss.on_ability_telegraph(a, center, a.telegraph)
	await _wait(a.telegraph)
	if _alive():
		_hit_circle(center, a.radius, a)
		ground_struck.emit(a, center, a.radius)

func _blast(a: BossAbility) -> void:
	_boss.begin_attack_telegraph(a.telegraph)
	_wind_up(a)
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
	_boss.on_ability_telegraph(a, spot, a.telegraph)
	await _wait(a.telegraph)
	if _alive():
		_hit_circle(spot, a.radius, a)
		ground_struck.emit(a, spot, a.radius)

func _hazard(a: BossAbility) -> void:
	var spot := _player.global_position
	_boss.begin_attack_telegraph(a.telegraph)
	_wind_up(a)
	BossTelegraph.circle(_scene(), spot, a.radius, a.telegraph, _tint(a))
	_boss.on_ability_telegraph(a, spot, a.telegraph)
	await _wait(a.telegraph)
	if not _alive():
		return
	var marker := BossTelegraph.circle(_scene(), spot, a.radius, 0.01, _tint(a))
	marker.persist = true
	BossFx.hazard_aura(marker, a.radius, _type(a))
	_hazards.append({"node": marker, "center": spot, "ability": a, "left": a.duration, "tick": 0.0})
	ground_struck.emit(a, spot, a.radius)

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
			hazard_ended.emit(h["ability"], h["center"], h["ability"].radius)

## Ends every hazard pool overlapping the circle whose ability passes
## `filter`; returns each as {"center", "radius"} (the Lord's cold putting
## out his fire pools).
func extinguish_hazards(center: Vector3, radius: float, filter: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in _hazards.duplicate():
		var a: BossAbility = h["ability"]
		if _flat_distance(h["center"], center) > a.radius + radius or not filter.call(a):
			continue
		if is_instance_valid(h["node"]):
			h["node"].queue_free()
		_hazards.erase(h)
		out.append({"center": h["center"], "radius": a.radius})
		hazard_ended.emit(a, h["center"], a.radius)
	return out

func hazard_count() -> int:
	return _hazards.size()

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
	_wind_up(a)
	BossTelegraph.line(_scene(), _boss.global_position, dir, length, CHARGE_HIT_RADIUS * 2.0, a.telegraph, _tint(a))
	await _wait(a.telegraph)
	if _alive():
		BossFx.trail(_boss, _type(a), length / CHARGE_SPEED + 0.2)
	var travelled := 0.0
	var hit := false
	var blocked := false
	while _alive() and travelled < length:
		await get_tree().physics_frame
		if not _alive():
			return
		var step := CHARGE_SPEED * get_physics_process_delta_time()
		_boss._pull = dir * CHARGE_SPEED
		travelled += step
		if _boss.blocks_charge(dir):
			blocked = true
			break
		if not hit and _player and _flat_distance(_boss.global_position, _player.global_position) <= CHARGE_HIT_RADIUS:
			hit = true
			_damage_player(a)
			_player.apply_impulse(dir * 9.0)
	# Bosses can follow an unblocked charge up (the Herald's spin slash).
	if not blocked and _alive() and _boss.has_method("on_charge_end"):
		_boss.call("on_charge_end", a)

func _volley(a: BossAbility) -> void:
	_boss.begin_attack_telegraph(a.telegraph)
	_wind_up(a)
	await _wait(a.telegraph)
	if not _alive() or _player == null:
		return
	var origin := _boss.get_cast_origin()
	var aim := (_player.global_position + Vector3(0, 0.9, 0) - origin).normalized()
	SpellFx.flash(_scene(), origin + aim * 1.0, BossFx.glow_of(_type(a)), 1.8, 0.2)
	BossFx.sound(BossFx.cast_sound(_type(a)), origin, -2.0, 1.2)
	for i in a.count:
		var t := 0.0 if a.count == 1 else float(i) / (a.count - 1) - 0.5
		var dir := aim.rotated(Vector3.UP, deg_to_rad(a.spread_degrees) * t)
		var projectile: Projectile = EnemyRangedAttack.PROJECTILE_SCENE.instantiate()
		projectile.damage_amount = _damage(a)
		projectile.damage_type = _type(a)
		projectile.source = _boss
		projectile.speed = 16.0 * _boss.get_projectile_speed_multiplier()
		_scene().add_child(projectile)
		projectile.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), origin + dir * 1.2)
		BossFx.dress_bolt(projectile, _type(a))

func _summon(a: BossAbility) -> void:
	_living_summons()
	_boss.begin_attack_telegraph(a.telegraph)
	_wind_up(a)
	BossTelegraph.circle(_scene(), _boss.global_position, 3.0, a.telegraph, _tint(a))
	await _wait(a.telegraph)
	if not _alive():
		return
	for i in mini(a.count, SUMMON_CAP - _summoned.size()):
		var unit := EnemyRoster.create_unit(a.unit_id)
		var angle := TAU * i / maxf(a.count, 1)
		_boss.get_parent().add_child(unit)
		unit.global_position = _boss.global_position + Vector3(cos(angle), 0.1, sin(angle)) * 3.0
		BossFx.summon_gate(_scene(), unit.global_position, _type(a))
		_summoned.append(unit)
		_boss.on_unit_summoned(unit)

func _pull(a: BossAbility) -> void:
	var center := _boss.get_pull_center()
	_boss.begin_attack_telegraph(a.telegraph + 0.8)
	_wind_up(a)
	BossTelegraph.circle(_scene(), center, a.max_range, a.telegraph, Color(0.6, 0.3, 0.9))
	BossFx.vortex(_scene(), center, minf(a.max_range, 14.0), _type(a), a.telegraph + 0.8)
	await _wait(a.telegraph)
	if not _alive() or _player == null:
		return
	var to_center := center - _player.global_position
	to_center.y = 0.0
	var distance := minf(to_center.length() - a.pull_stop, a.max_drag)
	if distance > 0.0 and to_center.length() <= a.max_range and not _boss.is_player_anchored(_player):
		# An impulse decays at Player.IMPULSE_FRICTION, travelling v^2 / 2f.
		_player.apply_impulse(to_center.normalized() * sqrt(2.0 * Player.IMPULSE_FRICTION * distance))
	BossTelegraph.circle(_scene(), center, a.radius, 0.8, _tint(a))
	await _wait(0.8)
	if _alive():
		_hit_circle(center, a.radius, a)
		ground_struck.emit(a, center, a.radius)

## Lands where the player stood at the cast.
func _leap(a: BossAbility) -> void:
	var start := _boss.global_position
	var target := _player.global_position
	_boss.begin_attack_telegraph(a.telegraph)
	_wind_up(a)
	BossTelegraph.circle(_scene(), target, a.radius, a.telegraph, _tint(a))
	_boss.on_ability_telegraph(a, target, a.telegraph)
	var crouch := a.telegraph * LEAP_CROUCH
	await _wait(crouch)
	if not _alive():
		return
	var flight := a.telegraph - crouch
	BossFx.trail(_boss, _type(a), flight + 0.2)
	var t := 0.0
	while t < flight:
		await get_tree().physics_frame
		if not _alive():
			return
		t += get_physics_process_delta_time()
		var k := minf(t / flight, 1.0)
		_boss.global_position = start.lerp(target, k) + Vector3.UP * sin(k * PI) * LEAP_HEIGHT
		_boss.velocity = Vector3.ZERO
	_hit_circle(target, a.radius, a)
	ground_struck.emit(a, target, a.radius)

func _blink(a: BossAbility) -> void:
	var target := _player.global_position
	_boss.begin_attack_telegraph(a.telegraph)
	_wind_up(a)
	BossTelegraph.circle(_scene(), target, a.radius, a.telegraph, _tint(a))
	_boss.on_ability_telegraph(a, target, a.telegraph)
	await _wait(a.telegraph)
	if not _alive():
		return
	BossFx.blink(_scene(), _boss.global_position, target, _type(a))
	_boss.global_position = target
	_boss.velocity = Vector3.ZERO
	_hit_circle(target, a.radius, a)
	ground_struck.emit(a, target, a.radius)

## Each circle steps a radius and a half toward where the player is now,
## so standing still or running straight back gets caught.
func _wave(a: BossAbility) -> void:
	_boss.begin_attack_telegraph(a.telegraph)
	_wind_up(a)
	var spot := _boss.global_position
	for i in a.count:
		if not _alive() or _player == null:
			return
		var to := _player.global_position - spot
		to.y = 0.0
		spot += to.normalized() * minf(a.radius * 1.5, to.length()) if to.length() > 0.1 else Vector3.ZERO
		spot.y = _player.global_position.y
		_delayed_circle(spot, a)
		await _wait(WAVE_STEP_SEC)
	await _wait(a.telegraph)

## Aimed once, at the cast: a sidestep during the telegraph dodges it.
func _lance(a: BossAbility) -> void:
	var origin := _boss.global_position
	var to := _player.global_position - origin
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.1 else -_boss.global_transform.basis.z
	var length := to.length() + LANCE_OVERSHOOT
	_boss.begin_attack_telegraph(a.telegraph)
	_wind_up(a)
	BossTelegraph.line(_scene(), origin, dir, length, a.radius * 2.0, a.telegraph, _tint(a))
	await _wait(a.telegraph)
	if not _alive() or _player == null:
		return
	BossFx.lance(_scene(), _boss.get_cast_origin(), dir, length, _type(a))
	var rel := _player.global_position - origin
	rel.y = 0.0
	var along := rel.dot(dir)
	if along >= 0.0 and along <= length and (rel - dir * along).length() <= a.radius and _player.health.is_alive():
		_damage_player(a)

## Ground abilities land in their element; hazard pools open quieter.
func _on_ground_struck(a: BossAbility, center: Vector3, radius: float) -> void:
	if is_inside_tree():
		BossFx.impact(_scene(), center, radius, _boss.strike_damage_type(a, center), a.kind != BossAbility.Kind.HAZARD)

## ---- Damage --------------------------------------------------------------

func _hit_circle(center: Vector3, radius: float, a: BossAbility, share: float = 1.0) -> void:
	if _player == null or not _player.health.is_alive():
		return
	if GroundHit.in_circle(center, radius, _player.global_position):
		_damage_player(a, share)

func _damage_player(a: BossAbility, share: float = 1.0) -> void:
	var amount := _damage(a) * share
	_player.take_damage(amount, _type(a), _boss, Player.HitKind.SPELL)
	if a.status != "" and _player.status_effects:
		_player.status_effects.apply_effect(a.status, _boss, amount)

func _damage(a: BossAbility) -> float:
	return _boss.roll_crit(_boss.get_ability_base_damage() * a.damage_mult)

func _type(a: BossAbility) -> int:
	return a.damage_type if a.damage_type >= 0 else _boss.get_ability_damage_type()

func _tint(a: BossAbility) -> Color:
	return Constants.DAMAGE_TYPE_COLOR.get(_type(a), Color(1.0, 0.25, 0.15))

## ---- Helpers -------------------------------------------------------------

## Nothing but other enemies between the cast origin and the player's chest.
func _can_see_player() -> bool:
	var space := _boss.get_world_3d().direct_space_state
	var exclude: Array[RID] = [_boss.get_rid()]
	var target := _player.global_position + Vector3(0, 1.0, 0)
	for i in 4:
		var query := PhysicsRayQueryParameters3D.create(_boss.get_cast_origin(), target, 1)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.get("collider") == _player:
			return true
		if not hit.get("collider") is Enemy:
			return false
		exclude.append((hit["collider"] as Enemy).get_rid())
	return false

func _alive() -> bool:
	return is_instance_valid(self) and is_instance_valid(_boss) and _boss.health.is_alive() and is_inside_tree()

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout

func _scene() -> Node:
	return _boss.get_parent()

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
