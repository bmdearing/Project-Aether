extends Node
class_name PlayerAbilityCast
## Casts AbilityLoadoutComponent's equipped abilities on ability_1..4
## input, checking/consuming ManaComponent + cooldown per Ability.
##
## Most abilities cast instantly at the player's own position (a self-
## centered nova) on press. Several (Ability.is_ground_targeted) instead
## enter a hold-to-aim mode: holding the key shows a ground ring following
## a raycast from the camera, and releasing casts centered on that point
## instead. Only one targeting session can be active at a time - a second
## targeted key pressed mid-aim is ignored until the first is released.
##
## Execution is otherwise deliberately generic for every ability: consume
## resource_cost, start cooldown, deal damage to every Enemy within the
## ability's own radius of the cast point, then apply Ability.
## applies_status_effects (Section 09, via StatusEffectComponent) to each
## hit. Not each ability's actual described mechanic (Comet/Winter's Eye/
## Frost Armor are distinct real mechanics) - a first pass so the ability
## bar's readouts aren't inert UI. Three abilities break this generic
## shape outright: Blink/Purge deal no damage at all (see _cast()'s early
## returns), and Black Hole/Caltrops layer extra behavior on top via their
## own effect scenes (BlackHoleField/CaltropsField) rather than anything
## this script does directly.

const RANGE_EFFECT_SCENE := preload("res://entities/effects/ability_range_effect/AbilityRangeEffect.tscn")
const MAX_TARGET_RANGE := 30.0
const RETICLE_HEIGHT_OFFSET := 0.05
const FLAME_WALL_RETICLE_HEIGHT := 0.05  # flat ground-plan slab, not the real wall's WALL_HEIGHT

## Ground-targeted abilities with a bespoke cast VFX instead of the
## generic ring - everything else still just uses RANGE_EFFECT_SCENE.
## Meteor ("26 - Ability Staging Ground": "descends from above, crashing
## into a targeted area") reuses Comet's own fall-and-impact VFX outright -
## same mechanic, just a different damage type/color, not worth a second
## near-identical scene.
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

## Spark ("creates 3 lightning projectiles that crawl the ground and
## search for enemies", user request 2026-08-30) - spawned directly by
## _fire_spark() below rather than through SPECIAL_EFFECT_SCENES/
## _play_range_effect(), since it's 3 independently-moving crawlers, not
## one VFX instance at a fixed cast point.
const SPARK_CRAWLER_SCENE := preload("res://entities/effects/spark_crawler/SparkCrawler.tscn")
const SPARK_COUNT := 3
const SPARK_SPREAD_DEG := 25.0


const BLINK_DISTANCE := 8.0
const PIERCING_BOLT_SCENE := preload("res://entities/effects/piercing_bolt/PiercingBolt.tscn")
## User request (2026-08-30): "Cinder Lance should throw a spear of fire
## at a crosshair, this should pierce" / "Thunder Javelin should work
## like Cinder Lance." Both replaced by PIERCING_BOLT_SCENE - a real
## traveling bolt (see that scene's own header) instead of the generic
## instant-AoE-at-cast-point every other first-pass ability still uses.
const PIERCING_BOLT_ABILITY_IDS := ["cinder_lance", "thunder_javelin"]
const THUNDER_SWEEP_BOLT_COUNT := 8
## Thunder Javelin is the fast one ("Fast, piercing projectile").
const BOLT_SPEEDS := {"cinder_lance": 22.0, "thunder_javelin": 42.0, "thunder_sweep": 18.0}

## Frost Armor ("A layer of frozen energy coats the Freeblood. Enemies
## that strike in melee range trigger a Retaliation Damage burst of Cold
## damage. Applies Chill on retaliation hit.") - a pure self-buff at cast
## time (no AoE hit on cast, same as Blink/Purge skip the generic loop),
## a fixed duration window during which EnemyMeleeAttack._resolve_hit()
## (the exact point a melee hit lands on the player) calls
## trigger_frost_armor_retaliation() back here. User-reported bug fix
## (2026-08-30): "Frost Armor doesn't properly deal cold retaliation
## damage to enemies when they melee attack the player" - it never had
## any retaliation mechanic at all before this, just the generic instant-
## AoE-at-cast-point every other first-pass ability used.
const FROST_ARMOR_DURATION := 8.0  # invented, no doc-given buff duration

