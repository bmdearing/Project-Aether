extends CharacterBody3D
class_name Enemy
## Base enemy. Regular units are MeleeUnit/RangedUnit scenes driven by an
## EnemyDefinition (see EnemyRoster); bosses subclass this and tune values
## directly. Chase movement lives here; attacking is an optional child
## component (EnemyMeleeAttack/EnemyRangedAttack) that drives the telegraph
## calls below - chasing and attacking are decoupled.

## Rolled in _ready() unless a scene sets BOSS. Offsets drop item level.
@export var rank: Constants.EnemyRank = Constants.EnemyRank.NORMAL
@export var move_speed: float = 3.0
@export var chase_range: float = 15.0
## Distance to close to and hold - melee archetypes keep this inside
## their attack range; ranged archetypes use it as a stand-off distance.
@export var stop_distance: float = 2.3
## >0 backs away once the player is closer than this (kiting).
@export var retreat_distance: float = 0.0
## Tuned to clear the Vault's gap (3m) + platform rise (1.2m) at faster
## move speeds - slow units are walled off by their own slowness.
@export var jump_velocity: float = 7.0
## Invented placeholder; definitions override it.
@export var xp_reward: float = 10.0
@export var gold_reward: int = 5

## Name on the hover health bar; falls back to the node's own name.
@export var display_name: String = ""

## Overrides the stats/visuals above at the start of _ready(); null keeps
## the scene/subclass values.
@export var definition: EnemyDefinition = null

var faction: String = ""
var armor_value: float = 0.0    # flat Physical mitigation in take_damage(): armor / (armor + 1000)
var evasion_value: float = 0.0  # dodge chance vs player weapon attacks only (take_damage()'s can_evade)
# Flat damage-absorb pool set at spawn from definition.ward_percent; no regen.
var _ward_pool: float = 0.0
var _ward_current: float = 0.0

func get_display_name() -> String:
	return display_name if display_name != "" else name

func get_ward() -> float:
	return _ward_current

func get_ward_max() -> float:
	return _ward_pool

## Removes up to `amount` Ward (drain-on-hit modifiers); returns what it took.
func drain_ward(amount: float) -> float:
	var drained := minf(amount, _ward_current)
	_ward_current -= drained
	return drained

## Bonus for a weapon hit aimed at the HeadZone (headshot).
@export var critical_spot_multiplier: float = 1.10

## Body size, fitted to the installed model by _fit_body_to_model(); the
## defaults match Enemy.tscn's placeholder capsule.
var body_height: float = 1.9
var body_radius: float = 0.45


@onready var health: HealthComponent = $HealthComponent
@onready var stance: StanceComponent = $StanceComponent
@onready var composure: ComposureComponent = $ComposureComponent
@onready var status_effects: StatusEffectComponent = $StatusEffectComponent
@onready var attack_hitbox: Area3D = $AttackHitbox

const RIPOSTE_INDICATOR_HEIGHT := 2.2
const RIPOSTE_INDICATOR_COLOR := Color(1.0, 0.05, 0.05)
const RIPOSTE_BLINK_INTERVAL := 0.25

## Colored dots above the head, one per active status effect.
const STATUS_ICON_HEIGHT := 2.0
const STATUS_ICON_RADIUS := 0.08
const STATUS_ICON_SPACING := 0.22
const STATUS_EFFECT_IDS := ["ignite", "chill", "freeze", "electrocute", "unraveling", "slow"]

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _player: Player
var _gap_jumping: bool = false
var _riposte_indicator: MeshInstance3D
var _riposte_blink_tween: Tween
var _status_icons: Dictionary = {}  # effect_id -> MeshInstance3D

## Set by _apply_model() when the definition supplies a real model.
var _anim_controller: EnemyAnimationController
var _model_root: Node3D
var _last_hit_react_msec: int = 0
const HIT_REACT_MIN_INTERVAL_MSEC := 600   # a flinch on every hit would keep a fast attacker locked in HitReact
const MODEL_TURN_SPEED := 8.0
const DEATH_LINGER_SEC := 1.5              # corpse stays after the death clip ends
## Yaw (radians) added when turning the model toward the player. 0.0 =
## the model's local +Z is its front (glTF/UAL convention, so rotating by
## atan2(dir.x, dir.z) points it at the player); a model whose front is
## another axis sets the difference (Arator's front is +X: -PI/2).
var model_forward_yaw_offset: float = 0.0

## In combat while the player is within detection range or for this long
## after the last hit; drives the hover health bar.
const OUT_OF_COMBAT_GRACE_MSEC := 5000
var _last_combat_msec: int = -OUT_OF_COMBAT_GRACE_MSEC - 1

func is_in_combat() -> bool:
	return Time.get_ticks_msec() - _last_combat_msec < OUT_OF_COMBAT_GRACE_MSEC

func _ready() -> void:
	_apply_definition()
	if rank != Constants.EnemyRank.BOSS:
		rank = _roll_rank()
	health.died.connect(_on_died)
	# Separate from _on_died() so it fires at the moment of death even when a
	# subclass override (FigmentBoss) awaits a death animation before super.
	health.died.connect(func(): EventBus.enemy_died.emit(self))
	add_to_group("enemy")
	var head_zone := get_node_or_null("HeadZone")
	if head_zone:
		head_zone.add_to_group("critical_spots")
	_player = get_tree().get_first_node_in_group("player") as Player
	_build_riposte_indicator()
	_build_status_icons()
	composure.broken_state_started.connect(_on_broken_state_started)
	composure.broken_state_ended.connect(_on_broken_state_ended)
	status_effects.effect_applied.connect(_on_status_effect_changed)
	status_effects.effect_expired.connect(_on_status_effect_changed)
	_apply_model()
	# Deferred so archetype subclasses' own health.max_health (set after
	# super._ready()) isn't overwritten by this.
	call_deferred("_apply_map_modifiers")

