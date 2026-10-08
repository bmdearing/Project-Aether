extends Node
class_name PlayerAbilityCast
## Casts the equipped abilities on ability_1..4 input, checking Mana and
## cooldowns.
##
## Most abilities cast instantly at the player's position. Ground-targeted
## ones enter hold-to-aim: holding shows a reticle at the camera raycast hit,
## releasing casts there. Only one targeting session at a time.
##
## The default cast damages every enemy in radius and applies the ability's
## statuses; abilities with bespoke mechanics branch off early in _cast().

const RANGE_EFFECT_SCENE := preload("res://entities/effects/ability_range_effect/AbilityRangeEffect.tscn")
const MAX_TARGET_RANGE := 30.0
const RETICLE_HEIGHT_OFFSET := 0.05
const FLAME_WALL_RETICLE_HEIGHT := 0.05  # flat ground-plan slab, not the real wall's WALL_HEIGHT

## Abilities with a bespoke cast VFX instead of the generic ring. Meteor
## reuses Comet's impact scene.
const SPECIAL_EFFECT_SCENES := {
	"comet": preload("res://entities/effects/comet_impact/CometImpact.tscn"),
	"meteor": preload("res://entities/effects/comet_impact/CometImpact.tscn"),
	"inferno": preload("res://entities/effects/inferno_pillar/InfernoPillar.tscn"),
	"stormcall": preload("res://entities/effects/stormcall_bolt/StormcallBolt.tscn"),
	"black_hole": preload("res://entities/effects/black_hole_field/BlackHoleField.tscn"),
	"caltrops": preload("res://entities/effects/caltrops_field/CaltropsField.tscn"),
	"flame_wall": preload("res://entities/effects/flame_wall_field/FlameWallField.tscn"),
	"winters_eye": preload("res://entities/effects/winters_eye_orb/WintersEyeOrb.tscn"),
	"tornado": preload("res://entities/effects/tornado_field/TornadoField.tscn"),
}

## Spark: ground crawlers spawned by _fire_spark().
const SPARK_CRAWLER_SCENE := preload("res://entities/effects/spark_crawler/SparkCrawler.tscn")
const SPARK_COUNT := 3
const SPARK_SPREAD_DEG := 25.0


const BLINK_DISTANCE := 8.0
const PIERCING_BOLT_SCENE := preload("res://entities/effects/piercing_bolt/PiercingBolt.tscn")
## Fired as a piercing bolt from the crosshair.
const PIERCING_BOLT_ABILITY_IDS := ["cinder_lance", "thunder_javelin"]
const THUNDER_SWEEP_BOLT_COUNT := 8
const BOLT_SPEEDS := {"cinder_lance": 22.0, "thunder_javelin": 42.0, "thunder_sweep": 18.0}

## Frost Armor: a self-buff; while active, enemy melee hits call
## trigger_frost_armor_retaliation() (from EnemyMeleeAttack._resolve_hit()).
const FROST_ARMOR_DURATION := 8.0

const FROST_ARMOR_BURST_COOLDOWN := 0.5  # a pack hitting at once triggers one burst, not one each
const FROST_SHARD_COUNT := 6
const FROST_SHARD_SPIN := 1.6

var _frost_armor_ability: Ability = null
var _frost_armor_remaining: float = 0.0
var _frost_armor_burst_cd: float = 0.0
var _frost_armor_fx: Node3D

## Flame Jets: a hold-to-channel cone that follows the camera each tick and
## slows the player (Player reads get_move_speed_multiplier()). The cost is
## paid on press, then Mana drains continuously; the channel ends when the
## key is released or Mana hits 0.
const FLAME_JETS_DURATION := 1.8  # auto-cast (Slate) length
const FLAME_JETS_MANUAL_CAP := 600.0
const FLAME_JETS_TICK_INTERVAL := 0.15
const FLAME_JETS_TICK_DAMAGE_PERCENT := 0.25
const FLAME_JETS_RANGE := 6.0
const FLAME_JETS_HALF_ANGLE_DEG := 20.0
const FLAME_JETS_MOVE_SPEED_MULTIPLIER := 0.4
const CHANNEL_MANA_DRAIN_INTERVAL := 0.15
const CHANNEL_MANA_DRAIN_PERCENT := 0.2

var _flame_jets_ability: Ability = null
var _flame_jets_remaining: float = 0.0
var _flame_jets_tick_timer: float = 0.0
var _flame_jets_drain_timer: float = 0.0
var _flame_jets_input_action: String = ""
## False for a Slate auto-cast: no key to hold and no Mana drain.
var _flame_jets_is_manual: bool = false
var _flame_jets_fx: CPUParticles3D

