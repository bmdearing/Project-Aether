extends CharacterBody3D
class_name Enemy
## Base enemy per the Trinity Rule (Section 21) - archetype subclasses
## tune exported values rather than duplicate component wiring. Chase
## movement lives here; attacking is an optional child component
## (EnemyMeleeAttack/EnemyRangedAttack) that drives the telegraph calls
## below - chasing and attacking are decoupled.

@export var archetype: Constants.EnemyArchetype
@export var move_speed: float = 3.0
@export var chase_range: float = 15.0
## Distance to close to and hold - melee archetypes keep this inside
## their attack range; ranged archetypes use it as a stand-off distance.
@export var stop_distance: float = 2.3
## >0 backs away once the player is closer than this (kiting).
@export var retreat_distance: float = 0.0
## Tuned to clear the Vault's gap (3m) + platform rise (1.2m) at this
## archetype's move_speed - HeavyHitter (1.8 move_speed) still can't
## make it, correctly walled off by its own slowness.
@export var jump_velocity: float = 7.0
## Invented, scaled by archetype toughness.
@export var xp_reward: float = 10.0
@export var gold_reward: int = 5

const TELEGRAPH_COLOR := Color(1.0, 0.95, 0.2)

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
const STATUS_EFFECT_IDS := ["ignite", "chill", "freeze", "electrocute", "unraveling"]

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _base_color: Color = Color.WHITE
var _player: Player
var _gap_jumping: bool = false
var _riposte_indicator: MeshInstance3D
var _riposte_blink_tween: Tween
var _status_icons: Dictionary = {}  # effect_id -> MeshInstance3D

func _ready() -> void:
	health.died.connect(_on_died)
	add_to_group("enemy")
	_player = get_tree().get_first_node_in_group("player") as Player
	_build_riposte_indicator()
	_build_status_icons()
	composure.broken_state_started.connect(_on_broken_state_started)
	composure.broken_state_ended.connect(_on_broken_state_ended)
	status_effects.effect_applied.connect(_on_status_effect_changed)
	status_effects.effect_expired.connect(_on_status_effect_changed)
	# Deferred so archetype subclasses' own health.max_health (set after
	# super._ready()) isn't overwritten by this.
	call_deferred("_apply_map_modifiers")

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
const TIER_HEALTH_GROWTH_PER_TIER := 0.15
const TIER_DAMAGE_GROWTH_PER_TIER := 0.10
const TIER_REWARD_GROWTH_PER_TIER := 0.20

func _apply_map_modifiers() -> void:
	if GameState.active_map == null:
		return
	var tier_bonus := 1.0 + (GameState.active_map.tier - 1) * TIER_REWARD_GROWTH_PER_TIER
	health.max_health *= GameState.active_map.enemy_health_multiplier * (1.0 + (GameState.active_map.tier - 1) * TIER_HEALTH_GROWTH_PER_TIER)
	health.current_health = health.max_health
	xp_reward *= tier_bonus
	gold_reward = int(gold_reward * tier_bonus)

func get_outgoing_damage_multiplier() -> float:
	if GameState.active_map == null:
		return 1.0
	return GameState.active_map.enemy_damage_multiplier * (1.0 + (GameState.active_map.tier - 1) * TIER_DAMAGE_GROWTH_PER_TIER)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_chase()
	move_and_slide()

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

	if dist > chase_range or dist < 0.001:
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
## Section 20: Brands "dropped as loot only" - same flat, independent
## treatment as Tomes. Stones/Shard are rarer (one flat roll picks
## between the 3, not 3 independent rolls).
const BRAND_DROP_CHANCE := 0.12
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
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.experience:
		player.experience.add_xp(xp_reward)
	if player and player.ward:
		player.ward.restore_on_kill()  # Patch v3.2: "On kill: 5% Ward Restoration baseline"
	_drop_gold()
	_maybe_drop_loot()
	queue_free()

func _drop_gold() -> void:
	if gold_reward <= 0:
		return
	var pickup: GoldPickup = GOLD_PICKUP_SCENE.instantiate()
	pickup.amount = gold_reward
	get_parent().add_child(pickup)
	pickup.global_position = global_position + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3))

func _maybe_drop_loot() -> void:
	if randf() <= TOME_DROP_CHANCE:
		var tome := TomeRoller.roll_for_unowned(GameState.owned_ability_ids)
		if tome:
			_spawn_pickup(tome)
			return  # one drop max per kill

	if randf() <= BRAND_DROP_CHANCE:
		var brand := BrandRoller.roll()
		if brand:
			_spawn_pickup(brand)
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

	var quantity_mult: float = GameState.active_map.loot_quantity_multiplier if GameState.active_map else 1.0
	if randf() > BASE_LOOT_DROP_CHANCE * quantity_mult:
		return
	var rarity_mult: float = GameState.active_map.loot_rarity_multiplier if GameState.active_map else 1.0
	var power_level: int = GameState.active_map.tier if GameState.active_map else 1
	var item := ItemRoller.roll(power_level, rarity_mult)
	if item == null:
		return
	_spawn_pickup(item)

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
func take_damage(amount: float, damage_type: Constants.DamageType, is_spell: bool = false) -> void:
	var multiplier := composure.get_damage_multiplier(is_spell) if composure else 1.0
	var status_multiplier := status_effects.get_damage_taken_multiplier(damage_type) if status_effects else 1.0
	var mitigated := amount * multiplier * status_multiplier
	var category = Constants.DAMAGE_TYPE_CATEGORY.get(damage_type)
	if status_effects and (category == Constants.DamageCategory.ELEMENTAL or category == Constants.DamageCategory.ESOTERIC):
		var shred := status_effects.get_resistance_shred()
		if shred > 0.0:
			mitigated *= (1.0 - DamageCalculator.resistance_mitigation(-shred))
	health.apply_damage(mitigated)

func _set_placeholder_color(c: Color) -> void:
	_base_color = c
	_apply_mesh_color(c)

func begin_attack_telegraph() -> void:
	_apply_mesh_color(TELEGRAPH_COLOR)

## progress: 0.0 (just telegraphed) -> 1.0 (about to strike).
func update_attack_telegraph(progress: float) -> void:
	_apply_mesh_color(TELEGRAPH_COLOR.lerp(_base_color, clamp(progress, 0.0, 1.0)))

func end_attack_telegraph() -> void:
	_apply_mesh_color(_base_color)

func _apply_mesh_color(c: Color) -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mesh.set_surface_override_material(0, mat)
