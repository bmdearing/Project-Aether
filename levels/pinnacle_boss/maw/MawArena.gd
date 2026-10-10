extends Node3D
class_name MawArena
## The Herald of the Maw's arena, built by PinnacleArena in place of the
## crescent: a round floor over the void, with no wall at the edge. Falling
## off kills.
##
##   dais        r 0-6     4 plates, sealed until phase 3 opens the Maw
##   inner ring  r 6-13    8 plates, can crack but never fall
##   outer ring  r 13-22   8 plates, crack and then fall
##   4 Anchor pylons (MawPylon), one per Maw Fragment, at r 17.5
##
## Driven by the boss's BossBrain signals (bind_boss()):
##   - a Void Rift pool that runs out cracks the plates under it,
##   - any ground hit on a cracked outer plate drops it,
##   - phase 3 opens the Maw (the dais falls away), and from then on the
##     Maw eats an outer plate every MAW_BITE_INTERVAL seconds.
## Standing on a cracked plate builds Entropic stacks that hurt more over
## time; stepping off clears them.

const MAW_RADIUS := 6.0
const INNER_RADIUS := 13.0
const OUTER_RADIUS := 22.0
const RING_PLATES := 8
const DAIS_PLATES := 4
const PYLON_RING := 17.5
## Maw Fragment -> where its pylon stands (degrees clockwise from -Z) and its colour.
const PYLONS := [
	{"id": &"maw_fragment_ash", "angle": 0.0, "color": Color(0.95, 0.5, 0.25)},
	{"id": &"maw_fragment_storm", "angle": 90.0, "color": Color(0.95, 0.88, 0.35)},
	{"id": &"maw_fragment_hollow", "angle": 180.0, "color": Color(0.65, 0.35, 0.95)},
	{"id": &"maw_fragment_tide", "angle": 270.0, "color": Color(0.3, 0.62, 1.0)},
]
## The player enters beside the Hollow pylon, the Herald waits across the inner ring.
const PLAYER_SPAWN := Vector3(2.5, 0.1, 15.5)
const BOSS_SPAWN := Vector3(0, 0.05, -9.5)
## On the inner ring, which never falls.
const PORTAL_SPOT := Vector3(0, 0.1, 9.5)
const RESCUE_RADIUS := 9.5

const FALL_DEATH_Y := -8.0
const MAW_OPEN_WARNING := 2.4
const MAW_BITE_INTERVAL := 25.0
const MAW_BITE_WARNING := 3.0
## A cracked plate struck by a ground ability shakes this long, then falls.
const STRIKE_FALL_WARNING := 1.0
## The plates beside a shattered pylon.
const PYLON_FALL_WARNING := 1.5

## Saved pylons soften phase 3: each delays the Maw's first bite and
## weakens its opening Unmaking (Xalatath._on_phase()).
const BITE_DELAY_PER_PYLON := 5.0
const OPENING_WEAKEN_PER_PYLON := 0.12
## Knocked over missing floor, the Herald clings to the lip: stunned and
## taking more damage, then the Maw drags at her before she climbs back.
const CLING_SEC := 4.0
const CLING_DAMAGE_TAKEN := 1.5
const MAW_DRAG_SHARE := 0.06
## Feed the Maw: plates it takes at once, and the next bite's timer after.
const FEED_PLATES := 2
const FEED_NEXT_BITE := 12.0

const ENTROPY_TICK := 0.5
const ENTROPY_STACKS_PER_SEC := 1.0
const ENTROPY_MAX_STACKS := 10.0
## Per stack, per tick, as a share of the player's maximum Life (before Entropic resistance).
const ENTROPY_DAMAGE_PER_STACK := 0.006

var outer_plates: Array[MawPlate] = []
var inner_plates: Array[MawPlate] = []
var dais_plates: Array[MawPlate] = []
var pylons: Array[MawPylon] = []
var boss: Enemy
var maw_open := false
var entropy_stacks := 0.0
var _active := true
var _bite_timer := 0.0
var _entropy_tick := 0.0
var _hot_plate: MawPlate
var _player: Player
var _maw_light: OmniLight3D
var _clinging := false
var _feed_marks: Array[Node] = []

func _ready() -> void:
	add_to_group("maw_arena")
	_build_plates()
	_build_pylons()
	_build_maw()

