extends CharacterBody3D
class_name Enemy
## Base enemy. Regular units are MeleeUnit/RangedUnit scenes driven by an
## EnemyDefinition (see EnemyRoster); bosses subclass this and tune values
## directly. Chase movement lives here; attacking is an optional child
## component (EnemyMeleeAttack/EnemyRangedAttack) that drives the telegraph
## calls below - chasing and attacking are decoupled.

## User request (2026-08-30): White/Blue/Rare/Boss rank, gating which item-
## level tier of loot this enemy can drop (see _compute_item_level()).
## Left at NORMAL here and rolled randomly in _ready() unless a scene
## explicitly overrides it to BOSS (a real boss encounter's own scene sets
## this before _ready() runs, same as any other @export override) - see
## _roll_rank()'s own header for why BOSS itself is never auto-rolled.
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

## Data-driven override of the stats/visuals above (Implementation Brief
## v4.1). Applied at the start of _ready(); null keeps whatever this
## enemy's own scene/subclass sets, so archetypes migrate one at a time.
@export var definition: EnemyDefinition = null

var faction: String = ""
var armor_value: float = 0.0    # flat Physical mitigation in take_damage(): armor / (armor + 1000)
var evasion_value: float = 0.0  # dodge chance vs player weapon attacks only (take_damage()'s can_evade)
# Flat damage-absorb pool set at spawn from definition.ward_percent; no regen.
var _ward_pool: float = 0.0
var _ward_current: float = 0.0

func get_display_name() -> String:
	return display_name if display_name != "" else name

## Implementation Brief v3.4 Section 3 (2026-08-31): "Every enemy has a
## headshot zone. Hitting it applies 25% increased damage taken to that
## hit only." Head only for now, per the brief's own scope limit.
@export var critical_spot_multiplier: float = 1.25


@onready var health: HealthComponent = $HealthComponent
@onready var stance: StanceComponent = $StanceComponent
@onready var composure: ComposureComponent = $ComposureComponent
@onready var status_effects: StatusEffectComponent = $StatusEffectComponent
@onready var attack_hitbox: Area3D = $AttackHitbox

const RIPOSTE_INDICATOR_HEIGHT := 2.2
const RIPOSTE_INDICATOR_COLOR := Color(1.0, 0.05, 0.05)
const RIPOSTE_BLINK_INTERVAL := 0.25

## Small colored dots above the head, one per active status effect (Section
## 09), stacked below the (higher, blinking) riposte indicator.
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

## User request (2026-08-31): enemy health bars "hang while we're in
## combat and disappear when they lose track of me/I am out of combat
## for 5 seconds." "In combat" = within chase_range of the player (the
## same distance _update_chase() already gates its own chase/attack
## logic on - "losing track of me" IS leaving chase_range, no separate
## concept needed) OR has taken damage recently - updated continuously
## from real state rather than a parallel combat-state machine.
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
	if definition == null or definition.ward_percent <= 0.0:
		return
	_ward_pool = health.max_health * definition.ward_percent
	_ward_current = _ward_pool

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
	var anim_tree := model.get_node_or_null("AnimationTree") as AnimationTree
	if anim_tree and anim_set:
		var controller := EnemyAnimationController.new()
		add_child(controller)
		controller.setup(anim_tree, anim_set)
		_anim_controller = controller

## Turns the model (not the body - collision/hitboxes stay symmetric) toward
## the player, and feeds ground speed to the animation tree.
func _update_model(delta: float) -> void:
	if _model_root == null or not health.is_alive():
		return
	if is_instance_valid(_player):
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.1 and (to_player.length() <= chase_range or is_in_combat()):
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

## Hidden red light above the head, only shown (blinking) while
## Riposte-able - "you melee attack an enemy whose stance is broken to
## riposte them" needs a clear on-screen signal of that window.
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

## Deterministic scaling by the active Map's own tier (`FigmentItem.tier`) -
## on top of enemy_health_multiplier/enemy_damage_multiplier, which are
## only a PROBABILISTIC bonus (FigmentRoller doesn't guarantee either affix
## rolls onto a given Map - see AFFIX_POOL there), so two Tier 5 Maps
## could otherwise end up equally tough as two Tier 1 Maps by chance.
## Tier itself always makes enemies tougher, harder-hitting, and more
## rewarding. Invented growth curve, not doc-sourced - Section 24 defers
## Map/tier balance entirely (same convention as every other flagged gap).
##
## v4.5: TIER_HEALTH_GROWTH_PER_TIER removed (user decision, 2026-09-22) -
## the mob level curve (definition.mob_level + MOB_LEVELS_PER_TIER per tier
## above 1, see _apply_map_modifiers() below) already grows health per tier for
## definition-driven enemies; keeping both double-counted tier's health
## contribution. Health at tier now comes from the level curve x
## enemy_health_multiplier (Figment affix roll) only. Damage/reward have no
## level-curve counterpart yet, so their own deterministic per-tier growth
## is unchanged.
const TIER_DAMAGE_GROWTH_PER_TIER := 0.10
const TIER_REWARD_GROWTH_PER_TIER := 0.20
const MOB_LEVELS_PER_TIER := 2