var _cooldowns: Dictionary = {}  # Ability -> float seconds remaining
## Spells have no cooldowns, so this short shared recovery (Ability.
## base_recovery_time, scaled by cast speed) is the only gap between casts.
var _cast_lockout: float = 0.0
var _player: Player
var _targeting_slot: int = -1
var _targeting_from_page: bool = false
## Cast copy -> {"copies", "ward_restore"} until CastTimeHandler fires it (CasterStance).
var _cast_plans: Dictionary = {}
## Unleash: yaw offset (degrees) for the copy being cast right now.
var _aim_yaw_offset: float = 0.0
var _reticle: MeshInstance3D
## ability_id -> Ability, lazily scanned from data/abilities/instances/ for
## Slate-designated abilities that may not be on the bar.
var _ability_by_id_cache: Dictionary = {}

func _ready() -> void:
	_player = get_parent()

func _physics_process(delta: float) -> void:
	if _flame_jets_fx:
		_flame_jets_fx.emitting = _flame_jets_remaining > 0.0
	for ability in _cooldowns.keys():
		_cooldowns[ability] = max(0.0, _cooldowns[ability] - delta)
	_cast_lockout = maxf(0.0, _cast_lockout - delta)
	if _frost_armor_remaining > 0.0:
		_frost_armor_remaining = max(0.0, _frost_armor_remaining - delta)
	_frost_armor_burst_cd = maxf(0.0, _frost_armor_burst_cd - delta)
	if is_instance_valid(_frost_armor_fx):
		if _frost_armor_remaining > 0.0:
			_frost_armor_fx.rotate_y(FROST_SHARD_SPIN * delta)
		else:
			_frost_armor_fx.queue_free()
	if _flame_jets_remaining > 0.0:
		if _flame_jets_is_manual and (not Input.is_action_pressed(_flame_jets_input_action) or _player.mana.current_mana <= 0.0):
			_flame_jets_remaining = 0.0
		else:
			_flame_jets_remaining = max(0.0, _flame_jets_remaining - delta)
			_flame_jets_tick_timer -= delta
			if _flame_jets_tick_timer <= 0.0:
				_flame_jets_tick_timer += FLAME_JETS_TICK_INTERVAL
				_tick_flame_jets()
			if _flame_jets_is_manual:
				_flame_jets_drain_timer -= delta
				if _flame_jets_drain_timer <= 0.0:
					_flame_jets_drain_timer += CHANNEL_MANA_DRAIN_INTERVAL
					_player.mana.spend(_flame_jets_ability.get_mana_cost(_player.stat_sheet) * CHANNEL_MANA_DRAIN_PERCENT)
					if _player.mana.current_mana <= 0.0:
						_flame_jets_remaining = 0.0

	for i in range(AbilityLoadoutComponent.SLOT_COUNT):
		var action := "ability_%d" % (i + 1)
		if Input.is_action_just_pressed(action) and not _player.is_input_blocked():
			_on_ability_pressed(i)
		elif i == _targeting_slot and Input.is_action_just_released(action):
			_release_targeted_cast()

	if _targeting_slot != -1:
		_update_reticle()

	_process_slate_autocasts()

## What key slot_index casts right now: the stance page while a Spell
## Library stance is held, the bar otherwise.
func get_bar_ability(slot_index: int) -> Ability:
	if _player.caster_stance and _player.caster_stance.uses_spell_page():
		return _player.ability_loadout.get_page2(slot_index)
	return _player.ability_loadout.get_equipped(slot_index)

func _slot_ability(slot_index: int, from_page: bool) -> Ability:
	return _player.ability_loadout.get_page2(slot_index) if from_page else _player.ability_loadout.get_equipped(slot_index)

func get_cooldown_remaining(ability: Ability) -> float:
	return _cooldowns.get(ability, 0.0) if ability else 0.0

func _on_ability_pressed(slot_index: int) -> void:
	var from_page := _player.caster_stance.uses_spell_page()
	var ability: Ability = _slot_ability(slot_index, from_page)
	if ability == null:
		return
	if ability.is_ground_targeted:
		if _targeting_slot != -1:
			return
		_targeting_slot = slot_index
		_targeting_from_page = from_page
		_show_reticle(ability)
	else:
		_try_cast(slot_index, _player.global_position, from_page)

func _release_targeted_cast() -> void:
	var slot_index := _targeting_slot
	_targeting_slot = -1
	_hide_reticle()
	_try_cast(slot_index, _get_ground_target_point(), _targeting_from_page)

