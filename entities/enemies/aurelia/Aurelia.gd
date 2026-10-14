extends PinnacleBoss
class_name Aurelia
## Aurelia, the final boss (model: Dread Jaina by Retera, Hive Workshop, in
## the Queen of Suffering's skin). Reached from the Reality Engine for now.
## Fought in the AureliaArena.
##
## Her kit:
##   Ice Spears: eight icicles in a star. Upgraded: they softly track you.
##   Fire Wall: a quarter circle of fire rolling outward that splits down the
##   middle. Upgraded: it leaves one or two fire pots, gone at the next phase.
##   Lightning Bolt: small strikes on you (1.5s, then 1s apart) mark where a
##   big bolt lands 0.75s after the last. Upgraded: one fewer warning strike.
##   Entangling Roots: lines of roots tear up out of the ground toward you
##   and Entangle you. Upgraded: a second wave follows between the first.
##   Staff Sweep and Searing Thrust: her two melee moves.
## Ailments combine on you (AureliaAilments): Chilled/Frozen + Lightning ->
## Electrocuted and Shocked; Entangled + Fire -> Forbidden Fire; Ignited +
## Cold -> Pallid. She hunts for them (ability_weight, urgent_ability): an
## Entangled player gets Searing Thrust (in reach) or Fire Wall at once, and
## otherwise she favours whatever completes a combo on the ailments you
## carry, or sets one up when you carry none.
## Phases:
##   1 (100%): the simple kit.
##   2 (90%): the fight begins - she casts faster; one spell upgrades.
##   3 (75%): Earth Wheel, 7 or 14 quakes (immune while it turns); another
##   spell upgrades.
##   4 (50%): two Fire Golems; a third spell upgrades; she casts faster again.
##   5 (25%): Earth Wheel, 14 or 21 quakes, then she calls out "Amaterasu"
##   and black fire starts eating the arena. Two Fire Golems chase you; a
##   golem knocking you up gets a Living Bomb planted in you (5s cooldown).
##   Every spell is upgraded.

enum Spell { ICE_SPEARS, FIRE_WALL, LIGHTNING, ROOTS }
const SPELLS: Array[int] = [Spell.ICE_SPEARS, Spell.FIRE_WALL, Spell.LIGHTNING, Spell.ROOTS]
const SPELL_NAMES := {Spell.ICE_SPEARS: "Ice Spears", Spell.FIRE_WALL: "Fire Wall", Spell.LIGHTNING: "Lightning Bolt", Spell.ROOTS: "Entangling Roots"}
const UPGRADE_CALLOUTS := {
	Spell.ICE_SPEARS: "Her Ice Spears hunt you",
	Spell.FIRE_WALL: "Her Fire Wall leaves embers burning",
	Spell.LIGHTNING: "Her lightning grows impatient",
	Spell.ROOTS: "Her roots come in waves",
}

const DISPLAY_NAME := "Aurelia"
const PHASES: Array[float] = [0.9, 0.75, 0.5, 0.25]
## Per phase: how much faster her own casts wind up, and cooldown speed.
const PHASE_CAST_SPEED: Array[float] = [1.0, 1.2, 1.2, 1.4, 1.4]
const PHASE_COOLDOWN_SCALE: Array[float] = [1.0, 0.8, 0.8, 0.65, 0.65]

const FROST := Color(0.6, 0.88, 1.0)
const FIRE := Color(1.0, 0.45, 0.12)
const STORM := Color(0.7, 0.75, 1.0)

const SPEAR_COUNT := 8
const SPEAR_LINE_LENGTH := 14.0

## Lightning Bolt: gaps after each warning strike, the big bolt's delay and
## size, how long a warning strike shows before it lands.
const BOLT_GAPS: Array[float] = [1.5, 1.0]
const BOLT_GAPS_UPGRADED: Array[float] = [1.0]
const BIG_BOLT_DELAY := 0.75
const SMALL_BOLT_RADIUS := 1.8
const SMALL_BOLT_WARNING := 0.45
const BIG_BOLT_RADIUS := 3.6
const BIG_BOLT_DAMAGE := 2.4

const ROOT_LINES := 5
const ROOT_FAN_DEG := 40.0
const ROOT_WAVE_GAP := 0.6

