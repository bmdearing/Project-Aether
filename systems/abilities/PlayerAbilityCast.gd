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

## Booming Blade: a toggle (GameState.booming_blade_on). While on, every melee
## swing (PlayerMeleeAttack._enter_strike) sends lightning along the ground
## ahead, at most once per BOOMING_BLADE_COOLDOWN, one more bolt every
## BOOMING_BLADE_LEVELS_PER_BOLT spell levels. Turning it off is free.
const BOOMING_BLADE_COOLDOWN := 0.45
const BOOMING_BLADE_LEVELS_PER_BOLT := 5
const BOOMING_BLADE_SPREAD_DEG := 7.0
## Ground bolts like Spark's crawlers, but running straight; each enemy
## takes at most one impact per BOOMING_BLADE_HIT_INTERVAL from all of them.
const BOOMING_BLADE_SPEED := 16.0
const BOOMING_BLADE_HIT_INTERVAL := 0.1
## Fan spacing for a Conduit's additional projectiles on single bolts.
const EXTRA_BOLT_SPREAD_DEG := 6.0
var _booming_blade_cd: float = 0.0

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
	_booming_blade_cd = maxf(0.0, _booming_blade_cd - delta)
	if _frost_armor_remaining > 0.0:
		_frost_armor_remaining = max(0.0, _frost_armor_remaining - delta)
		# Web: Shatter - the armour bursts around you as it ends.
		if _frost_armor_remaining == 0.0 and _frost_armor_ability and _frost_armor_ability.has_twist("frost_shatter"):
			var r := _frost_armor_ability.get_radius(_player.stat_sheet) * FROST_SHATTER_AREA
			_damage_area(_frost_armor_ability, _player.global_position, r, FROST_SHATTER_DAMAGE, true, WAVE_DURATION, Callable())
			_flash_ring(_player.global_position, r, _frost_armor_ability)
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
					var drain := 2.0 if _flame_jets_ability.has_twist("blue_flame") else 1.0  # Blue Flame burns Mana twice as fast
					_player.mana.spend(_flame_jets_ability.get_mana_cost(_player.stat_sheet) * CHANNEL_MANA_DRAIN_PERCENT * drain)
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
	if ability.ability_id == "booming_blade" and GameState.booming_blade_on:
		GameState.booming_blade_on = false
		_flash_ring(_player.global_position, 1.4, ability, Color(0.6, 0.6, 0.7))
		return
	var plan := _player.caster_stance.prepare_cast(ability, from_page)
	if plan.has("error"):
		EventBus.ability_cast_failed.emit(_player, ability, plan["error"])
		return
	var copies: int = plan["copies"]
	if _cast_lockout > 0.0:
		return
	var cursed_cost := 0.0 if from_page else _cursed_slot_cost(slot_index)
	if get_cooldown_remaining(ability) > 0.0 and cursed_cost <= 0.0:
		EventBus.ability_cast_failed.emit(_player, ability, "On cooldown")
		return
	var mana_cost := ability.get_mana_cost(_player.stat_sheet) * copies * (1.0 + cursed_cost / 100.0)
	if _player.mana.current_mana < mana_cost:
		EventBus.ability_cast_failed.emit(_player, ability, "Not enough Mana")
		return
	# Checked before spending, since CastTimeHandler refuses mid-windup.
	if _player.cast_time_handler.is_casting():
		EventBus.ability_cast_failed.emit(_player, ability, "Already casting")
		return
	_player.mana.spend(mana_cost)
	_cast_lockout = ability.base_recovery_time / maxf(_player.get_action_speed_multiplier(), 0.01)
	if ability.ability_id == "flame_jets":
		_flame_jets_input_action = "ability_%d" % (slot_index + 1)
		_flame_jets_is_manual = true
	_cooldowns[ability] = 0.0 if cursed_cost > 0.0 else ability.get_final_cooldown(_player.get_action_speed_multiplier(), _player.stat_sheet)
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
		_maybe_trigger_twice(ability, cast_position)
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
	ability = _web_variant(ability)
	_schedule_echo(ability, cast_position, damage_multiplier, apply_composure)
	_cast_resolved(ability, cast_position, damage_multiplier, apply_composure)

