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
## BOOMING_BLADE_LEVELS_PER_BOLT spell levels. Each trigger drains
## BOOMING_BLADE_TRIGGER_COST of its Mana cost. Turning it off is free.
const BOOMING_BLADE_COOLDOWN := 0.45
const BOOMING_BLADE_TRIGGER_COST := 0.3
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
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.damage_dealt.connect(_on_enchanted_hit)

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

	_tick_auras(delta)
	_tick_pale_thread(delta)
	_tick_toggles(delta)

	for i in range(AbilityLoadoutComponent.SLOT_COUNT):
		var action := "ability_%d" % (i + 1)
		if Input.is_action_just_pressed(action) and not _player.is_action_locked():
			_on_ability_pressed(i)

	# Polled rather than just_released: a tap inside one physics frame, or a
	# release swallowed by UI or focus loss, would otherwise never fire and
	# leave the reticle stuck on screen.
	if _targeting_slot != -1 and not Input.is_action_pressed("ability_%d" % (_targeting_slot + 1)):
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
	if _player.is_in_visceral():
		return
	var from_page := _player.caster_stance.uses_spell_page()
	var ability: Ability = _slot_ability(slot_index, from_page)
	if ability == null:
		return
	if ability.is_ground_targeted and not is_hex_aura(ability):
		if _targeting_slot != -1:
			return
		_targeting_slot = slot_index
		_targeting_from_page = from_page
		_show_reticle(ability)
	else:
		_try_cast(slot_index, _player.global_position, from_page)