const SWEEP_RADIUS := 5.0
const SWEEP_HALF_ANGLE := 70.0
const THRUST_LENGTH := 8.0
const THRUST_WIDTH := 2.0

const EARTH_WHEEL_COUNTS: Array[int] = [7, 14]
const FINAL_EARTH_WHEEL_COUNTS: Array[int] = [14, 21]
const GOLEM_COUNT := 2
const GOLEM_SCENE := "res://entities/enemies/aurelia/FireGolem.tscn"
const GOLEM_RING := 13.0
const LIVING_BOMB_COOLDOWN_MSEC := 5000
const LIVING_BOMB_DAMAGE := 1.8
const POT_TICK_SHARE := 0.25

## Spells upgraded so far (Spell values).
var upgraded: Array[int] = []
var amaterasu_called := false
var _arena: AureliaArena
var _golems: Array[Node] = []
var _last_bomb_msec := -LIVING_BOMB_COOLDOWN_MSEC

func _ready() -> void:
	super._ready()
	display_name = DISPLAY_NAME
	# Her blows are her two melee moves; the stock swing never fires.
	var melee := get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	if melee:
		melee.attack_range = 0.0
		melee.damage_type = Constants.DamageType.COLD
	if boss_brain:
		boss_brain.phase_cooldown_scale = PHASE_COOLDOWN_SCALE
		boss_brain.phase_changed.connect(_on_phase_changed)
	health.died.connect(_on_aurelia_died)
	tree_exiting.connect(_free_golems)

## Aurelia and her golems fight at this level, above the other Pinnacle
## bosses' Area Level (90): she's the final boss. 0 uses the Area Level.
static var boss_level := 95

func _apply_definition() -> void:
	super._apply_definition()
	apply_boss_level(self)

## Re-derives an enemy's Life and hit damage at boss_level (no-op at 0).
static func apply_boss_level(enemy: Enemy) -> void:
	if boss_level <= 0 or enemy.definition == null:
		return
	enemy.level = boss_level
	enemy.health.max_health = enemy._level_scaled_health(boss_level)
	enemy.health.current_health = enemy.health.max_health
	enemy._reset_ward()
	var melee := enemy.get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	if melee:
		melee.damage_amount = enemy._level_scaled_damage(boss_level)

func pinnacle_life() -> float:
	return 30_000_000.0 if Dev.enabled else 71_000_000.0

func phase_thresholds() -> Array[float]:
	return PHASES

func abilities() -> Array:
	return [
		{"id": "ice_spears", "display_name": "Ice Spears", "kind": BossAbility.Kind.CUSTOM, "cooldown": 7.0, "telegraph": 0.9, "max_range": 60.0, "damage_mult": 0.8, "damage_type": Constants.DamageType.COLD},
		{"id": "fire_wall", "display_name": "Fire Wall", "kind": BossAbility.Kind.CUSTOM, "cooldown": 9.0, "telegraph": 1.0, "max_range": 60.0, "damage_mult": 1.3, "damage_type": Constants.DamageType.FIRE},
		{"id": "lightning_bolt", "display_name": "Lightning Bolt", "kind": BossAbility.Kind.CUSTOM, "cooldown": 11.0, "telegraph": 0.7, "max_range": 60.0, "damage_mult": 0.5, "damage_type": Constants.DamageType.LIGHTNING},
		{"id": "entangling_roots", "display_name": "Entangling Roots", "kind": BossAbility.Kind.CUSTOM, "cooldown": 10.0, "telegraph": 0.9, "max_range": 60.0, "damage_mult": 0.6, "damage_type": Constants.DamageType.KINETIC},
		{"id": "staff_sweep", "display_name": "Staff Sweep", "kind": BossAbility.Kind.CUSTOM, "cooldown": 4.0, "telegraph": 0.7, "max_range": SWEEP_RADIUS, "damage_mult": 1.2, "damage_type": Constants.DamageType.COLD, "weight": 2.5},
		{"id": "searing_thrust", "display_name": "Searing Thrust", "kind": BossAbility.Kind.CUSTOM, "cooldown": 5.0, "telegraph": 0.8, "max_range": THRUST_LENGTH - 1.0, "damage_mult": 1.4, "damage_type": Constants.DamageType.FIRE, "weight": 2.0},
		{"id": "earth_wheel", "display_name": "Earth Wheel", "kind": BossAbility.Kind.CUSTOM, "cooldown": 9999.0, "min_phase": 3, "weight": 0.0, "max_range": 999.0},
		{"id": "fire_golems", "display_name": "Fire Golems", "kind": BossAbility.Kind.CUSTOM, "cooldown": 9999.0, "min_phase": 4, "weight": 0.0, "max_range": 999.0},
		{"id": "amaterasu", "display_name": "Amaterasu", "kind": BossAbility.Kind.CUSTOM, "cooldown": 9999.0, "min_phase": 5, "weight": 0.0, "max_range": 999.0},
	]