## Patch v3.9: also applies EnemyRarityComponent's health multiplier, if
## one was attached at spawn time - independent of GameState.active_map
## (rarity scaling still applies in the Hub/anywhere with no active Map),
## so this can no longer just early-return when active_map is null.
func _apply_map_modifiers() -> void:
	var rarity_mult := 1.0
	var rarity_component := get_node_or_null("EnemyRarityComponent") as EnemyRarityComponent
	if rarity_component:
		rarity_mult = rarity_component.get_health_multiplier()
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

## Patch v3.9: also applies EnemyRarityComponent's damage multiplier, if
## one was attached at spawn time - same active_map-independence as
## _apply_map_modifiers() above.
func get_outgoing_damage_multiplier() -> float:
	var rarity_mult := 1.0
	var rarity_component := get_node_or_null("EnemyRarityComponent") as EnemyRarityComponent
	if rarity_component:
		rarity_mult = rarity_component.get_damage_multiplier()
	if GameState.active_map == null:
		return rarity_mult
	return GameState.active_map.enemy_damage_multiplier * (1.0 + (GameState.active_map.tier - 1) * TIER_DAMAGE_GROWTH_PER_TIER) * rarity_mult

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_chase()
	move_and_slide()
	_update_model(delta)

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

	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if is_attack_locked():
		velocity.x = 0.0
		velocity.z = 0.0
		_last_combat_msec = Time.get_ticks_msec()
		return

	if dist <= chase_range:
		_last_combat_msec = Time.get_ticks_msec()

	# A hit from outside chase_range (landed or dodged - take_damage() marks
	# combat before its dodge roll) still pulls the enemy in, for the same
	# grace window the health bar uses.
	if (dist > chase_range and not is_in_combat()) or dist < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var dir := to_player / dist
	var speed := move_speed * status_effects.get_move_speed_multiplier()
	if retreat_distance > 0.0 and dist < retreat_distance:
		velocity.x = -dir.x * speed
		velocity.z = -dir.z * speed
	elif dist > stop_distance:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	_check_gap_jump()

const GAP_CHECK_AHEAD := 1.0
const GAP_PROBE_UP := 3.0       # probe ray starts this far above - must clear a raised landing like the Vault's platform
const GAP_CHECK_DROP := 2.0
const GAP_MAX_SEARCH := 6.0
const GAP_SEARCH_STEP := 0.5
const GAP_SAFETY_MARGIN := 1.0
const GAP_LANDING_MARGIN := 0.2

## Measures the actual gap ahead via raycast (not a hardcoded distance)
## and only jumps if this archetype's move_speed/jump_velocity arc can
## clear both the horizontal distance AND the landing height by the
## time it gets there - otherwise stops at the edge.
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
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3(0, GAP_PROBE_UP, 0), pos + Vector3(0, -GAP_CHECK_DROP, 0))
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
## User request: "make map items droppable." Rarer than gear/Brands -
## Figments are a stronger reward (an entire extra Map's worth of loot),
## same invented-rate convention as everything else in this table.
const FIGMENT_DROP_CHANCE := 0.06
const LOOT_PICKUP_SCENE := preload("res://entities/pickups/loot_pickup/LootPickup.tscn")
const GOLD_PICKUP_SCENE := preload("res://entities/pickups/gold_pickup/GoldPickup.tscn")

func _on_died() -> void:
	AudioManager.play_at(SoundLib.pick_random(SoundLib.library.enemy_death), global_position)
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.experience:
		player.experience.add_xp(xp_reward)
	if player and player.ward:
		player.ward.restore_on_kill()  # Patch v3.2: "On kill: 5% Ward Restoration baseline"
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
	pickup.global_position = global_position + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3))