## Hooks the arena up to the boss's abilities and phases.
func bind_boss(b: Enemy) -> void:
	boss = b
	if b.boss_brain:
		b.boss_brain.ground_struck.connect(func(_a, center, radius): strike_area(center, radius))
		b.boss_brain.hazard_ended.connect(func(_a, center, radius): crack_area(center, radius))
		b.boss_brain.phase_changed.connect(func(p): if p >= 3: open_maw())
	b.health.died.connect(_on_boss_died)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	_check_falls()
	if not _active:
		return
	_tick_entropy(delta)
	if maw_open:
		_bite_timer -= delta
		if _bite_timer <= 0.0:
			_bite_timer = MAW_BITE_INTERVAL
			bite()

## ---- Floor ----------------------------------------------------------------

func all_plates() -> Array[MawPlate]:
	var plates: Array[MawPlate] = []
	plates.append_array(dais_plates)
	plates.append_array(inner_plates)
	plates.append_array(outer_plates)
	return plates

## The plate under a world point, or null over the void or past the edge.
func plate_at(point: Vector3) -> MawPlate:
	var local := to_local(point)
	for plate in all_plates():
		if plate.contains_local(local):
			return plate
	return null

## Plates a ground circle touches (its centre and eight points around it).
func plates_in(center: Vector3, radius: float) -> Array[MawPlate]:
	var found: Array[MawPlate] = []
	var points: Array[Vector3] = [center]
	for i in 8:
		var angle := TAU * i / 8.0
		points.append(center + Vector3(cos(angle), 0, sin(angle)) * radius * 0.75)
	for p in points:
		var plate := plate_at(p)
		if plate and not found.has(plate):
			found.append(plate)
	return found

## A Void Rift running out: the plates under it crack (not the dais).
func crack_area(center: Vector3, radius: float) -> void:
	for plate in plates_in(center, radius):
		if not dais_plates.has(plate):
			plate.crack()

## A ground hit: cracked outer plates under it give way.
func strike_area(center: Vector3, radius: float) -> void:
	for plate in plates_in(center, radius):
		if plate.can_fall and plate.state == MawPlate.State.CRACKED and dais_plates.find(plate) < 0:
			plate.fall(STRIKE_FALL_WARNING)

## Phase 3: the dais shakes, then drops away and leaves the Maw open.
func open_maw() -> void:
	if maw_open:
		return
	maw_open = true
	_bite_timer = MAW_BITE_INTERVAL + BITE_DELAY_PER_PYLON * pylons_standing()
	BossTelegraph.circle(self, global_position, MAW_RADIUS, MAW_OPEN_WARNING, Color(0.55, 0.2, 0.85))
	for plate in dais_plates:
		plate.fall(MAW_OPEN_WARNING)
	var tween := create_tween()
	tween.tween_property(_maw_light, "light_energy", 4.0, MAW_OPEN_WARNING + 1.0)

## The Maw takes one outer plate that's still standing.
func bite() -> MawPlate:
	var standing := outer_plates.filter(func(p: MawPlate): return p.is_solid())
	if standing.is_empty():
		return null
	var plate: MawPlate = standing.pick_random()
	plate.fall(MAW_BITE_WARNING)
	return plate

## How hard the Maw's opening hits: 1.0 with no pylons left, weaker per pylon.
func opening_strength() -> float:
	return 1.0 - OPENING_WEAKEN_PER_PYLON * pylons_standing()

func is_clinging() -> bool:
	return _clinging

## The Herald knocked `distance` along `away`: if the floor there is gone she
## clings to the last solid spot instead and the Maw drags at her. False
## (and nothing happens) when there is floor behind her.
func cling(herald: Enemy, away: Vector3, distance: float) -> bool:
	var target := herald.global_position + away * distance
	var plate := plate_at(target)
	if plate and plate.is_solid():
		return false
	var lip := herald.global_position
	var step := 0.25
	var travelled := 0.0
	while travelled < distance:
		var next := lip + away * step
		var under := plate_at(next)
		if under == null or not under.is_solid():
			break
		lip = next
		travelled += step
	_clinging = true
	herald.global_position = lip
	herald.velocity = Vector3.ZERO
	herald.status_effects.apply_timed_effect("stun", CLING_SEC)
	herald.interrupt_attack()
	BossTelegraph.circle(self, lip, 1.6, CLING_SEC, Color(0.55, 0.2, 0.85))
	var maw_glow := Color(0.65, 0.3, 1.0)
	for i in 4:
		get_tree().create_timer(i * 0.9, false).timeout.connect(func():
			if is_instance_valid(herald) and herald.health.is_alive():
				LightningArc.spawn(self, lip + away * 1.5 + Vector3.DOWN * 2.0, herald.global_position + Vector3.UP, maw_glow))
	get_tree().create_timer(CLING_SEC, false).timeout.connect(_end_cling.bind(herald))
	return true