## Skill web echoes: twists that make a spell go off again, weaker, a moment
## later: twist -> [ability id, delays, damage share]. Echoes don't echo.
const ECHOES := {
	"thunderhead": ["stormcall", [0.5, 1.0], 0.6],
	"lingering_rot": ["entropic_decay", [1.0], 0.6],
	"aftershock": ["seismic_cry", [0.8], 0.5],
	"second_pulse": ["ice_pulse", [0.4], 0.5],
	"echo_sweep": ["thunder_sweep", [0.6], 0.7],
	"echoing_shout": ["intimidating_shout", [2.0], 1.0],
}
var _echoing := false
var _sweep_offset := 0.0

func _schedule_echo(ability: Ability, cast_position: Vector3, damage_multiplier: float, apply_composure: bool) -> void:
	if _echoing:
		return
	for twist in ECHOES:
		var e: Array = ECHOES[twist]
		if ability.ability_id != e[0] or not ability.has_twist(twist):
			continue
		if twist == "second_pulse" and ability.has_twist("shard_volley"):
			continue
		for delay in e[1]:
			get_tree().create_timer(delay, false).timeout.connect(_echo.bind(ability, cast_position, damage_multiplier * float(e[2]), apply_composure))

func _echo(ability: Ability, cast_position: Vector3, damage_multiplier: float, apply_composure: bool) -> void:
	if not is_instance_valid(_player):
		return
	_echoing = true
	# Self-centred spells go off around you again; targeted ones at the spot.
	var at := cast_position if ability.is_ground_targeted or ability.ability_id == "stormcall" else _player.global_position
	if ability.ability_id == "thunder_sweep":
		_sweep_offset = PI / THUNDER_SWEEP_BOLT_COUNT
	_cast_resolved(ability, at, damage_multiplier, apply_composure)
	_sweep_offset = 0.0
	_echoing = false

