extends PinnacleBoss
class_name Almighty
## Test Pinnacle boss for the classic-MDX pipeline (the Yhwach models in
## assets/models/enemies/pinnacle/almighty/; a fan model of a Bleach
## character, so placeholder only). Fought in the AlmightyArena. Built to
## find how stressful a Pinnacle can be: short gaps between casts, fast
## telegraphs, chained blinks, and a kill attack that can't be dodged.
##   Phase 1, "The Sealed King" (Aetheric): Flash Step (blinks behind you
##   and cuts, 2-3 times), Sacred Arrows, Heaven's Rain, Star Seal.
##   Phase 2 (60%): opens with Spirit Lances (beams across the arena through
##   you); Star Seal draws a second star.
##   Phase 3 (25%): he can't be pushed lower: a cocoon of eyes, the Almighty
##   model, back to full Life with new health-bar marks. Entropic from here.
##   Opens with Selection (columns of light that heal him when they hit);
##   Black Tide, Black Mire, Foreseen.
##   Phase 4 (60%): opens with Eyes of the Almighty: he hovers at the centre
##   while giant eyes round the rim aim and fire beams and two beams sweep
##   the floor from him.
##   Phase 5 (30%): opens with the Verdict: a long channel that kills you
##   outright when it ends unless you deal VERDICT_BREAK_SHARE of his Life
##   first; it comes back on a cooldown. Nightfall (in, then out).

const SEALED_NAME := "The Sealed King"
const AWAKENED_NAME := "The Almighty"
const AWAKENED_MODEL := preload("res://entities/enemies/models/AlmightyAwakenedModel.tscn")
const EYE_TEXTURE := preload("res://assets/models/enemies/pinnacle/almighty/Yhwach_Almighty/ZK_YOUHA.png")
const OVERLAY_SHADER := preload("res://entities/enemies/models/mdx_overlay_layer.gdshader")
const LIFE := 145_000_000.0
const AWAKEN_AT := 0.25
## Health-bar marks per form: the Sealed King's (phases 2-3), then the
## Almighty's on his new bar (phases 4-5). phase_thresholds() is both.
const SEALED_MARKS: Array[float] = [0.6, 0.25]
const AWAKENED_MARKS: Array[float] = [0.6, 0.3]
## Oppressive pacing: a short gap between casts, cooldowns shortening each phase.
const GLOBAL_GAP := 0.5
const OPENING_GAP := 1.0
const PHASE_COOLDOWN_SCALE: Array[float] = [0.9, 0.8, 0.7, 0.6, 0.5]
## The cocoon closes over AWAKEN_GATHER; he heals inside it over AWAKEN_HOLD.
const AWAKEN_GATHER := 1.6
const AWAKEN_HOLD := 1.8
const AETHER_COLOR := Color(0.45, 0.75, 1.0)
const VOID_COLOR := Color(0.58, 0.42, 1.0)
const LIGHT_COLOR := Color(0.85, 0.92, 1.0)
## Flash Step: he reappears this far behind you and cuts around himself.
const STEP_BEHIND := 2.4
const STEP_RADIUS := 3.6
const STEP_TELEGRAPH := 0.45
const STEP_GAP := 0.15
## Star Seal: a five-pointed star of this radius around the player.
const STAR_RADIUS := 5.5
const STAR_LINE_WIDTH := 1.3
## Heaven's Rain: arrows fall around (and on) the player for HEAVEN_SEC.
const HEAVEN_ARROWS := 16
const HEAVEN_SEC := 2.4
const HEAVEN_SPREAD := 4.5
const HEAVEN_RADIUS := 1.5
const HEAVEN_TELEGRAPH := 0.7
## Spirit Lances: beams across the arena, each through the player.
const LANCES := 6
const LANCE_LENGTH := 60.0
const LANCE_WIDTH := 1.4
const LANCE_STAGGER := 0.12
## Selection: columns of light; each that hits heals him.
const SELECTION_COLUMNS := 8
const SELECTION_RADIUS := 1.8
const SELECTION_TELEGRAPH := 0.9
const SELECTION_HEAL_SHARE := 0.005
## Foreseen: each circle aims at where the player will be when it lands.
const FORESEE_STEPS := 4
const FORESEE_GAP := 0.45
const FORESEE_TELEGRAPH := 1.0
const FORESEE_RADIUS := 2.4
## Eyes of the Almighty.
const EYES := 6
const EYES_RING := 16.0
const EYES_HEIGHT := 1.7
const EYE_RADIUS := 1.1
const EYES_CHANNEL_SEC := 11.0
const EYE_AIM := 0.9
const EYE_FIRE := 0.5
const EYE_REST := 1.2
const EYE_BEAM_WIDTH := 1.3
const EYE_BEAM_LENGTH := 45.0
const HOVER_HEIGHT := 2.5
## Floor beams run at waist height, under the player's eye line.
const BEAM_HEIGHT := 0.75
## Two beams from him sweep the floor; they turn back halfway through.
const SWEEP_DEG_PER_SEC := 22.0
const SWEEP_START := 2.0
const SWEEP_TICK := 0.25
const SWEEP_TICK_SHARE := 0.3
## The Verdict.
const VERDICT_SEC := 8.0
const VERDICT_BREAK_SHARE := 0.03
const VERDICT_STUN := 3.0
## Nightfall: dark falls outside NIGHT_INNER, then inside it.
const NIGHT_INNER := 7.0
const NIGHT_OUT_TELEGRAPH := 1.2
const NIGHT_IN_TELEGRAPH := 0.8

