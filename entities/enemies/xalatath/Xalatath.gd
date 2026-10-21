extends PinnacleBoss
class_name Xalatath
## Second Pinnacle boss, shown as "Herald of the Maw" (a placeholder: the
## model and ids are Xalatath's, which is Blizzard's and must be replaced).
## Entropic. Melee within reach, Entropic bolts beyond it. Fought in the
## MawArena (PinnacleArena builds it for her): a round floor over the void
## with four Anchor pylons.
##   Phase 1: Void Rift pools crack the floor when they run out; Shadow Lunge.
##   Void Beam: a channelled laser that turns after you (faster each
##   phase); standing pylons block it.
##   Luring the Lunge into a pylon stuns her, drains her Composure and opens
##   a Riposte window.
##   Her own attacks wear pylons down (MawPylon.wear()): a beam held on one,
##   a Lunge into one, ground hits and Void Rifts on one.
##   Phase 2 (66%): Mindbenders (three at a time) go for the pylons and shatter them;
##   Entropic Volley; from here a Lunge that misses the pylons ends in a
##   spin slash. Every pylon you save anchors you against Unmaking, stays a
##   stun wall, raises her Lens chance and weakens the Maw's opening.
##   Phase 3 (33%): the Maw opens under the dais. Unmaking drags you to its
##   lip for a slam unless a pylon anchors you; Collapse rains blasts; Feed
##   the Maw: she channels at the lip for a bigger, faster bite unless you
##   hit her hard enough to break it.
## The floor works against her too: a Riposte or a heavy Explosive hit knocks
## her back, and with no plate behind her she clings to the lip and the Maw
## drags at her (a big damage window, MawArena.cling()).
## Her melee is a Void Lash: a casting gesture, so it shows as a sweep of the
## void out to her reach, and its strike sphere is fitted to that reach.

const DISPLAY_NAME := "Herald of the Maw"
const BOLT_RANGE := 20.0
const BOLT_MIN_RANGE := 5.0
const BOLT_COOLDOWN := 2.8
const LUNGE_STUN_SEC := 2.0
const LUNGE_STANCE_DAMAGE := 60.0
## Knockback: a heavy Explosive hit is at least this share of her max Life.
const HEAVY_EXPLOSIVE_SHARE := 0.015
const KNOCKBACK_DISTANCE := 3.5
## Feed the Maw: damage (share of max Life) that breaks the channel.
const FEED_BREAK_SHARE := 0.04
const FEED_CHANNEL_SEC := 3.5
const FEED_STANCE_DAMAGE := 50.0
## Void Beam: a channelled laser that turns after the player; pylons block it.
const BEAM_CHANNEL_SEC := 5.0
const BEAM_LENGTH := 30.0
const BEAM_WIDTH := 1.2
const BEAM_HEIGHT := 1.2
const BEAM_TICK := 0.25
## Turn rate in phase 1; each later phase adds BEAM_TURN_PER_PHASE.
const BEAM_TURN_DEG_PER_SEC := 20.0
const BEAM_TURN_PER_PHASE := 20.0
const BEAM_COLOR := Color(0.6, 0.25, 0.95)
## Void Lash: her melee is a lash of the void out to her reach.
const LASH_HALF_ANGLE := 50.0

var feeding := false
var _feed_damage := 0.0
## The pylon the Void Beam last ran into (beam_length()).
var beam_blocker: MawPylon

var _arena: MawArena

func _ready() -> void:
	super._ready()
	display_name = DISPLAY_NAME
	var ranged := get_node_or_null("RangedAttack") as EnemyRangedAttack
	if ranged:
		ranged.fire_range = BOLT_RANGE
		ranged.min_range = BOLT_MIN_RANGE
		ranged.cooldown_duration = BOLT_COOLDOWN
	EventBus.riposte_executed.connect(_on_riposte)
	if boss_brain:
		boss_brain.phase_changed.connect(_on_phase)
	EventBus.damage_dealt.connect(_on_damage_dealt)