## Mana/cooldown are checked on release, not when targeting starts.
func _try_cast(slot_index: int, cast_position: Vector3, from_page: bool = false) -> void:
	var ability: Ability = _slot_ability(slot_index, from_page)
	if ability == null:
		return
	var plan := _player.caster_stance.prepare_cast(ability, from_page)
	if plan.has("error"):
		EventBus.ability_cast_failed.emit(_player, ability, plan["error"])
		return
	var copies: int = plan["copies"]
	if _cast_lockout > 0.0:
		return
	if get_cooldown_remaining(ability) > 0.0:
		EventBus.ability_cast_failed.emit(_player, ability, "On cooldown")
		return
	if _player.mana.current_mana < ability.get_mana_cost(_player.stat_sheet) * copies:
		EventBus.ability_cast_failed.emit(_player, ability, "Not enough Mana")
		return
	# Checked before spending, since CastTimeHandler refuses mid-windup.
	if _player.cast_time_handler.is_casting():
		EventBus.ability_cast_failed.emit(_player, ability, "Already casting")
		return
	_player.mana.spend(ability.get_mana_cost(_player.stat_sheet) * copies)
	_cast_lockout = ability.base_recovery_time / maxf(_player.get_action_speed_multiplier(), 0.01)
	if ability.ability_id == "flame_jets":
		_flame_jets_input_action = "ability_%d" % (slot_index + 1)
		_flame_jets_is_manual = true
	_cooldowns[ability] = ability.get_final_cooldown(_player.get_action_speed_multiplier(), _player.stat_sheet)
	# CastTimeHandler calls _on_cast_time_completed() immediately for
	# INSTANT/CHANNELED, or after the windup for CAST_TIME.
	var cast: Ability = plan["ability"]
	if cast != ability:
		_cast_plans[cast] = plan
	_player.cast_time_handler.try_cast(cast, cast_position)

func _on_cast_time_completed(ability: Ability, cast_position: Vector3) -> void:
	var plan: Dictionary = _cast_plans.get(ability, {})
	_cast_plans.erase(ability)
	if plan.get("ward_restore", false):
		_player.caster_stance.restore_ward_for_cast()
	var copies: int = plan.get("copies", 1)
	if copies <= 1:
		_cast(ability, cast_position)
		return
	# Unleash: aimed copies fan out, targeted copies line up across the target.
	var right := _player.camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	for i in copies:
		var offset := _player.caster_stance.unleash_offset(i, copies)
		_aim_yaw_offset = -offset * CasterStance.UNLEASH_SPREAD_DEG
		_cast(ability, cast_position + right * offset * CasterStance.UNLEASH_TARGET_SPACING)
	_aim_yaw_offset = 0.0

