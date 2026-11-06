extends PinnacleBoss
class_name DarknessDragon
## Pinnacle boss, shown as "Nyxareth, the Lightless" (a placeholder name).
## Entropic. Fought in the DarkArena: near-darkness and five Lightwells, with
## Dread building on a player who leaves the light (DarkArena). His Dread
## turns into damage: every stack makes his hits land harder.
##   Intro: he rises out of the dark (the model's birth clip).
##   Phase 1: bites; Shadow Breath, a cone that puts out any well it touches;
##   Wingquake, a slam whose ring of shadow rolls across the floor (jump it);
##   Umbral Rain, pools that are hard to see outside the light; Pounce and
##   Wingbeat for a player keeping their distance.
##   Phase 2, Nightfall (66%): he sleeps, untouchable, for NIGHTFALL_SEC; every
##   well goes out and Shades rise to smother any you relight. When he wakes,
##   each well still burning sears him for NIGHTFALL_BURST_SHARE of his Life,
##   and he opens with a Shadow Breath at whatever you lit.
##   Phase 3, Eclipse (33%): only one well burns at a time and the light moves
##   round the ring. Devouring Dark: a channel that drags you toward him and
##   Swallows you at the end unless you stand in the light.

const DISPLAY_NAME := "Nyxareth, the Lightless"
const VOID_COLOR := Color(0.55, 0.25, 0.95)
## Ground warnings: bright enough to read on a black floor.
const WARN_COLOR := Color(0.85, 0.55, 1.0)
const ENTROPIC := Constants.DamageType.ENTROPIC

const BREATH_LENGTH := 16.0
const BREATH_HALF_DEG := 32.0
const BREATH_HIT_SEC := 0.9

const QUAKE_RING_MAX := 22.0
const QUAKE_RING_SPEED := 13.0
## The rolling ring's share of the slam's damage.
const QUAKE_RING_SHARE := 0.7

const RAIN_SPOTS := 5
const RAIN_SPREAD := 6.0
## How much of a pool's warning shows when it falls outside the light.
const RAIN_DARK_OPACITY := 0.22

const NIGHTFALL_SEC := 25.0
const NIGHTFALL_SHADES := 5
const NIGHTFALL_SHADE_GAP := 1.2
const SHADE_UNIT := "hollowed_ghoul"
const NIGHTFALL_BURST_SHARE := 0.02
const WAKE_CLIP := "stand 03"
const WAKE_SEC := 2.5

const DEVOUR_CHANNEL_SEC := 4.5
const DEVOUR_PULL_SPEED := 3.2
const DEVOUR_LIFE_SHARE := 0.8
## The pull stops this close to him.
const DEVOUR_PULL_STOP := 5.0

var nightfall := false
var _arena: DarkArena

func _ready() -> void:
	super._ready()
	display_name = DISPLAY_NAME
	if boss_brain:
		boss_brain.phase_changed.connect(_on_phase)
	# A faint violet glow, so he never vanishes entirely in his own dark.
	var glow := OmniLight3D.new()
	glow.name = "DarkGlow"
	glow.light_color = VOID_COLOR
	glow.light_energy = 1.4
	glow.omni_range = 12.0
	glow.position.y = body_height * 0.7
	add_child(glow)
	_rise.call_deferred()

func pinnacle_life() -> float:
	return 60_000_000.0

func abilities() -> Array:
	return [
		{"id": "shadow_breath", "display_name": "Shadow Breath", "kind": BossAbility.Kind.CUSTOM, "cooldown": 13.0, "telegraph": 1.4, "damage_mult": 2.2, "max_range": BREATH_LENGTH,
			"description": "A cone of black flame. Any Lightwell it touches goes out."},
		{"id": "wingquake", "display_name": "Wingquake", "kind": BossAbility.Kind.CUSTOM, "cooldown": 11.0, "telegraph": 1.2, "radius": 6.5, "damage_mult": 1.8, "max_range": 20.0,
			"description": "He slams the ground, and a ring of shadow rolls out across the arena. Jump over it."},
		{"id": "umbral_rain", "display_name": "Umbral Rain", "kind": BossAbility.Kind.CUSTOM, "cooldown": 10.0, "telegraph": 1.6, "radius": 2.6, "damage_mult": 1.4, "max_range": 30.0,
			"description": "Pools of darkness fall around you. Outside the light their warnings are hard to see."},
		{"id": "pounce", "display_name": "Pounce", "kind": BossAbility.Kind.LEAP, "cooldown": 12.0, "telegraph": 1.3, "radius": 5.0, "damage_mult": 2.0, "min_range": 10.0, "max_range": 24.0, "damage_type": ENTROPIC},
		{"id": "devouring_dark", "display_name": "Devouring Dark", "kind": BossAbility.Kind.CUSTOM, "cooldown": 26.0, "telegraph": DEVOUR_CHANNEL_SEC, "max_range": 60.0, "min_phase": 3,
			"description": "He drinks the dark and drags you toward him. When the channel ends, anyone outside the light is Swallowed."},
	]