## Copies an EnemyDefinition's stats onto this enemy and its attack
## component (if any). Runs first in _ready(), so anything a subclass sets
## after super._ready() still wins - a definition-driven subclass simply
## doesn't set those values itself.
func _apply_definition() -> void:
	if definition == null:
		return
	display_name = definition.display_name
	faction = definition.faction
	move_speed = definition.move_speed
	chase_range = definition.chase_range
	stop_distance = definition.stop_distance
	retreat_distance = definition.retreat_distance
	armor_value = definition.armor_value
	evasion_value = definition.evasion_value
	var scaled_health := _level_scaled_health(definition.mob_level)
	var scaled_damage := _level_scaled_damage(definition.mob_level)
	health.max_health = scaled_health
	health.current_health = scaled_health
	_reset_ward()
	xp_reward = definition.xp_reward
	gold_reward = randi_range(definition.gold_reward_min, definition.gold_reward_max)

	var melee := get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	if melee:
		melee.damage_amount = scaled_damage
		melee.damage_type = definition.damage_type
		melee.attack_range = definition.attack_range
		melee.recovery_duration = definition.attack_cooldown
	var ranged := get_node_or_null("RangedAttack") as EnemyRangedAttack
	if ranged:
		ranged.damage_amount = scaled_damage
		ranged.damage_type = definition.damage_type
		ranged.fire_range = definition.attack_range
		ranged.cooldown_duration = definition.attack_cooldown

## Level curve from Constants.MOB_*: base at level 1 for the definition's
## archetype_category, growing linearly per level above 1.
func _level_scaled_health(level: int) -> float:
	var base_h: float = Constants.MOB_BASE_HEALTH.get(definition.archetype_category, 55.0)
	return base_h * (1.0 + Constants.MOB_HEALTH_GROWTH_PER_LEVEL * (level - 1))

func _level_scaled_damage(level: int) -> float:
	var base_d: float = Constants.MOB_BASE_DAMAGE.get(definition.archetype_category, 10.0)
	return base_d * (1.0 + Constants.MOB_DAMAGE_GROWTH_PER_LEVEL * (level - 1))

## Refills the Ward pool to definition.ward_percent of current max health.
## Called whenever max health is (re)derived, so it tracks tier/rarity scaling.
func _reset_ward() -> void:
	var percent := (definition.ward_percent if definition else 0.0) + (rarity_component.get_ward_percent() if rarity_component else 0.0)
	if percent <= 0.0:
		return
	_ward_pool = health.max_health * percent
	_ward_current = _ward_pool

## Refills Ward once delay seconds have passed since the last hit taken.
func recharge_ward_if_idle(delay: float) -> void:
	if _ward_current < _ward_pool and Time.get_ticks_msec() - _last_damaged_msec >= int(delay * 1000.0):
		_ward_current = _ward_pool

var _last_damaged_msec: int = -100000

## The EnemyRarityComponent added at spawn, or null (looked up lazily: it's
## attached after the enemy is created).
var rarity_component: EnemyRarityComponent:
	get:
		if _rarity_component == null or not is_instance_valid(_rarity_component):
			_rarity_component = get_node_or_null("EnemyRarityComponent") as EnemyRarityComponent
		return _rarity_component
var _rarity_component: EnemyRarityComponent

## Rarity affixes and Champion auras on top of Map scaling.
func get_attack_speed_multiplier() -> float:
	var mult := rarity_component.get_attack_speed_multiplier() if rarity_component else 1.0
	return maxf(mult * (status_effects.get_action_speed_multiplier() if status_effects else 1.0), 0.1)

## The type an attack deals: a damage-conversion affix (Dreamer) overrides it.
func convert_attack_type(damage_type: int) -> int:
	var converted := rarity_component.get_damage_conversion() if rarity_component else -1
	return converted if converted != -1 else damage_type

## Replaces the placeholder capsule with the definition's model and, if the
## model carries an "AnimationTree" node and the definition an AnimationSet,
## drives it through an EnemyAnimationController.
func _apply_model() -> void:
	if definition == null or definition.model_scene == null:
		return
	_install_model(definition.model_scene, definition.animation_set, definition.scale_modifier, definition.model_yaw_offset)

func _install_model(model_scene: PackedScene, anim_set: AnimationSet, model_scale: float, yaw_offset: float) -> void:
	var placeholder := get_node_or_null("MeshInstance3D")
	if placeholder:
		placeholder.queue_free()
	var model := model_scene.instantiate() as Node3D
	add_child(model)
	model.scale = Vector3.ONE * model_scale
	model.rotation.y = yaw_offset
	model_forward_yaw_offset = yaw_offset
	_model_root = model
	_fit_body_to_model(model)
	DrawDistance.apply(model, DrawDistance.ACTOR_RANGE)
	var anim_tree := model.get_node_or_null("AnimationTree") as AnimationTree
	if anim_tree and anim_set:
		var controller := EnemyAnimationController.new()
		add_child(controller)
		controller.setup(anim_tree, anim_set)
		_anim_controller = controller

const MIN_BODY_HEIGHT := 1.0
const MAX_BODY_RADIUS := 0.9
const BODY_RADIUS_PER_WIDTH := 0.22
const HEAD_RADIUS_PER_HEIGHT := 0.09

## Sizes the collision capsule, HeadZone and overhead markers to the model's
## rest-pose bounds, so tall units are hittable all the way up. Radius is
## capped so big models still fit through doorways.
func _fit_body_to_model(model: Node3D) -> void:
	var bounds := _model_bounds(model)
	if bounds.size == Vector3.ZERO:
		return
	body_height = maxf(bounds.end.y, MIN_BODY_HEIGHT)
	body_radius = clampf(maxf(bounds.size.x, bounds.size.z) * BODY_RADIUS_PER_WIDTH, 0.35, minf(MAX_BODY_RADIUS, body_height * 0.45))
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision and collision.shape is CapsuleShape3D:
		var capsule := collision.shape.duplicate() as CapsuleShape3D
		capsule.radius = body_radius
		capsule.height = body_height
		collision.shape = capsule
		collision.position.y = body_height / 2.0
	var head_zone := get_node_or_null("HeadZone") as Area3D
	if head_zone:
		var head_radius := clampf(body_height * HEAD_RADIUS_PER_HEIGHT, 0.18, 0.45)
		head_zone.position.y = body_height - head_radius
		var head_shape := head_zone.get_node("CollisionShape3D") as CollisionShape3D
		var sphere := head_shape.shape.duplicate() as SphereShape3D
		sphere.radius = head_radius
		head_shape.shape = sphere
	attack_hitbox.position.y = body_height / 2.0
	var top := body_height + 0.1
	if _riposte_indicator:
		_riposte_indicator.position.y = top + 0.3
	for icon in _status_icons.values():
		icon.position.y = top + 0.1

func _model_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var to_local := global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var box: AABB = (to_local * mesh.global_transform) * mesh.get_aabb()
		bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
	return bounds

## Distance from point to the surface of the body capsule (0 when inside),
## so area effects reach big units by their edge, not their centre.
func distance_to_body(point: Vector3) -> float:
	var axis_y := clampf(point.y, global_position.y, global_position.y + body_height)
	return maxf(point.distance_to(Vector3(global_position.x, axis_y, global_position.z)) - body_radius, 0.0)

