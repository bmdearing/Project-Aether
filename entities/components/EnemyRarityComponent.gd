extends Node
class_name EnemyRarityComponent
## Enemy rarity (Patch v3.9): stat multipliers, affixes, drop bonuses and
## visuals. GeneratedMap rolls rarity per pack (roll_pack()):
##   Normal    - no modifiers.
##   Elite     - the whole pack is Elite and shares one PACK affix.
##   Champion  - one member leads an otherwise Normal pack, with an aura
##               (stat lines on every enemy within its radius) and maybe a
##               second Champion affix.
##   Ascendant - a stronger unit (ASCENDANT_UNITS) with two affixes from its
##               own pool and its unit's spellbook (AscendantSpells), shown
##               on the boss-style health bar.
##
## Only exposes queries for stats: Enemy applies the scaling itself, because
## this child's _ready() runs before the parent has set its base health.

const MECHANIC_FRENZY := &"frenzy"
const MECHANIC_VOLATILE := &"volatile"
const MECHANIC_SOUL_EATER := &"soul_eater"
const MECHANIC_BLINK := &"blink"
const MECHANIC_NOVA := &"nova"
## Spawns as a pair (GeneratedMap._spawn_pack()); the split is its stat lines.
const MECHANIC_ARCHON := &"archon"

const AURA_TICK := 0.4
## An aura buff lasts this long after its Champion last reached the enemy.
const AURA_LINGER := 0.9
const FRENZY_MAX_STACKS := 5
const SOUL_EATER_MAX_STACKS := 10
const SOUL_EATER_RADIUS := 15.0
const WARD_RECHARGE_DELAY := 4.0
const VOLATILE_DELAY := 1.0
const VOLATILE_RADIUS := 3.0
## Volatile blast: this many of the enemy's own base hits.
const VOLATILE_DAMAGE_HITS := 1.5
const BLINK_MIN_RANGE := 6.0
const BLINK_MAX_RANGE := 25.0
const NOVA_RANGE := 7.0
const NOVA_RADIUS := 6.0
const NOVA_TELEGRAPH := 1.1
const NOVA_DAMAGE_HITS := 1.2
const UNSTOPPABLE_IMMUNITIES := ["chill", "slow", "electrocute", "freeze", "guard_break"]

@export var rarity: Constants.EnemyRarity = Constants.EnemyRarity.NORMAL
@export var affixes: Array[EnemyAffix] = []
## Every member of an Elite pack (the same Array, shared), for Frenzy.
var pack: Array = []

var _enemy: Enemy
## Champion aura source instance id -> {"affix": EnemyAffix, "until": msec}.
var _auras: Dictionary = {}
var _aura_timer: float = 0.0
var _frenzy_stacks: int = 0
var _soul_stacks: int = 0
var _mechanic_timers: Dictionary = {}  # mechanic -> seconds until ready
var _aura_ring: MeshInstance3D

func _ready() -> void:
	_enemy = get_parent() as Enemy
	EventBus.enemy_died.connect(_on_enemy_died)
	for affix in affixes:
		if affix.mechanic != &"":
			_mechanic_timers[affix.mechanic] = affix.mechanic_value
	_late_setup.call_deferred()  # the parent isn't ready yet (children ready first)

## Needs the parent Enemy's own nodes, so it waits until it's ready.
func _late_setup() -> void:
	if _enemy == null:
		return
	if is_unstoppable() and _enemy.status_effects:
		_enemy.status_effects.immune_to = UNSTOPPABLE_IMMUNITIES
	if rarity == Constants.EnemyRarity.ASCENDANT and _enemy.definition:
		AscendantSpells.attach(_enemy, _enemy.definition.resource_path.get_file().get_basename())
	_build_visuals()

## ---- Stat queries -------------------------------------------------------

func get_health_multiplier() -> float:
	return Constants.ENEMY_RARITY_HEALTH_MULT.get(rarity, 1.0) * (1.0 + _own_sum("more_life") / 100.0)

func get_damage_multiplier() -> float:
	var stacks := _frenzy_stacks * _mechanic_value(MECHANIC_FRENZY) + _soul_stacks * _mechanic_value(MECHANIC_SOUL_EATER)
	return Constants.ENEMY_RARITY_DAMAGE_MULT.get(rarity, 1.0) * (1.0 + _stat("more_damage") / 100.0) * (1.0 + stacks / 100.0)

func get_move_speed_multiplier() -> float:
	return 1.0 + (_stat("move_speed") + _soul_stacks * _mechanic_value(MECHANIC_SOUL_EATER)) / 100.0

func get_attack_speed_multiplier() -> float:
	return 1.0 + (_stat("attack_speed") + _frenzy_stacks * _mechanic_value(MECHANIC_FRENZY)) / 100.0