func pinnacle_life() -> float:
	return 20_000_000.0 if Dev.enabled else 62_000_000.0

func abilities() -> Array:
	var entropic := Constants.DamageType.ENTROPIC
	return [
		{"id": "void_rift", "display_name": "Void Rift", "kind": BossAbility.Kind.HAZARD, "cooldown": 9.0, "telegraph": 1.0, "radius": 3.5, "duration": 7.0, "damage_mult": 1.0, "damage_type": entropic},
		{"id": "shadow_lunge", "display_name": "Shadow Lunge", "kind": BossAbility.Kind.CHARGE, "cooldown": 8.0, "telegraph": 0.9, "damage_mult": 1.5, "min_range": 5.0, "max_range": 16.0, "damage_type": entropic},
		{"id": "void_beam", "display_name": "Void Beam", "kind": BossAbility.Kind.CUSTOM, "cooldown": 16.0, "telegraph": 1.0, "damage_mult": 0.3, "min_range": 6.0, "max_range": 28.0,
			"description": "She channels a beam of the void that slowly turns to follow you. Break line of sight behind an Anchor pylon."},
		{"id": "call_the_hollow", "display_name": "Call the Hollow", "kind": BossAbility.Kind.SUMMON, "cooldown": 24.0, "telegraph": 1.2, "count": 3, "unit_id": "veilborne_mindbender", "min_phase": 2},
		{"id": "entropic_volley", "display_name": "Entropic Volley", "kind": BossAbility.Kind.VOLLEY, "cooldown": 8.0, "telegraph": 0.9, "count": 7, "spread_degrees": 70.0, "damage_mult": 0.8, "min_range": 4.0, "max_range": 24.0, "min_phase": 2, "damage_type": entropic},
		{"id": "unmaking", "display_name": "Unmaking", "kind": BossAbility.Kind.PULL, "cooldown": 14.0, "telegraph": 1.1, "radius": MawArena.MAW_RADIUS + 3.5, "pull_stop": MawArena.MAW_RADIUS + 1.5, "damage_mult": 2.0, "max_range": MawArena.OUTER_RADIUS + 4.0, "min_phase": 3, "damage_type": entropic},
		{"id": "collapse", "display_name": "Collapse", "kind": BossAbility.Kind.BLAST, "cooldown": 12.0, "telegraph": 1.2, "radius": 3.0, "count": 5, "damage_mult": 1.3, "max_range": 24.0, "min_phase": 3, "damage_type": entropic},
		{"id": "feed_the_maw", "display_name": "Feed the Maw", "kind": BossAbility.Kind.CUSTOM, "cooldown": 22.0, "telegraph": FEED_CHANNEL_SEC, "max_range": 60.0, "min_phase": 3,
			"description": "She stands at the Maw's lip and feeds it: two plates fall at once and the next bite comes sooner. Hit her hard enough to break the channel."},
	]

func phase_openers() -> Dictionary:
	return {2: "call_the_hollow", 3: "unmaking"}

## A lance down the line you stand on, then a grasp that stops at the Maw's
## edge (an Anchor pylon holds you against it).
func range_answers() -> Array:
	var entropic := Constants.DamageType.ENTROPIC
	return [
		{"id": "entropic_lance", "display_name": "Entropic Lance", "kind": BossAbility.Kind.LANCE, "telegraph": 0.9, "radius": 1.3, "damage_mult": 1.9, "damage_type": entropic},
		{"id": "grasp_of_the_void", "display_name": "Grasp of the Void", "kind": BossAbility.Kind.PULL, "telegraph": 1.2, "radius": MawArena.MAW_RADIUS + 3.5, "pull_stop": MawArena.MAW_RADIUS + 1.5, "damage_mult": 1.7, "damage_type": entropic},
	]

func range_answer_distance() -> float:
	return 16.0