## damage_multiplier/apply_composure are only non-default for Slate auto-casts.
func _cast(ability: Ability, cast_position: Vector3, damage_multiplier: float = 1.0, apply_composure: bool = true) -> void:
	if ability.ability_id == "blink":
		_flash_ring(_player.global_position, 1.4, ability)
		_perform_blink()
		_flash_ring(_player.global_position, 1.4, ability)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.has_tag(Ability.TAG_WARCRY):
		_warcry(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "purge":
		_player.status_effects.clear_all_effects()
		_flash_ring(_player.global_position, 3.0, ability, Color(0.85, 0.95, 1.0))
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "frost_armor":
		_frost_armor_ability = ability
		_frost_armor_remaining = FROST_ARMOR_DURATION * ability.get_duration_multiplier(_player.stat_sheet)
		_ensure_frost_armor_fx()
		_flash_ring(_player.global_position, 1.4, ability)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "flame_jets":
		_flame_jets_ability = ability
		# A held cast channels until the key is released or Mana runs out.
		_flame_jets_remaining = FLAME_JETS_MANUAL_CAP if _flame_jets_is_manual else FLAME_JETS_DURATION
		_flame_jets_tick_timer = 0.0  # ticks on the very next physics frame, not after a full interval's delay
		_flame_jets_drain_timer = CHANNEL_MANA_DRAIN_INTERVAL
		_ensure_flame_jets_fx()
		_flame_jets_fx.emitting = true
		EventBus.ability_cast.emit(_player, ability)
		return
	# Field abilities: all damage comes from the effect scene's own ticks.
	if ability.ability_id == "black_hole":
		_play_range_effect(ability, cast_position)
		EventBus.ability_cast.emit(_player, ability)
		return
	if PIERCING_BOLT_ABILITY_IDS.has(ability.ability_id):
		_fire_piercing_bolt(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "thunder_sweep":
		_fire_radiating_bolts(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "flame_wall":
		_play_range_effect(ability, cast_position)
		EventBus.ability_cast.emit(_player, ability)
		return
	# The orb spawns at the player and travels toward cast_position.
	if ability.ability_id == "winters_eye":
		_fire_winters_eye(ability, cast_position)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "spark":
		_fire_spark(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "tornado":
		_play_range_effect(ability, cast_position)
		EventBus.ability_cast.emit(_player, ability)
		return

	# Comet/Meteor: damage lands with the falling mass, not on cast.
	if IMPACT_ABILITY_IDS.has(ability.ability_id):
		var impact := _play_range_effect(ability, cast_position)
		var radius := ability.get_radius(_player.stat_sheet)
		impact.connect("impacted", _damage_area.bind(ability, cast_position, radius, damage_multiplier, apply_composure, 0.0, Callable()))
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "stormcall":
		_cast_stormcall(ability, cast_position, damage_multiplier, apply_composure)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "static_discharge":
		_cast_static_discharge(ability, cast_position, damage_multiplier, apply_composure)
		EventBus.ability_cast.emit(_player, ability)
		return

	# Ice Pulse / Entropic Decay radiate outward: hits ride the expanding ring.
	var wave := WAVE_DURATION if WAVE_ABILITY_IDS.has(ability.ability_id) else 0.0
	_damage_area(ability, cast_position, ability.get_radius(_player.stat_sheet), damage_multiplier, apply_composure, wave, Callable())
	_play_range_effect(ability, cast_position)
	EventBus.ability_cast.emit(_player, ability)

const IMPACT_ABILITY_IDS := ["comet", "meteor"]
const WAVE_ABILITY_IDS := ["ice_pulse", "static_discharge", "entropic_decay"]
const WAVE_DURATION := 0.35  # AbilityRangeEffect's ring expands over the same time
const COMET_CHILLED_BONUS := 2.5  # "massively increased damage against Chilled or Frozen"
## Stormcall: full damage in the strike's core, then forks arc out to the
## nearest enemies in range - one more fork per enemy caught in the core.
const STORMCALL_CORE_RADIUS := 2.5
const STORMCALL_BASE_FORKS := 2
const STORMCALL_FORK_DAMAGE := 0.6
## Static Discharge: each enemy the discharge hits arcs on to the nearest
## enemy outside the burst within this range.
const STATIC_CHAIN_RANGE := 5.5
const STATIC_CHAIN_DAMAGE := 0.5
const ARC_HEIGHT := 1.0

## Hits every enemy within radius of centre. wave > 0 delays each hit by its
## distance so damage rides an expanding ring. on_hit(enemy) runs per hit.
func _damage_area(ability: Ability, centre: Vector3, radius: float, damage_multiplier: float, apply_composure: bool, wave: float, on_hit: Callable) -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null:
			continue
		var dist := enemy.distance_to_body(centre)
		if dist > radius:
			continue
		if wave > 0.0:
			get_tree().create_timer(wave * dist / maxf(radius, 0.01), false).timeout.connect(
				_hit_enemy.bind(ability, enemy, damage_multiplier, apply_composure, on_hit))
		else:
			_hit_enemy(ability, enemy, damage_multiplier, apply_composure, on_hit)

func _hit_enemy(ability: Ability, enemy: Enemy, damage_multiplier: float, apply_composure: bool, on_hit: Callable) -> void:
	if not is_instance_valid(enemy) or not enemy.health.is_alive():
		return
	var hit := ability.roll_damage(_player.stat_sheet)
	var damage: float = hit["final_damage"] * damage_multiplier
	if ability.ability_id == "comet" and (enemy.status_effects.has_effect("chill") or enemy.status_effects.has_effect("freeze")):
		damage *= COMET_CHILLED_BONUS
	enemy.take_damage(damage, ability.damage_type)
	if apply_composure and enemy.stance:
		enemy.stance.apply_attack_stance_damage(damage, ability.damage_type)
	EventBus.damage_dealt.emit(_player, enemy, damage, ability.damage_type, false, hit["is_critical"])
	ability.apply_statuses(enemy, _player, damage)
	if on_hit.is_valid():
		on_hit.call(enemy)

func _enemies_by_distance(centre: Vector3, max_dist: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy and enemy.health.is_alive() and enemy.distance_to_body(centre) <= max_dist:
			result.append(enemy)
	result.sort_custom(func(a: Enemy, b: Enemy): return centre.distance_to(a.global_position) < centre.distance_to(b.global_position))
	return result

func _cast_stormcall(ability: Ability, centre: Vector3, damage_multiplier: float, apply_composure: bool) -> void:
	_play_range_effect(ability, centre)
	var radius := ability.get_radius(_player.stat_sheet)
	var core: Array[Enemy] = []
	var outer: Array[Enemy] = []
	for enemy in _enemies_by_distance(centre, radius):
		if enemy.distance_to_body(centre) <= STORMCALL_CORE_RADIUS:
			core.append(enemy)
		else:
			outer.append(enemy)
	for enemy in core:
		_hit_enemy(ability, enemy, damage_multiplier, apply_composure, Callable())
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	var scene := _player.get_tree().current_scene
	for enemy in outer.slice(0, STORMCALL_BASE_FORKS + core.size()):
		LightningArc.spawn(scene, centre + Vector3.UP * 0.3, enemy.global_position + Vector3.UP * ARC_HEIGHT, color)
		_hit_enemy(ability, enemy, damage_multiplier * STORMCALL_FORK_DAMAGE, apply_composure, Callable())

func _cast_static_discharge(ability: Ability, centre: Vector3, damage_multiplier: float, apply_composure: bool) -> void:
	var radius := ability.get_radius(_player.stat_sheet)
	var chained := {}
	for enemy in _enemies_by_distance(centre, radius):
		chained[enemy.get_instance_id()] = true
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	var scene := _player.get_tree().current_scene
	var arc_on := func(from_enemy: Enemy) -> void:
		LightningArc.spawn(scene, centre + Vector3.UP * ARC_HEIGHT, from_enemy.global_position + Vector3.UP * ARC_HEIGHT, color)
		for next in _enemies_by_distance(from_enemy.global_position, STATIC_CHAIN_RANGE):
			if chained.has(next.get_instance_id()):
				continue
			chained[next.get_instance_id()] = true
			LightningArc.spawn(scene, from_enemy.global_position + Vector3.UP * ARC_HEIGHT, next.global_position + Vector3.UP * ARC_HEIGHT, color)
			_hit_enemy(ability, next, damage_multiplier * STATIC_CHAIN_DAMAGE, apply_composure, Callable())
			break
	_damage_area(ability, centre, radius, damage_multiplier, apply_composure, WAVE_DURATION, arc_on)
	_play_range_effect(ability, centre)

## Expanding ring with no damage - Blink/Purge feedback.
func _flash_ring(pos: Vector3, radius: float, ability: Ability, color: Color = Color(0, 0, 0, 0)) -> void:
	var ring: AbilityRangeEffect = RANGE_EFFECT_SCENE.instantiate()
	_player.get_tree().current_scene.add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.05
	ring.play(radius, color if color.a > 0.0 else Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE))

## Auto-casts spells designated on Slates with auto_cast_designated_spell
## (The Unbound Chorus) whenever they're off cooldown.
func _process_slate_autocasts() -> void:
	if _player.fate_board == null:
		return
	for placement_id in _player.fate_board.placements:
		var data: FateBoard.PlacedSlateData = _player.fate_board.placements[placement_id]
		if data.designated_ability_id == "" or not _has_modifier(data.slate, "auto_cast_designated_spell"):
			continue
		var ability := _resolve_ability_by_id(data.designated_ability_id)
		if ability == null or get_cooldown_remaining(ability) > 0.0:
			continue
		_auto_cast(ability, data.slate)

## Auto-casts cost no Mana, deal auto_cast_damage_percent damage and skip
## Composure damage. Spells have no cooldown, so this paces them.
const AUTO_CAST_MIN_INTERVAL := 2.0

func _auto_cast(ability: Ability, slate: Slate) -> void:
	_cooldowns[ability] = maxf(ability.get_final_cooldown(_player.get_action_speed_multiplier(), _player.stat_sheet), AUTO_CAST_MIN_INTERVAL)
	if ability.ability_id == "flame_jets":
		_flame_jets_is_manual = false
	var damage_percent := _modifier_value(slate, "auto_cast_damage_percent", 100.0)
	_cast(ability, _player.global_position, damage_percent / 100.0, false)

func _has_modifier(slate: Slate, stat_key: String) -> bool:
	for m in slate.modifiers:
		if m.stat_key == stat_key:
			return true
	return false

func _modifier_value(slate: Slate, stat_key: String, fallback: float) -> float:
	for m in slate.modifiers:
		if m.stat_key == stat_key:
			return m.value
	return fallback

func _resolve_ability_by_id(ability_id: String) -> Ability:
	if _ability_by_id_cache.is_empty():
		var dir := DirAccess.open("res://data/abilities/instances/")
		if dir:
			dir.list_dir_begin()
			var file_name := dir.get_next().trim_suffix(".remap")
			while file_name != "":
				if file_name.ends_with(".tres"):
					var ability: Ability = load("res://data/abilities/instances/" + file_name) as Ability
					if ability:
						_ability_by_id_cache[ability.ability_id] = ability
				file_name = dir.get_next().trim_suffix(".remap")
			dir.list_dir_end()
	return _ability_by_id_cache.get(ability_id)

func _limit_group(ability: Ability) -> StringName:
	return StringName("spell_limit_" + ability.ability_id)

## At the limit, the oldest instance makes way for the new one.
func _make_room_for(ability: Ability, limit: int) -> void:
	var live: Array[Node] = []
	for node in get_tree().get_nodes_in_group(_limit_group(ability)):
		if not node.is_queued_for_deletion():
			live.append(node)
	while live.size() >= limit:
		var oldest: Node = live.pop_front()
		oldest.remove_from_group(_limit_group(ability))
		oldest.queue_free()

func _play_range_effect(ability: Ability, cast_position: Vector3) -> Node3D:
	var scene: PackedScene = SPECIAL_EFFECT_SCENES.get(ability.ability_id, RANGE_EFFECT_SCENE)
	var limit := ability.get_limit(_player.stat_sheet) if ability.has_tag(Ability.TAG_LIMIT) else 0
	if limit > 0:
		_make_room_for(ability, limit)
	var effect: Node3D = scene.instantiate()
	_player.get_tree().current_scene.add_child(effect)
	if limit > 0:
		effect.add_to_group(_limit_group(ability))
	effect.global_position = cast_position
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	if ability.ability_id == "flame_wall":
		# The caster position orients the wall.
		effect.call("play", ability.get_radius(_player.stat_sheet), color, ability, _player.stat_sheet, _player, _player.global_position)
	elif ability.ability_id == "caltrops" or ability.ability_id == "black_hole" or ability.ability_id == "tornado":
		# Field scenes roll their own damage per tick.
		effect.call("play", ability.get_radius(_player.stat_sheet), color, ability, _player.stat_sheet, _player)
	else:
		effect.call("play", ability.get_radius(_player.stat_sheet), color)
	return effect

func get_move_speed_multiplier() -> float:
	return FLAME_JETS_MOVE_SPEED_MULTIPLIER if _flame_jets_remaining > 0.0 else 1.0

## Cone check against the camera's current forward direction.
func _tick_flame_jets() -> void:
	var origin := _player.camera.global_position
	var forward := -_player.camera.global_transform.basis.z
	var cos_half_angle := cos(deg_to_rad(FLAME_JETS_HALF_ANGLE_DEG))
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		var to_enemy: Vector3 = enemy.global_position + Vector3.UP * minf(enemy.body_height * 0.5, 1.0) - origin
		var dist := to_enemy.length()
		if dist - enemy.body_radius > FLAME_JETS_RANGE or dist < 0.01:
			continue
		if to_enemy.normalized().dot(forward) < cos_half_angle:
			continue
		if _line_blocked(origin, enemy.global_position + Vector3.UP):
			continue
		var hit := _flame_jets_ability.roll_damage(_player.stat_sheet)
		var damage: float = hit["final_damage"] * FLAME_JETS_TICK_DAMAGE_PERCENT
		enemy.take_damage(damage, _flame_jets_ability.damage_type)
		if enemy.stance:
			enemy.stance.apply_attack_stance_damage(damage, _flame_jets_ability.damage_type)
		EventBus.damage_dealt.emit(_player, enemy, damage, _flame_jets_ability.damage_type, false, hit["is_critical"])
		_flame_jets_ability.apply_statuses(enemy, _player, damage)

## The flame stream: soft additive puffs from just below the view, out along
## the aim for FLAME_JETS_RANGE, growing and cooling from white-yellow to red.
func _ensure_flame_jets_fx() -> void:
	if is_instance_valid(_flame_jets_fx):
		return
	var p := CPUParticles3D.new()
	p.amount = 160
	p.lifetime = 0.42
	p.local_coords = false
	p.emitting = false
	p.position = Vector3(0.12, -0.28, -0.6)
	p.direction = Vector3(0, 0, -1)
	p.spread = 8.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = FLAME_JETS_RANGE / 0.42 * 0.85
	p.initial_velocity_max = FLAME_JETS_RANGE / 0.42 * 1.05
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.angle_max = 180.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.9
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.15))
	curve.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.7, 0.9))
	ramp.add_point(0.3, Color(1.0, 0.55, 0.12, 0.85))
	ramp.add_point(0.7, Color(0.75, 0.15, 0.05, 0.45))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.2, 0.05, 0.02, 0.0))
	p.color_ramp = ramp
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = soft
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.6, 1.3, 1.1)
	var quad := QuadMesh.new()
	quad.material = mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player.camera.add_child(p)
	_flame_jets_fx = p