## Casts a bar slot directly (Arkanus' right-click Elemental Aether).
func cast_slot(slot_index: int) -> void:
	if not _player.is_in_visceral():
		_try_cast(slot_index, _player.global_position)

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
	if TOGGLE_SPELLS.has(ability.ability_id) and GameState.toggled_spells.has(ability.ability_id):
		_set_toggle(ability.ability_id, false)
		_flash_ring(_player.global_position, 1.4, ability, Color(0.6, 0.6, 0.7))
		return
	if ability.ability_id == "death_shroud" and GameState.death_shroud_on:
		GameState.death_shroud_on = false
		_flash_ring(_player.global_position, 1.4, ability, Color(0.6, 0.6, 0.7))
		return
	if is_hex_aura(ability) and GameState.hex_auras.has(ability.ability_id):
		GameState.hex_auras.erase(ability.ability_id)
		_flash_ring(_player.global_position, 1.4, ability, Color(0.6, 0.6, 0.7))
		return
	if ability.is_skill:
		var weapon_error := ability.skill_weapon_error(_player.get_active_weapon())
		if weapon_error != "":
			EventBus.ability_cast_failed.emit(_player, ability, weapon_error)
			return
	if TARGETED_ABILITY_IDS.has(ability.ability_id) and _crosshair_enemy() == null:
		EventBus.ability_cast_failed.emit(_player, ability, "No target")
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
	if ability.ability_id == "manasaber":
		mana_cost = manasaber_cost(_player.mana.max_mana) * copies
	if _player.mana.current_mana < mana_cost:
		EventBus.ability_cast_failed.emit(_player, ability, "Not enough Mana")
		return
	# Checked before spending, since CastTimeHandler refuses mid-windup.
	if _player.cast_time_handler.is_casting():
		EventBus.ability_cast_failed.emit(_player, ability, "Already casting")
		return
	_player.mana.spend(mana_cost)
	if ability.ability_id == "manasaber":
		_manasaber_spent = mana_cost / copies
		if _player.arm_rig:
			_player.arm_rig.play_slash(ability.get_cast_time(_player.stat_sheet), MANASABER_SLASH_STRIKE, MANASABER_SLASH_RECOVERY, false, manasaber_trail_color())
	_cast_lockout = ability.base_recovery_time / maxf(_player.get_action_speed_multiplier(), 0.01)
	if ability.ability_id == "flame_jets":
		_flame_jets_input_action = "ability_%d" % (slot_index + 1)
		_flame_jets_is_manual = true
	_cooldowns[ability] = 0.0 if cursed_cost > 0.0 else ability.get_final_cooldown(_player.get_action_speed_multiplier(), _player.stat_sheet)
	# CastTimeHandler calls _on_cast_time_completed() immediately for
	# INSTANT/CHANNELED, or after the windup for CAST_TIME.
	var cast: Ability = plan["ability"]
	if cast.is_skill:
		_begin_skill_swing(cast)
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
	"double_nova": ["nova", [0.5], 0.5],
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
	if ARKANUS_IDS.has(ability.ability_id):
		_cast_arkanus(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return
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
	if is_hex_aura(ability):
		if not GameState.hex_auras.has(ability.ability_id):
			GameState.hex_auras.append(ability.ability_id)
		_aura_ticker = 0.0
		_flash_ring(_player.global_position, ability.get_radius(_player.stat_sheet), ability)
		EventBus.ability_cast.emit(_player, ability)
		return
	if CURSE_EFFECTS.has(ability.ability_id):
		_cast_curse(ability, cast_position)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "linger":
		_cast_linger(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "pale_thread":
		_start_pale_thread(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "death_shroud":
		GameState.death_shroud_on = true
		_aura_ticker = 0.0
		_flash_ring(_player.global_position, ability.get_radius(_player.stat_sheet), ability)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.has_tag(Ability.TAG_WARCRY):
		_warcry(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "shatter":
		_cast_shatter(ability, cast_position, damage_multiplier, apply_composure)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "purge":
		_player.status_effects.clear_all_effects()
		if ability.has_twist("second_wind"):
			_player.health.heal(_player.health.max_health * 0.1)
		_flash_ring(_player.global_position, 4.5, ability, Color(0.85, 0.95, 1.0))
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "booming_blade":
		GameState.booming_blade_on = true
		_flash_ring(_player.global_position, 1.4, ability)
		EventBus.ability_cast.emit(_player, ability)
		return
	if TOGGLE_SPELLS.has(ability.ability_id):
		_set_toggle(ability.ability_id, true)
		_flash_ring(_player.global_position, maxf(ability.get_radius(_player.stat_sheet), 1.4) if ability.ability_id == "thunderstorm" else 1.4, ability)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "manasaber":
		_cast_manasaber(ability, damage_multiplier, apply_composure)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "puncture":
		_cast_puncture(ability, damage_multiplier, apply_composure)
		EventBus.ability_cast.emit(_player, ability)
		return
	if ability.ability_id == "invocation_of_arach":
		_cast_arach(ability)
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
	if ability.ability_id == "blizzard":
		_cast_blizzard(ability, cast_position, damage_multiplier, apply_composure)
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

## Shatter: Resonance adds this much per ailment broken beyond the first;
## Splinter carries part of each break to enemies nearby.
const SHATTER_RESONANCE := 0.25
const SHATTER_SPLINTER_SHARE := 0.4
const SHATTER_SPLINTER_RADIUS := 3.0

## Breaks every ailment on the enemies in the area: each one becomes a hit
## in its own element, worth the spell's damage times its weight
## (StatusEffectComponent.SHATTER_VALUES). Enemies without ailments take nothing.
func _cast_shatter(ability: Ability, centre: Vector3, damage_multiplier: float, apply_composure: bool) -> void:
	var radius := ability.get_radius(_player.stat_sheet)
	_play_range_effect(ability, centre)
	for enemy in _enemies_by_distance(centre, radius):
		var broken := enemy.status_effects.shatter_ailments()
		var resonance := 1.0 + SHATTER_RESONANCE * maxi(broken.size() - 1, 0) if ability.has_twist("resonance") else 1.0
		for entry in broken:
			if not is_instance_valid(enemy) or not enemy.health.is_alive():
				break
			var hit := ability.roll_damage(_player.stat_sheet)
			var damage: float = hit["final_damage"] * damage_multiplier * float(entry[1]) * resonance
			var damage_type: Constants.DamageType = entry[2]
			_shatter_hit(enemy, damage, damage_type, hit["is_critical"], apply_composure)
			_flash_ring(enemy.global_position + Vector3.UP * 0.1, 1.2, ability, Constants.DAMAGE_TYPE_COLOR.get(damage_type, Color.WHITE))
			if ability.has_twist("splinter"):
				for other in _enemies_by_distance(enemy.global_position, SHATTER_SPLINTER_RADIUS):
					if other != enemy:
						_shatter_hit(other, damage * SHATTER_SPLINTER_SHARE, damage_type, false, apply_composure)

func _shatter_hit(enemy: Enemy, damage: float, damage_type: Constants.DamageType, is_critical: bool, apply_composure: bool) -> void:
	if not enemy.take_damage(damage, damage_type, true):
		return
	if apply_composure and enemy.stance:
		enemy.stance.apply_attack_stance_damage(damage, damage_type)
	EventBus.damage_dealt.emit(_player, enemy, damage, damage_type, false, is_critical)

const IMPACT_ABILITY_IDS := ["comet"]
const WAVE_ABILITY_IDS := ["ice_pulse", "static_discharge", "entropic_decay", "nova"]
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
	# Appears a few metres ahead, not at the camera's shoulder where it would fill the view.
	var ahead := -_player.global_transform.basis.z * 2.5
	if ability.has_twist("spectral_host"):
		# Two wraiths split the Ward between them.
		for s in [-1.0, 1.0]:
			WraithMinion.summon(scene, _player, ability, stacks / 2, 1.0, ahead + right * s * 1.2)
	else:
		WraithMinion.summon(scene, _player, ability, stacks, 1.0, ahead + right * 1.0)
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
	["thunder_javelin", "frost_javelin", Constants.DamageType.COLD, ["chill"], false],
	["cinder_lance", "storm_lance", Constants.DamageType.LIGHTNING, ["shock"], false],
	["stormcall", "hellfire_call", Constants.DamageType.FIRE, ["ignite"], false],
	["entropic_decay", "pale_decay", Constants.DamageType.PALE, ["pallid"], false],
	["reap", "withering_scythe", Constants.DamageType.ENTROPIC, ["unraveling"], false],
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
	_manasaber_spent = 0.0  # an auto-cast spends nothing; it swings as if it took the full share
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

## Ice crystals circling the player at chest height while Frost Armor holds:
## clusters of glowing rime (spell_energy, faded low on screen so they pass
## over the HUD unseen and read at the sides of the view), each with a glint
## and a faint trail of frost mist.
func _ensure_frost_armor_fx() -> void:
	if is_instance_valid(_frost_armor_fx):
		return
	var root := Node3D.new()
	var mat := SpellFx.energy_material(Color(0.45, 0.75, 1.0), 1.5, 0.3, true)
	mat.set_shader_parameter("noise_scale", 14.0)
	mat.set_shader_parameter("rim_power", 1.4)
	var crystal := PrismMesh.new()
	crystal.size = Vector3(0.06, 0.24, 0.06)
	var sliver := PrismMesh.new()
	sliver.size = Vector3(0.035, 0.14, 0.035)
	var glint := SpellFx.glow_material(Color(1.4, 1.7, 2.0, 0.8), true, BaseMaterial3D.BILLBOARD_ENABLED)
	glint.vertex_color_use_as_albedo = false
	var glint_quad := QuadMesh.new()
	glint_quad.size = Vector2.ONE * 0.1
	for i in FROST_SHARD_COUNT:
		var a := TAU * i / FROST_SHARD_COUNT
		var shard := Node3D.new()
		shard.position = Vector3(cos(a) * 1.45, 1.0 + 0.12 * sin(a * 2.0), sin(a) * 1.45)
		shard.rotation = Vector3(0.2, -a, 0.15)
		root.add_child(shard)
		for piece in [[crystal, Vector3.ZERO, 0.0], [sliver, Vector3(0.05, -0.06, 0.02), -0.5], [sliver, Vector3(-0.04, -0.08, -0.03), 0.6]]:
			var mi := MeshInstance3D.new()
			mi.mesh = piece[0]
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = piece[1]
			mi.rotation.z = piece[2]
			shard.add_child(mi)
		var halo := MeshInstance3D.new()
		halo.mesh = glint_quad
		halo.material_override = glint
		halo.position.y = 0.08
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.add_child(halo)
	var mist := SpellFx.emitter(root, 30, 1.2)
	mist.position.y = 0.95
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	mist.emission_ring_axis = Vector3.UP
	mist.emission_ring_radius = 1.55
	mist.emission_ring_inner_radius = 1.35
	mist.emission_ring_height = 0.15
	mist.direction = Vector3.DOWN
	mist.spread = 20.0
	mist.initial_velocity_min = 0.05
	mist.initial_velocity_max = 0.2
	mist.scale_amount_min = 0.2
	mist.scale_amount_max = 0.4
	mist.color_ramp = SpellFx.ramp(Color(0.7, 0.9, 1.0, 0.0), Color(0.7, 0.9, 1.0, 0.1), 0.3)
	mist.mesh = SpellFx.glow_quad()
	mist.emitting = true
	_player.add_child(root)
	_frost_armor_fx = root

func has_frost_armor() -> bool:
	return _frost_armor_remaining > 0.0

func frost_armor_remaining() -> float:
	return _frost_armor_remaining

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
		# Each spark keeps its own hit cooldown per enemy.
		crawler.hit_key = StringName("spark_%d" % crawler.get_instance_id())
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
	# Each trigger drains part of the cast cost; it switches off when Mana can't pay.
	var drain := ability.get_mana_cost(_player.stat_sheet) * BOOMING_BLADE_TRIGGER_COST
	if _player.mana.current_mana < drain:
		GameState.booming_blade_on = false
		EventBus.ability_cast_failed.emit(_player, ability, "Not enough Mana")
		return
	_player.mana.spend(drain)
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

## ---- Curses and Pale spells ------------------------------------------------

## Area curses: ability_id -> the status they leave (StatusEffectComponent.apply_curse()).
const CURSE_EFFECTS := {"meager": "meager", "fracturing": "fracturing", "decompose": "decompose", "elemental_fragility": "elemental_fragility"}
const CURSE_DURATION := 6.0
## Curse strength per spell level above 1 (x1.57 at level 20).
const CURSE_STRENGTH_PER_LEVEL := 0.03
## Spells cast on the enemy nearest the crosshair; refused with no one there.
const TARGETED_ABILITY_IDS := ["pale_thread", "linger", "elemental_lightning", "elemental_aether", "invocation_of_arach"]
const TARGET_RANGE := 25.0
const TARGET_CONE_DEG := 10.0
const PALE_COLOR := Color(0.88, 0.95, 1.0)

static func curse_strength(ability: Ability, stat_sheet: StatSheet) -> float:
	return 1.0 + CURSE_STRENGTH_PER_LEVEL * (ability.get_effective_level(stat_sheet) - 1) + ability.web_value(SkillWeb.CURSE_STRENGTH) / 100.0

## Web: Lingering Hex makes it last LINGERING_HEX times as long.
const LINGERING_HEX := 1.5

static func curse_duration(ability: Ability, stat_sheet: StatSheet) -> float:
	return CURSE_DURATION * ability.get_duration_multiplier(stat_sheet) * (LINGERING_HEX if ability.has_twist("lingering_hex") else 1.0)

func _cast_curse(ability: Ability, centre: Vector3) -> void:
	var radius := ability.get_radius(_player.stat_sheet)
	var duration := curse_duration(ability, _player.stat_sheet)
	var strength := curse_strength(ability, _player.stat_sheet)
	_play_range_effect(ability, centre)
	for enemy in _enemies_near(centre, radius):
		enemy.status_effects.apply_curse(CURSE_EFFECTS[ability.ability_id], _player, duration, strength)

## The live enemy whose body is closest to the crosshair's line, within
## TARGET_CONE_DEG and TARGET_RANGE, with no wall in between.
func _crosshair_enemy() -> Enemy:
	var origin := _player.camera.global_position
	var forward := -_player.camera.global_transform.basis.z
	var max_slope := tan(deg_to_rad(TARGET_CONE_DEG))
	var best: Enemy = null
	var best_slope := INF
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.health.is_alive():
			continue
		var to := _body_centre(enemy) - origin
		var along := to.dot(forward)
		if along <= 0.0 or to.length() > TARGET_RANGE:
			continue
		var slope := maxf((to - forward * along).length() - enemy.body_radius, 0.0) / along
		if slope <= max_slope and slope < best_slope and not _line_blocked(origin, _body_centre(enemy)):
			best = enemy
			best_slope = slope
	return best

static func _body_centre(enemy: Enemy) -> Vector3:
	return enemy.global_position + Vector3.UP * enemy.body_height * 0.6

## Linger: the rolled hit is spread over the affliction as Pale ticks.
const LINGER_DURATION := 6.0
const LINGER_SPREAD_COUNT := 2

func _cast_linger(ability: Ability, damage_multiplier: float) -> void:
	var target := _crosshair_enemy()
	if target == null:
		return
	var duration := LINGER_DURATION * ability.get_duration_multiplier(_player.stat_sheet)
	var total: float = ability.roll_damage(_player.stat_sheet)["final_damage"] * damage_multiplier
	target.status_effects.apply_linger(_player, total / LINGER_DURATION, duration)
	_flash_ring(target.global_position, 1.2, ability, PALE_COLOR)

## A Lingering enemy's death passes Linger, fresh, to the nearest two
## within Linger's radius that don't have it.
func _on_enemy_died(node: Node) -> void:
	var dead := node as Enemy
	if dead and dead.status_effects and dead.status_effects.has_effect("arach_mark") and is_instance_valid(_player):
		var arach := _resolve_ability_by_id("invocation_of_arach")
		for i in (2 if arach and arach.has_twist("brood") else 1):  # Web: Brood
			_summon_spider(dead.global_position + Vector3(i * 0.6, 0.0, 0.0))
	if dead == null or dead.status_effects == null or not dead.status_effects.has_effect("linger") or not is_instance_valid(_player):
		return
	var ability := _resolve_ability_by_id("linger")
	var radius := ability.radius if ability else 10.0
	var duration := LINGER_DURATION * (ability.get_duration_multiplier(_player.stat_sheet) if ability else 1.0)
	var dps := dead.status_effects.get_linger_dps()
	var spread := 0
	for other in _enemies_by_distance(dead.global_position, radius):
		if spread >= linger_spread_count(ability):
			break
		if other == dead or other.status_effects.has_effect("linger"):
			continue
		other.status_effects.apply_linger(_player, dps, duration)
		_pale_flicker(_body_centre(dead), _body_centre(other))
		spread += 1

## Web: Contagion passes Linger to one more enemy.
static func linger_spread_count(ability: Ability) -> int:
	return LINGER_SPREAD_COUNT + (1 if ability and ability.has_twist("contagion") else 0)

## Pale Thread: ticks Pale damage (base damage is per second) and restores
## Ward while the target stays within the spell's radius.
const PALE_THREAD_DURATION := 5.0
const PALE_THREAD_TICK := 0.25
## Share of max Ward restored per second while the thread holds.
const PALE_THREAD_WARD_PER_SEC := 0.06
## Where the thread leaves the caster, in camera space (right, down, ahead).
const PALE_THREAD_HAND := Vector3(0.22, -0.28, -0.55)
## Web: Long Thread's break range.
const LONG_THREAD_RANGE := 26.0

static func pale_thread_range(ability: Ability) -> float:
	return LONG_THREAD_RANGE if ability.has_twist("long_thread") else ability.radius

var _thread_ability: Ability
var _thread_target: Enemy
var _thread_multiplier: float = 1.0
var _thread_remaining: float = 0.0
var _thread_ticker: float = 0.0
var _thread_beam: Node3D

func _start_pale_thread(ability: Ability, damage_multiplier: float) -> void:
	# A weaker second trigger doesn't replace a full-strength thread.
	if _thread_remaining > 0.0 and damage_multiplier < _thread_multiplier:
		return
	var target := _crosshair_enemy()
	if target == null:
		return
	_thread_ability = ability
	_thread_target = target
	_thread_multiplier = damage_multiplier
	_thread_remaining = PALE_THREAD_DURATION * ability.get_duration_multiplier(_player.stat_sheet)
	_thread_ticker = PALE_THREAD_TICK
	if not is_instance_valid(_thread_beam):
		_thread_beam = _make_beam(0.6)
		_player.get_tree().current_scene.add_child(_thread_beam)
	_update_thread_beam()

func _tick_pale_thread(delta: float) -> void:
	if _thread_remaining <= 0.0:
		return
	if not is_instance_valid(_thread_target) or not _thread_target.health.is_alive() or _thread_target.distance_to_body(_player.global_position) > pale_thread_range(_thread_ability):
		_end_pale_thread()
		return
	_thread_remaining -= delta
	_thread_ticker -= delta
	if _thread_ticker <= 0.0:
		_thread_ticker += PALE_THREAD_TICK
		var hit := _thread_ability.roll_damage(_player.stat_sheet)
		var damage: float = hit["final_damage"] * _thread_multiplier * PALE_THREAD_TICK
		_thread_target.take_damage(damage, Constants.DamageType.PALE, true, false, true)
		StatusEffectComponent.emitting_dot = true
		EventBus.damage_dealt.emit(_player, _thread_target, damage, Constants.DamageType.PALE, false, hit["is_critical"])
		StatusEffectComponent.emitting_dot = false
		_player.ward.restore(_player.ward.max_ward * PALE_THREAD_WARD_PER_SEC * PALE_THREAD_TICK)
	if _thread_remaining <= 0.0:
		_end_pale_thread()
	else:
		_update_thread_beam()

func _end_pale_thread() -> void:
	_thread_remaining = 0.0
	_thread_target = null
	if is_instance_valid(_thread_beam):
		_thread_beam.queue_free()

func _update_thread_beam() -> void:
	if not is_instance_valid(_thread_beam) or not is_instance_valid(_thread_target):
		return
	var from := _player.camera.global_transform * PALE_THREAD_HAND
	_place_beam(_thread_beam, from, _body_centre(_thread_target))
	# A slow shimmer along the thread.
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
	var mat := _thread_beam.get_meta("material") as ShaderMaterial
	mat.set_shader_parameter("alpha", float(_thread_beam.get_meta("alpha")) * pulse)

## A pale thread along its -Z, one unit long (stretched by _place_beam()):
## two crossed ribbons of the lightning shader, calmed to a slow waver, with
## a white-hot core in a soft glow.
func _make_beam(core_alpha: float) -> Node3D:
	var beam := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.06
	for perp in [Vector3.RIGHT, Vector3.UP]:
		var quad := [[-perp * w + Vector3(0, 0, 0.5), Vector2(0, 0)], [perp * w + Vector3(0, 0, 0.5), Vector2(1, 0)], [perp * w - Vector3(0, 0, 0.5), Vector2(1, 1)], [-perp * w - Vector3(0, 0, 0.5), Vector2(0, 1)]]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(quad[idx][1])
			st.add_vertex(quad[idx][0])
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = LightningArc.SHADER
	mat.set_shader_parameter("color", PALE_COLOR)
	mat.set_shader_parameter("alpha", core_alpha)
	mat.set_shader_parameter("core_width", 0.22)
	mat.set_shader_parameter("intensity", 1.6)
	mat.set_shader_parameter("flicker_amount", 0.0)
	mat.set_shader_parameter("wave_speed", 3.0)
	mat.set_shader_parameter("seed", randf() * 100.0)
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.add_child(mesh)
	beam.set_meta("material", mat)
	beam.set_meta("alpha", core_alpha)
	return beam

static func _place_beam(beam: Node3D, from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var dir := (to - from) / length
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
	var basis := Basis.looking_at(dir, up)
	basis.z *= length
	beam.global_transform = Transform3D(basis, (from + to) * 0.5)

## A short-lived thread between two points (Linger passing on).
func _pale_flicker(from: Vector3, to: Vector3) -> void:
	var beam := _make_beam(0.8)
	_player.get_tree().current_scene.add_child(beam)
	_place_beam(beam, from, to)
	var mat := beam.get_meta("material") as ShaderMaterial
	var tween := beam.create_tween()
	tween.tween_method(func(a: float) -> void: mat.set_shader_parameter("alpha", a), 0.8, 0.0, 0.45)
	tween.tween_callback(beam.queue_free)

## Auras: Death Shroud and curses with Hex Aura, switched on and off by
## casting. While on, they pulse their effect over every enemy within the
## spell's radius (it fades AURA_LINGER after they leave) and drain a share of
## maximum Mana per second (more than base regen, 5%), scaled by mana cost
## reduction. When Mana can't
## pay, every aura switches off. The drain is what pays for their strength.
const AURA_PULSE := 0.4
const AURA_LINGER := 1.0
## Death Shroud's Pallid at this strength: 35% less damage dealt.
const DEATH_SHROUD_STRENGTH := 1.75
const DEATH_SHROUD_DRAIN := 0.1
## Pale Pyre twist: per second, this share of maximum Life + Ward burns every
## enemy in the shroud (scaled by spell damage) and the player.
const PALE_PYRE_SHARE := 0.7
## Curse auras: stronger than the cast curse, and each drains on its own.
const HEX_AURA_STRENGTH := 1.25
const HEX_AURA_DRAIN := 0.08
var _aura_ticker: float = 0.0
var _aura_rings: Dictionary = {}  # ability_id -> {"mesh": MeshInstance3D, "radius": float}

func is_hex_aura(ability: Ability) -> bool:
	return ability != null and CURSE_EFFECTS.has(ability.ability_id) and ability.has_twist("hex_aura")

## Abilities switched on as auras right now.
func active_auras() -> Array[Ability]:
	var result: Array[Ability] = []
	if GameState.death_shroud_on:
		var shroud := _resolve_ability_by_id("death_shroud")
		if shroud:
			result.append(shroud)
	for id in GameState.hex_auras.duplicate():
		var hex := _resolve_ability_by_id(id)
		if hex and hex.has_twist("hex_aura"):
			result.append(hex)
		else:
			GameState.hex_auras.erase(id)  # the twist was refunded
	return result

## Mana an aura drains per second for this player.
static func aura_drain_per_second(ability: Ability, max_mana: float, stat_sheet: StatSheet) -> float:
	var share := DEATH_SHROUD_DRAIN if ability.ability_id == "death_shroud" else HEX_AURA_DRAIN
	return max_mana * share * ability.get_mana_cost_multiplier(stat_sheet)

func _tick_auras(delta: float) -> void:
	var auras := active_auras()
	var ids := auras.map(func(a: Ability): return a.ability_id)
	if GameState.toggled_spells.has("thunderstorm"):
		ids.append("thunderstorm")  # its ring is drawn by _tick_thunderstorm()
	for id in _aura_rings.keys():
		if not ids.has(id):
			if is_instance_valid(_aura_rings[id]["mesh"]):
				_aura_rings[id]["mesh"].queue_free()
			_aura_rings.erase(id)
	if auras.is_empty():
		return
	var drain := 0.0
	for a in auras:
		drain += aura_drain_per_second(a, _player.mana.max_mana, _player.stat_sheet) * delta
	if _player.mana.current_mana < drain:
		GameState.death_shroud_on = false
		GameState.hex_auras.clear()
		EventBus.ability_cast_failed.emit(_player, auras[0], "Not enough Mana")
		return
	_player.mana.spend(drain)
	for a in auras:
		_update_aura_ring(a)
		if a.ability_id == "death_shroud" and a.has_twist("pale_pyre"):
			_burn_pale_pyre(a, delta)
	_aura_ticker -= delta
	if _aura_ticker > 0.0:
		return
	_aura_ticker = AURA_PULSE
	for a in auras:
		var radius := a.get_radius(_player.stat_sheet)
		for enemy in _enemies_near(_player.global_position, radius):
			if a.ability_id == "death_shroud":
				enemy.status_effects.apply_curse("pallid", _player, AURA_PULSE + AURA_LINGER, DEATH_SHROUD_STRENGTH)
				if a.has_twist("grave_chill"):
					enemy.status_effects.apply_effect("slow", _player)
			else:
				# A cast curse already holding the slot wins over the aura's pulse.
				enemy.status_effects.apply_curse(CURSE_EFFECTS[a.ability_id], _player, AURA_PULSE + AURA_LINGER, curse_strength(a, _player.stat_sheet) * HEX_AURA_STRENGTH, false)

## Pale Pyre, every frame: the pyre's share of maximum Life + Ward per second
## burns you, and every enemy in the shroud through the shroud's spell scaling.
func _burn_pale_pyre(shroud: Ability, delta: float) -> void:
	var sheet := _player.stat_sheet
	_player.take_damage(_pale_pyre_per_sec() * delta * (1.0 - _player.get_dot_mitigation()), Constants.DamageType.PALE, null, Player.HitKind.DOT)
	var per_sec: float = shroud._base_hit(_pale_pyre_per_sec(), sheet)["base_damage"] * (1.0 + sheet.get_dot_multiplier())
	for enemy in _enemies_near(_player.global_position, shroud.get_radius(sheet)):
		enemy.take_dot(per_sec, delta, Constants.DamageType.PALE, _player, "pale_pyre")

func _pale_pyre_per_sec() -> float:
	return (_player.health.max_health + _player.ward.max_ward) * PALE_PYRE_SHARE

## A faint ring on the ground at an aura's edge, in the spell's colour,
## following the player.
func _update_aura_ring(ability: Ability) -> void:
	var radius := ability.get_radius(_player.stat_sheet)
	var entry: Dictionary = _aura_rings.get(ability.ability_id, {})
	var mesh: MeshInstance3D = entry.get("mesh")
	if not is_instance_valid(mesh):
		mesh = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var colour := PALE_COLOR if ability.ability_id == "death_shroud" else SpellArt.colour_of(ability)
		mat.albedo_color = Color(colour, 0.35)
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_player.add_child(mesh)
		entry = {"mesh": mesh, "radius": 0.0}
		_aura_rings[ability.ability_id] = entry
	if not is_equal_approx(radius, entry["radius"]):
		entry["radius"] = radius
		var torus := TorusMesh.new()
		torus.inner_radius = radius - 0.08
		torus.outer_radius = radius
		torus.rings = 64
		torus.ring_segments = 4
		mesh.mesh = torus
	# Flat on the ground whatever way the player faces.
	mesh.global_transform = Transform3D(Basis.from_scale(Vector3(1.0, 0.15, 1.0)), _player.global_position + Vector3.UP * 0.05)

## ---- Arkanus, the Forbidden Staff ------------------------------------------

const ARKANUS_IDS := ["elemental_lightning", "elemental_fire", "elemental_water", "elemental_earth", "elemental_aether"]
const ARKANUS_FIREBALL_SCENE := preload("res://entities/projectile/Projectile.tscn")
## Elemental Lightning: more damage on a shattered Freeze / a Drenched target.
const SHATTER_MORE := 1.2
const DRENCHED_MORE := 1.1
## Elemental Fire: fireballs fanned across this cone, at this speed and range.
const FIREBALL_COUNT := 7
const FIREBALL_CONE_DEG := 40.0
const FIREBALL_SPEED := 24.0
const FIREBALL_LIFETIME := 1.25
## Elemental Water: Drenched and (with Stone Skin) Entangled for these long.
const DRENCH_SECONDS := 4.0
const WATER_ENTANGLE_SECONDS := 2.5
## Elemental Earth: Stone Skin's duration (Player.STONE_SKIN_* for its effect).
const STONE_SKIN_SECONDS := 5.0
## Elemental Aether: more damage per element on the target (ELEMENT_GROUPS).
const AETHER_MORE_PER_ELEMENT := 0.4
const ELEMENT_GROUPS := [["drenched"], ["entangle"], ["chill", "freeze"], ["shock"], ["ignite", "forbidden_fire"]]

func _cast_arkanus(ability: Ability, damage_multiplier: float) -> void:
	match ability.ability_id:
		"elemental_lightning":
			_elemental_lightning(ability, damage_multiplier)
		"elemental_fire":
			_elemental_fire(ability, damage_multiplier)
		"elemental_water":
			_elemental_water(ability, damage_multiplier)
		"elemental_earth":
			_elemental_earth()
		"elemental_aether":
			_elemental_aether(ability, damage_multiplier)

## A bolt from the sky onto the enemy at the crosshair. A Frozen target's
## Freeze shatters: SHATTER_MORE damage and a guaranteed Critical Strike.
func _elemental_lightning(ability: Ability, damage_multiplier: float) -> void:
	var target := _crosshair_enemy()
	if target == null:
		return
	var sheet := _player.stat_sheet
	var statuses := target.status_effects
	var frozen := statuses.has_effect("freeze")
	var r := ability.get_base_damage_range(sheet)
	var hit: Dictionary = ability._base_hit(randf_range(r.x, r.y), sheet)
	var crit: bool = frozen or randf() < float(hit["crit_chance"])
	var damage: float = hit["base_damage"] * damage_multiplier * (float(hit["crit_damage_multiplier"]) if crit else 1.0)
	if frozen:
		damage *= SHATTER_MORE
		statuses.remove_effect("freeze")
	var drenched := statuses.has_effect("drenched")
	if drenched:
		damage *= DRENCHED_MORE
	ArkanusFx.lightning(_player.get_tree().current_scene, _body_centre(target), target.global_position, frozen, drenched)
	target.take_damage(damage, ability.damage_type, true)
	if target.stance:
		target.stance.apply_attack_stance_damage(damage, ability.damage_type)
	EventBus.damage_dealt.emit(_player, target, damage, ability.damage_type, false, crit)
	ability.apply_statuses(target, _player, damage)

## FIREBALL_COUNT fireballs fanned across the view. One that hits an Entangled
## enemy explodes: its damage again to everyone in the blast, plus Forbidden Flame.
func _elemental_fire(ability: Ability, damage_multiplier: float) -> void:
	var forward := -_player.camera.global_transform.basis.z
	var origin := _player.camera.global_position + forward * 0.8 + Vector3.DOWN * 0.3
	var scene := _player.get_tree().current_scene
	for i in FIREBALL_COUNT:
		var offset := deg_to_rad(FIREBALL_CONE_DEG) * (float(i) / float(FIREBALL_COUNT - 1) - 0.5)
		var dir := forward.rotated(Vector3.UP, offset)
		var hit := ability.roll_damage(_player.stat_sheet)
		var ball: Projectile = ARKANUS_FIREBALL_SCENE.instantiate()
		ball.damage_amount = hit["final_damage"] * damage_multiplier
		ball.is_critical = hit["is_critical"]
		ball.crit_multiplier = hit["crit_multiplier"]
		ball.damage_type = Constants.DamageType.FIRE
		ball.source = _player
		ball.speed = FIREBALL_SPEED
		ball.lifetime = FIREBALL_LIFETIME
		ball.is_spell_projectile = true
		ball.on_hit = func(enemy: Enemy, amount: float): _fireball_hit(ability, enemy, amount)
		scene.add_child(ball)
		ball.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), origin)
		ArkanusFx.dress_fireball(ball)
	ArkanusFx.fire_cast(scene, origin, forward)

func _fireball_hit(ability: Ability, enemy: Enemy, amount: float) -> void:
	if not is_instance_valid(enemy):
		return
	var scene := _player.get_tree().current_scene
	var centre := _body_centre(enemy)
	ArkanusFx.fireball_hit(scene, centre)
	ability.apply_statuses(enemy, _player, amount)
	if not enemy.status_effects.has_effect("entangle"):
		return
	var radius := ability.get_radius(_player.stat_sheet)
	ArkanusFx.forbidden_blast(scene, centre, enemy.global_position, radius)
	for other in _enemies_by_distance(enemy.global_position, radius):
		other.take_damage(amount, Constants.DamageType.FIRE, true)
		EventBus.damage_dealt.emit(_player, other, amount, Constants.DamageType.FIRE, false, false)
		other.status_effects.apply_forbidden_flame(_player, amount * ForbiddenFire.DAMAGE_SHARE, ForbiddenFire.DURATION)
		ArkanusFx.enemy_flame(other, ForbiddenFire.DURATION)

## A cold nova around you: hits, Chills and Drenches; with Stone Skin it also
## Entangles everything it reaches.
func _elemental_water(ability: Ability, damage_multiplier: float) -> void:
	var radius := ability.get_radius(_player.stat_sheet)
	var centre := _player.global_position
	var scene := _player.get_tree().current_scene
	var entangle := _player.status_effects.has_effect("stone_skin")
	ArkanusFx.water(scene, centre, radius, entangle)
	for enemy in _enemies_by_distance(centre, radius):
		_hit_enemy(ability, enemy, damage_multiplier, true, Callable())
		enemy.status_effects.apply_timed_effect("drenched", DRENCH_SECONDS)
		ArkanusFx.drench(enemy, DRENCH_SECONDS)
		if entangle:
			enemy.status_effects.apply_timed_effect("entangle", WATER_ENTANGLE_SECONDS)
			AureliaRoots.bind(enemy, WATER_ENTANGLE_SECONDS)

## Detonates on the enemy at the crosshair: AETHER_MORE_PER_ELEMENT more
## damage for each ELEMENT_GROUPS entry on it. Nothing is consumed.
func _elemental_aether(ability: Ability, damage_multiplier: float) -> void:
	var target := _crosshair_enemy()
	if target == null:
		return
	var elements := element_count(target)
	var hit := ability.roll_damage(_player.stat_sheet)
	var damage: float = hit["final_damage"] * damage_multiplier * (1.0 + AETHER_MORE_PER_ELEMENT * elements)
	ArkanusFx.aether(_player.get_tree().current_scene, _body_centre(target), target.global_position, elements)
	target.take_damage(damage, ability.damage_type, true)
	if target.stance:
		target.stance.apply_attack_stance_damage(damage, ability.damage_type)
	EventBus.damage_dealt.emit(_player, target, damage, ability.damage_type, false, hit["is_critical"])

## How many of ELEMENT_GROUPS the enemy carries.
static func element_count(enemy: Enemy) -> int:
	var count := 0
	for group in ELEMENT_GROUPS:
		if group.any(func(id: String) -> bool: return enemy.status_effects.has_effect(id)):
			count += 1
	return count

## Stone Skin for STONE_SKIN_SECONDS (Player reads it in _take_damage_single()).
func _elemental_earth() -> void:
	_player.status_effects.apply_timed_effect("stone_skin", STONE_SKIN_SECONDS)
	ArkanusFx.stone_skin(_player, STONE_SKIN_SECONDS)

## ---- Thunderstorm, Inner Power, Charged Reflexes, Manasaber, Puncture, Arach

## Switched on by casting and off by casting again (free), like Booming Blade.
const TOGGLE_SPELLS := ["thunderstorm", "inner_power", "charged_reflexes", "triangulation", "dark_arts", "enchantment"]

## Thunderstorm: every STORM_INTERVAL, a bolt strikes each enemy within its
## radius, and each round drains STORM_DRAIN of its Mana cost (it stops when
## Mana runs short). Enemies inside are kept Drenched.
const STORM_INTERVAL := 2.0
const STORM_DRAIN := 0.4
const STORM_DRENCH_PULSE := 0.5
const STORM_BOLT_HEIGHT := 9.0
## Web: Storm Front strikes this much more often.
const STORM_FRONT_INTERVAL := 0.75
var _storm_timer: float = 0.0
var _storm_drench_timer: float = 0.0

## Inner Power: Life regenerates this many times Mana's regeneration
## (Player._apply_derived_stats()); StatSheet.inner_power_multiplier() does
## the damage side.
const INNER_POWER_LIFE_SHARE := 2.0

## Charged Reflexes: ranged attack speed and reload speed multipliers while
## on; each shot drains this share of its Mana cost.
const CHARGED_REFLEXES_FIRE_RATE := 1.3
const CHARGED_REFLEXES_RELOAD := 1.4
const CHARGED_REFLEXES_SHOT_DRAIN := 0.15

## Manasaber: costs this share of maximum Mana and sweeps a cone ahead for
## MANASABER_DAMAGE x the Mana spent, as the spell's base damage.
const MANASABER_SHARE := 0.4
const MANASABER_DAMAGE := 2.5
const MANASABER_HALF_ANGLE := 70.0
## Each hit also adds this much of the main-hand weapon's hit (its full
## attack scaling, rolled as Aetheric). The slash plays on the viewmodel.
const MANASABER_WEAPON_DAMAGE := 1.2
const MANASABER_SLASH_STRIKE := 0.18
const MANASABER_SLASH_RECOVERY := 0.3
var _manasaber_spent: float = 0.0

## The Manasaber ribbon trailing the weapon: Aetheric, bright enough to bloom.
static func manasaber_trail_color() -> Color:
	var c: Color = Constants.DAMAGE_TYPE_COLOR[Constants.DamageType.AETHERIC]
	return Color(c.r * 1.3, c.g * 2.2, c.b * 2.4, 1.0)

## The main-hand weapon as an Aetheric copy, or null when there's nothing
## that attacks in hand.
func manasaber_weapon() -> Weapon:
	var weapon := _player.get_active_weapon()
	if weapon == null or not weapon.can_attack():
		return null
	var copy := weapon.duplicate() as Weapon
	copy.infused_damage_type = Constants.DamageType.AETHERIC
	return copy

## Puncture: stabs the nearest enemy within its reach and this cone, and
## leaves it Punctured (StatusEffectComponent.PUNCTURED_BLEED_TAKEN).
const PUNCTURE_CONE_DEG := 35.0
const PUNCTURE_DURATION := 6.0

## Invocation of Arach: the mark lasts ARACH_MARK_DURATION; with the spell
## prepared, a hit on a boss, an Ascendant or a marked enemy has
## ARACH_HIT_CHANCE to bring a spider (at most once per ARACH_HIT_COOLDOWN).
const ARACH_MARK_DURATION := 8.0
const ARACH_HIT_CHANCE := 0.1
const ARACH_HIT_COOLDOWN := 0.5
var _arach_cd: float = 0.0

static func manasaber_cost(max_mana: float) -> float:
	return max_mana * MANASABER_SHARE

## Webs: Focused Mind (3x), Overclock (+45%, double drain), Steady Hands (+70%).
const FOCUSED_MIND_LIFE_SHARE := 3.0
const OVERCLOCK_FIRE_RATE := 1.45
const STEADY_HANDS_RELOAD := 1.7

func _twist(ability_id: String, twist: String) -> bool:
	var a := _resolve_ability_by_id(ability_id)
	return a != null and a.has_twist(twist)

func inner_power_life_share() -> float:
	return FOCUSED_MIND_LIFE_SHARE if _twist("inner_power", "focused_mind") else INNER_POWER_LIFE_SHARE

func charged_reflexes_fire_rate() -> float:
	return OVERCLOCK_FIRE_RATE if _twist("charged_reflexes", "overclock") else CHARGED_REFLEXES_FIRE_RATE

func charged_reflexes_reload() -> float:
	return STEADY_HANDS_RELOAD if _twist("charged_reflexes", "steady_hands") else CHARGED_REFLEXES_RELOAD

func _set_toggle(id: String, on: bool) -> void:
	if on and not GameState.toggled_spells.has(id):
		GameState.toggled_spells.append(id)
		if id == "thunderstorm":
			_storm_timer = 0.3  # the first strike comes almost at once
	elif not on:
		GameState.toggled_spells.erase(id)
	if id == "inner_power":
		_player._apply_derived_stats()

## On the spell bar or the stance page.
func is_prepared(ability_id: String) -> bool:
	for i in AbilityLoadoutComponent.SLOT_COUNT:
		for a in [_player.ability_loadout.get_equipped(i), _player.ability_loadout.get_page2(i)]:
			if a and a.ability_id == ability_id:
				return true
	return false

func _tick_toggles(delta: float) -> void:
	_arach_cd = maxf(_arach_cd - delta, 0.0)
	# A toggle taken off the bar switches off.
	for id in GameState.toggled_spells.duplicate():
		if not is_prepared(id):
			_set_toggle(id, false)
	var sheet := _player.stat_sheet
	sheet.no_physical_damage = is_prepared("inner_power")
	sheet.inner_power_on = GameState.toggled_spells.has("inner_power")
	var inner := _resolve_ability_by_id("inner_power")
	sheet.inner_power_more = StatSheet.INNER_POWER_AETHERIC_MORE * (2.0 if inner and inner.has_twist("still_waters") else 1.0)
	_tick_resist_and_enchant(delta)
	_tick_thunderstorm(delta)

func _tick_thunderstorm(delta: float) -> void:
	if not GameState.toggled_spells.has("thunderstorm"):
		return
	var ability := _resolve_ability_by_id("thunderstorm")
	if ability == null:
		return
	var radius := ability.get_radius(_player.stat_sheet)
	_update_aura_ring(ability)
	_storm_drench_timer -= delta
	if _storm_drench_timer <= 0.0:
		_storm_drench_timer = STORM_DRENCH_PULSE
		for enemy in _enemies_near(_player.global_position, radius):
			enemy.status_effects.apply_timed_effect("drenched", STORM_DRENCH_PULSE + 0.5)
	_storm_timer -= delta
	if _storm_timer > 0.0:
		return
	_storm_timer = STORM_INTERVAL * (STORM_FRONT_INTERVAL if ability.has_twist("storm_front") else 1.0)
	var drain := ability.get_mana_cost(_player.stat_sheet) * STORM_DRAIN
	if _player.mana.current_mana < drain:
		_set_toggle("thunderstorm", false)
		EventBus.ability_cast_failed.emit(_player, ability, "Not enough Mana")
		return
	_player.mana.spend(drain)
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	var scene := _player.get_tree().current_scene
	for enemy in _enemies_near(_player.global_position, radius):
		var top := enemy.global_position + Vector3(randf_range(-1.5, 1.5), STORM_BOLT_HEIGHT, randf_range(-1.5, 1.5))
		LightningArc.spawn(scene, top, enemy.global_position + Vector3.UP * 0.2, color)
		SpellFx.light_pop(scene, enemy.global_position + Vector3.UP, color, 2.5, 5.0, 0.2)
		_hit_enemy(ability, enemy, 1.0, true, Callable())

## Called by PlayerRangedAttack for every shot or throw.
func on_ranged_shot() -> void:
	if not GameState.toggled_spells.has("charged_reflexes"):
		return
	var ability := _resolve_ability_by_id("charged_reflexes")
	if ability == null:
		return
	var drain := ability.get_mana_cost(_player.stat_sheet) * CHARGED_REFLEXES_SHOT_DRAIN * (2.0 if ability.has_twist("overclock") else 1.0)
	if _player.mana.current_mana < drain:
		_set_toggle("charged_reflexes", false)
		EventBus.ability_cast_failed.emit(_player, ability, "Not enough Mana")
		return
	_player.mana.spend(drain)

## An Aetheric blade sweeping the cone ahead. Its base hit is the Mana spent
## on the cast times MANASABER_DAMAGE, then every spell modifier and crit.
func _cast_manasaber(ability: Ability, damage_multiplier: float, apply_composure: bool) -> void:
	var sheet := _player.stat_sheet
	var spent := _manasaber_spent if _manasaber_spent > 0.0 else manasaber_cost(_player.mana.max_mana)
	var radius := ability.get_radius(sheet)
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else -_player.global_transform.basis.z
	forward = forward.rotated(Vector3.UP, deg_to_rad(_aim_yaw_offset))
	var origin := _player.global_position
	var blade := manasaber_weapon()
	if _saber_return and _player.arm_rig:
		_player.arm_rig.play_slash(0.0, MANASABER_SLASH_STRIKE, MANASABER_SLASH_RECOVERY, true, manasaber_trail_color())
	for enemy in _enemies_near(origin, radius):
		var to_enemy := enemy.global_position - origin
		to_enemy.y = 0.0
		if to_enemy.length() > 0.5 and rad_to_deg(forward.angle_to(to_enemy.normalized())) > MANASABER_HALF_ANGLE:
			continue
		var hit := ability._base_hit(spent * MANASABER_DAMAGE, sheet)
		var rolled := DamageCalculator.apply_crit(hit["base_damage"], hit["crit_chance"], hit["crit_damage_multiplier"])
		var crit: bool = rolled["is_critical"]
		var total := float(rolled["final_damage"])
		# Plus MANASABER_WEAPON_DAMAGE of the main-hand weapon's hit, as Aetheric.
		if blade:
			var weapon_hit := blade.roll_damage(MANASABER_WEAPON_DAMAGE, sheet)
			total += float(weapon_hit["final_damage"])
			crit = crit or weapon_hit["is_critical"]
		var damage: float = total * damage_multiplier
		enemy.take_damage(damage, ability.damage_type)
		if apply_composure and enemy.stance:
			enemy.stance.apply_attack_stance_damage(damage, ability.damage_type)
		EventBus.damage_dealt.emit(_player, enemy, damage, ability.damage_type, false, crit)
	var scene := _player.get_tree().current_scene
	var tint: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE).lightened(0.35)
	SpellFx.light_pop(scene, origin + forward * radius * 0.6 + Vector3.UP, tint, 3.0, radius * 1.4, 0.3)
	# Web: Twin Blade sweeps back for half damage (the return doesn't repeat).
	if ability.has_twist("twin_blade") and not _saber_return:
		var spent_now := spent
		get_tree().create_timer(REAP_SECOND_SWING_DELAY, false).timeout.connect(func():
			if is_instance_valid(_player):
				_saber_return = true
				_manasaber_spent = spent_now
				_cast_manasaber(ability, damage_multiplier * 0.5, apply_composure)
				_saber_return = false)

var _saber_return := false

func _cast_puncture(ability: Ability, damage_multiplier: float, apply_composure: bool) -> void:
	var origin := _player.global_position
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else -_player.global_transform.basis.z
	var reach := ability.get_radius(_player.stat_sheet)
	# Web: Skewer runs through a second enemy.
	var wanted := 2 if ability.has_twist("skewer") else 1
	var targets: Array[Enemy] = []
	for enemy in _enemies_by_distance(origin, reach):
		var to_enemy := enemy.global_position - origin
		to_enemy.y = 0.0
		if to_enemy.length() < 0.5 or rad_to_deg(forward.angle_to(to_enemy.normalized())) <= PUNCTURE_CONE_DEG:
			targets.append(enemy)
			if targets.size() >= wanted:
				break
	var scene := _player.get_tree().current_scene
	var tip := origin + forward * reach * 0.8 + Vector3.UP
	for target in targets:
		tip = _body_centre(target)
		_hit_enemy(ability, target, damage_multiplier, apply_composure, Callable())
		target.status_effects.apply_timed_effect("punctured", PUNCTURE_DURATION * ability.get_duration_multiplier(_player.stat_sheet))
	var start := _player.camera.global_transform * Vector3(0.2, -0.3, -0.5)
	SpellFx.flash(scene, tip, Color(1.3, 1.2, 1.1), 0.6, 0.15)
	SpellFx.burst(scene, tip, Color(0.7, 0.15, 0.12), 14, Vector2(1.5, 3.5), 0.35, Vector2(0.05, 0.1), 60.0, -6.0)
	_puncture_spike(start, tip)

## A pale spike lancing from the hand to the point struck, gone in a blink.
func _puncture_spike(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var spike := MeshInstance3D.new()
	var prism := CylinderMesh.new()
	prism.top_radius = 0.0
	prism.bottom_radius = 0.05
	prism.height = length
	prism.radial_segments = 6
	spike.mesh = prism
	spike.material_override = SpellFx.energy_material(Color(0.95, 0.9, 0.85), 1.2, 0.2, true)
	spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player.get_tree().current_scene.add_child(spike)
	var dir := (to - from) / length
	var side := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	# The cylinder's axis is +Y; it points tip-first along dir.
	var basis := Basis.looking_at(dir, side) * Basis(Vector3.RIGHT, -PI * 0.5)
	spike.global_transform = Transform3D(basis, (from + to) * 0.5)
	var tween := spike.create_tween()
	tween.tween_property(spike, "scale", Vector3(0.1, 1.0, 0.1), 0.18).set_delay(0.06)
	tween.tween_callback(spike.queue_free)

func _cast_arach(ability: Ability) -> void:
	var target := _crosshair_enemy()
	if target == null:
		return
	target.status_effects.apply_timed_effect("arach_mark", ARACH_MARK_DURATION * ability.get_duration_multiplier(_player.stat_sheet))
	_flash_ring(target.global_position, 1.2, ability)

func _summon_spider(at: Vector3) -> void:
	var ability := _resolve_ability_by_id("invocation_of_arach")
	if ability:
		SpiderMinion.summon(_player.get_tree().current_scene, _player, ability, at)

func _on_damage_dealt(source: Node, target: Node, _amount: float, _type: int, _riposte: bool, _crit: bool) -> void:
	if source != _player or _arach_cd > 0.0 or StatusEffectComponent.emitting_dot:
		return
	var enemy := target as Enemy
	if enemy == null or enemy.status_effects == null:
		return
	var big := enemy.rank == Constants.EnemyRank.BOSS or (enemy.rarity_component != null and enemy.rarity_component.rarity == Constants.EnemyRarity.ASCENDANT)
	if not big and not enemy.status_effects.has_effect("arach_mark"):
		return
	if not is_prepared("invocation_of_arach"):
		return
	_arach_cd = ARACH_HIT_COOLDOWN
	if randf() < ARACH_HIT_CHANCE:
		_summon_spider(enemy.global_position)

## ---- Blizzard, Triangulation, Dark Arts, Enchantment

## Blizzard: icicles fall on random enemies inside it every
## BlizzardField.ICICLE_INTERVAL for BlizzardField.DURATION; up to its limit at once.
const BLIZZARD_WHITEOUT_RADIUS := 1.5
const BLIZZARD_WHITEOUT_CHILL := 2.0

func _cast_blizzard(ability: Ability, cast_position: Vector3, damage_multiplier: float, apply_composure: bool) -> void:
	var limit := ability.get_limit(_player.stat_sheet)
	_make_room_for(ability, limit)
	var field := BlizzardField.new()
	_player.get_tree().current_scene.add_child(field)
	field.add_to_group(_limit_group(ability))
	field.global_position = cast_position
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	field.play(ability.get_radius(_player.stat_sheet), BlizzardField.DURATION * ability.get_duration_multiplier(_player.stat_sheet), color,
		func(enemy: Enemy) -> void:
			if not is_instance_valid(_player):
				return
			var at := enemy.global_position
			_hit_enemy(ability, enemy, damage_multiplier, apply_composure, Callable())
			# Web: Whiteout chills around each landing.
			if ability.has_twist("whiteout"):
				for near in _enemies_near(at, BLIZZARD_WHITEOUT_RADIUS):
					near.status_effects.apply_timed_effect("chill", BLIZZARD_WHITEOUT_CHILL))

## Triangulation / Dark Arts: while on, +Resistance (RESIST_SPELL_BASE, +
## RESIST_SPELL_PER_LEVEL per spell level past 1) to the Elemental or the
## Esoteric Resistances, and their web's MAX_RESISTANCE nodes raise the
## maximum. Enchantment: while on, every hit you deal adds flat Fire damage
## (ENCHANT_FLAT at level 1, growing like spell damage). Each drains
## TOGGLE_SPELL_DRAIN of maximum Mana per second (scaled by Mana cost
## reduction) and switches off when Mana can't pay.
const RESIST_SPELL_BASE := 15.0
const RESIST_SPELL_PER_LEVEL := 1.0
const TOGGLE_SPELL_DRAIN := 0.04
const RESIST_SPELLS := {"triangulation": ["fire", "cold", "lightning"], "dark_arts": ["esoteric"]}
const ENCHANT_FLAT := Vector2(5.0, 9.0)
## Twist id -> the element half of Enchantment's damage becomes.
const ENCHANT_SPLITS := {"frost_enchant": Constants.DamageType.COLD, "storm_enchant": Constants.DamageType.LIGHTNING}
var _enchanting := false

static func resist_spell_amount(ability: Ability, stat_sheet: StatSheet) -> float:
	return RESIST_SPELL_BASE + RESIST_SPELL_PER_LEVEL * (ability.get_effective_level(stat_sheet) - 1)

static func toggle_spell_drain_per_second(ability: Ability, max_mana: float, stat_sheet: StatSheet) -> float:
	return max_mana * TOGGLE_SPELL_DRAIN * ability.get_mana_cost_multiplier(stat_sheet)

func _tick_resist_and_enchant(delta: float) -> void:
	var sheet := _player.stat_sheet
	var res := {}
	var max_res := {}
	for id in ["triangulation", "dark_arts", "enchantment"]:
		if not GameState.toggled_spells.has(id):
			continue
		var ability := _resolve_ability_by_id(id)
		if ability == null:
			continue
		var drain := toggle_spell_drain_per_second(ability, _player.mana.max_mana, sheet) * delta
		if _player.mana.current_mana < drain:
			_set_toggle(id, false)
			EventBus.ability_cast_failed.emit(_player, ability, "Not enough Mana")
			continue
		_player.mana.spend(drain)
		for key in RESIST_SPELLS.get(id, []):
			res[key] = res.get(key, 0.0) + resist_spell_amount(ability, sheet)
			max_res[key] = max_res.get(key, 0.0) + ability.web_value(SkillWeb.MAX_RESISTANCE)
	sheet.spell_resistance = res
	sheet.spell_max_resistance = max_res

## Enchantment's added damage per hit at its level: [min, max].
static func enchant_range(ability: Ability, stat_sheet: StatSheet) -> Vector2:
	return ENCHANT_FLAT * Ability.level_growth(ability.get_effective_level(stat_sheet))

## Enchantment: an extra hit of its flat damage on each of your hits (not
## damage over time), scaled by your increased damage of that element.
func _on_enchanted_hit(source: Node, target: Node, _amount: float, _type: int, _riposte: bool, _crit: bool) -> void:
	if _enchanting or source != _player or StatusEffectComponent.emitting_dot or not GameState.toggled_spells.has("enchantment"):
		return
	var enemy := target as Enemy
	if enemy == null or not enemy.health.is_alive():
		return
	var ability := _resolve_ability_by_id("enchantment")
	if ability == null:
		return
	var sheet := _player.stat_sheet
	var r := enchant_range(ability, sheet)
	var flat := randf_range(r.x, r.y)
	var parts := {Constants.DamageType.FIRE: flat}
	for twist in ENCHANT_SPLITS:
		if ability.has_twist(twist):
			parts = {Constants.DamageType.FIRE: flat * 0.5, ENCHANT_SPLITS[twist]: flat * 0.5}
	_enchanting = true
	for type in parts:
		var dmg: float = parts[type] * (1.0 + sheet.get_increased_damage_percent(type, false) / 100.0) * sheet.outgoing_more_multiplier(type)
		enemy.take_damage(dmg, type)
	_enchanting = false

## Black Hole: projectiles it swallowed, fired back out as a nova when it
## collapses, each a Black Hole hit times BLACK_HOLE_NOVA_DAMAGE.
const BLACK_HOLE_NOVA_DAMAGE := 3.0
const BLACK_HOLE_NOVA_SPEED := 18.0
const BLACK_HOLE_NOVA_SCENE := preload("res://entities/projectile/Projectile.tscn")

func black_hole_nova(ability: Ability, centre: Vector3, count: int) -> void:
	if not is_instance_valid(_player) or count <= 0:
		return
	var scene := _player.get_tree().current_scene
	var offset := randf() * TAU
	for i in count:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, offset + TAU * i / count)
		var hit := ability.roll_damage(_player.stat_sheet)
		var shot: Projectile = BLACK_HOLE_NOVA_SCENE.instantiate()
		shot.damage_amount = hit["final_damage"] * BLACK_HOLE_NOVA_DAMAGE
		shot.is_critical = hit["is_critical"]
		shot.crit_multiplier = hit["crit_multiplier"]
		shot.damage_type = ability.damage_type
		shot.source = _player
		shot.speed = BLACK_HOLE_NOVA_SPEED
		shot.lifetime = 1.2
		shot.is_spell_projectile = true
		shot.set_meta(&"black_hole_nova", true)
		scene.add_child(shot)
		shot.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), centre)

## ---- Skills

## A Skill's windup and hit share of its weapon swing; the rest is recovery.
const SKILL_WINDUP_SHARE := 0.5
const SKILL_STRIKE_SHARE := 0.12

## Seconds for one swing of the main-hand weapon after attack speed, times
## the Skill's attack_time_multiplier.
func skill_swing_time(ability: Ability) -> float:
	var weapon := _player.get_active_weapon()
	if weapon == null:
		return 0.0
	return PlayerMeleeAttack.swing_seconds(weapon.weapon_type) / maxf(_player.get_attack_speed_multiplier(weapon), 0.01) * ability.attack_time_multiplier

## Times the Skill's cast to land at the strike of the weapon's swing, and plays it.
func _begin_skill_swing(ability: Ability) -> void:
	var total := skill_swing_time(ability)
	ability.skill_cast_time = total * (SKILL_WINDUP_SHARE + SKILL_STRIKE_SHARE)
	if _player.arm_rig:
		_player.arm_rig.play_attack(PlayerArmRig.Attack.LIGHT, total * SKILL_WINDUP_SHARE, total * SKILL_STRIKE_SHARE, total * (1.0 - SKILL_WINDUP_SHARE - SKILL_STRIKE_SHARE))