func phase_openers() -> Dictionary:
	return {2: "shadow_breath", 3: "devouring_dark"}

func range_answers() -> Array:
	return [
		{"id": "wingbeat", "display_name": "Wingbeat", "kind": BossAbility.Kind.PULL, "telegraph": 1.1, "radius": 6.0, "pull_stop": 5.5, "max_drag": 14.0, "damage_mult": 1.5, "damage_type": ENTROPIC},
		{"id": "pounce_answer", "display_name": "Pounce", "kind": BossAbility.Kind.LEAP, "telegraph": 1.2, "radius": 5.0, "damage_mult": 2.0, "damage_type": ENTROPIC},
	]

func range_answer_distance() -> float:
	return 16.0

func arena() -> DarkArena:
	if not is_instance_valid(_arena) and is_inside_tree():
		_arena = get_tree().get_first_node_in_group("dark_arena") as DarkArena
	return _arena

## Dread: every stack the player carries makes his hits land harder.
func get_outgoing_damage_multiplier() -> float:
	var a := arena()
	return super.get_outgoing_damage_multiplier() * (a.dread_damage_multiplier() if a else 1.0)

func roar_sound() -> AudioStream:
	return SoundLib.library.boss_deep_roar if SoundLib.library.boss_deep_roar else super.roar_sound()

## He climbs out of the dark before he fights.
func _rise() -> void:
	if not is_inside_tree() or boss_brain == null:
		return
	await get_tree().process_frame
	if _clip("birth", 3.6):
		boss_brain.casting = true
		await _wait(3.6)
		if is_instance_valid(boss_brain) and not boss_brain.is_queued_for_deletion():
			boss_brain.casting = false

func _on_phase(p: int) -> void:
	var a := arena()
	if p >= 3 and a:
		a.start_eclipse()

func on_melee_strike() -> void:
	var melee := get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	var reach := melee.attack_range if melee else 5.0
	var dir := _flat_to_player()
	var color := BossFx.glow_of(ENTROPIC)
	SpellFx.sweep(get_parent(), global_position, dir, reach + 0.6, 45.0, color, 0.24, 1.0 if randf() < 0.5 else -1.0, 1.4)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_whoosh), global_position, 0.0, 0.7)

func cast_custom(a: BossAbility) -> void:
	match a.id:
		"shadow_breath":
			await _shadow_breath(a)
		"wingquake":
			await _wingquake(a)
		"umbral_rain":
			await _umbral_rain(a)
		"devouring_dark":
			await _devouring_dark(a)
		_:
			await get_tree().process_frame

## ---- Shadow Breath ---------------------------------------------------------

func _shadow_breath(a: BossAbility) -> void:
	var dir := _flat_to_player()
	var origin := global_position
	_clip("spell attack", a.telegraph + BREATH_HIT_SEC)
	BossTelegraph.cone(get_parent(), origin, dir, BREATH_LENGTH, BREATH_HALF_DEG, a.telegraph, WARN_COLOR)
	BossFx.charge(self, get_cast_origin(), ENTROPIC, a.telegraph)
	await _wait(a.telegraph)
	if not _alive():
		return
	_breath_fx(dir)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_void_cast), global_position, 2.0, 0.7)
	var ar := arena()
	if ar:
		ar.snuff_cone(origin, dir, BREATH_LENGTH + 1.0, BREATH_HALF_DEG + 4.0)
	var p := _live_player()
	if p and _in_cone(p.global_position, origin, dir, BREATH_LENGTH, BREATH_HALF_DEG):
		boss_brain._damage_player(a)
	await _wait(BREATH_HIT_SEC)