func _line_blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] is StaticBody3D

## Ice shards circling the player at waist height while Frost Armor holds -
## they pass through the bottom of the first-person view.
func _ensure_frost_armor_fx() -> void:
	if is_instance_valid(_frost_armor_fx):
		return
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.6, 0.85, 1.0, 0.7)
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.34, 0.05)
	box.material = mat
	for i in FROST_SHARD_COUNT:
		var a := TAU * i / FROST_SHARD_COUNT
		var shard := MeshInstance3D.new()
		shard.mesh = box
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.position = Vector3(cos(a), 0.85 + 0.2 * sin(a * 2.0), sin(a)) * Vector3(1.05, 1.0, 1.05)
		shard.rotation = Vector3(0.35, -a, 0.3)
		root.add_child(shard)
	_player.add_child(root)
	_frost_armor_fx = root

func has_frost_armor() -> bool:
	return _frost_armor_remaining > 0.0

## Called when an enemy melee hit lands on the player.
func trigger_frost_armor_retaliation(attacker: Enemy) -> void:
	if not has_frost_armor() or _frost_armor_ability == null or attacker == null or _frost_armor_burst_cd > 0.0:
		return
	_frost_armor_burst_cd = FROST_ARMOR_BURST_COOLDOWN
	var mult := 1.0 + _player.stat_sheet.get_misc_bonus("increased_retaliation_damage") / 100.0
	# The burst hits everything within the ability's radius, and always the attacker.
	var centre := _player.global_position
	var radius := _frost_armor_ability.get_radius(_player.stat_sheet)
	_damage_area(_frost_armor_ability, centre, radius, mult, true, 0.0, Callable())
	if centre.distance_to(attacker.global_position) > radius:
		_hit_enemy(_frost_armor_ability, attacker, mult, true, Callable())
	_flash_ring(centre, radius, _frost_armor_ability)