func arena() -> MawArena:
	if not is_instance_valid(_arena) and is_inside_tree():
		_arena = get_tree().get_first_node_in_group("maw_arena") as MawArena
	return _arena

## Unmaking drags you to the open Maw rather than to her.
func get_pull_center() -> Vector3:
	var a := arena()
	return a.maw_center() if a and a.maw_open else super.get_pull_center()

func is_player_anchored(player_node: Player) -> bool:
	var a := arena()
	return a != null and a.is_anchored(player_node.global_position)

## Shadow Lunge into a pylon: she stops dead, stunned.
func blocks_charge(direction: Vector3) -> bool:
	var a := arena()
	var pylon := a.pylon_in_path(global_position, direction, body_radius + 0.4) if a else null
	if pylon == null:
		return false
	pylon.wear(MawArena.PYLON_WEAR_LUNGE)
	status_effects.apply_timed_effect("stun", LUNGE_STUN_SEC)
	interrupt_attack()
	# Slammed into the pylon: Composure drained and a Riposte window open.
	if stance:
		stance.apply_parry_damage(LUNGE_STANCE_DAMAGE)
	if composure and not composure.is_broken:
		composure.enter_broken_state()
	return true

## Her Mindbenders go for the pylons while any stand.
func on_unit_summoned(unit: Enemy) -> void:
	var a := arena()
	if a == null or a.pylons_standing() == 0:
		return
	var channel := MawChannel.new()
	channel.arena = a
	unit.add_child(channel)

## Phase 3: every pylon saved weakens the Maw's opening Unmaking.
func _on_phase(p: int) -> void:
	var a := arena()
	var unmaking := boss_brain.find("unmaking") if boss_brain else null
	if p >= 3 and a and unmaking:
		unmaking.damage_mult *= a.opening_strength()

func _on_died() -> void:
	var a := arena()
	if randf() < Pinnacle.maw_lens_chance(a.pylons_standing() if a else 0):
		var lens := Pinnacle.make_maw_lens(_compute_item_level())
		if lens:
			_spawn_pickup(lens)
	super._on_died()

func roar_sound() -> AudioStream:
	return SoundLib.pick_random(SoundLib.library.boss_ghost_moan)

func on_melee_strike() -> void:
	var melee := get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	var reach := melee.attack_range if melee else 4.0
	var dir := _flat_to_player()
	var color := BossFx.glow_of(Constants.DamageType.ENTROPIC)
	SpellFx.sweep(get_parent(), global_position, dir, reach + 0.6, LASH_HALF_ANGLE, color, 0.24, 1.0 if randf() < 0.5 else -1.0, 1.1)
	SpellFx.flash(get_parent(), get_cast_origin() + dir * 0.6, color, 2.0, 0.2)
	SpellFx.burst(get_parent(), global_position + dir * reach * 0.7 + Vector3.UP, color, 24, Vector2(2, 5), 0.4, Vector2(0.12, 0.24), 90.0, 0.0)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_whoosh), global_position, 0.0, 0.8)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_void_burst), global_position + dir * reach * 0.6, -6.0, 1.2)

## Void Beam turn rate this phase: 20, 40, then 60 degrees a second.
func beam_turn_deg_per_sec() -> float:
	var p := boss_brain.phase if boss_brain else 1
	return BEAM_TURN_DEG_PER_SEC + BEAM_TURN_PER_PHASE * (p - 1)

## Phases 2 and 3: Shadow Lunge ends in a slash all the way round her, after
## a short warning ring.
const LUNGE_SLASH_RADIUS := 4.5
const LUNGE_SLASH_TELEGRAPH := 0.4
const LUNGE_SLASH_SHARE := 0.8