func _cast_resolved(ability: Ability, cast_position: Vector3, damage_multiplier: float = 1.0, apply_composure: bool = true) -> void:
	if ability.ability_id == "blink":
		_flash_ring(_player.global_position, 1.4, ability)
		_blink_distance = BLINK_DISTANCE * (LONG_STEP if ability.has_twist("long_step") else 1.0)
		if ability.has_twist("purging_step"):
			_player.status_effects.clear_all_effects()
		_perform_blink()
		_flash_ring(_player.global_position, 1.4, ability)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "reap":
		_reap(ability, damage_multiplier, apply_composure, 1.0)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "wraith":
		_summon_wraith(ability)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.has_tag(Ability.TAG_WARCRY):
		_warcry(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "purge":
		_player.status_effects.clear_all_effects()
		if ability.has_twist("second_wind"):
			_player.health.heal(_player.health.max_health * 0.1)
		_flash_ring(_player.global_position, 3.0, ability, Color(0.85, 0.95, 1.0))
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "booming_blade":
		GameState.booming_blade_on = true
		_flash_ring(_player.global_position, 1.4, ability)
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
		# Web: Event Horizon - it collapses at the end in an Entropic blast.
		if ability.has_twist("event_horizon"):
			var lasts := BlackHoleField.DURATION * ability.get_duration_multiplier(_player.stat_sheet)
			get_tree().create_timer(lasts, false).timeout.connect(func():
				if is_instance_valid(_player):
					var r := ability.get_radius(_player.stat_sheet)
					_damage_area(ability, cast_position, r, damage_multiplier * EVENT_HORIZON_DAMAGE, apply_composure, 0.0, Callable())
					_flash_ring(cast_position, r, ability))
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
		# Web: Twin Funnels - two smaller tornadoes, 60% damage each.
		if ability.has_twist("twin_funnels"):
			var weaker := ability.duplicate() as Ability
			weaker.web_points = ability.web_points
			weaker.extra_more = ability.extra_more * 0.6
			var right := _player.camera.global_transform.basis.x
			right.y = 0.0
			for s in [-1.0, 1.0]:
				_play_range_effect(weaker, cast_position + right.normalized() * s * 2.0)
		else:
			_play_range_effect(ability, cast_position)
		EventBus.ability_cast.emit(_player, ability)
		return

	# Comet: damage lands with the falling mass, not on cast.
	if IMPACT_ABILITY_IDS.has(ability.ability_id):
		_cast_comet(_web_variant(ability), cast_position, damage_multiplier, apply_composure)
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

	# Inferno's Firestorm: three smaller columns scattered over the area.
	if ability.ability_id == "inferno" and ability.has_twist("inferno_firestorm"):
		var r := ability.get_radius(_player.stat_sheet)
		for i in 3:
			var angle := randf() * TAU
			var spot := cast_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(0.3, 1.0) * r * 0.8
			var delay := 0.15 * i
			get_tree().create_timer(delay, false).timeout.connect(func():
				if is_instance_valid(_player):
					_damage_area(ability, spot, r * 0.5, damage_multiplier * 0.5, apply_composure, 0.0, Callable())
					var fx: Node3D = SPECIAL_EFFECT_SCENES["inferno"].instantiate()
					_player.get_tree().current_scene.add_child(fx)
					fx.global_position = spot
					fx.call("play", r * 0.5, Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)))
		EventBus.ability_cast.emit(_player, ability)
		return

	# Ice Pulse's Shard Volley: icicles instead of the pulse.
	if ability.ability_id == "ice_pulse" and ability.has_twist("shard_volley"):
		_fire_shard_volley(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return

	# Ice Pulse / Entropic Decay radiate outward: hits ride the expanding ring.
	var wave := WAVE_DURATION if WAVE_ABILITY_IDS.has(ability.ability_id) else 0.0
	_damage_area(ability, cast_position, ability.get_radius(_player.stat_sheet), damage_multiplier, apply_composure, wave, Callable())
	_play_range_effect(ability, cast_position)
	EventBus.ability_cast.emit(_player, ability)

const IMPACT_ABILITY_IDS := ["comet"]
const WAVE_ABILITY_IDS := ["ice_pulse", "static_discharge", "entropic_decay"]
const WAVE_DURATION := 0.35  # AbilityRangeEffect's ring expands over the same time
const COMET_CHILLED_BONUS := 2.5  # "massively increased damage against Chilled or Frozen"
## Skill web: Meteor Shower's three smaller comets, Heavy Mass's slower fall.
const METEOR_SHOWER_COUNT := 3
const METEOR_SHOWER_DAMAGE := 0.45
const METEOR_SHOWER_AREA := 0.6
const METEOR_SHOWER_SPREAD := 0.9  # of the full radius, from the target
const HEAVY_MASS_FALL := 1.5
const EVENT_HORIZON_DAMAGE := 3.0
## Reap: the scythe's arc, and its web twists.
const REAP_HALF_ANGLE := 55.0
const REAP_WIDE_HALF_ANGLE := 90.0
const REAP_WIDE_DAMAGE := 0.75
const REAP_SECOND_SWING_DELAY := 0.35
const REAP_SECOND_SWING_DAMAGE := 0.5
const REAP_HARVEST_LIFE := 0.01
const REAP_COLOR := Color(0.45, 0.86, 1.0, 0.7)
## Wraith: Ward consumed per stack of more damage (WraithMinion.MORE_PER_STACK).
const WRAITH_WARD_PER_STACK := 7.0
const WRAITH_FEAST_WARD_PER_STACK := 4.0

## Reap: everything in a cone ahead takes the hit. direction_sign -1 is
## Second Swing's sweep back.
func _reap(ability: Ability, damage_multiplier: float, apply_composure: bool, direction_sign: float) -> void:
	var radius := ability.get_radius(_player.stat_sheet)
	var half := REAP_WIDE_HALF_ANGLE if ability.has_twist("wide_arc") else REAP_HALF_ANGLE
	var mult := damage_multiplier * (REAP_WIDE_DAMAGE if ability.has_twist("wide_arc") else 1.0)
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else -_player.global_transform.basis.z
	var origin := _player.global_position
	var harvest := ability.has_twist("harvest")
	for enemy in _enemies_near(origin, radius):
		var to_enemy := enemy.global_position - origin
		to_enemy.y = 0.0
		if to_enemy.length() > 0.5 and rad_to_deg(forward.angle_to(to_enemy.normalized())) > half:
			continue
		_hit_enemy(ability, enemy, mult, apply_composure, Callable())
		if harvest:
			_player.health.heal(_player.health.max_health * REAP_HARVEST_LIFE)
	_reap_arc(origin, forward, radius, half, direction_sign)
	if ability.has_twist("second_swing") and direction_sign > 0.0:
		get_tree().create_timer(REAP_SECOND_SWING_DELAY, false).timeout.connect(func():
			if is_instance_valid(_player):
				_reap(ability, damage_multiplier * REAP_SECOND_SWING_DAMAGE, apply_composure, -1.0))

## The scythe's sweep: a spectral blade racing across the arc, souls of
## light shed from its edge.
func _reap_arc(origin: Vector3, forward: Vector3, radius: float, half: float, direction_sign: float) -> void:
	var scene := _player.get_tree().current_scene
	var tint := Color(REAP_COLOR.r, REAP_COLOR.g, REAP_COLOR.b)
	SpellFx.sweep(scene, origin, forward, radius, half, tint, 0.25, direction_sign, 1.2)
	SpellFx.light_pop(scene, origin + forward * radius * 0.6 + Vector3.UP, tint, 2.0, radius * 1.2, 0.3)
	var wisps := SpellFx.burst(scene, origin + forward * radius * 0.7 + Vector3.UP * 0.9, tint, 18, Vector2(0.5, 1.5), 0.7, Vector2(0.06, 0.14), 120.0, 1.5)
	wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	wisps.emission_box_extents = Vector3(radius * 0.5, 0.3, radius * 0.3)
	wisps.look_at(wisps.global_position + forward, Vector3.UP)

## Wraith: spends all Ward on the summon (more damage per Ward stack). A
## new cast replaces the last one's wraiths.
func _summon_wraith(ability: Ability) -> void:
	for old in get_tree().get_nodes_in_group("minion"):
		if old is WraithMinion and (old as WraithMinion).player == _player:
			old.queue_free()
	var ward := _player.ward.current_ward
	var per := WRAITH_FEAST_WARD_PER_STACK if ability.has_twist("ward_feast") else WRAITH_WARD_PER_STACK
	var stacks := int(ward / per)
	_player.ward.drain(ward)
	var scene := _player.get_tree().current_scene
	var right := _player.global_transform.basis.x
	if ability.has_twist("spectral_host"):
		# Two wraiths split the Ward between them.
		for s in [-1.0, 1.0]:
			WraithMinion.summon(scene, _player, ability, stacks / 2, 1.0, right * s * 1.2)
	else:
		WraithMinion.summon(scene, _player, ability, stacks, 1.0, right * 1.0)
const FROST_SHATTER_DAMAGE := 1.5
const FROST_SHATTER_AREA := 1.6
const LONG_STEP := 1.6
const SHARD_VOLLEY_BASE := 5
const SHARD_VOLLEY_SPREAD_DEG := 9.0

## A cast's copy reshaped by its web: Comet's Molten Core turns it Fire.
## Conversions: [ability, twist, new damage type or -1, statuses it adds
## (replacing the spell's own when the type changes), always land].
const VARIANTS := [
	["comet", "molten_core", Constants.DamageType.FIRE, ["ignite"], false],
	["tornado", "firestorm", Constants.DamageType.FIRE, ["ignite"], false],
	["flame_wall", "frost_wall", Constants.DamageType.COLD, ["chill"], false],
	["caltrops", "barbed", -1, ["bleed"], false],
	["inferno", "conflagration", -1, ["ignite"], true],
	["static_discharge", "grounded", -1, ["shock"], true],
	["frost_armor", "rime", -1, ["chill"], true],
]

func _web_variant(ability: Ability) -> Ability:
	return web_variant(ability)

static func web_variant(ability: Ability) -> Ability:
	if ability.web_points.is_empty():
		return ability
	for v in VARIANTS:
		if ability.ability_id == v[0] and ability.has_twist(v[1]):
			var copy := ability.duplicate() as Ability
			copy.web_points = ability.web_points
			var statuses: Array[String] = []
			if int(v[2]) >= 0:
				copy.damage_type = v[2]
			else:
				statuses.assign(copy.applies_status_effects)
			for s in v[3]:
				if not statuses.has(s):
					statuses.append(s)
			copy.applies_status_effects = statuses
			if v[4]:
				copy.guaranteed_statuses = statuses.duplicate()
			return copy
	return ability

func _cast_comet(ability: Ability, target: Vector3, damage_multiplier: float, apply_composure: bool) -> void:
	var radius := ability.get_radius(_player.stat_sheet)
	var spots: Array[Vector3] = [target]
	var mult := damage_multiplier
	if ability.has_twist("meteor_shower"):
		spots = []
		var start := randf() * TAU
		for i in METEOR_SHOWER_COUNT:
			var angle := start + TAU * i / METEOR_SHOWER_COUNT
			spots.append(target + Vector3(cos(angle), 0, sin(angle)) * radius * METEOR_SHOWER_SPREAD * 0.6)
		radius *= METEOR_SHOWER_AREA
		mult *= METEOR_SHOWER_DAMAGE
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	for i in spots.size():
		var impact: CometImpact = SPECIAL_EFFECT_SCENES["comet"].instantiate()
		if ability.has_twist("heavy_mass"):
			impact.fall_duration *= HEAVY_MASS_FALL
		_player.get_tree().current_scene.add_child(impact)
		impact.global_position = spots[i]
		impact.impacted.connect(_damage_area.bind(ability, spots[i], radius, mult, apply_composure, 0.0, Callable()))
		# Staggered a touch so a shower reads as three strikes.
		get_tree().create_timer(0.12 * i, false).timeout.connect(impact.play.bind(radius, color))

## Shard Volley: icicles fanned ahead, or Frozen Nova's full ring.
func _fire_shard_volley(ability: Ability, damage_multiplier: float) -> void:
	var count := SHARD_VOLLEY_BASE + int(ability.web_value(SkillWeb.PROJECTILES)) + _player.stat_sheet.conduit_additional_projectiles
	var origin := _player.global_position + Vector3(0, 1.0, 0)
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else -_player.global_transform.basis.z
	var yaw := atan2(-forward.x, -forward.z) + deg_to_rad(_aim_yaw_offset)
	for i in count:
		var angle := yaw + (TAU * i / float(count) if ability.has_twist("frozen_nova") else deg_to_rad(SHARD_VOLLEY_SPREAD_DEG * (i - (count - 1) / 2.0)))
		_spawn_bolt(ability, damage_multiplier, Transform3D(Basis(Vector3.UP, angle), origin))
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
	if ability.ability_id == "comet":
		# Molten Core: the bonus goes to Ignited enemies instead.
		var primed := enemy.status_effects.has_effect("ignite") if ability.has_twist("molten_core") else (enemy.status_effects.has_effect("chill") or enemy.status_effects.has_effect("freeze"))
		if primed:
			damage *= COMET_CHILLED_BONUS
	# Web: Deep Freeze - Ice Pulse freezes enemies already Chilled.
	if ability.ability_id == "ice_pulse" and ability.has_twist("deep_freeze") and enemy.status_effects.has_effect("chill"):
		enemy.status_effects.apply_effect("freeze", _player, damage)
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
	# Web: Grounded - half the radius, double the damage.
	if ability.has_twist("grounded"):
		radius *= 0.5
		damage_multiplier *= 2.0
	var jumps := 3 if ability.has_twist("chain_lightning") else 1
	var chained := {}
	for enemy in _enemies_by_distance(centre, radius):
		chained[enemy.get_instance_id()] = true
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	var scene := _player.get_tree().current_scene
	var arc_on := func(from_enemy: Enemy) -> void:
		LightningArc.spawn(scene, centre + Vector3.UP * ARC_HEIGHT, from_enemy.global_position + Vector3.UP * ARC_HEIGHT, color)
		var from := from_enemy
		for jump in jumps:
			var found: Enemy = null
			for next in _enemies_by_distance(from.global_position, STATIC_CHAIN_RANGE):
				if not chained.has(next.get_instance_id()):
					found = next
					break
			if found == null:
				break
			chained[found.get_instance_id()] = true
			LightningArc.spawn(scene, from.global_position + Vector3.UP * ARC_HEIGHT, found.global_position + Vector3.UP * ARC_HEIGHT, color)
			_hit_enemy(ability, found, damage_multiplier * STATIC_CHAIN_DAMAGE, apply_composure, Callable())
			from = found
	_damage_area(ability, centre, radius, damage_multiplier, apply_composure, WAVE_DURATION, arc_on)
	_play_range_effect(ability, centre)

## Expanding ring with no damage - Blink/Purge feedback.
func _flash_ring(pos: Vector3, radius: float, ability: Ability, color: Color = Color(0, 0, 0, 0)) -> void:
	var ring: AbilityRangeEffect = RANGE_EFFECT_SCENE.instantiate()
	_player.get_tree().current_scene.add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.05
	var tint: Color = color if color.a > 0.0 else Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	ring.play(radius, tint)
	SpellCastFx.play(ability.ability_id, _player.get_tree().current_scene, pos, radius, tint)

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
		if scene == RANGE_EFFECT_SCENE:
			SpellCastFx.play(ability.ability_id, _player.get_tree().current_scene, cast_position, ability.get_radius(_player.stat_sheet), color)
	return effect

func get_move_speed_multiplier() -> float:
	if _flame_jets_remaining <= 0.0 or (_flame_jets_ability and _flame_jets_ability.has_twist("walking_fire")):
		return 1.0
	return FLAME_JETS_MOVE_SPEED_MULTIPLIER

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
	var tex := GlowTexture.radial()
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
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.collision_mask = 1
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] is StaticBody3D