func _fire_piercing_bolt(ability: Ability, damage_multiplier: float) -> void:
	var xform := _player.camera.global_transform
	xform.basis = Basis(Vector3.UP, deg_to_rad(_aim_yaw_offset)) * xform.basis
	_spawn_bolt(ability, damage_multiplier, xform)

## Ground bolts in a full horizontal circle around the player.
func _fire_radiating_bolts(ability: Ability, damage_multiplier: float) -> void:
	var origin := _player.global_position + Vector3(0, 0.3, 0)
	for i in range(THUNDER_SWEEP_BOLT_COUNT):
		var angle := TAU * i / float(THUNDER_SWEEP_BOLT_COUNT)
		var xform := Transform3D(Basis(Vector3.UP, angle), origin)
		_spawn_bolt(ability, damage_multiplier, xform)

## SPARK_COUNT crawlers fanned out ahead of the caster; each seeks on its own.
func _fire_spark(ability: Ability, damage_multiplier: float) -> void:
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = -_player.global_transform.basis.z
	forward = forward.normalized().rotated(Vector3.UP, deg_to_rad(_aim_yaw_offset))
	var origin := _player.global_position + forward * 0.5
	for i in range(SPARK_COUNT):
		var offset_deg := SPARK_SPREAD_DEG * (i - (SPARK_COUNT - 1) / 2.0)
		var heading: Vector3 = forward.rotated(Vector3.UP, deg_to_rad(offset_deg))
		var crawler: SparkCrawler = SPARK_CRAWLER_SCENE.instantiate()
		crawler.heading = heading
		crawler.ability = ability
		crawler.stat_sheet = _player.stat_sheet
		crawler.source = _player
		crawler.damage_multiplier = damage_multiplier
		_player.get_tree().current_scene.add_child(crawler)
		crawler.global_position = origin