## Patch v3.9 "Enemy Rarity System" - doc: "Certain affixes convert all
## drops from that enemy into a specific category... all-or-nothing."
## Short-circuits the entire cascade below when present, matching that.
func _maybe_drop_loot() -> void:
	var rarity_component := get_node_or_null("EnemyRarityComponent") as EnemyRarityComponent
	if rarity_component:
		var conversion_affix := rarity_component.get_drop_conversion_affix()
		if conversion_affix:
			_drop_converted(conversion_affix)
			return

	_maybe_drop_aether()
	if randf() <= TOME_DROP_CHANCE:
		var tome := TomeRoller.roll_for_unowned(GameState.owned_ability_ids)
		if tome:
			_spawn_pickup(tome)
			return  # one drop max per kill

	if randf() <= CURRENCY_DROP_CHANCE:
		_spawn_currency_pickup(Constants.roll_currency_drop())
		return

	if randf() <= CRAFTING_CONSUMABLE_DROP_CHANCE:
		var consumable := _roll_crafting_consumable()
		if consumable:
			_spawn_pickup(consumable)
			return

	if randf() <= SLATE_DROP_CHANCE:
		var power_level: int = GameState.active_map.tier if GameState.active_map else 1
		var slate := SlateRoller.roll(power_level)
		if slate:
			_spawn_slate_pickup(slate)
			return

	if randf() <= FIGMENT_DROP_CHANCE:
		var power_level: int = GameState.active_map.tier if GameState.active_map else GameState.player_level
		var figment := FigmentRoller.roll_for_drop(power_level)
		if figment:
			_spawn_pickup(figment)
			return

	if randf() <= AMMO_DROP_CHANCE:
		var ammo := _roll_ammo_drop()
		if ammo:
			_spawn_pickup(ammo)
			return

	var quantity_mult: float = GameState.active_map.loot_quantity_multiplier if GameState.active_map else 1.0
	if randf() > BASE_LOOT_DROP_CHANCE * quantity_mult:
		return
	var rarity_mult: float = GameState.active_map.loot_rarity_multiplier if GameState.active_map else 1.0
	var item := ItemRoller.roll(_compute_item_level(), rarity_mult)
	if item == null:
		return
	_spawn_pickup(item)

## Implementation Brief v4.2: ammo drops prefer the ammo type the player's
## ranged weapon actually uses. Rolled independently of (and just before)
## the gear roll below, so it doesn't change any earlier drop's odds.
const AMMO_DROP_CHANCE := 0.15

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

## Stub only (brief's own DO NOT: "Implement Figment drop conversion
## fully - stub only. Full Figment drop logic is a separate pass") -
## reuses the existing, already-working FigmentRoller.roll_for_drop()
## rather than half-building a second Figment-rolling path. Item Rarity/
## Quantity bonuses (EnemyRarityComponent.get_effective_rarity_bonus()/
## get_effective_quantity_bonus()) are real, aggregated data but not yet
## fed into the roll - that's the deferred "separate pass."
func _drop_converted(affix: EnemyAffix) -> void:
	match affix.drop_conversion_type:
		"figments":
			var power_level: int = GameState.active_map.tier if GameState.active_map else GameState.player_level
			var figment := FigmentRoller.roll_for_drop(power_level)
			if figment:
				_spawn_pickup(figment)
		_:
			pass  # other conversion types ("brands", etc.) have no seeded affix yet to reach this

func _roll_crafting_consumable() -> Item:
	var id: String = Constants.CRAFTING_CONSUMABLE_IDS[randi() % Constants.CRAFTING_CONSUMABLE_IDS.size()]
	var base := load(CRAFTING_CONSUMABLE_DIR + id + ".tres") as Item
	return base.duplicate(true) as Item if base else null

func _spawn_pickup(item: Item) -> void:
	var pickup: LootPickup = LOOT_PICKUP_SCENE.instantiate()
	pickup.item = item
	get_parent().add_child(pickup)
	pickup.global_position = global_position
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
	pickup.global_position = global_position

func _spawn_slate_pickup(slate: Slate) -> void:
	var pickup: LootPickup = LOOT_PICKUP_SCENE.instantiate()
	pickup.slate = slate
	get_parent().add_child(pickup)
	pickup.global_position = global_position
	EventBus.slate_dropped.emit(slate, global_position)

## Patch v3.2 Resistance Shred: enemies have no Resistance stat of their
## own (no StatSheet/gear here), but "0% base - shred%" is still a real,
## meaningful negative Resistance - this is the doc's own primary framing
## for the mechanic (shredding an ENEMY's Resistance), so it's wired even
## without a full enemy-side Resistance system to shred FROM.
## Implementation Brief v3.4 Section 3 - the brief's own `is_critical_spot
## (hit_position: Vector3)` doesn't fit this project's actual hit
## detection (no bones, no precise hit point anywhere - melee/ranged hits
## are both plain Area3D body-overlap checks). Adapted to area-overlap
## instead: true if the attacking Area3D (a weapon's hitbox, or a
## Projectile) is ALSO currently overlapping this enemy's own HeadZone at
## the moment of the hit - same intent (did this specific attack catch
## the head), different mechanism to match what this project actually has.
func is_critical_spot_hit(attacking_area: Area3D) -> bool:
	var head_zone := get_node_or_null("HeadZone") as Area3D
	if head_zone == null or attacking_area == null:
		return false
	return attacking_area.overlaps_area(head_zone)