## Ice crystals circling the player low, around the hips, while Frost Armor
## holds - they cross the bottom edge of the first-person view - with frost
## mist curling round the feet and glints of light.
func _ensure_frost_armor_fx() -> void:
	if is_instance_valid(_frost_armor_fx):
		return
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.55, 0.82, 1.0, 0.55)
	var crystal := PrismMesh.new()
	crystal.size = Vector3(0.045, 0.18, 0.045)
	crystal.material = mat
	var glint := SpellFx.glow_material(Color(0.7, 0.9, 1.0, 0.5), true, BaseMaterial3D.BILLBOARD_ENABLED)
	glint.vertex_color_use_as_albedo = false
	var glint_quad := QuadMesh.new()
	glint_quad.size = Vector2.ONE * 0.12
	for i in FROST_SHARD_COUNT:
		var a := TAU * i / FROST_SHARD_COUNT
		var shard := MeshInstance3D.new()
		shard.mesh = crystal
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.position = Vector3(cos(a) * 1.3, 0.35 + 0.1 * sin(a * 2.0), sin(a) * 1.3)
		shard.rotation = Vector3(0.2, -a, 0.15)
		root.add_child(shard)
		var halo := MeshInstance3D.new()
		halo.mesh = glint_quad
		halo.material_override = glint
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.add_child(halo)
	var mist := SpellFx.emitter(root, 24, 1.6)
	mist.position.y = 0.1
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	mist.emission_ring_axis = Vector3.UP
	mist.emission_ring_radius = 1.4
	mist.emission_ring_inner_radius = 1.0
	mist.emission_ring_height = 0.05
	mist.direction = Vector3.UP
	mist.spread = 30.0
	mist.initial_velocity_min = 0.05
	mist.initial_velocity_max = 0.25
	mist.tangential_accel_min = 0.3
	mist.tangential_accel_max = 0.6
	mist.scale_amount_min = 0.35
	mist.scale_amount_max = 0.6
	mist.color_ramp = SpellFx.ramp(Color(0.7, 0.9, 1.0, 0.0), Color(0.7, 0.9, 1.0, 0.08), 0.4)
	mist.mesh = SpellFx.glow_quad()
	mist.emitting = true
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
	var count := 1 + _player.stat_sheet.conduit_additional_projectiles
	var spread := EXTRA_BOLT_SPREAD_DEG
	# Web: Javelin Volley (+2 at 60%) and Twin Lances (+1 at 75%, a wider V).
	if ability.has_twist("javelin_volley"):
		count += 2
		damage_multiplier *= 0.6
	if ability.has_twist("twin_lances"):
		count += 1
		damage_multiplier *= 0.75
		spread = 10.0
	for i in count:
		var xform := _player.camera.global_transform
		var yaw := _aim_yaw_offset + spread * (i - (count - 1) / 2.0)
		xform.basis = Basis(Vector3.UP, deg_to_rad(yaw)) * xform.basis
		_spawn_bolt(ability, damage_multiplier, xform)