## Phase 2 opens with her star of ice: the fight has begun.
func phase_openers() -> Dictionary:
	return {2: "ice_spears", 3: "earth_wheel", 4: "fire_golems", 5: "amaterasu"}

func arena() -> AureliaArena:
	if not is_instance_valid(_arena) and is_inside_tree():
		_arena = get_tree().get_first_node_in_group("aurelia_arena") as AureliaArena
	return _arena

func phase() -> int:
	return boss_brain.phase if boss_brain else 1

func get_cast_speed_multiplier() -> float:
	return super.get_cast_speed_multiplier() * PHASE_CAST_SPEED[clampi(phase() - 1, 0, PHASE_CAST_SPEED.size() - 1)]

## A wind-up of `seconds` at her current cast speed.
func _t(seconds: float) -> float:
	return seconds / maxf(get_cast_speed_multiplier(), 0.01)

func is_upgraded(spell: int) -> bool:
	return upgraded.has(spell)

## ---- Combo brain ---------------------------------------------------------------

## Weight on a spell that completes a combo on the player's ailments, and on
## one that sets a combo up while they carry none.
const COMBO_WEIGHT := 6.0
const SETUP_WEIGHT := 1.8
const COMBO_FINISHERS := {
	"entangle": ["searing_thrust", "fire_wall"],
	"chill": ["lightning_bolt"],
	"freeze": ["lightning_bolt"],
	"ignite": ["ice_spears", "staff_sweep"],
}
const COMBO_SETUPS := ["entangling_roots", "ice_spears", "fire_wall"]

## When she last answered an Entangle (once per Entangle).
var _answered_entangle_msec := -100000

func ability_weight(ability: BossAbility) -> float:
	var p := _target_player()
	if p == null or p.status_effects == null:
		return 1.0
	var carrying := false
	for ailment in COMBO_FINISHERS:
		if p.status_effects.has_effect(ailment):
			carrying = true
			if COMBO_FINISHERS[ailment].has(ability.id):
				return COMBO_WEIGHT
	return SETUP_WEIGHT if not carrying and COMBO_SETUPS.has(ability.id) else 1.0

## An Entangled player is burned next: Searing Thrust if they're in reach,
## Fire Wall otherwise, whatever its cooldown.
func urgent_ability(distance: float) -> BossAbility:
	var p := _target_player()
	if p == null or p.status_effects == null or not p.status_effects.has_effect("entangle"):
		return null
	if Time.get_ticks_msec() - _answered_entangle_msec < AureliaAilments.ENTANGLE_SEC * 1000.0:
		return null
	if arena() and arena().earth_wheel_active:
		return null
	_answered_entangle_msec = Time.get_ticks_msec()
	return boss_brain.find("searing_thrust" if distance <= THRUST_LENGTH - 1.0 else "fire_wall")

## ---- Phases -------------------------------------------------------------------

func _on_phase_changed(p: int) -> void:
	var a := arena()
	if a:
		a.clear_fire_pots()
	match p:
		2, 3, 4:
			_upgrade_random()
		5:
			for spell in SPELLS:
				if not is_upgraded(spell):
					upgraded.append(spell)

func _upgrade_random() -> void:
	var left: Array[int] = []
	for spell in SPELLS:
		if not is_upgraded(spell):
			left.append(spell)
	if left.is_empty():
		return
	var pick: int = left.pick_random()
	upgraded.append(pick)
	if arena():
		arena().announce(UPGRADE_CALLOUTS[pick], Color(0.85, 0.9, 1.0), 2.2, 30)

## ---- Casting ------------------------------------------------------------------

