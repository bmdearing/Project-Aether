extends PinnacleBoss
class_name Almighty
## Test Pinnacle boss for the classic-MDX pipeline (the Yhwach models in
## assets/models/enemies/pinnacle/almighty/; a fan model of a Bleach
## character, so placeholder only). Fought in the AlmightyArena.
##   Phase 1, "The Sealed King" (Aetheric): sword melee, Sacred Arrows,
##   Rain of Light, Sealed Blade (charge), Star Seal (a pentagram drawn
##   under you that bursts along its lines).
##   At 50% Life he can't be pushed lower: he wraps himself in a black
##   cocoon of eyes, takes his Almighty form (the second model) and heals
##   back to full while the arena goes dark.
##   Phase 2, "The Almighty" (Entropic): opens with Selection (a pull), then
##   Black Tide, Black Mire, Star Seal and Foreseen: circles land where you
##   will be if you keep moving the way you are.

const SEALED_NAME := "The Sealed King"
const AWAKENED_NAME := "The Almighty"
const AWAKENED_MODEL := preload("res://entities/enemies/models/AlmightyAwakenedModel.tscn")
const EYE_TEXTURE := preload("res://assets/models/enemies/pinnacle/almighty/Yhwach_Almighty/ZK_YOUHA.png")
const OVERLAY_SHADER := preload("res://entities/enemies/models/mdx_overlay_layer.gdshader")
const AWAKEN_AT := 0.5
## The cocoon closes over AWAKEN_GATHER; he heals inside it over AWAKEN_HOLD.
const AWAKEN_GATHER := 1.6
const AWAKEN_HOLD := 1.8
const AETHER_TELL := Color(0.45, 0.75, 1.0, 0.5)
const VOID_TELL := Color(0.45, 0.3, 0.7, 0.5)
## Star Seal: a five-pointed star of this radius around the player.
const STAR_RADIUS := 5.5
const STAR_LINE_WIDTH := 1.3
## Foreseen: each circle aims at where the player will be when it lands.
const FORESEE_STEPS := 4
const FORESEE_GAP := 0.45
const FORESEE_TELEGRAPH := 1.0
const FORESEE_RADIUS := 2.4

var awakened := false
var _arena: AlmightyArena

func _ready() -> void:
	super._ready()
	display_name = SEALED_NAME
	_set_melee_type(Constants.DamageType.AETHERIC)

func pinnacle_life() -> float:
	# He heals back to full once, so the fight is 1.5x this.
	return 16_000_000.0 if Dev.enabled else 44_000_000.0

func phase_thresholds() -> Array[float]:
	return [AWAKEN_AT]