var awakened := false
var _arena: AlmightyArena

func _ready() -> void:
	super._ready()
	display_name = SEALED_NAME
	_set_melee_type(Constants.DamageType.AETHERIC)
	if boss_brain:
		boss_brain.global_gap = GLOBAL_GAP
		boss_brain.opening_gap = OPENING_GAP
		boss_brain._gap = OPENING_GAP
		boss_brain.phase_cooldown_scale = PHASE_COOLDOWN_SCALE
		boss_brain.phase_changed.connect(_on_phase)

func pinnacle_life() -> float:
	return LIFE

func phase_thresholds() -> Array[float]:
	var all: Array[float] = []
	all.append_array(SEALED_MARKS)
	all.append_array(AWAKENED_MARKS)
	return all

func boss_bar_marks() -> Array[float]:
	return AWAKENED_MARKS.duplicate() if awakened else SEALED_MARKS.duplicate()

func abilities() -> Array:
	var aether := Constants.DamageType.AETHERIC
	var entropic := Constants.DamageType.ENTROPIC
	return [
		{"id": "flash_step", "display_name": "Flash Step", "kind": BossAbility.Kind.CUSTOM, "cooldown": 6.0, "damage_mult": 1.1, "max_range": 30.0, "weight": 1.4,
			"description": "He vanishes and reappears behind you, cutting all round himself: twice while sealed, three times from phase 2."},
		{"id": "sacred_arrows", "display_name": "Sacred Arrows", "kind": BossAbility.Kind.VOLLEY, "cooldown": 5.0, "telegraph": 0.6, "count": 7, "spread_degrees": 60.0, "damage_mult": 0.7, "min_range": 4.0, "max_range": 26.0, "damage_type": aether},
		{"id": "heavens_rain", "display_name": "Heaven's Rain", "kind": BossAbility.Kind.CUSTOM, "cooldown": 9.0, "damage_mult": 1.0, "max_range": 30.0,
			"description": "Arrows of light fall around you, and every third one on you."},
		{"id": "star_seal", "display_name": "Star Seal", "kind": BossAbility.Kind.CUSTOM, "cooldown": 11.0, "telegraph": 1.1, "damage_mult": 1.8, "max_range": 26.0,
			"description": "A five-pointed star is drawn on the floor around you and bursts along its lines. Stand between them. From phase 2 a second star follows."},
		{"id": "spirit_lances", "display_name": "Spirit Lances", "kind": BossAbility.Kind.CUSTOM, "cooldown": 10.0, "telegraph": 0.8, "damage_mult": 1.4, "max_range": 40.0, "min_phase": 2,
			"description": "Beams cross the whole arena, every one of them through where you stand."},
		{"id": "selection", "display_name": "Selection", "kind": BossAbility.Kind.CUSTOM, "cooldown": 12.0, "damage_mult": 1.2, "max_range": 40.0, "min_phase": 3,
			"description": "Columns of light come down on and around you. Each one that hits you heals him."},
		{"id": "black_tide", "display_name": "Black Tide", "kind": BossAbility.Kind.WAVE, "cooldown": 9.0, "telegraph": 0.55, "radius": 2.6, "count": 7, "damage_mult": 1.2, "max_range": 24.0, "min_phase": 3, "damage_type": entropic},
		{"id": "black_mire", "display_name": "Black Mire", "kind": BossAbility.Kind.HAZARD, "cooldown": 10.0, "telegraph": 0.8, "radius": 3.5, "duration": 7.0, "damage_mult": 0.8, "max_range": 24.0, "min_phase": 3, "damage_type": entropic},
		{"id": "foreseen", "display_name": "Foreseen", "kind": BossAbility.Kind.CUSTOM, "cooldown": 9.0, "damage_mult": 1.5, "max_range": 30.0, "min_phase": 3,
			"description": "He sees where you are going: circles land on the spot you will reach if you keep moving the way you are. Change direction."},
		{"id": "eyes_of_the_almighty", "display_name": "Eyes of the Almighty", "kind": BossAbility.Kind.CUSTOM, "cooldown": 40.0, "damage_mult": 1.3, "max_range": 99.0, "min_phase": 4,
			"description": "He hovers at the centre while giant eyes round the rim aim beams at you, and two beams sweep the floor from him."},
		{"id": "verdict", "display_name": "The Verdict", "kind": BossAbility.Kind.CUSTOM, "cooldown": 45.0, "max_range": 99.0, "min_phase": 5, "weight": 0.5,
			"description": "A long channel. When it ends, you die, whatever your defences. Deal 3% of his Life before it does to break it."},
		{"id": "nightfall", "display_name": "Nightfall", "kind": BossAbility.Kind.CUSTOM, "cooldown": 14.0, "damage_mult": 2.0, "max_range": 40.0, "min_phase": 5,
			"description": "Darkness falls everywhere but close to him; then, at once, close to him."},
	]

func phase_openers() -> Dictionary:
	return {2: "spirit_lances", 3: "selection", 4: "eyes_of_the_almighty", 5: "verdict"}