## Head centre and radius in world space; radius 0 when there's no live HeadZone.
func get_critical_spot() -> Dictionary:
	var head_zone := get_node_or_null("HeadZone") as Area3D
	if head_zone == null or not head_zone.monitorable:
		return {"centre": Vector3.ZERO, "radius": 0.0}
	var sphere := (head_zone.get_node("CollisionShape3D") as CollisionShape3D).shape as SphereShape3D
	return {"centre": head_zone.global_position, "radius": sphere.radius if sphere else 0.0}

## Headshot test for a projectile: was it inside the head (plus margin)
## when it struck the body?
func is_critical_spot_point(point: Vector3, margin: float = 0.1) -> bool:
	var spot := get_critical_spot()
	return spot["radius"] > 0.0 and point.distance_to(spot["centre"]) <= spot["radius"] + margin

## Headshot test for melee: does the aim ray pass through the head?
func is_critical_spot_aimed(origin: Vector3, direction: Vector3) -> bool:
	var spot := get_critical_spot()
	if spot["radius"] <= 0.0:
		return false
	var dir := direction.normalized()
	var to_centre: Vector3 = spot["centre"] - origin
	var along := to_centre.dot(dir)
	return along >= 0.0 and (to_centre - dir * along).length() <= spot["radius"]

## Turns the model (not the body - collision/hitboxes stay symmetric) toward
## the player, and feeds ground speed to the animation tree.
func _update_model(delta: float) -> void:
	if _model_root == null or not health.is_alive():
		return
	if is_instance_valid(_player):
		var heading_for_target := is_instance_valid(move_target)
		var to_player := (move_target.global_position if heading_for_target else _player.global_position) - global_position
		to_player.y = 0.0
		if to_player.length() > 0.1 and (to_player.length() <= chase_range or is_in_combat() or heading_for_target):
			var target_yaw := atan2(to_player.x, to_player.z) + model_forward_yaw_offset - global_rotation.y
			_model_root.rotation.y = lerp_angle(_model_root.rotation.y, target_yaw, clamp(MODEL_TURN_SPEED * delta, 0.0, 1.0))
	if _anim_controller:
		_anim_controller.set_speed(Vector2(velocity.x, velocity.z).length())

func _build_status_icons() -> void:
	for i in range(STATUS_EFFECT_IDS.size()):
		var effect_id: String = STATUS_EFFECT_IDS[i]
		var icon := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = STATUS_ICON_RADIUS
		sphere.height = STATUS_ICON_RADIUS * 2.0
		icon.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var dmg_type: Constants.DamageType = Constants.STATUS_EFFECT_DAMAGE_TYPE.get(effect_id, Constants.DamageType.KINETIC)
		mat.albedo_color = Constants.DAMAGE_TYPE_COLOR.get(dmg_type, Color.WHITE)
		icon.material_override = mat
		icon.position = Vector3((i - (STATUS_EFFECT_IDS.size() - 1) / 2.0) * STATUS_ICON_SPACING, STATUS_ICON_HEIGHT, 0)
		icon.visible = false
		icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(icon)
		_status_icons[effect_id] = icon

func _on_status_effect_changed(effect_id: String) -> void:
	var icon: MeshInstance3D = _status_icons.get(effect_id)
	if icon:
		icon.visible = status_effects.has_effect(effect_id)

## Red light above the head, blinking while the enemy can be riposted.
func _build_riposte_indicator() -> void:
	_riposte_indicator = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	_riposte_indicator.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = RIPOSTE_INDICATOR_COLOR
	_riposte_indicator.material_override = mat
	_riposte_indicator.position = Vector3(0, RIPOSTE_INDICATOR_HEIGHT, 0)
	_riposte_indicator.visible = false
	_riposte_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_riposte_indicator)

func _on_broken_state_started() -> void:
	if _anim_controller:
		_anim_controller.play_stagger()
	_riposte_indicator.visible = true
	if _riposte_blink_tween:
		_riposte_blink_tween.kill()
	_riposte_blink_tween = create_tween()
	_riposte_blink_tween.set_loops()
	_riposte_blink_tween.tween_callback(func(): _riposte_indicator.visible = false).set_delay(RIPOSTE_BLINK_INTERVAL)
	_riposte_blink_tween.tween_callback(func(): _riposte_indicator.visible = true).set_delay(RIPOSTE_BLINK_INTERVAL)

func _on_broken_state_ended() -> void:
	if _riposte_blink_tween:
		_riposte_blink_tween.kill()
	_riposte_indicator.visible = false

## Per-tier scaling from the active Map, on top of its rolled enemy
## multipliers. Health scales through the mob level curve instead
## (MOB_LEVELS_PER_TIER).
const TIER_DAMAGE_GROWTH_PER_TIER := 0.10
const TIER_REWARD_GROWTH_PER_TIER := 0.20
const MOB_LEVELS_PER_TIER := 2

## Applies Map tier/affix scaling and the rarity health multiplier (which
## applies even without an active Map).
func _apply_map_modifiers() -> void:
	var rarity_mult := rarity_component.get_health_multiplier() if rarity_component else 1.0
	if GameState.active_map == null:
		if rarity_mult != 1.0:
			health.max_health *= rarity_mult
			health.current_health = health.max_health
			_reset_ward()
		return
	var tier_bonus := 1.0 + (GameState.active_map.tier - 1) * TIER_REWARD_GROWTH_PER_TIER
	# A definition-driven enemy's mob level rises with Map tier (tier 1 =
	# definition.mob_level, tier 5 = +8), so the level curve is the base the
	# multipliers below apply to. Scene-only enemies keep their own health.
	var base_health: float = health.max_health
	if definition:
		base_health = _level_scaled_health(definition.mob_level + (GameState.active_map.tier - 1) * MOB_LEVELS_PER_TIER)
	health.max_health = base_health * GameState.active_map.enemy_health_multiplier * rarity_mult
	health.current_health = health.max_health
	_reset_ward()
	xp_reward *= tier_bonus
	gold_reward = int(gold_reward * tier_bonus)

func get_outgoing_damage_multiplier() -> float:
	var mult := status_effects.get_outgoing_damage_multiplier() if status_effects else 1.0
	if status_effects and status_effects.has_effect("unraveling"):
		mult *= 1.0 - minf(GearEffects.player_bonus(get_tree(), "unraveled_damage_reduction") / 100.0, 0.9)
	if rarity_component:
		mult *= rarity_component.get_damage_multiplier()
	if GameState.active_map == null:
		return mult
	return GameState.active_map.enemy_damage_multiplier * (1.0 + (GameState.active_map.tier - 1) * TIER_DAMAGE_GROWTH_PER_TIER) * mult

