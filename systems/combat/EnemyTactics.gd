class_name EnemyTactics
extends RefCounted
## Pack positioning round the player, recomputed a few times a second for
## every engaged enemy (Enemy.takes_formation()):
## - melee units take evenly spaced angles round the player, keeping their
##   current order so nobody crosses through the pack - a pack surrounds
##   instead of queueing on one side;
## - ranged units fan out across their own arc, and when a bulky melee ally
##   is nearer the player they stand behind it, just far enough off its line
##   that the shot clears its body.
## Results land on Enemy.tactic_angle / Enemy.tactic_cover; angles use
## atan2(x, z) round the player (direction = (sin a, 0, cos a)).

## Factions that use pack tactics unless EnemyDefinition.tactics says otherwise.
const TACTICAL_FACTIONS := ["directorate", "karvis_legion", "synod"]
const UPDATE_FRAMES := 6
const ENGAGE_RADIUS := 24.0
## Melee units nearer the player than this join the ring.
const MELEE_RING_RANGE := 10.0
## Metres of arc between neighbouring shooters.
const RANGED_SPACING := 5.0
## The whole shooter fan stays inside this arc.
const RANGED_MAX_ARC := 4.2
## A screen this close to the shooter can cover it.
const COVER_SEARCH := 10.0
const COVER_HEALTH_RATIO := 1.6
const COVER_BODY_RADIUS := 0.62
const BULKY_ARCHETYPES := ["heavy", "elite"]
## Gap left between the shot line and the screen's body.
const COVER_MARGIN := 0.55
## A screen this tight to the player would need the shooter too far round.
const COVER_MAX_ANGLE := 1.0

static var _frame: int = -1000

static func update(player: Player, tree: SceneTree) -> void:
	var frame := Engine.get_physics_frames()
	if frame >= _frame and frame - _frame < UPDATE_FRAMES:
		return
	_frame = frame
	var centre := player.global_position
	var ring: Array[Enemy] = []
	var screens: Array[Enemy] = []
	var ranged: Array[Enemy] = []
	for node in tree.get_nodes_in_group("enemy"):
		var e := node as Enemy
		if e == null:
			continue
		e.tactic_angle = NAN
		e.tactic_cover = null
		if not e.takes_formation():
			continue
		var d := Enemy._flat(e.global_position - centre).length()
		if d > ENGAGE_RADIUS or d < 0.05:
			continue
		if e.is_ranged_unit():
			ranged.append(e)
		else:
			screens.append(e)
			if d <= MELEE_RING_RANGE:
				ring.append(e)
	if ring.size() >= 2:
		_spread(ring, centre, TAU / ring.size())
	if ranged.is_empty():
		return
	if ranged.size() >= 2:
		var reach := 0.0
		for e in ranged:
			reach += maxf(e.stop_distance, 4.0)
		var step := minf(RANGED_SPACING / (reach / ranged.size()), RANGED_MAX_ARC / (ranged.size() - 1))
		_spread(ranged, centre, step)
	var used: Dictionary = {}
	for e in ranged:
		_take_cover(e, screens, centre, used)

static func angle_of(point: Vector3, centre: Vector3) -> float:
	return atan2(point.x - centre.x, point.z - centre.z)

static func direction(angle: float) -> Vector3:
	return Vector3(sin(angle), 0.0, cos(angle))

## Even spacing of `step` radians, in the units' current angular order,
## rotated to the placement that moves them least.
static func _spread(units: Array[Enemy], centre: Vector3, step: float) -> void:
	var n := units.size()
	var sx := 0.0
	var sz := 0.0
	for e in units:
		var a := angle_of(e.global_position, centre)
		sx += sin(a)
		sz += cos(a)
	var mean := atan2(sx, sz) if absf(sx) + absf(sz) > 0.001 else 0.0
	var rel: Array = []
	for e in units:
		rel.append([wrapf(angle_of(e.global_position, centre) - mean, -PI, PI), e])
	rel.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var ox := 0.0
	var oz := 0.0
	for i in n:
		var slot := (i - (n - 1) * 0.5) * step
		var off := float(rel[i][0]) - slot
		ox += sin(off)
		oz += cos(off)
	var offset := atan2(ox, oz)
	for i in n:
		var e := rel[i][1] as Enemy
		e.tactic_angle = wrapf(mean + offset + (i - (n - 1) * 0.5) * step, -PI, PI)

## Stands a shooter behind the nearest bulky melee ally that is closer to the
## player, offset to the side its fan slot already leans toward.
## Later shooters behind the same screen alternate sides and step wider.
static func _take_cover(shooter: Enemy, screens: Array[Enemy], centre: Vector3, used: Dictionary) -> void:
	var own_range := Enemy._flat(shooter.global_position - centre).length()
	var stand := clampf(own_range, shooter.retreat_distance + 0.5, maxf(shooter.stop_distance, shooter.retreat_distance + 0.5))
	var best: Enemy = null
	var best_d := COVER_SEARCH
	for s in screens:
		if not _is_bulky(s, shooter):
			continue
		var s_range := Enemy._flat(s.global_position - centre).length()
		if s_range > stand - 2.0:
			continue
		var d := Enemy._flat(s.global_position - shooter.global_position).length()
		if d < best_d:
			best_d = d
			best = s
	if best == null:
		return
	var s_range := maxf(Enemy._flat(best.global_position - centre).length(), 0.5)
	var clear := (best.body_radius + COVER_MARGIN) / s_range
	if clear >= 1.0:
		return
	var off := asin(clear) + 0.08
	if off > COVER_MAX_ANGLE:
		return
	var s_angle := angle_of(best.global_position, centre)
	var lean := wrapf((shooter.tactic_angle if not is_nan(shooter.tactic_angle) else angle_of(shooter.global_position, centre)) - s_angle, -PI, PI)
	var side := 1.0 if lean > 0.0 or (absf(lean) < 0.001 and shooter.get_instance_id() % 2 == 0) else -1.0
	var taken: int = used.get(best, 0)
	used[best] = taken + 1
	if taken % 2 == 1:
		side = -side
	off += floorf(taken / 2.0) * 0.3
	shooter.tactic_angle = wrapf(s_angle + side * off, -PI, PI)
	shooter.tactic_cover = best

## Heavy/elite archetypes, wide bodies, or much more Life than the shooter
## (rarity counts through max_health).
static func _is_bulky(screen: Enemy, shooter: Enemy) -> bool:
	if screen.definition and screen.definition.archetype_category in BULKY_ARCHETYPES:
		return true
	return screen.body_radius >= COVER_BODY_RADIUS or screen.health.max_health >= shooter.health.max_health * COVER_HEALTH_RATIO