func _end_cling(herald: Enemy) -> void:
	_clinging = false
	if not is_instance_valid(herald) or not herald.health.is_alive():
		return
	var amount := herald.health.max_health * MAW_DRAG_SHARE
	herald.take_damage(amount, Constants.DamageType.ENTROPIC, true)
	EventBus.damage_dealt.emit(get_tree().get_first_node_in_group("player"), herald, amount, Constants.DamageType.ENTROPIC, true, false)
	if plate_at(herald.global_position) == null:
		herald.global_position = rescue_point(herald.global_position)

## Where the Herald stands to feed the Maw: on the inner ring at the lip,
## on her side of it.
func lip_point(from: Vector3) -> Vector3:
	var local := to_local(from)
	return to_global(MawPlate.direction(MawPlate.angle_of(local)) * (MAW_RADIUS + 1.2) + Vector3(0, 0.05, 0))

## Feed the Maw starting: the plates it will take shake as a warning.
func mark_feed_targets(warning: float) -> Array[MawPlate]:
	var standing := outer_plates.filter(func(p: MawPlate): return p.is_solid())
	standing.shuffle()
	var out: Array[MawPlate] = []
	for p in standing.slice(0, FEED_PLATES):
		out.append(p)
		var center := to_global(p.center_local())
		_feed_marks.append(BossTelegraph.circle(self, center, 3.5, warning, Color(0.55, 0.2, 0.85)))
	return out

func feed(plates: Array[MawPlate]) -> void:
	for p in plates:
		if p.is_solid():
			p.fall(0.6)
	_bite_timer = minf(_bite_timer, FEED_NEXT_BITE)

func cancel_feed(_plates: Array[MawPlate]) -> void:
	for mark in _feed_marks:
		if is_instance_valid(mark):
			mark.queue_free()
	_feed_marks.clear()

func maw_center() -> Vector3:
	return global_position

## A point on the inner ring at the same bearing as `point`.
func rescue_point(point: Vector3) -> Vector3:
	var local := to_local(point)
	return to_global(MawPlate.direction(MawPlate.angle_of(local)) * RESCUE_RADIUS + Vector3(0, 0.2, 0))

## ---- Pylons ---------------------------------------------------------------

func pylons_standing() -> int:
	return pylons.filter(func(p: MawPylon): return p.alive).size()

func is_anchored(point: Vector3) -> bool:
	return pylons.any(func(p: MawPylon): return p.shelters(point))

## A standing pylon within `reach` of pos, ahead along dir.
func pylon_in_path(pos: Vector3, dir: Vector3, reach: float) -> MawPylon:
	for p in pylons:
		if not p.alive:
			continue
		var offset := p.global_position - pos
		offset.y = 0.0
		if offset.length() <= reach + MawPylon.RADIUS and offset.dot(dir) > 0.0:
			return p
	return null

## The standing pylon fewest Mindbenders are already after, nearest first.
func pylon_for_channeler(point: Vector3) -> MawPylon:
	var best: MawPylon
	var best_score := INF
	for p in pylons:
		if not p.alive:
			continue
		var claimed := get_tree().get_nodes_in_group("maw_channel").filter(func(c): return c.pylon == p).size()
		var score := claimed * 1000.0 + p.global_position.distance_to(point)
		if score < best_score:
			best_score = score
			best = p
	return best

func _on_pylon_shattered(pylon: MawPylon) -> void:
	var angle := MawPlate.angle_of(to_local(pylon.global_position))
	for plate in outer_plates:
		var mid := (plate.start_angle + plate.end_angle) * 0.5
		if absf(angle_difference(mid, angle)) < deg_to_rad(30.0):
			plate.fall(PYLON_FALL_WARNING)

## ---- Hazards --------------------------------------------------------------