## Horizontal velocity added on top of chase movement for one physics frame
## (Black Hole's pull). Goes through move_and_slide(), so it can't push an
## enemy through walls.
var _pull := Vector3.ZERO
## When set, the enemy walks to and faces this node instead of the player
## (a Herald's Mindbender heading for an Anchor pylon).
var move_target: Node3D = null

func apply_pull(pull_velocity: Vector3) -> void:
	if rarity_component and rarity_component.is_unstoppable():
		return
	_pull += Vector3(pull_velocity.x, 0.0, pull_velocity.z)

## Melee hit shove: horizontal velocity that bleeds off over a few frames.
var _knockback := Vector3.ZERO
const KNOCKBACK_FRICTION := 22.0
const BOSS_KNOCKBACK_SCALE := 0.25

func apply_knockback(impulse: Vector3) -> void:
	if immovable or (rarity_component and rarity_component.is_unstoppable()):
		return
	if rank == Constants.EnemyRank.BOSS:
		impulse *= BOSS_KNOCKBACK_SCALE
	_knockback += Vector3(impulse.x, 0.0, impulse.z)
	if impulse.y > 0.0:
		velocity.y = maxf(velocity.y, impulse.y)

## A corrupted item's "nearby enemies have reduced Resistances" aura.
const SHRED_AURA_RADIUS := 8.0

func _aura_shred() -> float:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or player.global_position.distance_to(global_position) > SHRED_AURA_RADIUS:
		return 0.0
	return GearEffects.player_bonus(get_tree(), "resistance_shred_aura")

## Staggered: interrupted in the last STAGGER_SECONDS, or Broken (Composure).
const STAGGER_SECONDS := 1.5
var _staggered_until_msec: int = 0
## Whether the latest hit landed before this enemy was in combat (unaware).
var last_hit_was_unaware: bool = false

func is_staggered() -> bool:
	return Time.get_ticks_msec() < _staggered_until_msec or (composure != null and composure.is_broken)

## Cancels a wind-up or strike in progress and plays the stagger reaction.
func interrupt_attack() -> void:
	if rarity_component and rarity_component.is_unstoppable():
		return
	_staggered_until_msec = Time.get_ticks_msec() + int(STAGGER_SECONDS * 1000.0)
	for path in ["MeleeAttack", "RangedAttack"]:
		var attack := get_node_or_null(path)
		if attack and attack.has_method("interrupt"):
			attack.interrupt()
	if _anim_controller and health.is_alive():
		_anim_controller.play_stagger()

const HIT_FLASH_SEC := 0.09
static var _hit_flash_material: StandardMaterial3D

## Brief white overlay on every mesh of the model; runs on real time so hitstop doesn't stretch it.
func flash_hit() -> void:
	var root: Node = _model_root if _model_root else get_node_or_null("MeshInstance3D")
	if root == null:
		return
	if _hit_flash_material == null:
		_hit_flash_material = StandardMaterial3D.new()
		_hit_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hit_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hit_flash_material.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = _hit_flash_material
	get_tree().create_timer(HIT_FLASH_SEC, true, false, true).timeout.connect(func():
		for mesh in meshes:
			if is_instance_valid(mesh) and mesh.material_overlay == _hit_flash_material:
				mesh.material_overlay = null)

func _physics_process(delta: float) -> void:
	if immovable:
		# Hovering in place (the Lord of the Elements over the Pinnacle bay).
		velocity = Vector3.ZERO
		_pull = Vector3.ZERO
		_knockback = Vector3.ZERO
		_update_model(delta)
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_chase()
	velocity.x += _pull.x + _knockback.x
	velocity.z += _pull.z + _knockback.z
	_pull = Vector3.ZERO
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)
	# Standing still on the ground: nothing to resolve, so skip the physics
	# query (most of a large pack is idle at any moment).
	if not (is_on_floor() and velocity.is_zero_approx()):
		move_and_slide()
	_update_model(delta)

## Shrinks while the player hides in Dagger's Stealth stance.
func _detection_range() -> float:
	return chase_range * _player.stance_attack.get_detection_multiplier() if _player.stance_attack else chase_range

func _update_chase() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if not is_instance_valid(_player) or not health.is_alive():
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Mid-air from a gap jump: don't let chase/kite logic re-steer
	# horizontal velocity until landing, or a retreating kiter can get
	# steered back over the gap mid-flight and fall through.
	if _gap_jumping:
		if is_on_floor():
			_gap_jumping = false
		else:
			return

	var heading_for_target := is_instance_valid(move_target)
	var goal: Vector3 = move_target.global_position if heading_for_target else _player.global_position
	var to_player: Vector3 = goal - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if is_attack_locked():
		velocity.x = 0.0
		velocity.z = 0.0
		_last_combat_msec = Time.get_ticks_msec()
		return

	if dist <= _detection_range():
		_last_combat_msec = Time.get_ticks_msec()

	# A hit from outside chase_range (landed or dodged - take_damage() marks
	# combat before its dodge roll) still pulls the enemy in, for the same
	# grace window the health bar uses.
	if (dist > _detection_range() and not is_in_combat() and not heading_for_target) or dist < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var dir := to_player / dist
	var speed := move_speed * status_effects.get_move_speed_multiplier() * (rarity_component.get_move_speed_multiplier() if rarity_component else 1.0)
	# A shooter without a clear shot keeps closing in (around the wall)
	# instead of standing at range.
	var blocked_shot := is_ranged_unit() and not heading_for_target and not can_see_player()
	if retreat_distance > 0.0 and dist < retreat_distance and not blocked_shot:
		var away := _nav_direction(global_position - dir * 4.0, -dir)
		velocity.x = away.x * speed
		velocity.z = away.z * speed
	elif dist > stop_distance or blocked_shot:
		var step := _nav_direction(_approach_point(goal, dist, heading_for_target), dir)
		velocity.x = step.x * speed
		velocity.z = step.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	_check_stuck()

	_check_gap_jump()