func cast_custom(ability: BossAbility) -> void:
	match ability.id:
		"ice_spears":
			await _ice_spears(ability)
		"fire_wall":
			await _fire_wall(ability)
		"lightning_bolt":
			await _lightning_bolt(ability)
		"entangling_roots":
			await _entangling_roots(ability)
		"staff_sweep":
			await _staff_sweep(ability)
		"searing_thrust":
			await _searing_thrust(ability)
		"earth_wheel":
			await _earth_wheel(EARTH_WHEEL_COUNTS.pick_random())
		"fire_golems":
			await _summon_golems()
		"amaterasu":
			await _earth_wheel(FINAL_EARTH_WHEEL_COUNTS.pick_random())
			if health.is_alive():
				await _amaterasu()
			if health.is_alive():
				await _summon_golems()
		_:
			await get_tree().process_frame

func _target_player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _forward() -> Vector3:
	var p := _target_player()
	var to := (p.global_position - global_position) if p else -global_transform.basis.z
	to.y = 0.0
	return to.normalized() if to.length() > 0.05 else Vector3.FORWARD

func _floor_y() -> float:
	return arena().global_position.y if arena() else global_position.y

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout

func _damage(ability: BossAbility, mult: float = 1.0) -> float:
	return roll_crit(get_ability_base_damage() * ability.damage_mult * mult)

## Eight icicles in a star, one aimed at you; the lines show their paths.
func _ice_spears(ability: BossAbility) -> void:
	var t := _t(ability.telegraph)
	begin_attack_telegraph(t)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.COLD, t, false)
	AureliaSfx.play("cast", get_cast_origin(), -2.0)
	var origin := Vector3(global_position.x, _floor_y(), global_position.z)
	var aim := _forward()
	var dirs: Array[Vector3] = []
	for i in SPEAR_COUNT:
		dirs.append(aim.rotated(Vector3.UP, TAU * i / SPEAR_COUNT))
		BossTelegraph.line(get_parent(), origin + dirs[i] * 1.0, dirs[i], SPEAR_LINE_LENGTH, 0.7, t, FROST)
	SpellCastFx.mist_ring(get_parent(), origin, 2.5, FROST)
	await _wait(t)
	if not health.is_alive():
		return
	var track := is_upgraded(Spell.ICE_SPEARS)
	for dir in dirs:
		AureliaIcicle.fire(get_parent(), origin, dir, _damage(ability), self, track)
	SpellFx.shards(get_parent(), get_cast_origin(), FROST, 18, Vector2(3, 6), Vector2(0.06, 0.14), 0.6, 180.0)
	SpellFx.flash(get_parent(), get_cast_origin(), FROST, 3.0, 0.25)
	SpellFx.shockwave(get_parent(), origin + Vector3.UP * 0.05, 4.0, FROST, 0.3)
	AureliaSfx.play("spears_cast", origin, 2.0)
	AureliaSfx.play("spears_launch", origin, 0.0)

## A quarter circle of fire rolling out at you; upgraded, it drops fire pots.
func _fire_wall(ability: BossAbility) -> void:
	var t := _t(ability.telegraph)
	begin_attack_telegraph(t)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.FIRE, t, false)
	AureliaSfx.play("cast", get_cast_origin(), -2.0)
	var origin := Vector3(global_position.x, _floor_y(), global_position.z)
	var aim := _forward()
	var gap := randf_range(-AureliaFireWall.GAP_RANGE, AureliaFireWall.GAP_RANGE)
	# The two edges of the quarter it will sweep.
	for side in [-1.0, 1.0]:
		BossTelegraph.line(get_parent(), origin, aim.rotated(Vector3.UP, side * PI / 4.0), 10.0, 0.5, t, FIRE)
	BossTelegraph.line(get_parent(), origin, aim.rotated(Vector3.UP, gap), 10.0, AureliaFireWall.GAP_WIDTH, t, Color(1.0, 0.85, 0.5, 0.6))
	await _wait(t)
	if not health.is_alive():
		return
	AureliaFireWall.cast(get_parent(), origin, aim, _damage(ability), self, gap)
	SpellFx.flash(get_parent(), origin + aim * 1.5 + Vector3.UP, FIRE, 4.0, 0.3)
	SpellFx.light_pop(get_parent(), origin + aim * 2.0 + Vector3.UP * 1.5, FIRE, 3.5, 7.0, 0.5)
	AureliaSfx.play("fire_wall_cast", origin, 4.0)
	AureliaSfx.play("fire_wall_roll", origin + aim * 3.0, 0.0, 0.9)
	if is_upgraded(Spell.FIRE_WALL) and arena():
		var pots := randi_range(1, 2)
		for i in pots:
			var a := randf_range(-PI / 4.0 + 0.15, PI / 4.0 - 0.15)
			# Keep pots out of the gap.
			if absf(a - gap) < 0.18:
				a = gap + 0.18 * signf(a - gap if a != gap else 1.0)
			var r := randf_range(6.0, 14.0)
			var spot := origin + aim.rotated(Vector3.UP, a) * r
			var local := arena().to_local(spot)
			if Vector2(local.x, local.z).length() > AureliaArena.RADIUS - 2.0:
				spot = arena().to_global(Vector3(local.x, 0, local.z).normalized() * (AureliaArena.RADIUS - 3.0))
			# Each pot catches as the wall passes over its spot.
			get_tree().create_timer(r / AureliaFireWall.SPEED, false).timeout.connect(func():
				if health.is_alive() and arena():
					arena().add_fire_pot(spot, get_ability_base_damage() * POT_TICK_SHARE))