## Keep away and he steps onto your spot, then looses a bolt down your line.
## damage_type -1: Aetheric while sealed, Entropic once awakened (the melee's type).
func range_answers() -> Array:
	return [
		{"id": "sacred_step", "display_name": "Sacred Step", "kind": BossAbility.Kind.BLINK, "telegraph": 0.8, "radius": 3.2, "damage_mult": 1.6},
		{"id": "sacred_bow", "display_name": "Sacred Bow", "kind": BossAbility.Kind.LANCE, "telegraph": 0.7, "radius": 1.3, "damage_mult": 1.9},
	]

func range_answer_distance() -> float:
	return 12.0

func arena() -> AlmightyArena:
	if not is_instance_valid(_arena) and is_inside_tree():
		_arena = get_tree().get_first_node_in_group("almighty_arena") as AlmightyArena
	return _arena

func _on_phase(p: int) -> void:
	var a := arena()
	if a == null:
		return
	match p:
		2:
			a.announce("The seal weakens", AETHER_COLOR.lightened(0.3), 1.6, 44)
		4:
			a.announce("All is seen", VOID_COLOR.lightened(0.3), 1.6, 44)
		5:
			a.announce("Judgment", VOID_COLOR.lightened(0.3), 1.6, 54)

## Sealed, he can't be taken below AWAKEN_AT: the rest waits for his Almighty form.
func take_damage(amount: float, damage_type: Constants.DamageType, is_spell: bool = false, can_evade: bool = false, is_dot: bool = false, ignore_armor: bool = false) -> bool:
	if awakened:
		return super(amount, damage_type, is_spell, can_evade, is_dot, ignore_armor)
	var floor_life := health.max_health * AWAKEN_AT
	if health.current_health <= floor_life:
		return false
	health.min_health = floor_life
	var landed := super(amount, damage_type, is_spell, can_evade, is_dot, ignore_armor)
	health.min_health = 0.0
	return landed

func _set_melee_type(damage_type: Constants.DamageType) -> void:
	var melee := get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	if melee:
		melee.damage_type = damage_type

func _target_player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout

func _damage_type() -> Constants.DamageType:
	return Constants.DamageType.ENTROPIC if awakened else Constants.DamageType.AETHERIC

func _color() -> Color:
	return VOID_COLOR if awakened else AETHER_COLOR

func _tell() -> Color:
	return Color(_color(), 0.5)

func _hit(ability: BossAbility, mult: float = 1.0) -> float:
	return get_ability_base_damage() * ability.damage_mult * mult

func _strike(p: Player, amount: float, damage_type: Constants.DamageType, is_melee: bool = false) -> void:
	p.take_damage(amount, damage_type, self, Player.HitKind.ATTACK if is_melee else Player.HitKind.SPELL, is_melee)

func _floor_y() -> float:
	return arena().global_position.y if arena() else global_position.y

func _on_floor(point: Vector3) -> Vector3:
	return Vector3(point.x, _floor_y(), point.z)

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _clamp_to_arena(spot: Vector3) -> Vector3:
	var a := arena()
	if a == null:
		return spot
	var local := a.to_local(spot)
	var flat := Vector2(local.x, local.z)
	if flat.length() > AlmightyArena.RADIUS - 1.0:
		flat = flat.normalized() * (AlmightyArena.RADIUS - 1.0)
	return a.to_global(Vector3(flat.x, local.y, flat.y))

## ---- Awakening -------------------------------------------------------------

func run_phase_transition(phase: int, seconds: float) -> void:
	if phase != SEALED_MARKS.size() + 1 or awakened:
		await super(phase, seconds)
		return
	await _awaken()

func _awaken() -> void:
	velocity = Vector3.ZERO
	begin_channel(AWAKEN_GATHER + AWAKEN_HOLD)
	if arena():
		arena().awaken(AWAKEN_GATHER + AWAKEN_HOLD)
	var centre := global_position + Vector3.UP * body_height * 0.5
	var cocoon := _make_eye_sphere(body_height * 0.62, Vector2(4.0, 2.0), Vector2(0.05, -0.25))
	get_parent().add_child(cocoon)
	cocoon.global_position = centre
	cocoon.scale = Vector3.ONE * 0.05
	create_tween().tween_property(cocoon, "scale", Vector3.ONE, AWAKEN_GATHER).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	SpellFx.burst(get_parent(), centre, Color(0.05, 0.04, 0.08), 50, Vector2(1, 3), 0.8, Vector2(0.15, 0.35), 180.0, 0.0)
	BossFx.sound(SoundLib.library.boss_deep_roar, global_position, 3.0, 0.8)
	await _wait(AWAKEN_GATHER)
	if not health.is_alive():
		cocoon.queue_free()
		return
	_swap_to_awakened()
	create_tween().tween_method(_set_life, health.current_health, health.max_health, AWAKEN_HOLD)
	await _wait(AWAKEN_HOLD)
	cocoon.queue_free()
	if not health.is_alive():
		return
	awakened = true
	display_name = AWAKENED_NAME
	_set_melee_type(Constants.DamageType.ENTROPIC)
	_set_life(health.max_health)
	SpellFx.flash(get_parent(), centre, Color(0.85, 0.82, 1.0), 7.0, 0.4)
	SpellFx.shockwave(get_parent(), global_position + Vector3.UP * 0.05, 12.0, Color(0.3, 0.2, 0.5), 0.7)
	SpellFx.burst(get_parent(), centre, Color(0.04, 0.03, 0.06), 90, Vector2(7, 14), 1.0, Vector2(0.15, 0.4), 180.0, -3.0)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_heavy_impact), global_position, 6.0, 0.7)
	if arena():
		arena().announce(AWAKENED_NAME, VOID_COLOR.lightened(0.35), 2.0, 64)
	await _wait(0.4)