func abilities() -> Array:
	var aether := Constants.DamageType.AETHERIC
	var entropic := Constants.DamageType.ENTROPIC
	return [
		{"id": "sacred_arrows", "display_name": "Sacred Arrows", "kind": BossAbility.Kind.VOLLEY, "cooldown": 7.0, "telegraph": 0.8, "count": 5, "spread_degrees": 50.0, "damage_mult": 0.8, "min_range": 5.0, "max_range": 24.0, "damage_type": aether},
		{"id": "rain_of_light", "display_name": "Rain of Light", "kind": BossAbility.Kind.BLAST, "cooldown": 10.0, "telegraph": 1.2, "radius": 2.8, "count": 5, "damage_mult": 1.3, "max_range": 24.0, "damage_type": aether},
		{"id": "sealed_blade", "display_name": "Sealed Blade", "kind": BossAbility.Kind.CHARGE, "cooldown": 8.0, "telegraph": 0.8, "damage_mult": 1.5, "min_range": 5.0, "max_range": 15.0, "damage_type": Constants.DamageType.KINETIC},
		{"id": "star_seal", "display_name": "Star Seal", "kind": BossAbility.Kind.CUSTOM, "cooldown": 14.0, "telegraph": 1.6, "damage_mult": 1.8, "max_range": 26.0,
			"description": "A five-pointed star is drawn on the floor around you and bursts along its lines. Stand between them."},
		{"id": "selection", "display_name": "Selection", "kind": BossAbility.Kind.PULL, "cooldown": 16.0, "telegraph": 1.2, "radius": 5.0, "damage_mult": 1.6, "max_range": 26.0, "min_phase": 2, "damage_type": entropic},
		{"id": "black_tide", "display_name": "Black Tide", "kind": BossAbility.Kind.WAVE, "cooldown": 10.0, "telegraph": 0.7, "radius": 2.6, "count": 6, "damage_mult": 1.2, "max_range": 24.0, "min_phase": 2, "damage_type": entropic},
		{"id": "black_mire", "display_name": "Black Mire", "kind": BossAbility.Kind.HAZARD, "cooldown": 11.0, "telegraph": 1.0, "radius": 3.5, "duration": 7.0, "damage_mult": 0.8, "max_range": 24.0, "min_phase": 2, "damage_type": entropic},
		{"id": "foreseen", "display_name": "Foreseen", "kind": BossAbility.Kind.CUSTOM, "cooldown": 12.0, "damage_mult": 1.5, "max_range": 30.0, "min_phase": 2,
			"description": "He sees where you are going: circles land on the spot you will reach if you keep moving the way you are. Change direction."},
	]

func phase_openers() -> Dictionary:
	return {2: "selection"}

## Keep away and he steps onto your spot, then looses a bolt down your line.
## damage_type -1: Aetheric while sealed, Entropic once awakened (the melee's type).
func range_answers() -> Array:
	return [
		{"id": "sacred_step", "display_name": "Sacred Step", "kind": BossAbility.Kind.BLINK, "telegraph": 1.0, "radius": 3.2, "damage_mult": 1.6},
		{"id": "sacred_bow", "display_name": "Sacred Bow", "kind": BossAbility.Kind.LANCE, "telegraph": 0.9, "radius": 1.3, "damage_mult": 1.9},
	]

func range_answer_distance() -> float:
	return 14.0

func arena() -> AlmightyArena:
	if not is_instance_valid(_arena) and is_inside_tree():
		_arena = get_tree().get_first_node_in_group("almighty_arena") as AlmightyArena
	return _arena

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

## ---- Awakening -------------------------------------------------------------

func run_phase_transition(phase: int, seconds: float) -> void:
	if phase != 2 or awakened:
		await super(phase, seconds)
		return
	await _awaken()

func _awaken() -> void:
	velocity = Vector3.ZERO
	begin_channel(AWAKEN_GATHER + AWAKEN_HOLD)
	if arena():
		arena().awaken(AWAKEN_GATHER + AWAKEN_HOLD)
	var centre := global_position + Vector3.UP * body_height * 0.5
	var cocoon := _make_cocoon(body_height * 0.62)
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
	# Back at full: the 50% mark no longer means anything on his bar.
	boss_brain.phase_thresholds.clear()
	SpellFx.flash(get_parent(), centre, Color(0.85, 0.82, 1.0), 7.0, 0.4)
	SpellFx.shockwave(get_parent(), global_position + Vector3.UP * 0.05, 12.0, Color(0.3, 0.2, 0.5), 0.7)
	SpellFx.burst(get_parent(), centre, Color(0.04, 0.03, 0.06), 90, Vector2(7, 14), 1.0, Vector2(0.15, 0.4), 180.0, -3.0)
	BossFx.sound(SoundLib.pick_random(SoundLib.library.boss_heavy_impact), global_position, 6.0, 0.7)
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

## A black sphere crawling with the Almighty's eyes.
func _make_cocoon(radius: float) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.01, 0.01, 0.015)
	var eyes := ShaderMaterial.new()
	eyes.shader = OVERLAY_SHADER
	eyes.set_shader_parameter("layer_texture", EYE_TEXTURE)
	eyes.set_shader_parameter("uv_scale", Vector2(4.0, 2.0))
	eyes.set_shader_parameter("uv_scroll", Vector2(0.05, -0.25))
	mat.next_pass = eyes
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## ---- Custom abilities ----------------------------------------------------------

