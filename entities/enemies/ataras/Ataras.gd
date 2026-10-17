extends PinnacleBoss
class_name Ataras
## Third Pinnacle boss: Ataras, a jackal-headed lord of the sands (model:
## Anubithas / Anubis by Mr Ogre man and vindorei, Hive Workshop). Kinetic.
## Fought in the SandArena.
##   Slash: his ordinary melee attack.
##   Sandstorm Cuts: two fast slashes around him, then a thrust ahead. The
##   thrust can be parried, and a parry staggers him.
##   Echoes: after Sandstorm Cuts a sand afterimage stays where he stood and
##   replays the cuts from there ECHO_DELAY seconds later, so you dodge what
##   he did then and what he's doing now.
##   Sand Globes: floating globes that can be killed; each fires at you every
##   2 seconds for a little damage.
##   Jackal Fangs: three quick slashes, stepping in with each.
##   Dune Reaver: a spin, then an overhead cleave down a line.
##   Scarab Rush: a dash through you along a marked line, then a backhand.
##   Desert Sweep: a wide, low sweep around him; jump over it.
##   Mirage Barrage: he blinks four times, leaving a sand clone each time;
##   each clone then hurls a stone at you down a marked line.
##   Sand Pillars: at 85%, 65% and 45% he marks the ground under you, and
##   SandPillar.DELAY seconds later a pillar bursts up there and stays.
##   Phase 2 (50%): Shifting Sands - two of the arena's three wedges turn to
##   quicksand for a while (SandArena). Once the sand settles he starts
##   casting Ticking Time: for 4 seconds the ground you cross is marked, and
##   every mark becomes a permanent sand trap. The traps slow him and drain
##   his Composure too (SandArena), so luring him over them opens him up.
##   Phase 3 (35%): Fiery Sun - he blinks to the centre (immune) and raises a
##   sun that slams down; anyone not behind a pillar takes SUN_FIRE_DAMAGE
##   Fire and SUN_KINETIC_DAMAGE Kinetic. The blast brings the pillars down.

const DISPLAY_NAME := "Ataras"
const PHASES: Array[float] = [0.5, 0.35]
const TELL := Color(1.0, 0.6, 0.25)

const PILLAR_AT: Array[float] = [0.85, 0.65, 0.45]
const PILLAR_DAMAGE := 1.6
const PILLAR_RING := Vector2(7.0, 17.0)

const SUN_HEIGHT := 16.0
const SUN_GROW := 2.0
const SUN_HOLD := 2.5
const SUN_FALL := 0.7
const SUN_FIRE_DAMAGE := 7000.0
const SUN_KINETIC_DAMAGE := 5000.0
const SHADE_COLOR := Color(0.35, 0.75, 1.0, 0.55)
const SUN_COLOR := Color(1.0, 0.45, 0.12)

const FANG_HITS := 3
const FANG_RADIUS := 3.6
const FANG_HALF_ANGLE := 70.0
const FANG_TELEGRAPH := 0.3
const FANG_GAP := 0.08
const FANG_STEP := 1.4

const REAVER_RADIUS := 4.4
const REAVER_SPIN_TELEGRAPH := 0.45
const REAVER_CLEAVE_LENGTH := 7.0
const REAVER_CLEAVE_WIDTH := 2.2
const REAVER_CLEAVE_TELEGRAPH := 0.4
const REAVER_CLEAVE_DAMAGE := 1.4

const RUSH_MAX := 12.0
const RUSH_WIDTH := 2.0
const RUSH_TELEGRAPH := 0.5
const RUSH_SEC := 0.22
const RUSH_BACKHAND_TELEGRAPH := 0.3

const SWEEP_RADIUS := 6.5
const SWEEP_HALF_ANGLE := 120.0
const SWEEP_TELEGRAPH := 0.75
## Feet this far above the floor clear the sweep.
const SWEEP_JUMP_CLEARANCE := 0.45

const MIRAGE_JUMPS := 4
const MIRAGE_HOP := 0.4
const MIRAGE_AIM := 0.7
const MIRAGE_STAGGER := 0.35
const MIRAGE_DAMAGE := Vector2(2500.0, 4000.0)
const MIRAGE_LINE := 30.0
const MIRAGE_COLOR := Color(0.95, 0.78, 0.45, 0.6)

const SLASH_RADIUS := 3.8
const SLASH_HALF_ANGLE := 75.0
const SLASH_TELEGRAPH := 0.35
const SLASH_GAP := 0.15
const THRUST_LENGTH := 8.0
const THRUST_WIDTH := 1.8
const THRUST_TELEGRAPH := 0.55
const THRUST_DAMAGE := 1.6