func _set_life(value: float) -> void:
	health.current_health = value
	health.health_changed.emit(value, health.max_health)

## The Almighty model takes over, facing where the Sealed King faced.
func _swap_to_awakened() -> void:
	var yaw: float = _model_root.rotation.y if _model_root else definition.model_yaw_offset
	if _anim_controller:
		_anim_controller.queue_free()
		_anim_controller = null
	if _model_root:
		_model_root.queue_free()
		_model_root = null
	_install_model(AWAKENED_MODEL, definition.animation_set, definition.scale_modifier, definition.model_yaw_offset)
	_model_root.rotation.y = yaw

## A black sphere crawling with the Almighty's eyes (the cocoon, the rim eyes).
func _make_eye_sphere(radius: float, uv_scale: Vector2, uv_scroll: Vector2) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.01, 0.01, 0.015)
	var eyes := ShaderMaterial.new()
	eyes.shader = OVERLAY_SHADER
	eyes.set_shader_parameter("layer_texture", EYE_TEXTURE)
	eyes.set_shader_parameter("uv_scale", uv_scale)
	eyes.set_shader_parameter("uv_scroll", uv_scroll)
	mat.next_pass = eyes
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## ---- Custom abilities ----------------------------------------------------------

func cast_custom(ability: BossAbility) -> void:
	match ability.id:
		"flash_step":
			await _flash_step(ability)
		"heavens_rain":
			await _heavens_rain(ability)
		"star_seal":
			await _star_seal(ability)
			if boss_brain and boss_brain.phase >= 2 and health.is_alive():
				await _star_seal(ability)
		"spirit_lances":
			await _spirit_lances(ability)
		"selection":
			await _selection(ability)
		"foreseen":
			await _foreseen(ability)
		"eyes_of_the_almighty":
			await _eyes_of_the_almighty(ability)
		"verdict":
			await _verdict()
		"nightfall":
			await _nightfall(ability)
		_:
			await get_tree().process_frame

## Blinks behind the player and cuts all round himself, 2 or 3 times.
func _flash_step(ability: BossAbility) -> void:
	var cuts := 2 if boss_brain == null or boss_brain.phase < 2 else 3
	for i in cuts:
		var p := _target_player()
		if p == null or not health.is_alive():
			break
		var behind := p.global_transform.basis.z
		behind.y = 0.0
		behind = behind.normalized() if behind.length() > 0.05 else Vector3.BACK
		var spot := _on_floor(_clamp_to_arena(p.global_position + behind * STEP_BEHIND))
		BossFx.blink(get_parent(), global_position, spot, _damage_type())
		global_position = spot
		velocity = Vector3.ZERO
		BossTelegraph.circle(get_parent(), spot, STEP_RADIUS, STEP_TELEGRAPH, _tell())
		begin_attack_telegraph(STEP_TELEGRAPH)
		await _wait(STEP_TELEGRAPH)
		if not health.is_alive():
			return
		var facing := p.global_position - global_position
		facing.y = 0.0
		facing = facing.normalized() if facing.length() > 0.05 else -global_transform.basis.z
		SpellFx.sweep(get_parent(), global_position + Vector3.UP * 1.3, facing, STEP_RADIUS + 0.6, 170.0, _color(), 0.22, 1.0 if i % 2 == 0 else -1.0)
		BossFx.sound(BossFx.cast_sound(_damage_type()), global_position, 0.0, 1.4)
		if p.health.is_alive() and _flat_distance(p.global_position, global_position) <= STEP_RADIUS + 0.3:
			_strike(p, _hit(ability), _damage_type(), true)
		await _wait(STEP_GAP)

## Arrows of light fall around the player for HEAVEN_SEC; every third on them.
func _heavens_rain(ability: BossAbility) -> void:
	begin_channel(HEAVEN_SEC)
	BossFx.charge(self, get_cast_origin(), _damage_type(), 0.5, true)
	var gap := HEAVEN_SEC / HEAVEN_ARROWS
	for i in HEAVEN_ARROWS:
		var p := _target_player()
		if p == null or not health.is_alive():
			break
		var spot := p.global_position
		if i % 3 != 0:
			var a := randf() * TAU
			spot += Vector3(sin(a), 0.0, cos(a)) * randf_range(1.0, HEAVEN_SPREAD)
		_rain_arrow(_on_floor(_clamp_to_arena(spot)), ability)
		await _wait(gap)
	await _wait(HEAVEN_TELEGRAPH)