## Warning strikes on you, then the big bolt where the last one landed.
func _lightning_bolt(ability: BossAbility) -> void:
	var gaps: Array[float] = BOLT_GAPS_UPGRADED if is_upgraded(Spell.LIGHTNING) else BOLT_GAPS
	var t := _t(ability.telegraph)
	var total := t + SMALL_BOLT_WARNING + BIG_BOLT_DELAY
	for g in gaps:
		total += g
	begin_channel(total)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.LIGHTNING, t, false)
	AureliaSfx.play("cast", get_cast_origin(), -2.0)
	await _wait(maxf(t - SMALL_BOLT_WARNING, 0.05))
	var spot := Vector3.ZERO
	for i in gaps.size() + 1:
		if not health.is_alive():
			return
		var p := _target_player()
		spot = Vector3(p.global_position.x, _floor_y(), p.global_position.z) if p else global_position
		BossTelegraph.circle(get_parent(), spot, SMALL_BOLT_RADIUS, SMALL_BOLT_WARNING, STORM)
		await _wait(SMALL_BOLT_WARNING)
		if not health.is_alive():
			return
		_small_bolt(spot, ability)
		if i < gaps.size():
			await _wait(maxf(gaps[i] - SMALL_BOLT_WARNING, 0.05))
	# The big one comes down where the last warning struck.
	BossTelegraph.circle(get_parent(), spot, BIG_BOLT_RADIUS, BIG_BOLT_DELAY, Color(0.85, 0.85, 1.0))
	SpellFx.ground_mark(get_parent(), spot, BIG_BOLT_RADIUS, SpellFx.Mark.CRACKS, Color(0.1, 0.1, 0.14, 0.4), STORM, BIG_BOLT_DELAY + 0.5, BIG_BOLT_DELAY)
	await _wait(BIG_BOLT_DELAY)
	if health.is_alive():
		_big_bolt(spot, ability)

func _small_bolt(spot: Vector3, ability: BossAbility) -> void:
	var parent := get_parent()
	LightningArc.spawn(parent, spot + Vector3(randf_range(-1, 1), 14.0, randf_range(-1, 1)), spot, STORM, 1.2)
	SpellFx.burst(parent, spot + Vector3.UP * 0.3, STORM, 14, Vector2(3, 7), 0.3, Vector2(0.04, 0.1), 140.0, -8.0)
	SpellFx.light_pop(parent, spot + Vector3.UP * 1.5, STORM, 2.5, 5.0, 0.25)
	AureliaSfx.play("bolt_small", spot, 0.0)
	_hit_circle(spot, SMALL_BOLT_RADIUS, _damage(ability), Constants.DamageType.LIGHTNING)