const FROST_ARMOR_BURST_COOLDOWN := 0.5  # a pack hitting at once triggers one burst, not one each
const FROST_SHARD_COUNT := 6
const FROST_SHARD_SPIN := 1.6

var _frost_armor_ability: Ability = null
var _frost_armor_remaining: float = 0.0
var _frost_armor_burst_cd: float = 0.0
var _frost_armor_fx: Node3D

## Flame Jets ("flamethrower type spell, slowing the character down and
## throwing flames at what the player is looking at" - user request,
## 2026-08-30). Re-aims at the camera's CURRENT forward direction every
## tick rather than locking direction at cast time - "what the player is
## looking at" reads as continuous, not a single snapshot. Player.
## _effective_speed() reads get_move_speed_multiplier() below every
## physics frame while this is active, same pattern PlayerMeleeAttack's
## own attack-speed penalty already follows.
##
## Patch v3.8b: reworked into a real hold-to-channel spell. resource_cost/
## cooldown still spend/start once at press (same economy every other
## ability uses), but the channel itself now also drains Mana continuously
## (CHANNEL_MANA_DRAIN_PERCENT of resource_cost every CHANNEL_MANA_DRAIN_
## INTERVAL) and cuts off the instant the ability_N key releases or Mana
## hits 0 - no grace tick either way. FLAME_JETS_DURATION is now a hard
## cap (a held key can't channel forever), not the sole end condition.
## Flame Jets is the only CHANNELED-cast_type ability in the project right
## now, so this stays flame_jets-specific rather than a generic system -
## CastTimeHandler.gd already fires CHANNELED abilities' _cast() the same
## instant as INSTANT ones (no windup to interrupt), so "not interruptible
## by damage" needs no separate change here.
const FLAME_JETS_DURATION := 1.8
const FLAME_JETS_TICK_INTERVAL := 0.15
const FLAME_JETS_TICK_DAMAGE_PERCENT := 0.25
const FLAME_JETS_RANGE := 6.0
const FLAME_JETS_HALF_ANGLE_DEG := 20.0
const FLAME_JETS_MOVE_SPEED_MULTIPLIER := 0.4
const CHANNEL_MANA_DRAIN_INTERVAL := 0.15
const CHANNEL_MANA_DRAIN_PERCENT := 0.08

var _flame_jets_ability: Ability = null
var _flame_jets_remaining: float = 0.0
var _flame_jets_tick_timer: float = 0.0
var _flame_jets_drain_timer: float = 0.0
var _flame_jets_input_action: String = ""
## false for a Slate auto-cast (The Unbound Chorus etc. - EXPLICITLY "no
## resource cost", never calls ManaComponent.spend()) - the hold-to-
## channel key check and continuous Mana drain below only apply to a real
## player-held cast, or auto-cast Flame Jets would either drain Mana it's
## documented never to cost, or get cut off instantly since no key is
## actually being held for it.
var _flame_jets_is_manual: bool = false
var _flame_jets_fx: CPUParticles3D

var _cooldowns: Dictionary = {}  # Ability -> float seconds remaining
var _player: Player
var _targeting_slot: int = -1
var _reticle: MeshInstance3D
## ability_id -> Ability, lazily scanned from data/abilities/instances/ -
## same dir-scan AbilitiesScreen._scan_owned_abilities() already does, kept
## here too since Slate-designated abilities (see below) aren't necessarily
## in the 4-slot hotbar AbilityLoadoutComponent tracks.
var _ability_by_id_cache: Dictionary = {}

func _ready() -> void:
	_player = get_parent()

func _physics_process(delta: float) -> void:
	if _flame_jets_fx:
		_flame_jets_fx.emitting = _flame_jets_remaining > 0.0
	for ability in _cooldowns.keys():
		_cooldowns[ability] = max(0.0, _cooldowns[ability] - delta)
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