func _rain_arrow(spot: Vector3, ability: BossAbility) -> void:
	BossTelegraph.circle(get_parent(), spot, HEAVEN_RADIUS, HEAVEN_TELEGRAPH, _tell())
	var arrow := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.03
	shaft.bottom_radius = 0.09
	shaft.height = 3.2
	arrow.mesh = shaft
	arrow.material_override = SpellFx.glow_material(LIGHT_COLOR, true, BaseMaterial3D.BILLBOARD_DISABLED)
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(arrow)
	arrow.global_position = spot + Vector3.UP * 18.0
	var tween := arrow.create_tween()
	tween.tween_property(arrow, "global_position", spot + Vector3.UP * 1.4, HEAVEN_TELEGRAPH).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(arrow.queue_free)
	await _wait(HEAVEN_TELEGRAPH)
	if not is_inside_tree() or not health.is_alive():
		return
	SpellFx.flash(get_parent(), spot + Vector3.UP * 0.4, _color(), 2.2, 0.25)
	SpellFx.shards(get_parent(), spot + Vector3.UP * 0.2, LIGHT_COLOR, 10)
	var p := _target_player()
	if p and p.health.is_alive() and _flat_distance(p.global_position, spot) <= HEAVEN_RADIUS + 0.3:
		_strike(p, _hit(ability), _damage_type())

## A pentagram around the player's spot; each of its five lines bursts in a wall of light.
func _star_seal(ability: BossAbility) -> void:
	var p := _target_player()
	if p == null:
		await get_tree().process_frame
		return
	var centre := _on_floor(p.global_position)
	var turn := randf() * TAU
	var points: Array[Vector3] = []
	for i in 5:
		var a := turn + TAU * i / 5.0
		points.append(centre + Vector3(sin(a), 0.0, cos(a)) * STAR_RADIUS)
	begin_channel(ability.telegraph)
	BossFx.charge(self, get_cast_origin(), _damage_type(), ability.telegraph, true)
	for i in 5:
		var from := points[i]
		var to := points[(i + 2) % 5]
		BossTelegraph.line(get_parent(), from, to - from, from.distance_to(to), STAR_LINE_WIDTH, ability.telegraph, _tell())
	await _wait(ability.telegraph)
	if not health.is_alive():
		return
	for i in 5:
		var from := points[i]
		var to := points[(i + 2) % 5]
		AlmightyBeam.fire(get_parent(), from + Vector3.UP * 0.5, to - from, from.distance_to(to), _color(), STAR_LINE_WIDTH, 0.45)
	SpellFx.shockwave(get_parent(), centre + Vector3.UP * 0.05, STAR_RADIUS, _color(), 0.4)
	BossFx.sound(BossFx.cast_sound(_damage_type()), centre, 2.0, 0.8)
	p = _target_player()
	if p and p.health.is_alive():
		for i in 5:
			if _segment_distance(p.global_position, points[i], points[(i + 2) % 5]) <= STAR_LINE_WIDTH * 0.5 + 0.3:
				_strike(p, _hit(ability), _damage_type())
				break

static func _segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var p2 := Vector2(point.x, point.z)
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var ab := b2 - a2
	var t := clampf((p2 - a2).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p2.distance_to(a2 + ab * t)

## Beams across the arena at even angles, each through the player's spot as
## it's drawn, one after another.
func _spirit_lances(ability: BossAbility) -> void:
	begin_channel(ability.telegraph + LANCES * LANCE_STAGGER)
	BossFx.charge(self, get_cast_origin(), _damage_type(), ability.telegraph, true)
	var turn := randf() * PI
	for i in LANCES:
		var p := _target_player()
		if p == null or not health.is_alive():
			break
		var a := turn + PI * i / LANCES
		var dir := Vector3(sin(a), 0.0, cos(a))
		var from := _on_floor(p.global_position) - dir * LANCE_LENGTH * 0.5
		BossTelegraph.line(get_parent(), from, dir, LANCE_LENGTH, LANCE_WIDTH, ability.telegraph, _tell())
		_fire_lance(from, dir, ability)
		await _wait(LANCE_STAGGER)
	await _wait(ability.telegraph)

func _fire_lance(from: Vector3, dir: Vector3, ability: BossAbility) -> void:
	await _wait(ability.telegraph)
	if not is_inside_tree() or not health.is_alive():
		return
	var beam := AlmightyBeam.fire(get_parent(), from + Vector3.UP * BEAM_HEIGHT, dir, LANCE_LENGTH, _color(), LANCE_WIDTH, 0.35)
	BossFx.sound(BossFx.cast_sound(_damage_type()), from + dir * LANCE_LENGTH * 0.5, -2.0, 1.2)
	var p := _target_player()
	if p and p.health.is_alive() and beam.hits(p.global_position, 0.3):
		_strike(p, _hit(ability), _damage_type())

## Columns of light on and around the player; each one that hits heals him.
func _selection(ability: BossAbility) -> void:
	var p := _target_player()
	if p == null:
		await get_tree().process_frame
		return
	begin_channel(SELECTION_TELEGRAPH + 0.6)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.AETHERIC, SELECTION_TELEGRAPH, true)
	var centre := p.global_position
	for i in SELECTION_COLUMNS:
		var spot := centre
		if i > 0:
			var a := TAU * i / (SELECTION_COLUMNS - 1) + randf() * 0.3
			spot += Vector3(sin(a), 0.0, cos(a)) * randf_range(2.5, 6.0)
		_selection_column(_on_floor(_clamp_to_arena(spot)), ability)
		await _wait(0.06)
	await _wait(SELECTION_TELEGRAPH + 0.2)