## ---- Navigation ----------------------------------------------------------
## Paths come from the map's navigation mesh (GeneratedMap bakes one at
## load); without one, or when the goal is off the mesh (across a gap), the
## enemy heads straight at it as before.
const REPATH_INTERVAL := 0.5
const REPATH_GOAL_MOVE := 1.5
const WAYPOINT_REACHED := 0.7
## A path ending further than this from its goal can't reach it.
const UNREACHABLE_SLACK := 2.5
const STUCK_CHECK_SEC := 0.8
const STUCK_MIN_MOVE := 0.35
const UNSTICK_SEC := 0.45
## Melee enemies spread around the player within this range.
const SURROUND_RANGE := 6.0
const SIGHT_CACHE_MSEC := 250

var _path := PackedVector3Array()
var _path_index: int = 0
var _path_goal := Vector3.INF
var _repath_left: float = 0.0
var _stuck_anchor := Vector3.ZERO
var _stuck_timer: float = 0.0
var _unstick_dir := Vector3.ZERO
var _unstick_left: float = 0.0
var _surround_angle: float = randf_range(-0.9, 0.9)
var _sight_msec: int = -SIGHT_CACHE_MSEC
var _sight: bool = true

func is_ranged_unit() -> bool:
	return get_node_or_null("RangedAttack") != null

## Clear line from this enemy's cast origin to the player's chest (other
## enemies don't block). Cached for a quarter second.
func can_see_player() -> bool:
	if not is_instance_valid(_player):
		return false
	var now := Time.get_ticks_msec()
	if now - _sight_msec < SIGHT_CACHE_MSEC:
		return _sight
	_sight_msec = now
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid()]
	var target := _player.global_position + Vector3(0, 1.0, 0)
	_sight = false
	for i in 4:
		var query := PhysicsRayQueryParameters3D.create(get_cast_origin(), target, 1)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.get("collider") == _player:
			_sight = true
			break
		if not hit.get("collider") is Enemy:
			break
		exclude.append((hit["collider"] as Enemy).get_rid())
	return _sight

## Close to the player, melee enemies aim at a spot beside them rather
## than all at the same point, so a pack spreads around instead of queuing.
func _approach_point(goal: Vector3, dist: float, heading_for_target: bool) -> Vector3:
	if heading_for_target or is_ranged_unit() or dist > SURROUND_RANGE:
		return goal
	var from_goal := global_position - goal
	from_goal.y = 0.0
	if from_goal.length() < 0.01:
		return goal
	return goal + from_goal.normalized().rotated(Vector3.UP, _surround_angle) * stop_distance * 0.8

## Direction to walk toward goal: along the navigation path when there is
## one, else fallback.
func _nav_direction(goal: Vector3, fallback: Vector3) -> Vector3:
	var dir := fallback
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0 and not NavigationServer3D.map_get_regions(map).is_empty():
		_repath_left -= get_physics_process_delta_time()
		if _repath_left <= 0.0 or goal.distance_to(_path_goal) > REPATH_GOAL_MOVE:
			_repath_left = REPATH_INTERVAL * randf_range(0.8, 1.2)
			_path_goal = goal
			_path = NavigationServer3D.map_get_path(map, global_position, goal, true)
			_path_index = 1
			if _path.is_empty() or _flat(_path[_path.size() - 1] - goal).length() > UNREACHABLE_SLACK:
				_path = PackedVector3Array()
		while _path_index < _path.size() and _flat(_path[_path_index] - global_position).length() < WAYPOINT_REACHED:
			_path_index += 1
		if _path_index < _path.size():
			var to_next := _flat(_path[_path_index] - global_position)
			if to_next.length() > 0.01:
				dir = to_next.normalized()
	if _unstick_left > 0.0:
		_unstick_left -= get_physics_process_delta_time()
		dir = (dir + _unstick_dir).normalized()
	return dir

## Trying to move but hardly moving (wedged on a corner or another enemy):
## repath and sidestep for a moment.
func _check_stuck() -> void:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	if not moving:
		_stuck_timer = 0.0
		_stuck_anchor = global_position
		return
	_stuck_timer += get_physics_process_delta_time()
	if _stuck_timer < STUCK_CHECK_SEC:
		return
	if _flat(global_position - _stuck_anchor).length() < STUCK_MIN_MOVE:
		_repath_left = 0.0
		var heading := _flat(velocity).normalized()
		_unstick_dir = heading.rotated(Vector3.UP, PI / 2.0 * (1.0 if randf() < 0.5 else -1.0))
		_unstick_left = UNSTICK_SEC
	_stuck_timer = 0.0
	_stuck_anchor = global_position

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

const GAP_CHECK_AHEAD := 1.0
const GAP_PROBE_UP := 3.0       # probe ray starts this far above - must clear a raised landing like the Vault's platform
const GAP_CHECK_DROP := 2.0
const GAP_MAX_SEARCH := 6.0
const GAP_SEARCH_STEP := 0.5
const GAP_SAFETY_MARGIN := 1.0
const GAP_LANDING_MARGIN := 0.2

## Raycasts the gap ahead and jumps only if this unit's speed/jump arc can
## clear both its width and the landing height; otherwise stops at the edge.
func _check_gap_jump() -> void:
	if not is_on_floor():
		return
	var horizontal_vel := Vector3(velocity.x, 0.0, velocity.z)
	var move_speed_h := horizontal_vel.length()
	if move_speed_h < 0.1:
		return
	var dir := horizontal_vel / move_speed_h
	var space_state := get_world_3d().direct_space_state
	var launch_y := global_position.y

	if _floor_height_at(space_state, global_position + dir * GAP_CHECK_AHEAD) != null:
		return  # solid ground ahead, nothing to do

	var far_floor_y = null
	var far_t := 0.0
	var t := GAP_CHECK_AHEAD + GAP_SEARCH_STEP
	while t <= GAP_CHECK_AHEAD + GAP_MAX_SEARCH:
		var h = _floor_height_at(space_state, global_position + dir * t)
		if h != null:
			far_floor_y = h
			far_t = t
			break
		t += GAP_SEARCH_STEP

	if far_floor_y == null:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var required_distance: float = far_t + GAP_SAFETY_MARGIN
	var required_rise: float = far_floor_y - launch_y
	var flight_time := required_distance / move_speed_h
	var height_at_landing := jump_velocity * flight_time - 0.5 * _gravity * flight_time * flight_time

	if height_at_landing >= required_rise + GAP_LANDING_MARGIN:
		velocity.y = jump_velocity
		_gap_jumping = true
	else:
		velocity.x = 0.0
		velocity.z = 0.0