func get_cooldown_remaining(ability: Ability) -> float:
	return _cooldowns.get(ability, 0.0) if ability else 0.0

func _on_ability_pressed(slot_index: int) -> void:
	var ability: Ability = _player.ability_loadout.get_equipped(slot_index)
	if ability == null:
		return
	if ability.is_ground_targeted:
		if _targeting_slot != -1:
			return
		_targeting_slot = slot_index
		_show_reticle(ability)
	else:
		_try_cast(slot_index, _player.global_position)

func _release_targeted_cast() -> void:
	var slot_index := _targeting_slot
	_targeting_slot = -1
	_hide_reticle()
	_try_cast(slot_index, _get_ground_target_point())

## Mana/cooldown are checked here, not when targeting starts - a targeted
## cast only spends/starts cooldown on an actual release, same as an
## instant cast only ever fires once, at the moment its checks pass.
func _try_cast(slot_index: int, cast_position: Vector3) -> void:
	var ability: Ability = _player.ability_loadout.get_equipped(slot_index)
	if ability == null:
		return
	if get_cooldown_remaining(ability) > 0.0:
		EventBus.ability_cast_failed.emit(_player, ability, "On cooldown")
		return
	if ability.ability_id == "tornado" and get_tree().get_nodes_in_group("tornado_field").size() >= ability.get_limit(_player.stat_sheet):
		EventBus.ability_cast_failed.emit(_player, ability, "Limit reached")
		return
	if _player.mana.current_mana < ability.get_mana_cost(_player.stat_sheet):
		EventBus.ability_cast_failed.emit(_player, ability, "Not enough Mana")
		return
	# Patch v4.3: CastTimeHandler.try_cast() refuses while a cast is winding
	# up - which used to happen AFTER mana was spent and the cooldown started,
	# silently eating both.
	if _player.cast_time_handler.is_casting():
		EventBus.ability_cast_failed.emit(_player, ability, "Already casting")
		return
	_player.mana.spend(ability.get_mana_cost(_player.stat_sheet))
	if ability.ability_id == "flame_jets":
		_flame_jets_input_action = "ability_%d" % (slot_index + 1)
		_flame_jets_is_manual = true
	# Section 12: Instinct -> "+1% Attack/Cast speed per point" - divides
	# the authored cooldown, same treatment PlayerMeleeAttack/
	# PlayerRangedAttack give their own timings. get_final_cooldown() caps
	# the combined reduction at Constants.MAX_COOLDOWN_REDUCTION.
	_cooldowns[ability] = ability.get_final_cooldown(_player.get_action_speed_multiplier(), _player.stat_sheet)
	# Patch v3.7 Section 2: routes through CastTimeHandler - INSTANT/
	# CHANNELED abilities call _cast() back immediately (synchronously,
	# via _on_cast_time_completed below), CAST_TIME ones only after their
	# windup finishes (or not at all if interrupted by taking damage).
	_player.cast_time_handler.try_cast(ability, cast_position)

func _on_cast_time_completed(ability: Ability, cast_position: Vector3) -> void:
	_cast(ability, cast_position)