const GLOBE_COUNT := 3
const GLOBE_CAP := 5
const GLOBE_RING := Vector2(8.0, 16.0)
const GLOBE_SCENE := preload("res://entities/enemies/ataras/SandGlobe.tscn")

const TICKING_DURATION := 4.0
const TICKING_INTERVAL := 0.4
const TICKING_RADIUS := 1.6
const TICKING_MARK_COLOR := Color(1.0, 0.75, 0.35, 0.5)

const ECHO_DELAY := 3.0
const ECHO_COLOR := Color(0.95, 0.78, 0.45, 0.35)
const SAND_COLOR := Color(0.95, 0.72, 0.38)
## A parried thrust: Composure lost and how long he reels.
const THRUST_PARRY_STANCE := 50.0
const THRUST_PARRY_STUN := 2.0

var _arena: SandArena
var _globes: Array[Node] = []
## Ticking Time waits until Shifting Sands has run its course.
var _sands_settled := false
var _pillars: Array[SandPillar] = []
var _pillars_cast := 0

func _ready() -> void:
	super._ready()
	display_name = DISPLAY_NAME

func pinnacle_life() -> float:
	return 24_000_000.0 if Dev.enabled else 65_000_000.0

func phase_thresholds() -> Array[float]:
	return PHASES

func abilities() -> Array:
	return [
		{"id": "sandstorm_cuts", "display_name": "Sandstorm Cuts", "kind": BossAbility.Kind.CUSTOM, "cooldown": 7.0, "max_range": 6.0, "damage_mult": 1.1, "weight": 1.5},
		{"id": "jackal_fangs", "display_name": "Jackal Fangs", "kind": BossAbility.Kind.CUSTOM, "cooldown": 6.0, "max_range": 5.0, "damage_mult": 0.8, "weight": 1.2},
		{"id": "dune_reaver", "display_name": "Dune Reaver", "kind": BossAbility.Kind.CUSTOM, "cooldown": 7.0, "max_range": 5.0, "damage_mult": 1.0},
		{"id": "scarab_rush", "display_name": "Scarab Rush", "kind": BossAbility.Kind.CUSTOM, "cooldown": 8.0, "min_range": 3.5, "max_range": 12.0, "damage_mult": 1.2},
		{"id": "desert_sweep", "display_name": "Desert Sweep", "kind": BossAbility.Kind.CUSTOM, "cooldown": 9.0, "max_range": 6.0, "damage_mult": 1.3},
		{"id": "mirage_barrage", "display_name": "Mirage Barrage", "kind": BossAbility.Kind.CUSTOM, "cooldown": 20.0, "max_range": 40.0, "weight": 0.9},
		{"id": "sand_globes", "display_name": "Sand Globes", "kind": BossAbility.Kind.CUSTOM, "cooldown": 22.0, "telegraph": 1.0, "max_range": 40.0},
		{"id": "sand_pillar", "display_name": "Sand Pillar", "kind": BossAbility.Kind.CUSTOM, "cooldown": 9999.0, "weight": 0.0, "max_range": 99.0},
		{"id": "shifting_sands", "display_name": "Shifting Sands", "kind": BossAbility.Kind.CUSTOM, "cooldown": 9999.0, "min_phase": 2, "weight": 0.0, "max_range": 99.0},
		{"id": "ticking_time", "display_name": "Ticking Time", "kind": BossAbility.Kind.CUSTOM, "cooldown": 16.0, "min_phase": 2, "max_range": 40.0},
		{"id": "fiery_sun", "display_name": "Fiery Sun", "kind": BossAbility.Kind.CUSTOM, "cooldown": 9999.0, "min_phase": 3, "weight": 0.0, "max_range": 999.0},
	]

func phase_openers() -> Dictionary:
	return {2: "shifting_sands", 3: "fiery_sun"}

## A Sand Pillar as each of PILLAR_AT is crossed, until the Sun.
func urgent_ability(_distance: float) -> BossAbility:
	if boss_brain == null or _pillars_cast >= PILLAR_AT.size() or boss_brain.phase >= 3:
		return null
	if health.current_health / maxf(health.max_health, 1.0) > PILLAR_AT[_pillars_cast]:
		return null
	return boss_brain.find("sand_pillar")

func arena() -> SandArena:
	if not is_instance_valid(_arena) and is_inside_tree():
		_arena = get_tree().get_first_node_in_group("sand_arena") as SandArena
	return _arena