func on_charge_end(a: BossAbility) -> void:
	if a.id != "shadow_lunge" or boss_brain == null or boss_brain.phase < 2:
		return
	var tint: Color = Constants.DAMAGE_TYPE_COLOR[Constants.DamageType.ENTROPIC]
	BossTelegraph.circle(get_parent(), global_position, LUNGE_SLASH_RADIUS, LUNGE_SLASH_TELEGRAPH, tint)
	await get_tree().create_timer(LUNGE_SLASH_TELEGRAPH, false).timeout
	if not is_instance_valid(self) or not health.is_alive() or not is_inside_tree():
		return
	var color := BossFx.glow_of(Constants.DamageType.ENTROPIC)
	SpellFx.sweep(get_parent(), global_position, _flat_to_player(), LUNGE_SLASH_RADIUS + 0.6, 180.0, color, 0.3, 1.0, 1.1)
	SpellFx.shockwave(get_parent(), global_position, LUNGE_SLASH_RADIUS, color)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_whoosh), global_position, 0.0, 0.7)
	var p := get_tree().get_first_node_in_group("player") as Player
	if p:
		var flat := p.global_position - global_position
		flat.y = 0.0
		if flat.length() <= LUNGE_SLASH_RADIUS:
			boss_brain._damage_player(a, LUNGE_SLASH_SHARE)

## ---- The floor works against her too --------------------------------------

func _on_riposte(_source: Node, target: Node) -> void:
	if target == self:
		_knock_back()

func _on_damage_dealt(source: Node, target: Node, amount: float, damage_type: int, _more: bool, _crit: bool) -> void:
	if target != self or not source is Player:
		return
	if feeding:
		_feed_damage += amount
	if damage_type == Constants.DamageType.EXPLOSIVE and amount >= health.max_health * HEAVY_EXPLOSIVE_SHARE:
		_knock_back()

## Shoved away from the player; over missing floor she clings to the lip.
func _knock_back() -> void:
	var a := arena()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if a == null or player == null or not health.is_alive() or a.is_clinging():
		return
	var away := global_position - player.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else -global_transform.basis.z
	if not a.cling(self, away, KNOCKBACK_DISTANCE):
		# An impulse decays at KNOCKBACK_FRICTION, travelling v^2 / 2f.
		_knockback += away * sqrt(2.0 * KNOCKBACK_FRICTION * KNOCKBACK_DISTANCE)

## While she clings, hits land harder.
func take_damage(amount: float, damage_type: Constants.DamageType, is_spell: bool = false, can_evade: bool = false, is_dot: bool = false, ignore_armor: bool = false) -> bool:
	var a := arena()
	if a and a.is_clinging():
		amount *= MawArena.CLING_DAMAGE_TAKEN
	return super.take_damage(amount, damage_type, is_spell, can_evade, is_dot, ignore_armor)

## Phase 3: no ranged pressure while she feeds, and only with the Maw open.
func can_use_ability(a: BossAbility) -> bool:
	if a.id == "feed_the_maw":
		var ar := arena()
		return ar != null and ar.maw_open and not ar.is_clinging()
	return true

func cast_custom(a: BossAbility) -> void:
	if a.id == "void_beam":
		await _void_beam(a)
		return
	if a.id != "feed_the_maw":
		await get_tree().process_frame
		return
	var ar := arena()
	if ar == null:
		return
	var lip := ar.lip_point(global_position)
	var tween := create_tween()
	tween.tween_property(self, "global_position", lip, 0.5)
	await tween.finished
	if not health.is_alive():
		return
	feeding = true
	_feed_damage = 0.0
	begin_channel(a.telegraph)
	var tendrils := _feed_tendrils(ar.maw_center(), a.telegraph)
	BossFx.sound(roar_sound(), global_position, 0.0, 0.85)
	var targets := ar.mark_feed_targets(a.telegraph)
	var left := a.telegraph
	while left > 0.0 and health.is_alive():
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()
		if _feed_damage >= health.max_health * FEED_BREAK_SHARE or status_effects.is_stunned():
			break
	feeding = false
	if is_instance_valid(tendrils):
		tendrils.emitting = false
		SpellFx.free_after(tendrils, 1.0)
	if not health.is_alive():
		return
	if left > 0.0:
		# Broken: the bite is called off and she reels.
		ar.cancel_feed(targets)
		interrupt_attack()
		if stance:
			stance.apply_parry_damage(FEED_STANCE_DAMAGE)
		status_effects.apply_timed_effect("stun", 1.5)
		SpellFx.flash(get_parent(), get_cast_origin(), BEAM_COLOR, 3.0, 0.3)
	else:
		BossFx.impact(get_parent(), ar.maw_center(), MawArena.MAW_RADIUS, Constants.DamageType.ENTROPIC)
		ar.feed(targets)