func _selection_column(spot: Vector3, ability: BossAbility) -> void:
	BossTelegraph.circle(get_parent(), spot, SELECTION_RADIUS, SELECTION_TELEGRAPH, Color(LIGHT_COLOR, 0.45))
	await _wait(SELECTION_TELEGRAPH)
	if not is_inside_tree() or not health.is_alive():
		return
	AlmightyBeam.fire(get_parent(), spot + Vector3.UP * 20.0, Vector3.DOWN, 20.0, AETHER_COLOR, SELECTION_RADIUS * 1.3, 0.5)
	SpellFx.flash(get_parent(), spot + Vector3.UP * 0.4, LIGHT_COLOR, 3.0, 0.3)
	var p := _target_player()
	if p and p.health.is_alive() and _flat_distance(p.global_position, spot) <= SELECTION_RADIUS + 0.3:
		_strike(p, _hit(ability), Constants.DamageType.AETHERIC)
		# What he takes flows back to him.
		SpellFx.burst(get_parent(), p.global_position + Vector3.UP, LIGHT_COLOR, 20, Vector2(3, 6), 0.6)
		health.heal(health.max_health * SELECTION_HEAL_SHARE)
		SpellFx.flash(get_parent(), get_cast_origin(), LIGHT_COLOR, 2.0, 0.3)

## Circles one after another, each on where the player will be by the time
## it lands if they keep their current heading.
func _foreseen(ability: BossAbility) -> void:
	begin_channel(FORESEE_STEPS * FORESEE_GAP + FORESEE_TELEGRAPH)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.ENTROPIC, 0.6, true)
	for i in FORESEE_STEPS:
		var p := _target_player()
		if p == null or not health.is_alive():
			break
		var heading := Vector3(p.velocity.x, 0.0, p.velocity.z)
		var spot := _on_floor(_clamp_to_arena(p.global_position + heading * FORESEE_TELEGRAPH))
		_foreseen_circle(spot, ability)
		await _wait(FORESEE_GAP)
	await _wait(FORESEE_TELEGRAPH)

func _foreseen_circle(spot: Vector3, ability: BossAbility) -> void:
	BossTelegraph.circle(get_parent(), spot, FORESEE_RADIUS, FORESEE_TELEGRAPH, _tell())
	await _wait(FORESEE_TELEGRAPH)
	if not is_inside_tree() or not health.is_alive():
		return
	AlmightyBeam.fire(get_parent(), spot + Vector3.UP * 12.0, Vector3.DOWN, 12.0, VOID_COLOR, FORESEE_RADIUS * 1.2, 0.4)
	SpellFx.burst(get_parent(), spot + Vector3.UP * 0.3, Color(0.05, 0.04, 0.08), 26, Vector2(3, 7), 0.6, Vector2(0.1, 0.25), 70.0, -6.0)
	var p := _target_player()
	if p and p.health.is_alive() and _flat_distance(p.global_position, spot) <= FORESEE_RADIUS + 0.3:
		_strike(p, _hit(ability), Constants.DamageType.ENTROPIC)

## ---- Eyes of the Almighty --------------------------------------------------------