func get_damage_taken_multiplier() -> float:
	return maxf(1.0 + _stat("damage_taken") / 100.0, 0.1)

func get_ward_percent() -> float:
	return _own_sum("ward_percent") / 100.0

func is_unstoppable() -> bool:
	return affixes.any(func(a: EnemyAffix): return a.unstoppable)

func get_name_color() -> Color:
	return Constants.ENEMY_RARITY_NAME_COLOR.get(rarity, Color.WHITE)

## "Swift · Searing" for the health bar.
func get_affix_names() -> String:
	return "  ·  ".join(affixes.map(func(a: EnemyAffix): return a.display_name))

## Summed across every rolled affix.
func get_effective_rarity_bonus() -> float:
	return _own_sum("item_rarity_bonus")

func get_effective_quantity_bonus() -> float:
	return _own_sum("item_quantity_bonus")

## First (doc: conversion is "all-or-nothing", never partial/stacked)
## converts_drops affix, or null if this enemy has none.
func get_drop_conversion_affix() -> EnemyAffix:
	for affix in affixes:
		if affix.converts_drops:
			return affix
	return null

func get_damage_conversion() -> int:
	for affix in affixes:
		if affix.converts_damage:
			return affix.damage_conversion_type
	return -1

## Own affixes plus every live Champion aura reaching this enemy. A
## Champion's own aura reaches itself through the same broadcast.
func _stat(key: String) -> float:
	var total := 0.0
	for affix in affixes:
		if not affix.has_aura:
			total += float(affix.get(key))
	var now := Time.get_ticks_msec()
	for source_id in _auras.keys():
		var entry: Dictionary = _auras[source_id]
		if now > int(entry["until"]):
			_auras.erase(source_id)
			continue
		total += float((entry["affix"] as EnemyAffix).get(key))
	return total

func _own_sum(key: String) -> float:
	var total := 0.0
	for affix in affixes:
		total += float(affix.get(key))
	return total

func _mechanic_value(mechanic: StringName) -> float:
	for affix in affixes:
		if affix.mechanic == mechanic:
			return affix.mechanic_value
	return 0.0

func has_mechanic(mechanic: StringName) -> bool:
	return affixes.any(func(a: EnemyAffix): return a.mechanic == mechanic)

func receive_aura(source: Node, affix: EnemyAffix) -> void:
	_auras[source.get_instance_id()] = {"affix": affix, "until": Time.get_ticks_msec() + int(AURA_LINGER * 1000.0)}

## ---- Hit hooks (Enemy / its attacks) ----------------------------------------

## Damage type -> % of each hit added as that type, from its own affixes and
## every aura reaching it.
func get_added_damage() -> Dictionary:
	var added := {}
	var sources: Array = affixes.filter(func(a: EnemyAffix): return not a.has_aura)
	var now := Time.get_ticks_msec()
	for entry in _auras.values():
		if now <= int(entry["until"]):
			sources.append(entry["affix"])
	for affix: EnemyAffix in sources:
		if affix.added_damage_percent > 0.0:
			added[affix.added_damage_type] = float(added.get(affix.added_damage_type, 0.0)) + affix.added_damage_percent
	return added

## A landed hit on the player: added damage, on-hit statuses and leech.
func on_hit_player(player: Player, damage: float) -> void:
	var added := get_added_damage()
	for damage_type in added:
		player.take_damage(damage * float(added[damage_type]) / 100.0, damage_type, _enemy, Player.HitKind.ATTACK)
	for affix in affixes:
		if affix.on_hit_status != "" and randf() < affix.on_hit_chance and player.status_effects:
			player.status_effects.apply_effect(affix.on_hit_status, _enemy, damage)
		if affix.leech > 0.0:
			_enemy.health.heal(damage * affix.leech / 100.0)

## ---- Per-frame behaviour ------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _enemy == null or not _enemy.health.is_alive():
		return
	if affixes.is_empty() and _auras.is_empty():
		return  # a Normal enemy outside every aura
	var regen := _stat("life_regen")
	if regen > 0.0 and _enemy.health.current_health < _enemy.health.max_health:
		_enemy.health.heal(_enemy.health.max_health * regen / 100.0 * delta)
	_aura_timer -= delta
	if _aura_timer <= 0.0:
		_aura_timer = AURA_TICK
		_broadcast_auras()
	if get_ward_percent() > 0.0:
		_enemy.recharge_ward_if_idle(WARD_RECHARGE_DELAY)
	for mechanic in _mechanic_timers.keys():
		_mechanic_timers[mechanic] = maxf(_mechanic_timers[mechanic] - delta, 0.0)
	if _mechanic_timers.get(MECHANIC_BLINK, -1.0) == 0.0:
		_try_blink()
	if _mechanic_timers.get(MECHANIC_NOVA, -1.0) == 0.0:
		_try_nova()