func _big_bolt(spot: Vector3, ability: BossAbility) -> void:
	var parent := get_parent()
	for i in 3:
		LightningArc.spawn(parent, spot + Vector3(randf_range(-2, 2), 18.0, randf_range(-2, 2)), spot + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)), Color(0.85, 0.88, 1.0), 3.0, true, 4)
	BossFx.impact(parent, spot, BIG_BOLT_RADIUS, Constants.DamageType.LIGHTNING)
	SpellFx.flash(parent, spot + Vector3.UP * 1.5, Color(0.9, 0.92, 1.0), 7.0, 0.3)
	AureliaSfx.play("bolt_big", spot, 4.0)
	AureliaSfx.play("bolt_big_thunder", spot, 2.0, 0.85)
	_hit_circle(spot, BIG_BOLT_RADIUS, _damage(ability, BIG_BOLT_DAMAGE / ability.damage_mult), Constants.DamageType.LIGHTNING, "shock")

func _hit_circle(center: Vector3, radius: float, amount: float, type: int, status: String = "") -> void:
	var p := _target_player()
	if p == null or not p.health.is_alive() or absf(p.global_position.y - center.y) > 3.0:
		return
	if Vector2(p.global_position.x - center.x, p.global_position.z - center.z).length() <= radius + 0.4:
		AureliaAilments.hit(p, amount, type, self)
		if status != "" and p.status_effects:
			p.status_effects.apply_effect(status, self, amount)

## Lines of roots fanning out toward you; upgraded, a second wave fills
## the gaps between the first.
func _entangling_roots(ability: BossAbility) -> void:
	var t := _t(ability.telegraph)
	begin_attack_telegraph(t)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.KINETIC, t, false)
	AureliaSfx.play("roots_cast", get_cast_origin(), 0.0)
	var origin := Vector3(global_position.x, _floor_y(), global_position.z)
	var aim := _forward()
	var dirs: Array[Vector3] = []
	for i in ROOT_LINES:
		dirs.append(aim.rotated(Vector3.UP, deg_to_rad(lerpf(-ROOT_FAN_DEG, ROOT_FAN_DEG, float(i) / (ROOT_LINES - 1)))))
	for dir in dirs:
		BossTelegraph.line(get_parent(), origin, dir, AureliaRoots.LENGTH, AureliaRoots.WIDTH, t, AureliaAilments.ENTANGLE_COLOR)
	await _wait(t)
	if not health.is_alive():
		return
	var shared := {"hit": false}
	for dir in dirs:
		AureliaRoots.send(get_parent(), origin, dir, _damage(ability), self, shared)
	SpellFx.shockwave(get_parent(), origin + Vector3.UP * 0.05, 3.0, AureliaAilments.ENTANGLE_COLOR, 0.3)
	AureliaSfx.play("roots_erupt", origin, 2.0)
	if not is_upgraded(Spell.ROOTS):
		return
	# The second wave: between the first lines, a moment later.
	var half := deg_to_rad(ROOT_FAN_DEG) / (ROOT_LINES - 1)
	var second: Array[Vector3] = []
	for i in ROOT_LINES - 1:
		second.append(dirs[i].rotated(Vector3.UP, half))
	for dir in second:
		BossTelegraph.line(get_parent(), origin, dir, AureliaRoots.LENGTH, AureliaRoots.WIDTH, ROOT_WAVE_GAP, AureliaAilments.ENTANGLE_COLOR)
	await _wait(ROOT_WAVE_GAP)
	if not health.is_alive():
		return
	var shared2 := {"hit": false}
	for dir in second:
		AureliaRoots.send(get_parent(), origin, dir, _damage(ability), self, shared2)
	AureliaSfx.play("roots_erupt", origin, 0.0, 0.9)

## Melee: a wide frosted sweep of the staff round her front.
func _staff_sweep(ability: BossAbility) -> void:
	var t := _t(ability.telegraph)
	var origin := global_position
	begin_attack_telegraph(t)
	BossTelegraph.circle(get_parent(), origin, SWEEP_RADIUS, t, FROST)
	await _wait(t)
	if not health.is_alive():
		return
	var facing := _forward()
	SpellFx.sweep(get_parent(), origin, facing, SWEEP_RADIUS + 0.5, SWEEP_HALF_ANGLE, FROST, 0.22, 1.0, 1.1)
	SpellFx.shards(get_parent(), origin + facing * SWEEP_RADIUS * 0.6 + Vector3.UP * 0.8, FROST, 16, Vector2(2, 5), Vector2(0.05, 0.13), 0.6, 80.0)
	SpellCastFx.mist_ring(get_parent(), origin, SWEEP_RADIUS * 0.8, FROST)
	AureliaSfx.play("sweep", origin, 2.0)
	var p := _target_player()
	if p == null:
		return
	var rel := p.global_position - origin
	rel.y = 0.0
	if rel.length() <= SWEEP_RADIUS + 0.4 and (rel.length() < 0.6 or rad_to_deg(facing.angle_to(rel.normalized())) <= SWEEP_HALF_ANGLE):
		AureliaAilments.hit(p, _damage(ability), Constants.DamageType.COLD, self, Player.HitKind.ATTACK, true)
		if p.status_effects:
			p.status_effects.apply_effect("chill", self, _damage(ability))