static func _in_cone(point: Vector3, origin: Vector3, dir: Vector3, length: float, half_deg: float) -> bool:
	var to := point - origin
	to.y = 0.0
	if to.length() > length:
		return false
	return to.length() < 0.5 or rad_to_deg(dir.angle_to(to.normalized())) <= half_deg

## Black smoke with a violet core, rolling out along the cone.
func _breath_fx(dir: Vector3) -> void:
	var from := get_cast_origin() + dir * body_radius
	for layer in [[false, Color(0.04, 0.0, 0.08, 0.85), Color(0.0, 0.0, 0.0, 0.7), 90], [true, Color(0.8, 0.5, 1.0, 0.9), Color(VOID_COLOR, 0.6), 60]]:
		var p := SpellFx.emitter(get_parent(), layer[3], 0.7)
		p.global_position = from
		p.direction = (dir + Vector3.DOWN * 0.15).normalized()
		p.spread = BREATH_HALF_DEG
		p.initial_velocity_min = BREATH_LENGTH * 1.2
		p.initial_velocity_max = BREATH_LENGTH * 1.6
		p.damping_min = 8.0
		p.damping_max = 12.0
		p.scale_amount_min = 0.8
		p.scale_amount_max = 1.8
		p.scale_amount_curve = SpellFx.curve(0.4, 1.6)
		p.color_ramp = SpellFx.ramp(layer[1], layer[2], 0.2)
		p.mesh = SpellFx.glow_quad(layer[0])
		SpellFx.stop_after(p, BREATH_HIT_SEC, 0.7)

## ---- Wingquake -------------------------------------------------------------

func _wingquake(a: BossAbility) -> void:
	var center := global_position
	_clip("attack slam", a.telegraph + 1.0)
	BossTelegraph.circle(get_parent(), center, a.radius, a.telegraph, WARN_COLOR)
	BossFx.charge(self, get_cast_origin(), ENTROPIC, a.telegraph, false)
	await _wait(a.telegraph)
	if not _alive():
		return
	boss_brain._hit_circle(center, a.radius, a)
	BossFx.impact(get_parent(), center, a.radius, ENTROPIC)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_heavy_impact), center, 2.0, 0.8)
	SpellFx.shockwave(get_parent(), center, QUAKE_RING_MAX, VOID_COLOR, (QUAKE_RING_MAX - a.radius) / QUAKE_RING_SPEED)
	# The ring rolls outward; it catches the player only if they're on the ground as it passes.
	var r := a.radius
	var hit := false
	while r < QUAKE_RING_MAX and _alive():
		await get_tree().physics_frame
		var before := r
		r += QUAKE_RING_SPEED * get_physics_process_delta_time()
		var p := _live_player()
		if hit or p == null:
			continue
		var d := Vector2(p.global_position.x - center.x, p.global_position.z - center.z).length()
		if d > before and d <= r + 0.3:
			hit = true
			if p.is_on_floor():
				boss_brain._damage_player(a, QUAKE_RING_SHARE)

## ---- Umbral Rain -----------------------------------------------------------

func _umbral_rain(a: BossAbility) -> void:
	var p := _live_player()
	if p == null:
		await get_tree().process_frame
		return
	begin_attack_telegraph(a.telegraph)
	BossFx.charge(self, get_cast_origin(), ENTROPIC, a.telegraph)
	var ar := arena()
	var spots: Array[Vector3] = [p.global_position]
	for i in RAIN_SPOTS - 1:
		var angle := randf() * TAU
		spots.append(p.global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(2.0, RAIN_SPREAD))
	for spot in spots:
		var t := BossTelegraph.circle(get_parent(), spot, a.radius, a.telegraph, WARN_COLOR)
		if ar and not ar.is_lit(spot):
			_dim(t, RAIN_DARK_OPACITY)
	await _wait(a.telegraph)
	if not _alive():
		return
	for spot in spots:
		BossFx.impact(get_parent(), spot, a.radius, ENTROPIC, false)
		boss_brain._hit_circle(spot, a.radius, a)

## Fades a telegraph's discs to `factor` of their usual opacity.
static func _dim(t: BossTelegraph, factor: float) -> void:
	for child in t.get_children():
		var mi := child as MeshInstance3D
		if mi and mi.material_override is StandardMaterial3D:
			(mi.material_override as StandardMaterial3D).albedo_color.a *= factor

## ---- Devouring Dark --------------------------------------------------------