func _broadcast_auras() -> void:
	for affix in affixes:
		if not affix.has_aura:
			continue
		for node in get_tree().get_nodes_in_group("enemy"):
			var other := node as Enemy
			if other == null or other.global_position.distance_to(_enemy.global_position) > affix.aura_radius:
				continue
			var component := other.get_node_or_null("EnemyRarityComponent") as EnemyRarityComponent
			if component:
				component.receive_aura(_enemy, affix)

func _on_enemy_died(dead: Node) -> void:
	if dead == _enemy:
		if has_mechanic(MECHANIC_VOLATILE):
			_explode.call_deferred(_enemy.global_position)
		return
	if not is_instance_valid(_enemy) or not _enemy.health.is_alive():
		return
	if has_mechanic(MECHANIC_FRENZY) and pack.has(dead):
		_frenzy_stacks = mini(_frenzy_stacks + 1, FRENZY_MAX_STACKS)
	if has_mechanic(MECHANIC_SOUL_EATER) and dead is Node3D and (dead as Node3D).global_position.distance_to(_enemy.global_position) <= SOUL_EATER_RADIUS:
		_soul_stacks = mini(_soul_stacks + 1, SOUL_EATER_MAX_STACKS)

## Volatile: a red ring where it fell, then a blast. Runs on the map, not the
## corpse, which may be freed first.
func _explode(at: Vector3) -> void:
	var map := _enemy.get_parent() if is_instance_valid(_enemy) else get_tree().current_scene
	var damage := _enemy.get_ability_base_damage() * VOLATILE_DAMAGE_HITS if is_instance_valid(_enemy) else 20.0
	var damage_type := _enemy.get_ability_damage_type() if is_instance_valid(_enemy) else Constants.DamageType.EXPLOSIVE
	var radius := VOLATILE_RADIUS * (_enemy.get_area_multiplier() if is_instance_valid(_enemy) else 1.0)
	BossTelegraph.circle(map, at, radius, VOLATILE_DELAY, Color(1.0, 0.45, 0.1))
	await get_tree().create_timer(VOLATILE_DELAY).timeout
	AudioManager.play_at(SoundLib.pick_random(SoundLib.library.explosion), at, -4.0)
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.global_position.distance_to(at) <= radius:
		player.take_damage(damage, damage_type, null, Player.HitKind.SPELL)

func _try_blink() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or not _enemy.is_in_combat():
		return
	var dist := player.global_position.distance_to(_enemy.global_position)
	if dist < BLINK_MIN_RANGE or dist > BLINK_MAX_RANGE:
		return
	_mechanic_timers[MECHANIC_BLINK] = _mechanic_value(MECHANIC_BLINK)
	var away := (_enemy.global_position - player.global_position)
	away.y = 0.0
	var spot := player.global_position + away.normalized() * 2.2
	SmokePuff.spawn(_enemy.get_parent(), _enemy.global_position, 1.3)
	_enemy.global_position = spot + Vector3.UP * 0.1
	SmokePuff.spawn(_enemy.get_parent(), spot, 1.3)

func _try_nova() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.global_position.distance_to(_enemy.global_position) > NOVA_RANGE:
		return
	_mechanic_timers[MECHANIC_NOVA] = _mechanic_value(MECHANIC_NOVA)
	var at := _enemy.global_position
	var radius := NOVA_RADIUS * _enemy.get_area_multiplier()
	BossTelegraph.circle(_enemy.get_parent(), at, radius, NOVA_TELEGRAPH, Color(0.45, 0.8, 1.0))
	await get_tree().create_timer(NOVA_TELEGRAPH).timeout
	if not is_instance_valid(_enemy) or not _enemy.health.is_alive():
		return
	player = get_tree().get_first_node_in_group("player") as Player
	if player and player.global_position.distance_to(_enemy.global_position) <= radius:
		player.take_damage(_enemy.get_ability_base_damage() * NOVA_DAMAGE_HITS, Constants.DamageType.COLD, _enemy, Player.HitKind.SPELL)
		if player.status_effects:
			player.status_effects.apply_effect("chill", _enemy)

## ---- Visuals ------------------------------------------------------------------