## Melee: the staff driven forward in a jet of flame.
func _searing_thrust(ability: BossAbility) -> void:
	var t := _t(ability.telegraph)
	var origin := global_position
	var dir := _forward()
	begin_attack_telegraph(t)
	BossTelegraph.line(get_parent(), origin, dir, THRUST_LENGTH, THRUST_WIDTH, t, FIRE)
	await _wait(t)
	if not health.is_alive():
		return
	var jet := SpellFx.emitter(get_parent(), 70, 0.45)
	jet.global_position = origin + Vector3.UP * 1.1
	jet.one_shot = true
	jet.explosiveness = 0.85
	jet.direction = dir
	jet.spread = 7.0
	jet.initial_velocity_min = THRUST_LENGTH * 2.2
	jet.initial_velocity_max = THRUST_LENGTH * 3.0
	jet.damping_min = THRUST_LENGTH * 3.5
	jet.damping_max = THRUST_LENGTH * 4.5
	jet.scale_amount_min = 0.2
	jet.scale_amount_max = 0.45
	jet.color_ramp = SpellFx.ramp(Color(1.0, 0.9, 0.6, 1.0), Color(FIRE, 0.8), 0.2)
	jet.mesh = SpellFx.glow_quad()
	jet.emitting = true
	SpellFx.free_after(jet, 1.0)
	SpellFx.ground_mark(get_parent(), origin + dir * THRUST_LENGTH * 0.6, 1.8, SpellFx.Mark.SCORCH, Color(0.08, 0.05, 0.04, 0.8), FIRE, 3.0, 1.0)
	SpellFx.light_pop(get_parent(), origin + dir * 3.0 + Vector3.UP * 1.2, FIRE, 3.0, 6.0, 0.3)
	AureliaSfx.play("thrust", origin + dir * 3.0, 2.0)
	var p := _target_player()
	if p == null:
		return
	var rel := p.global_position - origin
	rel.y = 0.0
	var along := rel.dot(dir)
	if along >= 0.0 and along <= THRUST_LENGTH and (rel - dir * along).length() <= THRUST_WIDTH * 0.5 + 0.4:
		AureliaAilments.hit(p, _damage(ability), Constants.DamageType.FIRE, self, Player.HitKind.ATTACK, true)

## ---- Earth Wheel, golems, Amaterasu -------------------------------------------

## She blinks to the hub and turns the wheel; immune until it stops.
func _earth_wheel(count: int) -> void:
	var a := arena()
	if a == null:
		await get_tree().process_frame
		return
	invulnerable = true
	var centre := a.global_position + Vector3.UP * 0.05
	SpellFx.flash(get_parent(), get_cast_origin(), Color(0.95, 0.75, 0.45), 3.0, 0.25)
	SmokePuff.spawn(get_parent(), global_position, 1.0, Color(0.5, 0.42, 0.35))
	global_position = centre
	SpellFx.flash(get_parent(), get_cast_origin(), Color(0.95, 0.75, 0.45), 3.0, 0.25)
	SpellFx.shockwave(get_parent(), centre, AureliaArena.HUB_RADIUS * 2.0, Color(0.95, 0.7, 0.4), 0.5)
	AureliaSfx.play("quake_wave", centre, 2.0, 0.9)
	a.announce("Earth Wheel", Color(1.0, 0.8, 0.5), 1.6, 40)
	var p := _target_player()
	var angle := 0.0
	if p:
		var local := a.to_local(p.global_position)
		angle = atan2(local.x, local.z)
	begin_channel(AureliaArena.EARTH_WHEEL_FIRST_WARNING + AureliaArena.EARTH_WHEEL_WARNING * (count - 1))
	await a.earth_wheel(count, angle)
	invulnerable = false