func cast_custom(ability: BossAbility) -> void:
	match ability.id:
		"star_seal":
			await _star_seal(ability)
		"foreseen":
			await _foreseen(ability)
		_:
			await get_tree().process_frame

## A pentagram around the player's spot; each of its five lines bursts.
func _star_seal(ability: BossAbility) -> void:
	var p := _target_player()
	if p == null:
		await get_tree().process_frame
		return
	var tell: Color = VOID_TELL if awakened else AETHER_TELL
	var centre := Vector3(p.global_position.x, global_position.y, p.global_position.z)
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
		BossTelegraph.line(get_parent(), from, to - from, from.distance_to(to), STAR_LINE_WIDTH, ability.telegraph, tell)
	await _wait(ability.telegraph)
	if not health.is_alive():
		return
	var color := Color(tell, 1.0)
	for i in 5:
		var from := points[i]
		var to := points[(i + 2) % 5]
		for k in 4:
			SpellFx.flash(get_parent(), from.lerp(to, (k + 0.5) / 4.0) + Vector3.UP * 0.4, color, 1.6, 0.3)
	SpellFx.shockwave(get_parent(), centre + Vector3.UP * 0.05, STAR_RADIUS, color, 0.4)
	BossFx.sound(BossFx.cast_sound(_damage_type()), centre, 2.0, 0.8)
	p = _target_player()
	if p and p.health.is_alive():
		for i in 5:
			if _segment_distance(p.global_position, points[i], points[(i + 2) % 5]) <= STAR_LINE_WIDTH * 0.5 + 0.3:
				p.take_damage(get_ability_base_damage() * ability.damage_mult, _damage_type(), self, Player.HitKind.SPELL)
				break

static func _segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var p2 := Vector2(point.x, point.z)
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var ab := b2 - a2
	var t := clampf((p2 - a2).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p2.distance_to(a2 + ab * t)

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
		var spot := p.global_position + heading * FORESEE_TELEGRAPH
		spot = _clamp_to_arena(Vector3(spot.x, global_position.y, spot.z))
		_foreseen_circle(spot, ability)
		await _wait(FORESEE_GAP)
	await _wait(FORESEE_TELEGRAPH)

func _foreseen_circle(spot: Vector3, ability: BossAbility) -> void:
	BossTelegraph.circle(get_parent(), spot, FORESEE_RADIUS, FORESEE_TELEGRAPH, VOID_TELL)
	await _wait(FORESEE_TELEGRAPH)
	if not is_inside_tree() or not health.is_alive():
		return
	SpellFx.flash(get_parent(), spot + Vector3.UP * 0.5, Color(0.55, 0.45, 0.9), 3.0, 0.3)
	SpellFx.burst(get_parent(), spot + Vector3.UP * 0.3, Color(0.05, 0.04, 0.08), 26, Vector2(3, 7), 0.6, Vector2(0.1, 0.25), 70.0, -6.0)
	var p := _target_player()
	if p and p.health.is_alive() and Vector2(p.global_position.x - spot.x, p.global_position.z - spot.z).length() <= FORESEE_RADIUS + 0.3:
		p.take_damage(get_ability_base_damage() * ability.damage_mult, Constants.DamageType.ENTROPIC, self, Player.HitKind.SPELL)

func _clamp_to_arena(spot: Vector3) -> Vector3:
	var a := arena()
	if a == null:
		return spot
	var local := a.to_local(spot)
	var flat := Vector2(local.x, local.z)
	if flat.length() > AlmightyArena.RADIUS - 1.0:
		flat = flat.normalized() * (AlmightyArena.RADIUS - 1.0)
	return a.to_global(Vector3(flat.x, local.y, flat.y))