func can_use_ability(ability: BossAbility) -> bool:
	if ability.id == "ticking_time":
		return _sands_settled or arena() == null
	if ability.id == "sand_globes":
		_globes = _globes.filter(func(g): return is_instance_valid(g) and g.health.is_alive())
		return _globes.size() + GLOBE_COUNT <= GLOBE_CAP
	return true

func cast_custom(ability: BossAbility) -> void:
	match ability.id:
		"sandstorm_cuts":
			var origin := global_position
			var dir := _forward()
			await _sandstorm_cuts(ability, origin, dir, false)
			if health.is_alive():
				_leave_echo(ability, origin, dir)
		"jackal_fangs":
			await _jackal_fangs(ability)
		"dune_reaver":
			await _dune_reaver(ability)
		"scarab_rush":
			await _scarab_rush(ability)
		"desert_sweep":
			await _desert_sweep(ability)
		"mirage_barrage":
			await _mirage_barrage()
		"sand_pillar":
			await _sand_pillar()
		"fiery_sun":
			await _fiery_sun()
		"sand_globes":
			await _sand_globes(ability)
		"shifting_sands":
			await _shifting_sands()
		"ticking_time":
			await _ticking_time()
		_:
			await get_tree().process_frame

func _target_player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _forward() -> Vector3:
	var p := _target_player()
	var to := (p.global_position - global_position) if p else -global_transform.basis.z
	to.y = 0.0
	return to.normalized() if to.length() > 0.05 else Vector3.FORWARD

## Two fast slashes around `origin`, then a thrust along `dir`. An echo
## replays it from where he stood, without the animation or the parry.
func _sandstorm_cuts(ability: BossAbility, origin: Vector3, dir: Vector3, echo: bool) -> void:
	var damage := get_ability_base_damage() * ability.damage_mult
	var tint := ECHO_COLOR if echo else Color(1.0, 0.7, 0.3)
	for i in 2:
		if not echo:
			begin_attack_telegraph(SLASH_TELEGRAPH)
		BossTelegraph.circle(get_parent(), origin, SLASH_RADIUS, SLASH_TELEGRAPH, tint)
		await get_tree().create_timer(SLASH_TELEGRAPH, false).timeout
		if not health.is_alive():
			return
		var p := _target_player()
		var facing := dir if echo else _forward()
		_slash_fx(origin, facing, i, echo)
		if p and _in_slash(p.global_position, origin, facing):
			p.take_damage(damage, Constants.DamageType.KINETIC, self, Player.HitKind.ATTACK)
		await get_tree().create_timer(SLASH_GAP, false).timeout
	if not echo:
		dir = _forward()
		origin = global_position
		begin_attack_telegraph(THRUST_TELEGRAPH)
	BossTelegraph.line(get_parent(), origin, dir, THRUST_LENGTH, THRUST_WIDTH, THRUST_TELEGRAPH, tint if echo else Color(1.0, 0.55, 0.2))
	await get_tree().create_timer(THRUST_TELEGRAPH, false).timeout
	if not health.is_alive():
		return
	_thrust_fx(origin, dir, echo)
	var p := _target_player()
	if p == null:
		return
	var rel := p.global_position - origin
	rel.y = 0.0
	var along := rel.dot(dir)
	if along < 0.0 or along > THRUST_LENGTH or (rel - dir * along).length() > THRUST_WIDTH * 0.5 + 0.4:
		return
	if not echo and p.parry_handler and p.parry_handler.attempt_parry(self, p.ward):
		# Parried: he's thrown off balance.
		interrupt_attack()
		if stance:
			stance.apply_parry_damage(THRUST_PARRY_STANCE)
		status_effects.apply_timed_effect("stun", THRUST_PARRY_STUN)
		EventBus.enemy_attack_resolved.emit(self, p, true, true)
		return
	p.take_damage(damage * THRUST_DAMAGE, Constants.DamageType.PIERCING, self, Player.HitKind.ATTACK)

## A crescent of sand across the slash, alternating sides; echoes are fainter.
func _slash_fx(origin: Vector3, facing: Vector3, index: int, echo: bool) -> void:
	var color := Color(SAND_COLOR, 0.45) if echo else SAND_COLOR
	SpellFx.sweep(get_parent(), origin, facing, SLASH_RADIUS + 0.6, SLASH_HALF_ANGLE, color, 0.2, 1.0 if index % 2 == 0 else -1.0, 1.0)
	SpellFx.burst(get_parent(), origin + facing * SLASH_RADIUS * 0.6 + Vector3.UP * 0.6, color, 18, Vector2(2, 5), 0.5, Vector2(0.08, 0.18), 80.0, -6.0)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_whoosh), origin, -2.0 if echo else 2.0, 0.9 if echo else 1.0)