## World Y of the floor/platform below pos, or null if none. Probes from
## well above pos so a raised landing is actually visible.
func _floor_height_at(space_state: PhysicsDirectSpaceState3D, pos: Vector3):
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3(0, GAP_PROBE_UP, 0), pos + Vector3(0, -GAP_CHECK_DROP, 0), 1)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null
	return result["position"].y

## Invented drop rates - no doc-sourced table exists.
const BASE_LOOT_DROP_CHANCE := 0.35
const TOME_DROP_CHANCE := 0.08  # flat, independent of the gear roll below
## Spell upgrade material: its own roll, on top of whatever else drops.
const AETHER_DROP_CHANCE := 0.18
const AETHER_DROP_COUNT := Vector2i(1, 3)
## Crafting currency (Orbs, Brands, Edicts) drops as loot only, picked by
## Constants.CURRENCY_DROP_WEIGHTS. Stones/Shard are rarer (one flat roll
## picks between the 3, not 3 independent rolls).
const CURRENCY_DROP_CHANCE := 0.12
const CRAFTING_CONSUMABLE_DROP_CHANCE := 0.03
const CRAFTING_CONSUMABLE_DIR := "res://data/consumables/instances/"
const SLATE_DROP_CHANCE := 0.10
const FIGMENT_DROP_CHANCE := 0.06
const LOOT_PICKUP_SCENE := preload("res://entities/pickups/loot_pickup/LootPickup.tscn")
const GOLD_PICKUP_SCENE := preload("res://entities/pickups/gold_pickup/GoldPickup.tscn")

func _on_died() -> void:
	AudioManager.play_at(SoundLib.pick_random(SoundLib.library.enemy_death), global_position)
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.experience:
		player.experience.add_xp(xp_reward)
	if player and player.ward:
		player.ward.restore_on_kill()
	_drop_gold()
	_maybe_drop_loot()
	if _anim_controller:
		_play_death_then_free()
		return
	queue_free()

## Definition-driven enemies with a death clip linger on it instead of
## vanishing. Leaves the "enemy" group and drops collision immediately so
## the corpse can't be targeted, hit, or counted as alive meanwhile.
func _play_death_then_free() -> void:
	remove_from_group("enemy")
	collision_layer = 0
	velocity = Vector3.ZERO
	var head_zone := get_node_or_null("HeadZone") as Area3D
	if head_zone:
		head_zone.set_deferred("monitorable", false)
	_riposte_indicator.visible = false
	for icon in _status_icons.values():
		icon.visible = false
	_anim_controller.play_death()
	await get_tree().create_timer(_anim_controller.get_death_duration() + DEATH_LINGER_SEC).timeout
	queue_free()

func _drop_gold() -> void:
	if gold_reward <= 0:
		return
	var pickup: GoldPickup = GOLD_PICKUP_SCENE.instantiate()
	pickup.amount = gold_reward
	get_parent().add_child(pickup)
	pickup.global_position = _drop_position()

## A drop-conversion rarity affix replaces all drops with its category.
## Otherwise Item Quantity scales the number of drop rolls and Item Rarity
## the quality of each.
func _maybe_drop_loot() -> void:
	if rarity_component:
		var conversion_affix := rarity_component.get_drop_conversion_affix()
		if conversion_affix:
			for i in Loot.roll_count(Loot.multipliers(rarity_component)["quantity"]):
				_drop_converted(conversion_affix)
			return

	_maybe_drop_aether()
	var mods := Loot.multipliers(rarity_component)
	for i in Loot.roll_count(Loot.base_drop_rolls(rank, rarity_component) * mods["quantity"]):
		_roll_drop(mods["rarity"])

## One drop roll: at most one drop, from the first category that hits.
func _roll_drop(rarity_mult: float) -> void:
	if randf() <= TOME_DROP_CHANCE:
		var tome := TomeRoller.roll_for_unowned(GameState.owned_ability_ids)
		if tome:
			_spawn_pickup(tome)
			return  # one drop per roll

	if randf() <= CURRENCY_DROP_CHANCE:
		_spawn_currency_pickup(Constants.roll_currency_drop())
		return

	if randf() <= CRAFTING_CONSUMABLE_DROP_CHANCE:
		_spawn_currency_pickup(StringName(Constants.CRAFTING_CONSUMABLE_IDS.pick_random()))
		return

	if randf() <= SLATE_DROP_CHANCE:
		var power_level: int = GameState.active_map.tier if GameState.active_map else 1
		var slate := SlateRoller.roll(power_level, rarity_mult)
		if slate:
			_spawn_slate_pickup(slate)
			return

	if randf() <= FIGMENT_DROP_CHANCE:
		var power_level: int = GameState.active_map.tier if GameState.active_map else GameState.player_level
		var figment := FigmentRoller.roll_for_drop(power_level)
		if figment:
			_spawn_pickup(figment)
			return

	if randf() <= JEWEL_DROP_CHANCE:
		_spawn_pickup(JewelRoller.roll(_compute_item_level(), rarity_mult))
		return

	if randf() <= LENS_DROP_CHANCE:
		_spawn_pickup(LensRoller.roll(_compute_item_level(), rarity_mult))
		return

	if randf() <= AMMO_DROP_CHANCE:
		var ammo := _roll_ammo_drop()
		if ammo:
			_spawn_pickup(ammo)
			return

	if randf() > BASE_LOOT_DROP_CHANCE:
		return
	var item := ItemRoller.roll(_compute_item_level(), rarity_mult)
	if item == null:
		return
	_spawn_pickup(item)

## Ammo drops prefer the type the player's ranged weapon uses.
const AMMO_DROP_CHANCE := 0.15
## Socketable jewels (JewelRoller), rolled just before ammo.
const JEWEL_DROP_CHANCE := 0.04
## Lenses (LensRoller), for Slate sockets; rolled just after jewels.
const LENS_DROP_CHANCE := 0.025

func _roll_ammo_drop() -> Item:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return null
	var ammo_type := _get_preferred_ammo_type(player)
	if ammo_type == Constants.AmmoType.ARROW:
		return null  # arrows are infinite, never drop
	var ammo_id: String = Constants.AMMO_TYPE_PICKUP_ID.get(ammo_type, "")
	if ammo_id.is_empty():
		return null
	var base := load(CRAFTING_CONSUMABLE_DIR + ammo_id + ".tres") as Item
	return base.duplicate(true) as Item if base else null