## He blinks to the centre and hovers; EYES giant eyes open round the rim and
## each, in turn, aims a beam at the player and fires; from SWEEP_START two
## beams from him sweep the floor, turning back halfway.
func _eyes_of_the_almighty(ability: BossAbility) -> void:
	var centre := _on_floor(arena().global_position if arena() else global_position)
	BossFx.blink(get_parent(), global_position, centre, Constants.DamageType.ENTROPIC)
	global_position = centre
	velocity = Vector3.ZERO
	begin_channel(EYES_CHANNEL_SEC)
	BossFx.sound(SoundLib.library.boss_deep_roar, centre, 3.0, 0.7)
	if _model_root:
		create_tween().tween_property(_model_root, "position:y", HOVER_HEIGHT, 0.8).set_trans(Tween.TRANS_SINE)
	var eyes: Array[MeshInstance3D] = []
	var turn := randf() * TAU
	for i in EYES:
		var a := turn + TAU * i / EYES
		var eye := _make_eye_sphere(EYE_RADIUS, Vector2(2.0, 1.0), Vector2.ZERO)
		get_parent().add_child(eye)
		eye.global_position = centre + Vector3(sin(a), 0.0, cos(a)) * EYES_RING + Vector3.UP * EYES_HEIGHT
		eye.look_at(Vector3(centre.x, eye.global_position.y, centre.z), Vector3.UP)
		eye.scale = Vector3.ONE * 0.05
		create_tween().tween_property(eye, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var glow := OmniLight3D.new()
		glow.light_color = VOID_COLOR
		glow.light_energy = 1.5
		glow.omni_range = 4.0
		eye.add_child(glow)
		eyes.append(eye)
		SpellFx.burst(get_parent(), eye.global_position, Color(0.05, 0.04, 0.08), 20, Vector2(2, 5), 0.6)
	var sweeps: Array[AlmightyBeam] = []
	var cycle := EYE_AIM + EYE_FIRE + EYE_REST
	var elapsed := 0.0
	var sweep_angle := randf() * TAU
	var sweep_dir := 1.0
	var sweep_tick := 0.0
	var fired: Array[float] = []
	fired.resize(EYES)
	fired.fill(-99.0)
	while elapsed < EYES_CHANNEL_SEC and health.is_alive():
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		elapsed += dt
		for i in EYES:
			var eye := eyes[i]
			eye.global_position.y = centre.y + EYES_HEIGHT + sin(elapsed * 1.4 + i) * 0.25
			# Eyes fire in turn: each starts its cycle cycle/EYES later.
			var t := elapsed - 0.8 - cycle * i / EYES
			if t >= 0.0 and t - fired[i] >= cycle:
				fired[i] = t
				_eye_shot(eye, ability)
		if elapsed >= SWEEP_START:
			if sweeps.is_empty():
				for k in 2:
					sweeps.append(AlmightyBeam.make(get_parent(), VOID_COLOR, 1.1))
				BossFx.sound(SoundLib.library.boss_beam_start, centre, 2.0)
			if sweep_dir > 0.0 and elapsed >= SWEEP_START + (EYES_CHANNEL_SEC - SWEEP_START) * 0.5:
				sweep_dir = -1.0
				SpellFx.flash(get_parent(), get_cast_origin(), VOID_COLOR, 3.0, 0.3)
			sweep_angle += deg_to_rad(SWEEP_DEG_PER_SEC) * sweep_dir * dt
			for k in 2:
				var dir := Vector3(sin(sweep_angle + PI * k), 0.0, cos(sweep_angle + PI * k))
				sweeps[k].place(centre + Vector3.UP * BEAM_HEIGHT + dir * 0.8, dir, AlmightyArena.RADIUS + 2.0)
			sweep_tick -= dt
			if sweep_tick <= 0.0:
				sweep_tick = SWEEP_TICK
				var p := _target_player()
				if p and p.health.is_alive() and (sweeps[0].hits(p.global_position, 0.3) or sweeps[1].hits(p.global_position, 0.3)):
					_strike(p, _hit(ability, SWEEP_TICK_SHARE), Constants.DamageType.ENTROPIC)
	for beam in sweeps:
		beam.queue_free()
	for eye in eyes:
		if is_instance_valid(eye):
			SpellFx.burst(get_parent(), eye.global_position, Color(0.05, 0.04, 0.08), 24, Vector2(3, 6), 0.6)
			eye.queue_free()
	if _model_root:
		create_tween().tween_property(_model_root, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	SpellFx.shockwave(get_parent(), centre + Vector3.UP * 0.05, 6.0, VOID_COLOR, 0.4)

## One eye: a line from it through the player's spot, then a beam down it.
func _eye_shot(eye: MeshInstance3D, ability: BossAbility) -> void:
	var p := _target_player()
	if p == null:
		return
	var from := eye.global_position
	var flat := p.global_position - from
	flat.y = 0.0
	flat = flat.normalized() if flat.length() > 0.05 else -eye.global_transform.basis.z
	# Down from the eye to waist height where the player stood, then on into the floor.
	var aim := _on_floor(p.global_position) + Vector3.UP * BEAM_HEIGHT
	var dir: Vector3 = (aim - from).normalized() if aim.distance_to(from) > 0.1 else flat
	var length := minf(EYE_BEAM_LENGTH, (from.y - _floor_y()) / maxf(-dir.y, 0.01))
	var reach := length * Vector2(dir.x, dir.z).length()
	BossTelegraph.line(get_parent(), _on_floor(from), flat, reach, EYE_BEAM_WIDTH, EYE_AIM, _tell())
	SpellFx.flash(get_parent(), from, VOID_COLOR, 2.4, EYE_AIM)
	await _wait(EYE_AIM)
	if not is_instance_valid(eye) or not health.is_alive():
		return
	var beam := AlmightyBeam.fire(get_parent(), from, dir, length, VOID_COLOR, EYE_BEAM_WIDTH, EYE_FIRE)
	BossFx.sound(BossFx.cast_sound(Constants.DamageType.ENTROPIC), from, -2.0, 0.9)
	p = _target_player()
	if p and p.health.is_alive() and beam.hits(p.global_position, 0.3):
		_strike(p, _hit(ability), Constants.DamageType.ENTROPIC)

## ---- The Verdict -----------------------------------------------------------------

## A long channel that ends in your death unless enough damage breaks it.
func _verdict() -> void:
	var a := arena()
	if a:
		a.announce("The Verdict", VOID_COLOR.lightened(0.35), 1.8, 60)
	begin_channel(VERDICT_SEC)
	velocity = Vector3.ZERO
	var start := health.current_health + get_ward()
	var needed := health.max_health * VERDICT_BREAK_SHARE
	var orb := _make_eye_sphere(1.6, Vector2(3.0, 1.5), Vector2(0.08, -0.4))
	get_parent().add_child(orb)
	orb.global_position = global_position + Vector3.UP * (body_height + 4.5)
	orb.scale = Vector3.ONE * 0.1
	create_tween().tween_property(orb, "scale", Vector3.ONE * 2.6, VERDICT_SEC).set_trans(Tween.TRANS_SINE)
	BossTelegraph.circle(get_parent(), _on_floor(a.global_position if a else global_position), AlmightyArena.RADIUS + 2.0, VERDICT_SEC, Color(VOID_COLOR, 0.25))
	var meter := Label3D.new()
	meter.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	meter.no_depth_test = true
	meter.font_size = 72
	meter.pixel_size = 0.012
	meter.outline_size = 14
	meter.modulate = VOID_COLOR.lightened(0.5)
	get_parent().add_child(meter)
	meter.global_position = global_position + Vector3.UP * (body_height + 1.0)
	BossFx.sound(SoundLib.library.boss_deep_roar, global_position, 4.0, 0.6)
	var left := VERDICT_SEC
	var broken := false
	var pulse := 0.0
	while left > 0.0 and health.is_alive():
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		left -= dt
		var dealt := start - (health.current_health + get_ward())
		meter.text = "BREAK  %d%%   %.1fs" % [int(clampf(dealt / needed, 0.0, 1.0) * 100.0), maxf(left, 0.0)]
		if dealt >= needed:
			broken = true
			break
		pulse -= dt
		if pulse <= 0.0:
			pulse = 1.0
			SpellFx.flash(get_parent(), orb.global_position, VOID_COLOR, 2.5 + (VERDICT_SEC - left) * 0.4, 0.3)
	meter.queue_free()
	if not health.is_alive():
		orb.queue_free()
		return
	if broken:
		SpellFx.burst(get_parent(), orb.global_position, Color(0.05, 0.04, 0.08), 80, Vector2(6, 12), 0.9, Vector2(0.15, 0.4), 180.0, -4.0)
		SpellFx.flash(get_parent(), orb.global_position, Color(0.9, 0.9, 1.0), 6.0, 0.4)
		orb.queue_free()
		if a:
			a.announce("Judgment broken", AETHER_COLOR.lightened(0.4), 1.6, 48)
		interrupt_attack()
		status_effects.apply_timed_effect("stun", VERDICT_STUN)
		if composure and not composure.is_broken:
			composure.enter_broken_state()
		await _wait(VERDICT_STUN)
		return
	# Unbroken: the sentence is carried out.
	var p := _target_player()
	SpellFx.flash(get_parent(), orb.global_position, Color(0.95, 0.95, 1.0), 10.0, 0.6)
	orb.queue_free()
	if p and p.health.is_alive():
		AlmightyBeam.fire(get_parent(), p.global_position + Vector3.UP * 25.0, Vector3.DOWN, 25.0, VOID_COLOR, 3.5, 0.8)
		SpellFx.shockwave(get_parent(), _on_floor(p.global_position) + Vector3.UP * 0.05, 8.0, VOID_COLOR, 0.6)
		BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_heavy_impact), p.global_position, 8.0, 0.6)
		# Past every defence: straight off Life.
		p.health.apply_damage(p.health.max_health * 10.0 + p.health.current_health)
	await _wait(0.8)