## A spear of driven sand down the thrust's strip.
func _thrust_fx(origin: Vector3, dir: Vector3, echo: bool) -> void:
	var color := Color(SAND_COLOR, 0.5) if echo else SAND_COLOR
	var p := SpellFx.emitter(get_parent(), 60, 0.5)
	p.global_position = origin + Vector3.UP * 0.9
	p.one_shot = true
	p.explosiveness = 0.9
	p.direction = dir
	p.spread = 6.0
	p.initial_velocity_min = THRUST_LENGTH * 2.0
	p.initial_velocity_max = THRUST_LENGTH * 3.0
	p.damping_min = THRUST_LENGTH * 3.0
	p.damping_max = THRUST_LENGTH * 4.0
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.35
	p.color_ramp = SpellFx.ramp(Color(color.lightened(0.3), 1.0), Color(color, 0.7), 0.15)
	p.mesh = SpellFx.glow_quad(false)
	p.emitting = true
	SpellFx.free_after(p, 1.0)
	SmokePuff.spawn(get_parent(), origin + dir * THRUST_LENGTH, 0.8, Color(0.75, 0.62, 0.42))
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_sand), origin + dir * THRUST_LENGTH * 0.5, -2.0 if echo else 2.0)

func _in_slash(point: Vector3, origin: Vector3, facing: Vector3) -> bool:
	var rel := point - origin
	rel.y = 0.0
	return rel.length() <= SLASH_RADIUS + 0.4 and (rel.length() < 0.6 or rad_to_deg(facing.angle_to(rel.normalized())) <= SLASH_HALF_ANGLE)

## A sand afterimage where he stood; it replays the cuts after ECHO_DELAY.
func _leave_echo(ability: BossAbility, origin: Vector3, dir: Vector3) -> void:
	var ghost := _make_ghost()
	get_parent().add_child(ghost)
	ghost.global_position = origin
	SmokePuff.spawn(get_parent(), origin, 1.0, Color(0.85, 0.7, 0.45))
	ghost.look_at(origin + dir, Vector3.UP)
	get_tree().create_timer(ECHO_DELAY, false).timeout.connect(func():
		if not is_instance_valid(ghost):
			return
		if health.is_alive():
			await _sandstorm_cuts(ability, origin, dir, true)
		if is_instance_valid(ghost):
			var fade := ghost.create_tween()
			fade.tween_property(ghost, "scale", Vector3(1.0, 0.01, 1.0), 0.4)
			fade.tween_callback(ghost.queue_free))

## His model in translucent sand, frozen mid-stance.
func _make_ghost(tint: Color = ECHO_COLOR) -> Node3D:
	var root := Node3D.new()
	root.add_to_group("ataras_echo")
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = tint
	if definition and definition.model_scene:
		var model := definition.model_scene.instantiate() as Node3D
		root.add_child(model)
		model.scale = Vector3.ONE * definition.scale_modifier
		model.rotation.y = definition.model_yaw_offset + PI
		for node in model.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = mat
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		body.mesh = capsule
		body.position.y = 1.0
		body.material_override = mat
		root.add_child(body)
	return root

## ---- Melee combos ---------------------------------------------------------

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout

func _hit(ability: BossAbility, mult: float = 1.0) -> float:
	return get_ability_base_damage() * ability.damage_mult * mult

func _strike(p: Player, amount: float, is_melee: bool = true) -> void:
	p.take_damage(amount, Constants.DamageType.KINETIC, self, Player.HitKind.ATTACK, is_melee)

func _arena_floor_y() -> float:
	return arena().global_position.y if arena() else global_position.y

func _in_arc(point: Vector3, origin: Vector3, facing: Vector3, radius: float, half_deg: float) -> bool:
	var rel := point - origin
	rel.y = 0.0
	return rel.length() <= radius + 0.4 and (rel.length() < 0.6 or rad_to_deg(facing.angle_to(rel.normalized())) <= half_deg)

func _in_line(point: Vector3, origin: Vector3, dir: Vector3, length: float, width: float) -> bool:
	var rel := point - origin
	rel.y = 0.0
	var along := rel.dot(dir)
	return along >= -0.5 and along <= length and (rel - dir * along).length() <= width * 0.5 + 0.4