func _summon_golems() -> void:
	_golems = _golems.filter(func(g): return is_instance_valid(g) and g.health.is_alive())
	var needed := GOLEM_COUNT - _golems.size()
	if needed <= 0:
		await get_tree().process_frame
		return
	var t := _t(1.2)
	begin_channel(t)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.FIRE, t, false)
	AureliaSfx.play("cast", get_cast_origin(), -2.0)
	var centre := arena().global_position if arena() else global_position
	var p := _target_player()
	var base := randf() * TAU
	if p:
		var local := p.global_position - centre
		base = atan2(local.x, local.z) + PI / 2.0
	var spots: Array[Vector3] = []
	for i in needed:
		var a := base + PI * i
		spots.append(centre + Vector3(sin(a), 0, cos(a)) * GOLEM_RING)
		BossTelegraph.circle(get_parent(), spots[i], 2.0, t, FIRE)
	await _wait(t)
	if not health.is_alive():
		return
	AureliaSfx.play("golem_summon", global_position, 2.0)
	for spot in spots:
		BossFx.summon_gate(get_parent(), spot, Constants.DamageType.FIRE)
		var golem: FireGolem = (load(GOLEM_SCENE) as PackedScene).instantiate()
		get_parent().add_child(golem)
		golem.global_position = spot + Vector3.UP * 0.1
		golem.player_knocked_up.connect(_on_player_knocked_up)
		_golems.append(golem)

func _amaterasu() -> void:
	var a := arena()
	if a == null:
		return
	amaterasu_called = true
	var t := _t(1.6)
	begin_channel(t)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.FIRE, t, false)
	AureliaSfx.play("cast", get_cast_origin(), -2.0)
	a.announce("Amaterasu", Color(0.85, 0.55, 1.0), 2.4, 72)
	AureliaSfx.play("amaterasu_cast", global_position, 4.0)
	await _wait(t)
	if not health.is_alive():
		return
	SpellFx.flash(get_parent(), get_cast_origin(), Color(0.4, 0.05, 0.5), 6.0, 0.4)
	AureliaSfx.play("amaterasu_ignite", global_position, 4.0, 0.8)
	a.start_amaterasu()

## A golem threw you up: she plants a Living Bomb (phase 5, 5s cooldown).
func _on_player_knocked_up(_golem: FireGolem, p: Player) -> void:
	if phase() < 5 or not health.is_alive() or not is_instance_valid(p):
		return
	if Time.get_ticks_msec() - _last_bomb_msec < LIVING_BOMB_COOLDOWN_MSEC:
		return
	_last_bomb_msec = Time.get_ticks_msec()
	# A seed of fire flung from her hand into the player.
	var from := get_cast_origin()
	var ember := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.8
	ember.mesh = quad
	var mat := SpellFx.glow_material(FIRE, true, BaseMaterial3D.BILLBOARD_ENABLED)
	mat.vertex_color_use_as_albedo = false
	ember.material_override = mat
	ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(ember)
	ember.global_position = from
	SpellFx.flash(get_parent(), from, FIRE, 2.0, 0.2)
	AureliaSfx.play("bomb_plant", from, 0.0)
	var tween := ember.create_tween()
	tween.tween_method(func(f: float):
		if is_instance_valid(p):
			ember.global_position = from.lerp(p.global_position + Vector3.UP, f) + Vector3.UP * sin(f * PI) * 2.0, 0.0, 1.0, 0.3)
	tween.tween_callback(func():
		ember.queue_free()
		if is_instance_valid(p) and p.health.is_alive() and health.is_alive():
			LivingBomb.plant(p, roll_crit(get_ability_base_damage() * LIVING_BOMB_DAMAGE), self))

func living_golems() -> Array[Node]:
	_golems = _golems.filter(func(g): return is_instance_valid(g) and g.health.is_alive())
	return _golems

func _free_golems() -> void:
	for g in _golems:
		if is_instance_valid(g):
			g.queue_free()

func _on_aurelia_died() -> void:
	for g in _golems:
		if is_instance_valid(g) and g.health.is_alive():
			g.health.apply_damage(g.health.current_health + 1.0)
	for bomb in get_tree().get_nodes_in_group("living_bomb"):
		bomb.queue_free()