## Each enemy rolls its own crit independently (roll_damage() per-target,
## not once and reused) - a shared roll would make them all crit together.
## damage_multiplier/apply_composure exist for _auto_cast() below (Slate-
## designated auto-cast damage is reduced and doesn't apply Composure
## damage per The Unbound Chorus's own modifiers) - a real player press
## always calls this with both at their defaults.
func _cast(ability: Ability, cast_position: Vector3, damage_multiplier: float = 1.0, apply_composure: bool = true) -> void:
	# Blink/Purge ("26 - Ability Staging Ground", Utility) have "No damage
	# component" per the doc itself - the only two abilities in this
	# project that skip the generic enemy-damage loop entirely.
	if ability.ability_id == "blink":
		_flash_ring(_player.global_position, 1.4, ability)
		_perform_blink()
		_flash_ring(_player.global_position, 1.4, ability)
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
		_flame_jets_remaining = FLAME_JETS_DURATION
		_flame_jets_tick_timer = 0.0  # ticks on the very next physics frame, not after a full interval's delay
		_flame_jets_drain_timer = CHANNEL_MANA_DRAIN_INTERVAL
		_ensure_flame_jets_fx()
		_flame_jets_fx.emitting = true
		EventBus.ability_cast.emit(_player, ability)
		return
	# Black Hole ("shouldn't be a DoT, but deals Entropic damage every
	# .25 seconds", 2026-08-30) - ALL of its damage now comes from
	# BlackHoleField's own repeated ticks (see that scene's header), not
	# an instant hit here.
	if ability.ability_id == "black_hole":
		_play_range_effect(ability, cast_position)
		EventBus.ability_cast.emit(_player, ability)
		return
	if PIERCING_BOLT_ABILITY_IDS.has(ability.ability_id):
		_fire_piercing_bolt(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return
	# Thunder Sweep: "should fire out bolts of lightning along the floor
	# originating from the player" - THUNDER_SWEEP_BOLT_COUNT PiercingBolts
	# spawned radiating outward in a full circle around the player
	# (matches the doc's older "strikes all surrounding enemies" intent
	# via coverage rather than one big AoE), each flattened to travel
	# along the ground rather than following the camera's pitch.
	if ability.ability_id == "thunder_sweep":
		_fire_radiating_bolts(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return
	# Flame Wall: no instant burst on cast, per the user's own description
	# ("makes a wall of fire that ignites... and does damage over time") -
	# all its damage comes from FlameWallField's own Ignite-on-entry +
	# repeated tick, same "bespoke mechanic skips the generic loop"
	# precedent as Black Hole/Frost Armor/Blink/Purge above.
	if ability.ability_id == "flame_wall":
		_play_range_effect(ability, cast_position)
		EventBus.ability_cast.emit(_player, ability)
		return
	# Winter's Eye: the orb SPAWNS at the player and travels TOWARD
	# cast_position - doesn't fit _play_range_effect()'s generic "spawn
	# the VFX at cast_position" pattern, so it gets its own dispatch.
	if ability.ability_id == "winters_eye":
		_fire_winters_eye(ability, cast_position)
		EventBus.ability_cast.emit(_player, ability)
		return
	# Spark: 3 independently-seeking ground crawlers, not one AoE-at-a-point
	# VFX - see _fire_spark()'s own header.
	if ability.ability_id == "spark":
		_fire_spark(ability, damage_multiplier)
		EventBus.ability_cast.emit(_player, ability)
		return
	# Tornado: all damage comes from TornadoField's own repeated ticks
	# while it drifts/hunts, same "bespoke mechanic skips the generic
	# loop" precedent as Black Hole/Flame Wall above.
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
		var dist := centre.distance_to(enemy.global_position)
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
	for effect_id in ability.applies_status_effects:
		enemy.status_effects.apply_effect(effect_id, _player, damage)
	if on_hit.is_valid():
		on_hit.call(enemy)

func _enemies_by_distance(centre: Vector3, max_dist: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy and enemy.health.is_alive() and centre.distance_to(enemy.global_position) <= max_dist:
			result.append(enemy)
	result.sort_custom(func(a: Enemy, b: Enemy): return centre.distance_to(a.global_position) < centre.distance_to(b.global_position))
	return result

func _cast_stormcall(ability: Ability, centre: Vector3, damage_multiplier: float, apply_composure: bool) -> void:
	_play_range_effect(ability, centre)
	var radius := ability.get_radius(_player.stat_sheet)
	var core: Array[Enemy] = []
	var outer: Array[Enemy] = []
	for enemy in _enemies_by_distance(centre, radius):
		if centre.distance_to(enemy.global_position) <= STORMCALL_CORE_RADIUS:
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

## Section 10 Unique "The Unbound Chorus": "Designate one Spell skill -
## that skill automatically triggers when its cooldown expires." Scoped to
## exactly that one doc-sourced mechanic (auto_cast_designated_spell) for
## now - Slate.requires_spell_designation and FateBoard.PlacedSlateData.
## designated_ability_id are the general "a Slate is bound to a spell"
## framework this reads from; other interaction types (buff/retrigger/
## modify a designated spell) would need their own concrete Slate designs
## to implement against, same as this one did.
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

## Modifiers 2-4 off The Unbound Chorus specifically: 60% damage
## (auto_cast_damage_percent), no resource cost (satisfied structurally -
## this never calls ManaComponent.spend(), unlike _try_cast()), no
## Riposte window/Composure damage (apply_composure=false).
func _auto_cast(ability: Ability, slate: Slate) -> void:
	_cooldowns[ability] = ability.get_final_cooldown(_player.get_action_speed_multiplier(), _player.stat_sheet)
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

func _play_range_effect(ability: Ability, cast_position: Vector3) -> Node3D:
	var scene: PackedScene = SPECIAL_EFFECT_SCENES.get(ability.ability_id, RANGE_EFFECT_SCENE)
	var effect: Node3D = scene.instantiate()
	_player.get_tree().current_scene.add_child(effect)
	effect.global_position = cast_position
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	if ability.ability_id == "flame_wall":
		# Needs the caster's own position too, to orient the wall - see
		# FlameWallField.play()'s own comment.
		effect.call("play", ability.get_radius(_player.stat_sheet), color, ability, _player.stat_sheet, _player, _player.global_position)
	elif ability.ability_id == "caltrops" or ability.ability_id == "black_hole" or ability.ability_id == "tornado":
		# CaltropsField/BlackHoleField need the ability + StatSheet directly -
		# both roll their own damage per tick rather than reusing one hit's
		# damage repeatedly.
		effect.call("play", ability.get_radius(_player.stat_sheet), color, ability, _player.stat_sheet, _player)
	else:
		effect.call("play", ability.get_radius(_player.stat_sheet), color)
	return effect

## Called by EnemyMeleeAttack._resolve_hit() at the exact moment an enemy's
## melee strike lands on the player - "melee range" per Frost Armor's own
## doc text, not any damage the player takes. Rolls a fresh hit off the
## Ability's own scaling (same pattern every other ability's damage
## already follows) rather than a fixed number, so gear/stats still matter.
func get_move_speed_multiplier() -> float:
	return FLAME_JETS_MOVE_SPEED_MULTIPLIER if _flame_jets_remaining > 0.0 else 1.0

## Cone check via dot product against the camera's CURRENT forward
## direction (not whatever it was at cast time) - a flamethrower stream
## should track where the player is looking while it's firing.
func _tick_flame_jets() -> void:
	var origin := _player.camera.global_position
	var forward := -_player.camera.global_transform.basis.z
	var cos_half_angle := cos(deg_to_rad(FLAME_JETS_HALF_ANGLE_DEG))
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		var to_enemy: Vector3 = enemy.global_position - origin
		var dist := to_enemy.length()
		if dist > FLAME_JETS_RANGE or dist < 0.01:
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
		for effect_id in _flame_jets_ability.applies_status_effects:
			enemy.status_effects.apply_effect(effect_id, _player, damage)

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

func trigger_frost_armor_retaliation(attacker: Enemy) -> void:
	if not has_frost_armor() or _frost_armor_ability == null or attacker == null or _frost_armor_burst_cd > 0.0:
		return
	_frost_armor_burst_cd = FROST_ARMOR_BURST_COOLDOWN
	# Patch v4.0 "Increased Retaliation Damage" - the only real retaliation
	# trigger in this project right now (a general passive-block-triggers-
	# a-counterattack mechanic doesn't exist to hook "Retaliate on Passive
	# Block" into - see PATCH_NOTES.md for that gap).
	var mult := 1.0 + _player.stat_sheet.get_misc_bonus("increased_retaliation_damage") / 100.0
	# The burst hits everything within the ability's radius, and always the attacker.
	var centre := _player.global_position
	var radius := _frost_armor_ability.get_radius(_player.stat_sheet)
	_damage_area(_frost_armor_ability, centre, radius, mult, true, 0.0, Callable())
	if centre.distance_to(attacker.global_position) > radius:
		_hit_enemy(_frost_armor_ability, attacker, mult, true, Callable())
	_flash_ring(centre, radius, _frost_armor_ability)

## Fired from the camera's own forward direction ("at a crosshair") -
## not ground-targeted, no aim-hold step, matches "throw a spear ... at a
## crosshair" reading as an instant-direction throw, not a placed point.
func _fire_piercing_bolt(ability: Ability, damage_multiplier: float) -> void:
	_spawn_bolt(ability, damage_multiplier, _player.camera.global_transform)

## THUNDER_SWEEP_BOLT_COUNT bolts spawned at evenly-spaced yaw angles
## around the player, each flattened to the horizontal plane (a "ground
## bolt" shouldn't inherit the camera's up/down look pitch the way a
## crosshair-aimed bolt should).
func _fire_radiating_bolts(ability: Ability, damage_multiplier: float) -> void:
	var origin := _player.global_position + Vector3(0, 0.3, 0)
	for i in range(THUNDER_SWEEP_BOLT_COUNT):
		var angle := TAU * i / float(THUNDER_SWEEP_BOLT_COUNT)
		var xform := Transform3D(Basis(Vector3.UP, angle), origin)
		_spawn_bolt(ability, damage_multiplier, xform)

## Spawns SPARK_COUNT crawlers in a fan spread in front of the caster
## (flattened to the horizontal plane), each independently re-targeting
## the nearest enemy once it's loose - see SparkCrawler's own header.
func _fire_spark(ability: Ability, damage_multiplier: float) -> void:
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = -_player.global_transform.basis.z
	forward = forward.normalized()
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
	bolt.applies_status_effects = ability.applies_status_effects
	if ability.ability_id == "thunder_sweep":
		bolt.follow_ground = true
		bolt.max_distance = ability.get_radius(_player.stat_sheet)
	# Configured before entering the tree so _ready() colours it by damage type.
	_player.get_tree().current_scene.add_child(bolt)
	bolt.global_transform = xform

## "26 - Ability Staging Ground", Utility - Blink: "Teleport a short
## distance in a targeted direction. No attack component." Raycasts along
## the camera's forward direction (flattened to the horizontal plane, so
## looking up/down doesn't launch the player into the air or the floor)
## so the player can't blink through a wall - stops just short of
## whatever it hits, or travels the full BLINK_DISTANCE if nothing's there.
## Cast from the CAMERA's height, not the player's feet-level
## global_position - a horizontal ray started exactly at floor height
## grazes the floor collider and reports an immediate 0-distance "hit" at
## the origin itself, which zeroed out every blink (caught by
## scratch_big_test.gd during verification).
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

## Ray from the camera through the (fixed, first-person) crosshair to
## whatever it's aimed at - floor, wall, or enemy collision all work as a
## target surface. Aiming at open sky (nothing hit) falls back to
## projecting onto a horizontal plane at the player's own feet height, so
## there's always a sensible point rather than an undefined one. Capped
## at MAX_TARGET_RANGE either way.
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

## Flame Wall is not circular AoE (Patch v3.8b) - its real shape, per
## FlameWallField.gd, is a WALL_THICKNESS-deep rectangle spanning
## max(radius, 1.5) * 2 in width, oriented perpendicular to the caster ->
## cast-point line. The shared reticle swaps to a flat box matching that
## exact footprint (reading FlameWallField's own WALL_THICKNESS constant
## rather than duplicating the number) instead of the generic Torus used
## by every other ground-targeted ability.
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
		# Same orientation rule as FlameWallField.play(): look_at() points
		# local -Z at the caster, which puts local X (the box's width axis)
		# perpendicular to the caster->target line.
		var flat_caster_pos := Vector3(_player.global_position.x, _reticle.global_position.y, _player.global_position.z)
		if _reticle.global_position.distance_to(flat_caster_pos) > 0.01:
			_reticle.look_at(flat_caster_pos, Vector3.UP)
	else:
		_reticle.rotation = Vector3.ZERO

func _hide_reticle() -> void:
	if _reticle:
		_reticle.visible = false