## How far he can travel along `dir` before a wall or pillar, up to `wanted`.
func _clear_distance(dir: Vector3, wanted: float) -> float:
	var from := global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * (wanted + 1.0), 1)
	var exclude: Array[RID] = [get_rid()]
	var p := _target_player()
	if p:
		exclude.append(p.get_rid())  # he dashes through the player
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return wanted
	return maxf(minf(wanted, from.distance_to(hit["position"]) - 1.0), 0.0)

## Slides him `distance` along `dir` over `seconds`.
func _lunge(dir: Vector3, distance: float, seconds: float) -> void:
	var travel := _clear_distance(dir, distance)
	if travel <= 0.05:
		return
	velocity = Vector3.ZERO
	var tween := create_tween()
	tween.tween_property(self, "global_position", global_position + dir * travel, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished

## Three quick slashes, stepping in with each.
func _jackal_fangs(ability: BossAbility) -> void:
	var damage := _hit(ability)
	for i in FANG_HITS:
		var facing := _forward()
		var to_player := _target_player().global_position.distance_to(global_position) if _target_player() else 0.0
		_lunge(facing, minf(FANG_STEP, maxf(to_player - 2.0, 0.0)), FANG_TELEGRAPH * 0.6)
		begin_attack_telegraph(FANG_TELEGRAPH)
		BossTelegraph.circle(get_parent(), global_position + facing * FANG_STEP * 0.5, FANG_RADIUS, FANG_TELEGRAPH, TELL)
		await _wait(FANG_TELEGRAPH)
		if not health.is_alive():
			return
		_slash_fx(global_position, facing, i, false)
		var p := _target_player()
		if p and _in_arc(p.global_position, global_position, facing, FANG_RADIUS, FANG_HALF_ANGLE):
			_strike(p, damage)
		await _wait(FANG_GAP)

## A spin around him, then an overhead cleave down a line.
func _dune_reaver(ability: BossAbility) -> void:
	begin_attack_telegraph(REAVER_SPIN_TELEGRAPH)
	BossTelegraph.circle(get_parent(), global_position, REAVER_RADIUS, REAVER_SPIN_TELEGRAPH, TELL)
	await _wait(REAVER_SPIN_TELEGRAPH)
	if not health.is_alive():
		return
	var facing := _forward()
	SpellFx.sweep(get_parent(), global_position, facing, REAVER_RADIUS + 0.6, 180.0, SAND_COLOR, 0.3, 1.0, 1.0)
	SpellFx.burst(get_parent(), global_position + Vector3.UP * 0.6, SAND_COLOR, 30, Vector2(3, 6), 0.5, Vector2(0.08, 0.18), 180.0, -6.0)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_whoosh), global_position, 3.0, 0.85)
	var p := _target_player()
	if p and _in_arc(p.global_position, global_position, facing, REAVER_RADIUS, 180.0):
		_strike(p, _hit(ability))
	var dir := _forward()
	var origin := global_position
	begin_attack_telegraph(REAVER_CLEAVE_TELEGRAPH)
	BossTelegraph.line(get_parent(), origin, dir, REAVER_CLEAVE_LENGTH, REAVER_CLEAVE_WIDTH, REAVER_CLEAVE_TELEGRAPH, Color(1.0, 0.5, 0.2))
	await _wait(REAVER_CLEAVE_TELEGRAPH)
	if not health.is_alive():
		return
	_thrust_fx(origin, dir, false)
	SmokePuff.spawn(get_parent(), origin + dir * REAVER_CLEAVE_LENGTH * 0.6, 1.0, Color(0.8, 0.66, 0.44))
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_heavy_impact), origin + dir * 3.0, 0.0)
	p = _target_player()
	if p and _in_line(p.global_position, origin, dir, REAVER_CLEAVE_LENGTH, REAVER_CLEAVE_WIDTH):
		_strike(p, _hit(ability, REAVER_CLEAVE_DAMAGE))