func _fire_winters_eye(ability: Ability, target: Vector3) -> void:
	var orb: Node3D = SPECIAL_EFFECT_SCENES["winters_eye"].instantiate()
	_player.get_tree().current_scene.add_child(orb)
	orb.global_position = _player.global_position + Vector3(0, 1.0, 0)
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	orb.call("play", ability.get_radius(_player.stat_sheet), color, ability, _player.stat_sheet, _player, target)

func _spawn_bolt(ability: Ability, damage_multiplier: float, xform: Transform3D) -> void:
	var bolt: PiercingBolt = PIERCING_BOLT_SCENE.instantiate()
	var hit := ability.roll_damage(_player.stat_sheet)
	bolt.damage_amount = hit["final_damage"] * damage_multiplier
	bolt.is_critical = hit["is_critical"]
	bolt.damage_type = ability.damage_type
	bolt.speed = BOLT_SPEEDS.get(ability.ability_id, bolt.speed) * ability.get_projectile_speed_multiplier(_player.stat_sheet)
	bolt.source = _player
	bolt.ability = ability
	if ability.ability_id == "thunder_sweep":
		bolt.follow_ground = true
		bolt.max_distance = ability.get_radius(_player.stat_sheet)
	# Configured before entering the tree so _ready() colours it by damage type.
	_player.get_tree().current_scene.add_child(bolt)
	bolt.global_transform = xform