## Elite: a faint blue glow. Champion: a gold ring on the ground at its aura's
## reach. Ascendant: a strong orange glow.
func _build_visuals() -> void:
	if _enemy == null or rarity == Constants.EnemyRarity.NORMAL:
		return
	var light := OmniLight3D.new()
	light.light_color = get_name_color()
	light.light_energy = {Constants.EnemyRarity.ELITE: 0.5, Constants.EnemyRarity.CHAMPION: 0.9, Constants.EnemyRarity.ASCENDANT: 1.6}.get(rarity, 0.5)
	light.omni_range = 2.5 if rarity == Constants.EnemyRarity.ELITE else 4.0
	light.position = Vector3(0, 1.0, 0)
	_enemy.add_child(light)
	for affix in affixes:
		if affix.has_aura:
			_aura_ring = MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = affix.aura_radius - 0.12
			torus.outer_radius = affix.aura_radius
			torus.rings = 64
			_aura_ring.mesh = torus
			_aura_ring.scale = Vector3(1, 0.04, 1)
			_aura_ring.position = Vector3(0, 0.05, 0)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			# Elemental banners take their element's colour.
			var ring_color: Color = Constants.DAMAGE_TYPE_COLOR.get(affix.added_damage_type, get_name_color()) if affix.added_damage_percent > 0.0 else get_name_color()
			mat.albedo_color = Color(ring_color, 0.45)
			_aura_ring.material_override = mat
			_enemy.add_child(_aura_ring)
			break

## ---- Spawn-time rolls (static) -----------------------------------------------

const AFFIX_DIR := "res://data/enemies/affixes/"
static var _affix_cache: Array[EnemyAffix] = []

static func _build_affix_cache() -> void:
	for file_name in DirAccess.get_files_at(AFFIX_DIR):
		file_name = file_name.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			var affix := load(AFFIX_DIR + file_name) as EnemyAffix
			if affix:
				_affix_cache.append(affix)

static func affixes_for_category(category: EnemyAffix.AffixCategory) -> Array[EnemyAffix]:
	if _affix_cache.is_empty():
		_build_affix_cache()
	var result: Array[EnemyAffix] = []
	for affix in _affix_cache:
		if affix.category == category:
			result.append(affix)
	return result

static func roll_pack_rarity() -> Constants.EnemyRarity:
	var weights: Dictionary = Constants.ENEMY_PACK_RARITY_WEIGHTS.duplicate()
	# Figment Tree: Monsters sector.
	weights[Constants.EnemyRarity.ELITE] *= 1.0 + FigmentTree.effect("rarity_weight:elite") / 100.0
	weights[Constants.EnemyRarity.CHAMPION] *= 1.0 + FigmentTree.effect("rarity_weight:champion") / 100.0
	weights[Constants.EnemyRarity.ASCENDANT] *= 1.0 + FigmentTree.effect("rarity_weight:ascendant") / 100.0
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := randf() * total
	for r in weights:
		roll -= weights[r]
		if roll <= 0.0:
			return r
	return Constants.EnemyRarity.NORMAL

## Champion: one aura, and a 50% chance of a second (non-aura or aura) affix.
## Ascendant: two from its pool. Elite rolls through roll_pack().
static func roll_affixes(rarity: Constants.EnemyRarity) -> Array[EnemyAffix]:
	var result: Array[EnemyAffix] = []
	match rarity:
		Constants.EnemyRarity.ELITE:
			var pool := affixes_for_category(EnemyAffix.AffixCategory.PACK)
			if not pool.is_empty():
				result.append(pool.pick_random())
		Constants.EnemyRarity.CHAMPION:
			var pool := affixes_for_category(EnemyAffix.AffixCategory.CHAMPION)
			var auras := pool.filter(func(a: EnemyAffix): return a.has_aura)
			if not auras.is_empty():
				result.append(auras.pick_random())
			var rest := pool.filter(func(a: EnemyAffix): return not result.has(a))
			if not rest.is_empty() and randf() < 0.5:
				result.append(rest.pick_random())
		Constants.EnemyRarity.ASCENDANT:
			var pool := affixes_for_category(EnemyAffix.AffixCategory.ASCENDANT)
			pool.shuffle()
			result.append_array(pool.slice(0, mini(2, pool.size())))
	return result

static func attach(enemy: Enemy, rarity: Constants.EnemyRarity, rolled: Array[EnemyAffix], pack_members: Array = []) -> EnemyRarityComponent:
	var component := EnemyRarityComponent.new()
	component.name = "EnemyRarityComponent"
	component.rarity = rarity
	component.affixes = rolled
	component.pack = pack_members
	enemy.add_child(component)
	return component

## A Normal component (so the enemy can still receive Champion auras).
static func attach_normal(enemy: Enemy) -> EnemyRarityComponent:
	var none: Array[EnemyAffix] = []
	return attach(enemy, Constants.EnemyRarity.NORMAL, none)

## Kept for callers that roll a lone enemy: rolls its own rarity.
static func roll_and_attach(enemy: Enemy) -> EnemyRarityComponent:
	var rarity := roll_pack_rarity()
	return attach(enemy, rarity, roll_affixes(rarity))