## A dash through the player along a marked line, then a backhand.
func _scarab_rush(ability: BossAbility) -> void:
	var p := _target_player()
	if p == null:
		return
	var dir := _forward()
	var origin := global_position
	var length := _clear_distance(dir, clampf(origin.distance_to(p.global_position) + 2.5, 4.0, RUSH_MAX))
	begin_attack_telegraph(RUSH_TELEGRAPH)
	BossTelegraph.line(get_parent(), origin, dir, length, RUSH_WIDTH, RUSH_TELEGRAPH, Color(1.0, 0.5, 0.2))
	await _wait(RUSH_TELEGRAPH)
	if not health.is_alive():
		return
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_whoosh), origin, 2.0, 1.2)
	_thrust_fx(origin, dir, false)
	await _lunge(dir, length, RUSH_SEC)
	p = _target_player()
	if p and _in_line(p.global_position, origin, dir, length, RUSH_WIDTH):
		_strike(p, _hit(ability))
	if not health.is_alive():
		return
	var facing := _forward()
	begin_attack_telegraph(RUSH_BACKHAND_TELEGRAPH)
	BossTelegraph.circle(get_parent(), global_position, FANG_RADIUS, RUSH_BACKHAND_TELEGRAPH, TELL)
	await _wait(RUSH_BACKHAND_TELEGRAPH)
	if not health.is_alive():
		return
	_slash_fx(global_position, facing, 1, false)
	p = _target_player()
	if p and _in_arc(p.global_position, global_position, facing, FANG_RADIUS, FANG_HALF_ANGLE):
		_strike(p, _hit(ability, 0.75))

## A wide, low sweep around him; a player in the air clears it.
func _desert_sweep(ability: BossAbility) -> void:
	var facing := _forward()
	begin_attack_telegraph(SWEEP_TELEGRAPH)
	BossTelegraph.circle(get_parent(), global_position, SWEEP_RADIUS, SWEEP_TELEGRAPH, Color(1.0, 0.75, 0.3))
	await _wait(SWEEP_TELEGRAPH)
	if not health.is_alive():
		return
	SpellFx.sweep(get_parent(), global_position, facing, SWEEP_RADIUS + 0.5, SWEEP_HALF_ANGLE, SAND_COLOR, 0.32, 1.0, 0.35)
	SpellFx.burst(get_parent(), global_position + facing * SWEEP_RADIUS * 0.5 + Vector3.UP * 0.3, SAND_COLOR, 36, Vector2(4, 8), 0.5, Vector2(0.08, 0.2), 120.0, -8.0)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_whoosh), global_position, 4.0, 0.7)
	var p := _target_player()
	if p and _in_arc(p.global_position, global_position, facing, SWEEP_RADIUS, SWEEP_HALF_ANGLE) and p.global_position.y - _arena_floor_y() < SWEEP_JUMP_CLEARANCE:
		_strike(p, _hit(ability))

## ---- Mirage Barrage -------------------------------------------------------

## Four blinks, a clone left at each spot; then each clone hurls a stone.
func _mirage_barrage() -> void:
	var clones: Array[Node3D] = []
	for i in MIRAGE_JUMPS:
		var clone := _make_ghost(MIRAGE_COLOR)
		get_parent().add_child(clone)
		clone.global_position = global_position
		var p := _target_player()
		if p:
			clone.look_at(Vector3(p.global_position.x, global_position.y, p.global_position.z), Vector3.UP)
		clones.append(clone)
		SmokePuff.spawn(get_parent(), global_position, 0.9, Color(0.85, 0.7, 0.45))
		BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_whoosh), global_position, 0.0, 1.3)
		var spot := _mirage_spot()
		velocity = Vector3.ZERO
		global_position = Vector3(spot.x, global_position.y, spot.z)
		SmokePuff.spawn(get_parent(), global_position, 0.9, Color(0.85, 0.7, 0.45))
		await _wait(MIRAGE_HOP)
		if not health.is_alive():
			_free_nodes(clones)
			return
	begin_channel(MIRAGE_AIM + MIRAGE_STAGGER * MIRAGE_JUMPS)
	for i in clones.size():
		_clone_throw(clones[i], i * MIRAGE_STAGGER)
	await _wait(MIRAGE_AIM + MIRAGE_STAGGER * MIRAGE_JUMPS + 0.2)
	for clone in clones:
		if is_instance_valid(clone):
			var fade := clone.create_tween()
			fade.tween_property(clone, "scale", Vector3(1.0, 0.01, 1.0), 0.35)
			fade.tween_callback(clone.queue_free)

## One clone: after `delay` it marks a line at the player, then throws.
func _clone_throw(clone: Node3D, delay: float) -> void:
	await _wait(delay)
	var p := _target_player()
	if not is_instance_valid(clone) or p == null or not health.is_alive():
		return
	var origin := clone.global_position
	var dir := p.global_position - origin
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.05 else Vector3.FORWARD
	clone.look_at(origin + dir, Vector3.UP)
	BossTelegraph.line(get_parent(), origin, dir, MIRAGE_LINE, 1.2, MIRAGE_AIM, TELL)
	await _wait(MIRAGE_AIM)
	if not is_instance_valid(clone) or not health.is_alive():
		return
	AtarasStone.fire(get_parent(), origin, dir, randf_range(MIRAGE_DAMAGE.x, MIRAGE_DAMAGE.y), self)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_sand), origin, 0.0, 1.2)