func _devouring_dark(a: BossAbility) -> void:
	var ar := arena()
	if not _clip("spell channeling", a.telegraph, true):
		begin_channel(a.telegraph)
	BossFx.vortex(get_parent(), global_position, 14.0, ENTROPIC, a.telegraph)
	BossFx.sound(roar_sound(), global_position, 2.0, 0.8)
	var left := a.telegraph
	while left > 0.0 and _alive() and not status_effects.is_stunned():
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		left -= dt
		var p := _live_player()
		if p == null or (ar and ar.is_lit(p.global_position)):
			continue
		var to := global_position - p.global_position
		to.y = 0.0
		if to.length() > DEVOUR_PULL_STOP:
			p.move_and_collide(to.normalized() * DEVOUR_PULL_SPEED * dt)
	if not _alive() or left > 0.0:
		return
	var target := _live_player()
	if target and ar and not ar.is_lit(target.global_position):
		BossFx.impact(get_parent(), target.global_position, 3.0, ENTROPIC)
		ar.swallow(DEVOUR_LIFE_SHARE)
	elif target and not ar:
		boss_brain._damage_player(a, 3.0)

## ---- Nightfall -------------------------------------------------------------

## Phase 2 opens with Nightfall in place of the usual short roar.
func run_phase_transition(phase: int, seconds: float) -> void:
	if phase != 2:
		await super.run_phase_transition(phase, seconds)
		return
	nightfall = true
	var ar := arena()
	_clip("sleep", NIGHTFALL_SEC, true)
	if ar:
		ar.snuff_all()
	BossFx.vortex(get_parent(), global_position, 10.0, ENTROPIC, 2.0)
	for i in NIGHTFALL_SHADES:
		await _wait(NIGHTFALL_SHADE_GAP)
		if not _alive():
			return
		_raise_shade(i)
	await _wait(maxf(NIGHTFALL_SEC - NIGHTFALL_SHADE_GAP * NIGHTFALL_SHADES - WAKE_SEC, 1.0))
	if not _alive():
		return
	if not _clip(WAKE_CLIP, WAKE_SEC):
		_clip("birth", WAKE_SEC)
	await _wait(WAKE_SEC)
	if not _alive():
		return
	nightfall = false
	_sear(ar)

## Each well still burning as he wakes burns him.
func _sear(ar: DarkArena) -> void:
	if ar == null:
		return
	var burning := 0
	for w in ar.wells:
		if not w.lit:
			continue
		burning += 1
		BossFx.lance(get_parent(), w.global_position + Vector3.UP * Lightwell.LIGHT_HEIGHT, (get_cast_origin() - w.global_position).normalized(), w.global_position.distance_to(global_position), Constants.DamageType.FIRE)
	if burning > 0:
		health.apply_damage(health.max_health * NIGHTFALL_BURST_SHARE * burning)
		SpellFx.flash(get_parent(), get_cast_origin(), Lightwell.FLAME_COLOR, 4.0 + burning, 0.4)
		BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_fire), global_position, 2.0)

func _raise_shade(i: int) -> void:
	var ar := arena()
	var unit := EnemyRoster.create_unit(SHADE_UNIT)
	if unit == null:
		return
	get_parent().add_child(unit)
	var angle := TAU * (i + 0.5) / NIGHTFALL_SHADES + randf_range(-0.3, 0.3)
	var ring := (DarkArena.RADIUS - 4.0) if ar else 12.0
	var origin := ar.global_position if ar else global_position
	unit.global_position = origin + Vector3(sin(angle), 0.1, cos(angle)) * ring
	unit.display_name = "Shade"
	BossFx.summon_gate(get_parent(), unit.global_position, ENTROPIC)
	if ar:
		var channel := ShadeChannel.new()
		channel.arena = ar
		unit.add_child(channel)

## ---- Helpers ---------------------------------------------------------------

## Plays one of the model's clips; false when it has no such clip.
func _clip(clip: String, seconds: float, loop := false) -> bool:
	return _anim_controller != null and _anim_controller.play_clip(clip, seconds, loop)

func _wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds, false).timeout

func _alive() -> bool:
	return is_inside_tree() and health.is_alive()

func _live_player() -> Player:
	var p := get_tree().get_first_node_in_group("player") as Player
	return p if p and p.health.is_alive() else null

func _flat_to_player() -> Vector3:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var to := (p.global_position - global_position) if p else -global_transform.basis.z
	to.y = 0.0
	return to.normalized() if to.length() > 0.05 else Vector3.FORWARD