## ---- Nightfall -------------------------------------------------------------------

## Dark falls everywhere beyond NIGHT_INNER of him, then inside it.
func _nightfall(ability: BossAbility) -> void:
	var centre := _on_floor(global_position)
	velocity = Vector3.ZERO
	begin_channel(NIGHT_OUT_TELEGRAPH + NIGHT_IN_TELEGRAPH)
	BossFx.charge(self, get_cast_origin(), Constants.DamageType.ENTROPIC, NIGHT_OUT_TELEGRAPH, true)
	var ring := _ring_mesh(NIGHT_INNER, AlmightyArena.RADIUS * 2.0, Color(VOID_COLOR, 0.28))
	get_parent().add_child(ring)
	ring.global_position = centre + Vector3.UP * 0.05
	await _wait(NIGHT_OUT_TELEGRAPH)
	ring.queue_free()
	if not health.is_alive():
		return
	SpellFx.shockwave(get_parent(), centre + Vector3.UP * 0.05, AlmightyArena.RADIUS * 2.0, Color(0.1, 0.06, 0.2), 0.5)
	SpellFx.burst(get_parent(), centre + Vector3.UP * 0.5, Color(0.04, 0.03, 0.06), 80, Vector2(10, 18), 0.8, Vector2(0.2, 0.45), 30.0, 0.0)
	var p := _target_player()
	if p and p.health.is_alive() and _flat_distance(p.global_position, centre) > NIGHT_INNER - 0.3:
		_strike(p, _hit(ability), Constants.DamageType.ENTROPIC)
	BossTelegraph.circle(get_parent(), centre, NIGHT_INNER, NIGHT_IN_TELEGRAPH, _tell())
	await _wait(NIGHT_IN_TELEGRAPH)
	if not health.is_alive():
		return
	AlmightyBeam.fire(get_parent(), centre + Vector3.UP * 16.0, Vector3.DOWN, 16.0, VOID_COLOR, NIGHT_INNER * 2.0, 0.5)
	SpellFx.shockwave(get_parent(), centre + Vector3.UP * 0.05, NIGHT_INNER, VOID_COLOR, 0.4)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_heavy_impact), centre, 4.0, 0.8)
	p = _target_player()
	if p and p.health.is_alive() and _flat_distance(p.global_position, centre) <= NIGHT_INNER + 0.3:
		_strike(p, _hit(ability), Constants.DamageType.ENTROPIC)

## A flat ring from `inner` to `outer` metres, for Nightfall's first strike.
static func _ring_mesh(inner: float, outer: float, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 64
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		var i0 := Vector3(sin(a0), 0, cos(a0)) * inner
		var i1 := Vector3(sin(a1), 0, cos(a1)) * inner
		var o0 := Vector3(sin(a0), 0, cos(a0)) * outer
		var o1 := Vector3(sin(a1), 0, cos(a1)) * outer
		for v in [i0, o0, o1, i0, o1, i1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mi.material_override = mat
	return mi