## A blink target: on the floor, away from the player and the pillars.
func _mirage_spot() -> Vector3:
	var centre := arena().global_position if arena() else global_position
	var p := _target_player()
	var best := global_position
	for attempt in 12:
		var angle := randf() * TAU
		var spot := centre + Vector3(sin(angle), 0.0, cos(angle)) * randf_range(6.0, SandArena.RADIUS - 4.0)
		if p and Vector2(spot.x - p.global_position.x, spot.z - p.global_position.z).length() < 6.0:
			continue
		var blocked := false
		for pillar in _pillars:
			if is_instance_valid(pillar) and Vector2(spot.x - pillar.global_position.x, spot.z - pillar.global_position.z).length() < SandPillar.RADIUS + 2.0:
				blocked = true
				break
		if not blocked:
			return spot
		best = spot
	return best

func _free_nodes(nodes: Array[Node3D]) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()

## ---- Sand Pillars and the Fiery Sun ---------------------------------------

## A pillar marked under the player; it erupts SandPillar.DELAY later.
func _sand_pillar() -> void:
	_pillars_cast += 1
	var p := _target_player()
	if p == null:
		return
	begin_attack_telegraph(0.6)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.KINETIC, 0.6, false)
	var spot := Vector3(p.global_position.x, _arena_floor_y(), p.global_position.z)
	_raise_pillar(spot)
	await _wait(0.6)

func _raise_pillar(spot: Vector3) -> void:
	var damage := get_ability_base_damage() * PILLAR_DAMAGE
	_pillars.append(SandPillar.raise(get_parent(), spot, damage, self))

## He blinks to the centre and raises a sun that slams down. Behind a
## pillar (seen from the centre) you're safe; anywhere else takes the blast.
func _fiery_sun() -> void:
	var centre := arena().global_position if arena() else global_position
	invulnerable = true
	SmokePuff.spawn(get_parent(), global_position, 1.2, Color(0.85, 0.7, 0.45))
	velocity = Vector3.ZERO
	global_position = Vector3(centre.x, global_position.y, centre.z)
	SmokePuff.spawn(get_parent(), global_position, 1.2, Color(0.85, 0.7, 0.45))
	# Pillars he never got to raise come up now, so there's cover.
	_pillars = _pillars.filter(func(x): return is_instance_valid(x))
	var missing := PILLAR_AT.size() - _pillars.size()
	for i in missing:
		var angle := TAU * (i + randf() * 0.5) / maxf(missing, 1)
		_raise_pillar(centre + Vector3(sin(angle), 0.0, cos(angle)) * randf_range(PILLAR_RING.x, PILLAR_RING.y))
	_pillars_cast = PILLAR_AT.size()
	begin_channel(SUN_GROW + SUN_HOLD + SUN_FALL)
	BossFx.sound(SoundLib.library.boss_deep_roar, global_position, 2.0, 0.9)
	var sun := AtarasSun.new()
	get_parent().add_child(sun)
	sun.global_position = centre + Vector3.UP * SUN_HEIGHT
	await sun.grow(SUN_GROW)
	if not health.is_alive():
		sun.queue_free()
		return
	var warn := SUN_HOLD + SUN_FALL
	BossTelegraph.circle(get_parent(), centre, SandArena.RADIUS, warn, Color(SUN_COLOR, 0.3))
	for pillar in _pillars:
		if is_instance_valid(pillar):
			var out := pillar.global_position - centre
			out.y = 0.0
			var dist := out.length()
			if dist > 0.5:
				out /= dist
				BossTelegraph.line(get_parent(), pillar.global_position + out * SandPillar.RADIUS, out, maxf(SandArena.RADIUS - dist - SandPillar.RADIUS, 1.0), SandPillar.RADIUS * 2.0, warn, SHADE_COLOR)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_fire), sun.global_position, 4.0, 0.6)
	await _wait(SUN_HOLD)
	if not health.is_alive():
		sun.queue_free()
		return
	begin_attack_telegraph(SUN_FALL)
	await sun.slam(centre, SUN_FALL)
	_sun_blast(centre)
	invulnerable = false