## can_evade: true only for player weapon attack hits (melee swing, ranged
## projectile). Spells, DoT ticks, riders and ripostes leave it false.
## Returns false if the hit was dodged (caller should skip its on-hit
## follow-ups), true otherwise - including a hit fully absorbed by Ward.
## is_dot: a damage-over-time tick - no floating damage number.
func take_damage(amount: float, damage_type: Constants.DamageType, is_spell: bool = false, can_evade: bool = false, is_dot: bool = false) -> bool:
	_last_combat_msec = Time.get_ticks_msec()
	var show_number := not is_dot and health.is_alive()
	if can_evade and not is_spell and evasion_value > 0.0:
		if randf() < DamageCalculator.dodge_chance(evasion_value):
			EventBus.enemy_hit_dodged.emit(self)
			return false
	var multiplier := composure.get_damage_multiplier(is_spell) if composure else 1.0
	var status_multiplier := status_effects.get_damage_taken_multiplier(damage_type) if status_effects else 1.0
	if status_effects and damage_type == Constants.DamageType.LIGHTNING:
		status_multiplier *= status_effects.get_shock_multiplier()
	var mitigated := amount * multiplier * status_multiplier
	var category = Constants.DAMAGE_TYPE_CATEGORY.get(damage_type)
	if category == Constants.DamageCategory.PHYSICAL and armor_value > 0.0:
		mitigated *= (1.0 - armor_value / (armor_value + 1000.0))
	if status_effects and (category == Constants.DamageCategory.ELEMENTAL or category == Constants.DamageCategory.ESOTERIC):
		var shred := status_effects.get_resistance_shred()
		if shred > 0.0:
			mitigated *= (1.0 - DamageCalculator.resistance_mitigation(-shred))
	if _ward_current > 0.0:
		var absorbed: float = min(_ward_current, mitigated)
		_ward_current -= absorbed
		mitigated -= absorbed
		if show_number:
			_spawn_damage_number(absorbed, damage_type, DamageNumber.WARD_ALPHA, WARD_NUMBER_EXTRA_HEIGHT)
		if mitigated <= 0.0:
			AudioManager.play_at(SoundLib.pick_random(SoundLib.library.hit_flesh), global_position, -4.0)
			return true
	health.apply_damage(mitigated)
	if show_number:
		_spawn_damage_number(mitigated, damage_type)
	AudioManager.play_at(SoundLib.pick_random(SoundLib.library.hit_flesh), global_position, -2.0)
	if _anim_controller and health.is_alive() and Time.get_ticks_msec() - _last_hit_react_msec >= HIT_REACT_MIN_INTERVAL_MSEC:
		_last_hit_react_msec = Time.get_ticks_msec()
		_anim_controller.play_hit_react()
	return true

const DAMAGE_NUMBER_SCENE := preload("res://ui/damage_number/DamageNumber.tscn")
const DAMAGE_NUMBER_HEIGHT := 1.8
const WARD_NUMBER_EXTRA_HEIGHT := 0.35  # Ward numbers sit a little above health numbers

## Crit is always false for now: take_damage() has no crit info (callers
## hold it in their roll_damage() result but don't pass it through).
func _spawn_damage_number(amount: float, damage_type: Constants.DamageType, alpha: float = 1.0, extra_height: float = 0.0) -> void:
	if amount <= 0.0 or not is_inside_tree():
		return
	var number: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	get_tree().current_scene.add_child(number)
	number.global_position = global_position + Vector3(randf_range(-0.3, 0.3), DAMAGE_NUMBER_HEIGHT + extra_height, randf_range(-0.3, 0.3))
	number.setup(amount, damage_type, false, alpha)

## Never returns BOSS - a boss encounter's own scene/script sets `rank`
## to BOSS directly (see _ready()'s own guard), it doesn't come from this
## weighted roll. Falls back to NORMAL if the weight table were ever
## emptied, which it isn't.
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

## User request (2026-08-30): "the right tier is based on the level of the
## area and mobs. White mobs are the area level, blue mobs are the area +1,
## rare mobs are the area + 2 levels, bosses are the area + 5 levels."
## Scoped to ItemRoller drops specifically (real weapon/armor/shield base
## types) - Slate/Figment rolls just below keep using the Map tier
## directly, a separate tier concept this request didn't touch.
func _compute_item_level() -> int:
	var area_level: int = GameState.active_map.tier if GameState.active_map else GameState.player_level
	return area_level + Constants.ENEMY_RANK_ITEM_LEVEL_OFFSET.get(rank, 0)

## Rooted in place from an attack's wind-up until its animation finishes.
func is_attack_locked() -> bool:
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