## ---- Void Beam -------------------------------------------------------------

## Channels a beam that starts on the player and turns after them at
## BEAM_TURN_DEG_PER_SEC; a standing pylon cuts it short, so pylons are cover.
func _void_beam(a: BossAbility) -> void:
	var dir := _flat_to_player()
	var origin := global_position
	BossTelegraph.line(get_parent(), origin, dir, BEAM_LENGTH, BEAM_WIDTH, a.telegraph, BEAM_COLOR)
	begin_attack_telegraph(a.telegraph)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.ENTROPIC, a.telegraph)
	await get_tree().create_timer(a.telegraph, false).timeout
	if not health.is_alive():
		return
	begin_channel(BEAM_CHANNEL_SEC)
	BossFx.sound(SoundLib.library.boss_beam_start, global_position, 2.0)
	var beam := _make_beam_mesh()
	get_parent().add_child(beam)
	var tick_damage := get_ability_base_damage() * a.damage_mult
	var left := BEAM_CHANNEL_SEC
	var tick := 0.0
	while left > 0.0 and health.is_alive() and not status_effects.is_stunned():
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		left -= dt
		var want := _flat_to_player()
		var turn_rate := deg_to_rad(beam_turn_deg_per_sec())
		var turn := clampf(dir.signed_angle_to(want, Vector3.UP), -turn_rate * dt, turn_rate * dt)
		dir = dir.rotated(Vector3.UP, turn).normalized()
		origin = global_position
		var length := beam_length(origin, dir)
		# The pylon taking the beam wears down while it holds.
		if is_instance_valid(beam_blocker) and beam_blocker.alive:
			beam_blocker.wear(MawArena.PYLON_WEAR_BEAM_PER_SEC * dt)
		_place_beam(beam, origin, dir, length)
		tick -= dt
		if tick <= 0.0:
			tick = BEAM_TICK
			var p := get_tree().get_first_node_in_group("player") as Player
			if p and _beam_hits(p.global_position, origin, dir, length):
				p.take_damage(tick_damage, Constants.DamageType.ENTROPIC, self, Player.HitKind.SPELL)
	if is_inside_tree():
		SpellFx.flash(get_parent(), get_cast_origin(), BEAM_COLOR, 2.5, 0.3)
	beam.queue_free()

## How far the beam reaches before the first standing pylon in its way;
## that pylon is left in beam_blocker (null when nothing blocks it).
func beam_length(origin: Vector3, dir: Vector3) -> float:
	var length := BEAM_LENGTH
	beam_blocker = null
	var a := arena()
	if a == null:
		return length
	for pylon in a.pylons:
		if not pylon.alive:
			continue
		var offset := pylon.global_position - origin
		offset.y = 0.0
		var along := offset.dot(dir)
		var side := (offset - dir * along).length()
		if along > 0.0 and side < MawPylon.RADIUS:
			var hit := along - sqrt(MawPylon.RADIUS * MawPylon.RADIUS - side * side)
			if hit < length:
				length = hit
				beam_blocker = pylon
	return maxf(length, 0.0)

func _beam_hits(point: Vector3, origin: Vector3, dir: Vector3, length: float) -> bool:
	var rel := point - origin
	rel.y = 0.0
	var along := rel.dot(dir)
	return along >= 0.0 and along <= length and (rel - dir * along).length() <= BEAM_WIDTH * 0.5 + 0.4