func _tick_entropy(delta: float) -> void:
	var plate: MawPlate = null
	if is_instance_valid(_player) and _player.health.is_alive() and absf(_player.global_position.y - global_position.y) < 0.8:
		plate = plate_at(_player.global_position)
		if plate and plate.state != MawPlate.State.CRACKED and plate.state != MawPlate.State.FALLING:
			plate = null
	if plate != _hot_plate:
		if _hot_plate:
			_hot_plate.set_heat(0.0)
		_hot_plate = plate
		entropy_stacks = 0.0
		_entropy_tick = ENTROPY_TICK
	if plate == null:
		return
	entropy_stacks = minf(entropy_stacks + ENTROPY_STACKS_PER_SEC * delta, ENTROPY_MAX_STACKS)
	plate.set_heat(entropy_stacks / ENTROPY_MAX_STACKS)
	_entropy_tick -= delta
	if _entropy_tick <= 0.0:
		_entropy_tick += ENTROPY_TICK
		var amount := _player.health.max_health * ENTROPY_DAMAGE_PER_STACK * ceilf(entropy_stacks) * (1.0 - _player.get_dot_mitigation())
		_player.take_damage(amount, Constants.DamageType.ENTROPIC, boss if is_instance_valid(boss) else null, Player.HitKind.DOT)

## Anything that drops below the floor: the player dies, the Herald is
## pulled back onto the inner ring, anything else dies.
func _check_falls() -> void:
	var floor_y := global_position.y
	if is_instance_valid(_player) and _player.health.is_alive() and _player.global_position.y < floor_y + FALL_DEATH_Y:
		_player.health.apply_damage(_player.health.current_health + 1.0)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy.global_position.y >= floor_y + FALL_DEATH_Y or not enemy.health.is_alive():
			continue
		if enemy == boss:
			enemy.velocity = Vector3.ZERO
			enemy.global_position = rescue_point(enemy.global_position)
		else:
			enemy.health.apply_damage(enemy.health.max_health * 10.0)

func _on_boss_died() -> void:
	_active = false
	entropy_stacks = 0.0
	if _hot_plate:
		_hot_plate.set_heat(0.0)
		_hot_plate = null

## ---- Building -------------------------------------------------------------

func _build_plates() -> void:
	var dais_step := TAU / DAIS_PLATES
	for i in DAIS_PLATES:
		dais_plates.append(_add_plate("Dais%d" % i, 0.0, MAW_RADIUS, dais_step * i + dais_step * 0.5, dais_step * (i + 1) + dais_step * 0.5, true))
	var step := TAU / RING_PLATES
	for i in RING_PLATES:
		inner_plates.append(_add_plate("Inner%d" % i, MAW_RADIUS, INNER_RADIUS, step * i, step * (i + 1), false))
		outer_plates.append(_add_plate("Outer%d" % i, INNER_RADIUS, OUTER_RADIUS, step * i, step * (i + 1), true))

func _add_plate(plate_name: String, r_inner: float, r_outer: float, a_start: float, a_end: float, falls: bool) -> MawPlate:
	var plate := MawPlate.new().setup(r_inner, r_outer, a_start, a_end, falls)
	plate.name = plate_name
	add_child(plate)
	return plate

func _build_pylons() -> void:
	for entry in PYLONS:
		var pylon := MawPylon.new()
		pylon.name = "Pylon_" + String(entry["id"]).trim_prefix("maw_fragment_").capitalize()
		pylon.fragment_id = entry["id"]
		pylon.color = entry["color"]
		pylon.position = MawPlate.direction(deg_to_rad(entry["angle"])) * PYLON_RING
		add_child(pylon)
		pylon.shattered.connect(_on_pylon_shattered)
		pylons.append(pylon)

## The Maw itself, deep under the dais: a glowing violet throat that shows
## once the dais falls.
func _build_maw() -> void:
	var throat := MeshInstance3D.new()
	throat.name = "MawThroat"
	var cone := CylinderMesh.new()
	cone.top_radius = MAW_RADIUS * 0.95
	cone.bottom_radius = 0.6
	cone.height = 26.0
	cone.cap_top = false
	cone.radial_segments = 48
	throat.mesh = cone
	throat.position.y = -1.2 - cone.height / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.0, 0.06)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.1, 0.7)
	mat.emission_energy_multiplier = 0.15
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	throat.material_override = mat
	throat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(throat)
	var core := MeshInstance3D.new()
	core.name = "MawCore"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 1.4
	core_mesh.height = 2.8
	core.mesh = core_mesh
	core.position.y = throat.position.y - cone.height / 2.0 + 1.0
	core.material_override = MawPylon._glow_material(Color(0.75, 0.35, 1.0), 4.0)
	add_child(core)
	_maw_light = OmniLight3D.new()
	_maw_light.name = "MawLight"
	_maw_light.light_color = Color(0.6, 0.25, 1.0)
	_maw_light.light_energy = 0.0
	_maw_light.omni_range = 14.0
	_maw_light.position.y = -14.0
	add_child(_maw_light)