## Ammo type of the first non-bow ranged weapon in the active weapon set,
## then the inactive one. Bows-only returns ARROW (no drop); no ranged
## weapon at all rolls a random firearm type.
func _get_preferred_ammo_type(player: Player) -> Constants.AmmoType:
	var equipment := player.equipment
	var weapons: Array = [player.get_active_weapon(), equipment.primary_weapons[1 - equipment.active_weapon_set]]
	var saw_bow := false
	for weapon in weapons:
		if weapon is Weapon and weapon.is_ranged:
			if weapon.ammo_type == Constants.AmmoType.ARROW:
				saw_bow = true
			else:
				return weapon.ammo_type
	if saw_bow:
		return Constants.AmmoType.ARROW
	var types := [Constants.AmmoType.PISTOL, Constants.AmmoType.RIFLE, Constants.AmmoType.SHOTGUN, Constants.AmmoType.AUTOMATIC]
	return types[randi() % types.size()]

## Stub: only "figments" conversion exists so far.
func _drop_converted(affix: EnemyAffix) -> void:
	match affix.drop_conversion_type:
		"figments":
			var power_level: int = GameState.active_map.tier if GameState.active_map else GameState.player_level
			var figment := FigmentRoller.roll_for_drop(power_level)
			if figment:
				_spawn_pickup(figment)
		_:
			pass  # other conversion types ("brands", etc.) have no seeded affix yet to reach this

func _spawn_pickup(item: Item) -> void:
	var pickup: LootPickup = LOOT_PICKUP_SCENE.instantiate()
	pickup.item = item
	get_parent().add_child(pickup)
	pickup.global_position = _drop_position()
	EventBus.loot_dropped.emit(item, global_position)

func _maybe_drop_aether() -> void:
	var rank_bonus: int = Constants.ENEMY_RANK_ITEM_LEVEL_OFFSET.get(rank, 0)
	if randf() > AETHER_DROP_CHANCE * (1.0 + rank_bonus * 0.5):
		return
	var tier: int = GameState.active_map.tier if GameState.active_map else 1
	_spawn_currency_pickup(Ability.AETHER_CURRENCY, randi_range(AETHER_DROP_COUNT.x, AETHER_DROP_COUNT.y) + rank_bonus + (tier - 1))

func _spawn_currency_pickup(currency_id: StringName, count: int = 1) -> void:
	var pickup: LootPickup = LOOT_PICKUP_SCENE.instantiate()
	pickup.currency_id = currency_id
	pickup.currency_count = count
	get_parent().add_child(pickup)
	pickup.global_position = _drop_position()

func _spawn_slate_pickup(slate: Slate) -> void:
	var pickup: LootPickup = LOOT_PICKUP_SCENE.instantiate()
	pickup.slate = slate
	get_parent().add_child(pickup)
	pickup.global_position = _drop_position()
	EventBus.slate_dropped.emit(slate, global_position)

## Enemies have 0% base Resistance, so Resistance Shred makes it negative.
## can_evade: true only for player weapon attack hits (melee swing, ranged
## projectile). Spells, DoT ticks, riders and ripostes leave it false.
## Returns false if the hit was dodged (caller should skip its on-hit
## follow-ups), true otherwise - including a hit fully absorbed by Ward.
## is_dot: a damage-over-time tick - smaller floating number.
## ignore_armor: War Pick's Armor Pierce.
func take_damage(amount: float, damage_type: Constants.DamageType, is_spell: bool = false, can_evade: bool = false, is_dot: bool = false, ignore_armor: bool = false) -> bool:
	if not is_dot:
		last_hit_was_unaware = not is_in_combat()
	_last_combat_msec = Time.get_ticks_msec()
	if invulnerable:
		return false
	var show_number := health.is_alive()
	if can_evade and not is_spell and evasion_value > 0.0:
		if randf() < DamageCalculator.dodge_chance(evasion_value):
			EventBus.enemy_hit_dodged.emit(self)
			return false
	var multiplier := composure.get_damage_multiplier(is_spell) if composure else 1.0
	var status_multiplier := status_effects.get_damage_taken_multiplier(damage_type) if status_effects else 1.0
	if status_effects and damage_type == Constants.DamageType.LIGHTNING:
		status_multiplier *= status_effects.get_shock_multiplier()
	if status_effects and status_effects.has_effect("pallid"):
		status_multiplier *= 1.0 + GearEffects.player_bonus(get_tree(), "pallid_damage_taken") / 100.0
	if rarity_component:
		status_multiplier *= rarity_component.get_damage_taken_multiplier()
	_last_damaged_msec = Time.get_ticks_msec()
	var mitigated := amount * multiplier * status_multiplier
	var category = Constants.DAMAGE_TYPE_CATEGORY.get(damage_type)
	if category == Constants.DamageCategory.PHYSICAL and armor_value > 0.0 and not is_dot and not ignore_armor:
		var armor := armor_value * (status_effects.get_armor_multiplier() if status_effects else 1.0)
		mitigated *= (1.0 - armor / (armor + 1000.0))
	if status_effects and (category == Constants.DamageCategory.ELEMENTAL or category == Constants.DamageCategory.ESOTERIC):
		var shred := status_effects.get_resistance_shred() + _aura_shred()
		if shred > 0.0:
			mitigated *= (1.0 - DamageCalculator.resistance_mitigation(-shred))
	if _ward_current > 0.0:
		var absorbed: float = min(_ward_current, mitigated)
		_ward_current -= absorbed
		mitigated -= absorbed
		if show_number:
			_spawn_damage_number(absorbed, damage_type, DamageNumber.WARD_ALPHA, WARD_NUMBER_EXTRA_HEIGHT, is_dot)
		if mitigated <= 0.0:
			return true
	health.apply_damage(mitigated)
	if show_number:
		_spawn_damage_number(mitigated, damage_type, 1.0, 0.0, is_dot)
	if _anim_controller and health.is_alive() and Time.get_ticks_msec() - _last_hit_react_msec >= HIT_REACT_MIN_INTERVAL_MSEC:
		_last_hit_react_msec = Time.get_ticks_msec()
		_anim_controller.play_hit_react()
	return true

const DAMAGE_NUMBER_SCENE := preload("res://ui/damage_number/DamageNumber.tscn")
const WARD_NUMBER_EXTRA_HEIGHT := 0.35  # Ward numbers sit a little above health numbers

## Crit is always false for now: take_damage() has no crit info (callers
## hold it in their roll_damage() result but don't pass it through).
func _spawn_damage_number(amount: float, damage_type: Constants.DamageType, alpha: float = 1.0, extra_height: float = 0.0, is_dot: bool = false) -> void:
	if amount <= 0.0 or not is_inside_tree():
		return
	var number: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	get_tree().current_scene.add_child(number)
	number.global_position = global_position + Vector3(randf_range(-0.3, 0.3), body_height - 0.1 + extra_height, randf_range(-0.3, 0.3))
	number.setup(amount, damage_type, false, alpha, is_dot)