func _flat_to_player() -> Vector3:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var to := (p.global_position - global_position) if p else -global_transform.basis.z
	to.y = 0.0
	return to.normalized() if to.length() > 0.05 else Vector3.FORWARD

## A white-hot core inside a violet sheath, sparks where it ends, a hum.
func _make_beam_mesh() -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	beam.mesh = _beam_cylinder(0.5)
	beam.material_override = _beam_material(Color(BEAM_COLOR, 0.45))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for layer in [["Core", 0.16, Color(1.0, 0.9, 1.0, 1.0)], ["Inner", 0.3, Color(0.85, 0.55, 1.0, 0.6)]]:
		var mi := MeshInstance3D.new()
		mi.name = layer[0]
		mi.mesh = _beam_cylinder(layer[1])
		mi.material_override = _beam_material(layer[2])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.add_child(mi)
	var sparks := SpellFx.emitter(beam, 40, 0.4)
	sparks.name = "EndSparks"
	sparks.top_level = true
	sparks.spread = 180.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 5.0
	sparks.gravity = Vector3(0, -6, 0)
	sparks.scale_amount_min = 0.06
	sparks.scale_amount_max = 0.14
	sparks.color_ramp = SpellFx.ramp(Color(1, 1, 1, 1), Color(BEAM_COLOR.lightened(0.3), 0.9), 0.2)
	sparks.mesh = SpellFx.glow_quad()
	var light := OmniLight3D.new()
	light.name = "EndLight"
	light.top_level = true
	light.light_color = BEAM_COLOR
	light.light_energy = 2.5
	light.omni_range = 5.0
	beam.add_child(light)
	var hum := AudioStreamPlayer3D.new()
	hum.name = "Hum"
	hum.top_level = true
	hum.stream = SoundLib.library.boss_beam_loop
	if hum.stream is AudioStreamOggVorbis:
		(hum.stream as AudioStreamOggVorbis).loop = true
	hum.unit_size = 10.0
	hum.autoplay = hum.stream != null
	beam.add_child(hum)
	return beam

static func _beam_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat

static func _beam_cylinder(radius: float) -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 1.0
	cylinder.radial_segments = 10
	return cylinder

func _place_beam(beam: MeshInstance3D, origin: Vector3, dir: Vector3, length: float) -> void:
	var from := origin + Vector3(0, BEAM_HEIGHT, 0)
	var side := dir.cross(Vector3.UP).normalized()
	var width := BEAM_WIDTH * (1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.03))
	# The cylinder's Y axis runs along the beam.
	beam.global_transform = Transform3D(Basis(side * width, dir * maxf(length, 0.05), side.cross(dir) * width), from + dir * length / 2.0)
	var end := from + dir * length
	for n in ["EndSparks", "EndLight"]:
		(beam.get_node(n) as Node3D).global_position = end
	# The hum follows the nearest point of the beam to the listener.
	var hum := beam.get_node("Hum") as Node3D
	var camera := get_viewport().get_camera_3d()
	var t := clampf((camera.global_position - from).dot(dir), 0.0, length) if camera else 0.0
	hum.global_position = from + dir * t

## Violet motes drawn from her hands down into the Maw while she feeds it.
func _feed_tendrils(maw_center: Vector3, seconds: float) -> CPUParticles3D:
	var p := SpellFx.emitter(get_parent(), 50, 0.9)
	p.global_position = get_cast_origin()
	var down := maw_center - get_cast_origin()
	p.direction = down.normalized()
	p.spread = 15.0
	p.initial_velocity_min = down.length() * 0.8
	p.initial_velocity_max = down.length() * 1.2
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.35
	p.color_ramp = SpellFx.ramp(Color(BEAM_COLOR.lightened(0.4), 0.9), Color(BEAM_COLOR, 0.7), 0.2)
	p.mesh = SpellFx.glow_quad()
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.ENTROPIC, seconds, false)
	return p