## Ground bolts in a full horizontal circle around the player.
func _fire_radiating_bolts(ability: Ability, damage_multiplier: float) -> void:
	var origin := _player.global_position + Vector3(0, 0.3, 0)
	var count := THUNDER_SWEEP_BOLT_COUNT + _player.stat_sheet.conduit_additional_projectiles
	# Web: Focused Sweep - twice the bolts, all across the front half.
	var focused := ability.has_twist("focused_sweep")
	var back := _player.camera.global_transform.basis.z
	var forward_yaw := atan2(back.x, back.z) + PI
	if focused:
		count *= 2
	for i in range(count):
		var angle := TAU * i / float(count) + _sweep_offset
		if focused:
			angle = forward_yaw + PI * (float(i) / maxf(count - 1, 1) - 0.5)
		var xform := Transform3D(Basis(Vector3.UP, angle), origin)
		_spawn_bolt(ability, damage_multiplier, xform)

## SPARK_COUNT crawlers (plus a Conduit's extra projectiles) fanned out ahead
## of the caster; each seeks on its own.
func _fire_spark(ability: Ability, damage_multiplier: float) -> void:
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = -_player.global_transform.basis.z
	forward = forward.normalized().rotated(Vector3.UP, deg_to_rad(_aim_yaw_offset))
	var origin := _player.global_position + forward * 0.5
	var count := SPARK_COUNT + int(ability.web_value(SkillWeb.PROJECTILES)) + _player.stat_sheet.conduit_additional_projectiles
	# Web: Overcharge (fast, short-lived) or Stalking Spark (slow, long-lived).
	var speed_mult := 1.7 if ability.has_twist("overcharge") else (0.6 if ability.has_twist("stalking_spark") else 1.0)
	var life_mult := 0.5 if ability.has_twist("overcharge") else (2.0 if ability.has_twist("stalking_spark") else 1.0)
	for i in range(count):
		var offset_deg := SPARK_SPREAD_DEG * (i - (count - 1) / 2.0)
		var heading: Vector3 = forward.rotated(Vector3.UP, deg_to_rad(offset_deg))
		var crawler: SparkCrawler = SPARK_CRAWLER_SCENE.instantiate()
		crawler.speed = SparkCrawler.MOVE_SPEED * ability.get_projectile_speed_multiplier(_player.stat_sheet) * speed_mult
		crawler.lifetime = SparkCrawler.LIFETIME * ability.get_duration_multiplier(_player.stat_sheet) * life_mult
		crawler.heading = heading
		crawler.ability = ability
		crawler.stat_sheet = _player.stat_sheet
		crawler.source = _player
		crawler.damage_multiplier = damage_multiplier
		_player.get_tree().current_scene.add_child(crawler)
		crawler.global_position = origin