## Weighted roll; never returns BOSS (boss scenes set it directly).
func _roll_rank() -> Constants.EnemyRank:
	var total := 0.0
	for w in Constants.ENEMY_RANK_SPAWN_WEIGHTS.values():
		total += w
	var roll := randf() * total
	var cumulative := 0.0
	for r in Constants.ENEMY_RANK_SPAWN_WEIGHTS:
		cumulative += Constants.ENEMY_RANK_SPAWN_WEIGHTS[r]
		if roll <= cumulative:
			return r
	return Constants.EnemyRank.NORMAL

## Area level plus the rank offset (Normal +0, Magic +1, Rare +2, Boss +5).
## Used for gear and jewel drops; Slates/Figments use the Map tier.
func _compute_item_level() -> int:
	var area_level: int = GameState.active_map.tier if GameState.active_map else GameState.player_level
	return area_level + Constants.ENEMY_RANK_ITEM_LEVEL_OFFSET.get(rank, 0)

## Never moves, falls or gets pushed: it hovers where it was placed.
var immovable: bool = false

## Where this enemy's spells and projectiles start.
func get_cast_origin() -> Vector3:
	return global_position + Vector3(0, 0.95, 0)

## Called by BossBrain as an ability is telegraphed at `target`, landing
## after `delay` seconds; bosses override it for casting effects.
func on_ability_telegraph(_ability: BossAbility, _target: Vector3, _delay: float) -> void:
	pass

## Where a PULL ability drags the player and slams.
func get_pull_center() -> Vector3:
	return global_position

## True when the player can't be pulled (the Herald's Anchor pylons).
func is_player_anchored(_player_node: Player) -> bool:
	return false

## Called every step of a CHARGE; true ends it early.
func blocks_charge(_direction: Vector3) -> bool:
	return false

## Called for each unit a SUMMON ability brings in.
func on_unit_summoned(_unit: Enemy) -> void:
	pass

## Set by a BossBrain child: abilities, phases and the casting lock.
var boss_brain: BossBrain
## Phase transitions: hits land but deal nothing.
var invulnerable: bool = false

func is_casting() -> bool:
	return boss_brain != null and boss_brain.casting

## Base damage boss abilities scale from: the boss's own attack damage.
func get_ability_base_damage() -> float:
	var melee := get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	var ranged := get_node_or_null("RangedAttack") as EnemyRangedAttack
	var base := melee.damage_amount if melee else (ranged.damage_amount if ranged else 20.0)
	return base * get_outgoing_damage_multiplier()

## Damage type for abilities that don't set their own (BossAbility.damage_type -1).
func get_ability_damage_type() -> int:
	var melee := get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	return melee.damage_type if melee else (definition.damage_type if definition else Constants.DamageType.KINETIC)

## In an attack's wind-up or strike, or casting (not its follow-through):
## when a BossBrain may not start an ability.
func is_mid_attack() -> bool:
	if is_casting():
		return true
	for path in ["MeleeAttack", "RangedAttack"]:
		var attack := get_node_or_null(path)
		if attack and attack.has_method("is_attacking") and attack.is_attacking():
			return true
	return false

## Rooted in place from an attack's wind-up until its animation finishes.
func is_attack_locked() -> bool:
	if is_casting():
		return true
	for path in ["MeleeAttack", "RangedAttack"]:
		var attack := get_node_or_null(path)
		if attack and attack.has_method("is_attacking") and attack.is_attacking():
			return true
	return _anim_controller != null and _anim_controller.is_playing_attack()

## The attack animation is the telegraph: started at wind-up begin and
## timed so its hit frame lands when the wind-up ends (windup_sec later).
func begin_attack_telegraph(windup_sec: float) -> void:
	if _anim_controller:
		_anim_controller.play_attack(windup_sec)

## Several drops from one kill spread out instead of stacking in one spot.
const DROP_SCATTER := 0.9

## A scatter spot only counts if there's floor at most this far below the feet,
## so drops never hang over a ledge or gap (the Vault's jump platform).
const DROP_MAX_STEP := 0.6
const DROP_ATTEMPTS := 8
## Drops float this high above the floor they land on.
const DROP_HOVER := 0.35

## A random spot near the body that has floor under it, set onto that floor.
## Falls back to the floor under the body itself.
func _drop_position() -> Vector3:
	for attempt in DROP_ATTEMPTS:
		var angle := randf() * TAU
		var spot := global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf() * DROP_SCATTER
		var floor_y: float = _floor_below(spot, DROP_MAX_STEP)
		if not is_nan(floor_y):
			return Vector3(spot.x, floor_y + DROP_HOVER, spot.z)
	var under: float = _floor_below(global_position, 100.0)
	if not is_nan(under):
		return Vector3(global_position.x, under + DROP_HOVER, global_position.z)
	return _nearest_floor_spot()

## Nothing under the body (a boss hovering over the void): the nearest floor
## in rings out to DROP_SEARCH_RADIUS, nearest the player first; else the
## player's own feet, which are always reachable.
const DROP_SEARCH_RADIUS := 16.0

func _nearest_floor_spot() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
	var radius := 1.5
	while radius <= DROP_SEARCH_RADIUS:
		var best := Vector3.INF
		for i in 12:
			var angle := TAU * i / 12.0
			var spot := global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
			var floor_y: float = _floor_below(spot, 20.0)
			if is_nan(floor_y):
				continue
			var found := Vector3(spot.x, floor_y + DROP_HOVER, spot.z)
			if best == Vector3.INF or (player and found.distance_to(player.global_position) < best.distance_to(player.global_position)):
				best = found
		if best != Vector3.INF:
			return best + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
		radius += 1.5
	return player.global_position + Vector3(randf_range(-0.6, 0.6), DROP_HOVER, randf_range(-0.6, 0.6)) if player else global_position

## Height of the level geometry below `point` (searched from a little above
## it down to max_drop below), skipping creatures. NAN when there's none.
func _floor_below(point: Vector3, max_drop: float) -> float:
	if not is_inside_tree():
		return point.y
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid()]
	for i in 4:
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.8, point + Vector3.DOWN * max_drop, 1)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return NAN
		if hit["collider"] is CharacterBody3D or hit["collider"] is RigidBody3D:
			exclude.append(hit["rid"])
			continue
		return (hit["position"] as Vector3).y
	return NAN