func _sun_blast(centre: Vector3) -> void:
	var parent := get_parent()
	SunExplosion.spawn(parent, centre, SandArena.RADIUS)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_heavy_impact), centre, 8.0, 0.6)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_fire), centre, 6.0, 0.8)
	var p := _target_player()
	if p and p.health.is_alive() and not is_sheltered(centre, p.global_position):
		p.take_damage(SUN_FIRE_DAMAGE, Constants.DamageType.FIRE, self, Player.HitKind.SPELL)
		p.take_damage(SUN_KINETIC_DAMAGE, Constants.DamageType.KINETIC, self, Player.HitKind.SPELL)
	for pillar in _pillars:
		if is_instance_valid(pillar):
			pillar.crumble()
	_pillars.clear()

## True when a standing pillar is between `from` and `point`.
func is_sheltered(from: Vector3, point: Vector3) -> bool:
	for pillar in _pillars:
		if is_instance_valid(pillar) and pillar.shelters(from, point):
			return true
	return false

## Globes rise around the arena and start firing.
func _sand_globes(ability: BossAbility) -> void:
	begin_attack_telegraph(ability.telegraph)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.KINETIC, ability.telegraph)
	var spots: Array[Vector3] = []
	var centre := arena().global_position if arena() else global_position
	for i in GLOBE_COUNT:
		var angle := randf() * TAU
		spots.append(centre + Vector3(sin(angle), 0, cos(angle)) * randf_range(GLOBE_RING.x, GLOBE_RING.y))
		BossTelegraph.circle(get_parent(), spots[i], 1.2, ability.telegraph, Color(0.95, 0.8, 0.45))
	await get_tree().create_timer(ability.telegraph, false).timeout
	if not health.is_alive():
		return
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_sand), global_position, 0.0)
	for spot in spots:
		BossFx.summon_gate(get_parent(), spot, Constants.DamageType.KINETIC)
		var globe: Enemy = GLOBE_SCENE.instantiate()
		get_parent().add_child(globe)
		globe.global_position = spot + Vector3.UP * SandGlobe.HOVER
		_globes.append(globe)

func _shifting_sands() -> void:
	var a := arena()
	if a == null:
		_sands_settled = true
		await get_tree().process_frame
		return
	if not a.wedges_ended.is_connected(_on_sands_settled):
		a.wedges_ended.connect(_on_sands_settled)
	a.start_wedges()
	begin_channel(1.2)
	BossFx.sound(SoundLib.library.boss_deep_roar, global_position, 0.0, 1.15)
	SpellFx.shockwave(get_parent(), global_position + Vector3.UP * 0.05, 14.0, SAND_COLOR, 1.0)
	await get_tree().create_timer(1.2, false).timeout

func _on_sands_settled() -> void:
	_sands_settled = true

## Ticking Time: for a few seconds the ground the player crosses is marked;
## when it ends, every mark becomes a permanent sand trap.
func _ticking_time() -> void:
	begin_channel(TICKING_DURATION)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.KINETIC, TICKING_DURATION)
	var marks: Array[Vector3] = []
	var elapsed := 0.0
	while elapsed < TICKING_DURATION:
		var p := _target_player()
		if p and (marks.is_empty() or marks[-1].distance_to(p.global_position) > TICKING_RADIUS * 0.9):
			var spot := Vector3(p.global_position.x, (arena().global_position.y if arena() else 0.0), p.global_position.z)
			marks.append(spot)
			BossTelegraph.circle(get_parent(), spot, TICKING_RADIUS, TICKING_DURATION - elapsed, TICKING_MARK_COLOR)
			SpellFx.burst(get_parent(), spot + Vector3.UP * 0.2, SAND_COLOR, 10, Vector2(1, 3), 0.6, Vector2(0.06, 0.14), 40.0, -3.0)
		await get_tree().create_timer(TICKING_INTERVAL, false).timeout
		elapsed += TICKING_INTERVAL
		if not health.is_alive():
			return
	var a := arena()
	if a:
		if not marks.is_empty():
			BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_sand), marks[-1], 0.0, 0.8)
		for spot in marks:
			a.add_trap(spot, TICKING_RADIUS)
			SmokePuff.spawn(get_parent(), spot, 0.6, Color(0.8, 0.66, 0.42))

func _on_died() -> void:
	for g in _globes:
		if is_instance_valid(g) and g.health.is_alive():
			g.health.apply_damage(g.health.current_health + 1.0)
	for pillar in _pillars:
		if is_instance_valid(pillar):
			pillar.crumble()
	_pillars.clear()
	invulnerable = false
	super._on_died()