func _fire_winters_eye(ability: Ability, target: Vector3) -> void:
	# Web: Twin Eyes - two orbs either side of the target, 60% each.
	if ability.has_twist("twin_eyes"):
		var weaker := ability.duplicate() as Ability
		weaker.extra_more = ability.extra_more * 0.6
		var right := _player.camera.global_transform.basis.x
		right.y = 0.0
		for s in [-1.0, 1.0]:
			_spawn_winters_eye(weaker, target + right.normalized() * s * 3.0)
		return
	_spawn_winters_eye(ability, target)

func _spawn_winters_eye(ability: Ability, target: Vector3) -> void:
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

## Teleports along the camera's aim, up included: the player's own body is
## swept so it stops short of walls, floors and ceilings. Looking down while
## grounded blinks flat instead of into the floor. A blink that ends against
## a wall whose top is within BLINK_MANTLE_HEIGHT climbs onto it.
func _perform_blink() -> void:
	var direction := -_player.camera.global_transform.basis.z
	if direction.y < 0.0 and _player.is_on_floor():
		direction.y = 0.0
	if direction.length() < 0.01:
		direction = -_player.global_transform.basis.z
	direction = direction.normalized()
	var motion := direction * _blink_distance
	var from := _player.global_transform
	var hit := _player.move_and_collide(motion, true)
	var travel := motion if hit == null else hit.get_travel()
	var target := from.translated(travel)
	if hit and absf(hit.get_normal().y) < 0.5:
		target = _blink_mantle(target, Vector3(direction.x, 0.0, direction.z))
	_player.global_position = target.origin
	_player.velocity.y = maxf(_player.velocity.y, 0.0)