## Teleports horizontally along the camera's facing, stopping short of walls.
## The ray starts at camera height: from the feet it would graze the floor
## and report a 0-distance hit.
func _perform_blink() -> void:
	var camera := _player.camera
	var ray_origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	direction.y = 0.0
	if direction.length() < 0.01:
		direction = -_player.global_transform.basis.z
	direction = direction.normalized()
	var space_state := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + direction * BLINK_DISTANCE)
	query.exclude = [_player.get_rid()]
	var result := space_state.intersect_ray(query)
	var distance: float = max(ray_origin.distance_to(result["position"]) - 0.5, 0.0) if result else BLINK_DISTANCE
	_player.global_position += direction * distance

## Crosshair raycast hit, capped at MAX_TARGET_RANGE. With no hit, falls back
## to the plane at the player's feet.
func _get_ground_target_point() -> Vector3:
	var camera := _player.camera
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var space_state := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * MAX_TARGET_RANGE)
	query.exclude = [_player.get_rid()]
	var result := space_state.intersect_ray(query)
	if result:
		return result["position"]
	if direction.y < -0.01:
		var t: float = (_player.global_position.y - origin.y) / direction.y
		return origin + direction * clamp(t, 0.0, MAX_TARGET_RANGE)
	return origin + direction * MAX_TARGET_RANGE

## A ring for most abilities; Flame Wall gets a box matching its footprint.
func _show_reticle(ability: Ability) -> void:
	if _reticle == null:
		_reticle = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_reticle.material_override = mat
		_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_player.get_tree().current_scene.add_child(_reticle)

	if ability.ability_id == "flame_wall":
		var box := BoxMesh.new()
		var half_width: float = max(ability.get_radius(_player.stat_sheet), 1.5)
		box.size = Vector3(half_width * 2.0, FLAME_WALL_RETICLE_HEIGHT, FlameWallField.WALL_THICKNESS)
		_reticle.mesh = box
	else:
		var torus := TorusMesh.new()
		torus.outer_radius = max(ability.get_radius(_player.stat_sheet), 0.2)
		torus.inner_radius = max(ability.get_radius(_player.stat_sheet) - 0.15, 0.05)
		_reticle.mesh = torus

	var mat: StandardMaterial3D = _reticle.material_override
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	color.a = 0.75
	mat.albedo_color = color
	_reticle.visible = true
	_update_reticle()

func _update_reticle() -> void:
	if _reticle == null:
		return
	var target_point := _get_ground_target_point()
	_reticle.global_position = target_point + Vector3(0, RETICLE_HEIGHT_OFFSET, 0)
	if _reticle.mesh is BoxMesh:
		# Same orientation as FlameWallField.play(): width perpendicular to the caster.
		var flat_caster_pos := Vector3(_player.global_position.x, _reticle.global_position.y, _player.global_position.z)
		if _reticle.global_position.distance_to(flat_caster_pos) > 0.01:
			_reticle.look_at(flat_caster_pos, Vector3.UP)
	else:
		_reticle.rotation = Vector3.ZERO

func _hide_reticle() -> void:
	if _reticle:
		_reticle.visible = false

## ---- Warcries ------------------------------------------------------------
## Every Warcry also fires EventBus.warcry_used, which ruptures the Greataxe's
## Earthquake fields.
const BATTLE_CRY_MORE_DAMAGE := 20.0      # % more damage, +1 per level
const BATTLE_CRY_DURATION := 6.0
const INTIMIDATE_DURATION := 6.0
const SEISMIC_CRY_KNOCKBACK := 9.0
const WARCRY_COLOR := Color(1.0, 0.75, 0.3)

func _warcry(ability: Ability, damage_multiplier: float) -> void:
	var centre := _player.global_position
	var radius := ability.get_radius(_player.stat_sheet)
	var duration_mult := ability.get_duration_multiplier(_player.stat_sheet)
	_flash_ring(centre, radius, ability, WARCRY_COLOR)
	match ability.ability_id:
		"battle_cry":
			var more := BATTLE_CRY_MORE_DAMAGE + (ability.get_effective_level(_player.stat_sheet) - 1)
			_player.unique_effects.add_timed_more(&"battle_cry", more, BATTLE_CRY_DURATION * duration_mult)
		"intimidating_shout":
			for enemy in _enemies_near(centre, radius):
				enemy.status_effects.apply_timed_effect("intimidated", INTIMIDATE_DURATION * duration_mult)
		"seismic_cry":
			_damage_area(ability, centre, radius, damage_multiplier, true, 0.0, Callable())
			for enemy in _enemies_near(centre, radius):
				var away := enemy.global_position - centre
				away.y = 0.0
				enemy.apply_knockback(away.normalized() * SEISMIC_CRY_KNOCKBACK)
	EventBus.warcry_used.emit(_player)

func _enemies_near(centre: Vector3, radius: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy and enemy.health.is_alive() and enemy.distance_to_body(centre) <= radius:
			result.append(enemy)
	return result