var _blink_distance := BLINK_DISTANCE
const BLINK_MANTLE_HEIGHT := 3.0
const BLINK_MANTLE_REACH := 1.2

## Lifts the end point over a wall's edge when the body fits on top of it.
func _blink_mantle(at: Transform3D, flat_dir: Vector3) -> Transform3D:
	if flat_dir.length() < 0.1:
		return at
	var step := flat_dir.normalized() * BLINK_MANTLE_REACH
	for lift: float in [1.0, 2.0, BLINK_MANTLE_HEIGHT]:
		var up := Vector3.UP * lift
		if _player.test_move(at, up):
			return at
		var raised := at.translated(up)
		if not _player.test_move(raised, step):
			return raised.translated(step)
	return at

## Crosshair raycast hit, capped at MAX_TARGET_RANGE. With no hit, falls back
## to the plane at the player's feet.
func _get_ground_target_point() -> Vector3:
	var camera := _player.camera
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var space_state := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * MAX_TARGET_RANGE, 1)
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
			if ability.has_twist("rallying_cry"):
				_player.health.heal(_player.health.max_health * 0.05)
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

## Corrupted "Cursed Skill": the extra Mana cost (%) of the ability bar slot
## it names (1-4), 0 when no equipped item curses this slot. That slot has
## no cooldown.
func _cursed_slot_cost(slot_index: int) -> float:
	var extra := 0.0
	for item in _player.equipment.get_all_equipped_items():
		for affix in item.affixes:
			if affix.stat_key == "skill_no_cooldown_extra_cost" and int(affix.value_max) == slot_index + 1:
				extra += affix.value
	return extra

## Corrupted "Maw-Touched": a chance for a cast to go off again at
## MAW_TOUCHED_DAMAGE.
const MAW_TOUCHED_DAMAGE := 0.5

func _maybe_trigger_twice(ability: Ability, cast_position: Vector3) -> void:
	var chance := _player.stat_sheet.get_misc_bonus("skill_double_trigger_chance") / 100.0
	if chance > 0.0 and ability.deals_damage() and randf() < chance:
		_cast(ability, cast_position, MAW_TOUCHED_DAMAGE)

## Called by PlayerMeleeAttack at the start of every melee strike.
func on_melee_swing() -> void:
	if not GameState.booming_blade_on or _booming_blade_cd > 0.0:
		return
	var ability := _resolve_ability_by_id("booming_blade")
	if ability == null:
		return
	_booming_blade_cd = BOOMING_BLADE_COOLDOWN
	var count := booming_blade_bolt_count(ability, _player.stat_sheet)
	var spread := BOOMING_BLADE_SPREAD_DEG
	# Web: Arc Blade - two more bolts, fanned wide.
	if ability.has_twist("arc_blade"):
		count += 2
		spread = 18.0
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else -_player.global_transform.basis.z
	for i in count:
		var yaw := spread * (i - (count - 1) / 2.0)
		var crawler: SparkCrawler = SPARK_CRAWLER_SCENE.instantiate()
		crawler.straight = true
		crawler.heading = forward.rotated(Vector3.UP, deg_to_rad(yaw))
		crawler.speed = BOOMING_BLADE_SPEED * ability.get_projectile_speed_multiplier(_player.stat_sheet)
		crawler.range_m = ability.get_radius(_player.stat_sheet)
		crawler.hit_key = &"booming_blade"
		crawler.hit_interval = BOOMING_BLADE_HIT_INTERVAL
		crawler.ability = ability
		crawler.stat_sheet = _player.stat_sheet
		crawler.source = _player
		_player.get_tree().current_scene.add_child(crawler)
		crawler.global_position = _player.global_position + forward * 0.6

static func booming_blade_bolt_count(ability: Ability, stat_sheet: StatSheet) -> int:
	return 1 + ability.get_effective_level(stat_sheet) / BOOMING_BLADE_LEVELS_PER_BOLT + (stat_sheet.conduit_additional_projectiles if stat_sheet else 0)
