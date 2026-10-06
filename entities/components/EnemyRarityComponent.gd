extends Node
class_name EnemyRarityComponent
## Patch v3.9 "Enemy Rarity System" - a SEPARATE axis from Constants.
## EnemyRank (see Constants.gd's own comment on ENEMY_RARITY_NAME) -
## carries stat multipliers, rolled affixes, drop bonuses, and visual
## distinction for T2-T4 enemies. Attached dynamically by whichever
## script spawns the enemy (GeneratedMap._spawn_enemy_at()) - not a fixed
## child in every Enemy .tscn, so nothing else may assume it's present.
##
## Stat scaling is deliberately NOT applied from this node's own _ready()
## the way an earlier draft of this component tried - this project has a
## well-documented recurring bug class where a CHILD node's _ready() runs
## BEFORE its PARENT's (see Enemy.gd's own _apply_map_modifiers(), already
## deferred for exactly this reason: "so archetype subclasses' own
## health.max_health isn't overwritten"). Multiplying enemy.health.
## max_health from here would hit that identical bug - the parent hasn't
## set its own base health yet at this component's _ready() time. Instead
## this exposes pure query methods; Enemy.gd's own already-correctly-timed
## _apply_map_modifiers()/get_outgoing_damage_multiplier() call them.

@export var rarity: Constants.EnemyRarity = Constants.EnemyRarity.NORMAL
@export var affixes: Array[EnemyAffix] = []

func get_health_multiplier() -> float:
	return Constants.ENEMY_RARITY_HEALTH_MULT.get(rarity, 1.0)

func get_damage_multiplier() -> float:
	return Constants.ENEMY_RARITY_DAMAGE_MULT.get(rarity, 1.0)

func get_name_color() -> Color:
	return Constants.ENEMY_RARITY_NAME_COLOR.get(rarity, Color.WHITE)

## Doc: "Item Rarity on the enemy affects the quality of converted drops" -
## summed across every rolled affix (Champion/Ascendant can carry 1-2,
## Elite packs carry exactly 1).
func get_effective_rarity_bonus() -> float:
	var total := 0.0
	for affix in affixes:
		total += affix.item_rarity_bonus
	return total

func get_effective_quantity_bonus() -> float:
	var total := 0.0
	for affix in affixes:
		total += affix.item_quantity_bonus
	return total

## First (doc: conversion is "all-or-nothing", never partial/stacked)
## converts_drops affix, or null if this enemy has none.
func get_drop_conversion_affix() -> EnemyAffix:
	for affix in affixes:
		if affix.converts_drops:
			return affix
	return null

func _ready() -> void:
	# Visual only - safe here (unlike stat scaling above) since it only
	# needs get_parent() to exist, not any of the parent's own _ready()-
	# time state. DO NOT list: "Champion auras... visual placeholder only."
	if rarity >= Constants.EnemyRarity.CHAMPION:
		_spawn_aura_placeholder()

func _spawn_aura_placeholder() -> void:
	var light := OmniLight3D.new()
	light.light_color = get_name_color()
	light.light_energy = 0.8
	light.omni_range = 3.0
	# Deferred - this component's own _ready() fires while the parent
	# Enemy's add_child() call (in GeneratedMap._spawn_enemy_at()) is
	# still busy entering the whole subtree into the tree; a direct
	# add_child() on the parent here is rejected ("Parent node is busy
	# setting up children") until that finishes.
	get_parent().add_child.call_deferred(light)

## --- Spawn-time helpers (static) ---------------------------------------
## Lazily-cached the same one-time-scan way ItemRoller's own pools are -
## only 4 starter files today, but scanning stays correct as more are added.
const AFFIX_DIR := "res://data/enemies/affixes/"
static var _affix_cache: Array[EnemyAffix] = []

static func _build_affix_cache() -> void:
	var dir := DirAccess.open(AFFIX_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next().trim_suffix(".remap")
	while file_name != "":
		if file_name.ends_with(".tres"):
			var affix: EnemyAffix = load(AFFIX_DIR + file_name)
			if affix:
				_affix_cache.append(affix)
		file_name = dir.get_next().trim_suffix(".remap")
	dir.list_dir_end()

static func _affixes_for_category(category: EnemyAffix.AffixCategory) -> Array[EnemyAffix]:
	if _affix_cache.is_empty():
		_build_affix_cache()
	var result: Array[EnemyAffix] = []
	for affix in _affix_cache:
		if affix.category == category:
			result.append(affix)
	return result

## Weighted roll off Constants.ENEMY_RARITY_SPAWN_WEIGHTS - same cumulative-
## weight pattern Enemy._roll_rank() already uses for the OTHER axis.
static func _roll_rarity() -> Constants.EnemyRarity:
	var total := 0.0
	for w in Constants.ENEMY_RARITY_SPAWN_WEIGHTS.values():
		total += w
	var roll := randf() * total
	var cumulative := 0.0
	for r in Constants.ENEMY_RARITY_SPAWN_WEIGHTS:
		cumulative += Constants.ENEMY_RARITY_SPAWN_WEIGHTS[r]
		if roll <= cumulative:
			return r
	return Constants.EnemyRarity.NORMAL

## Doc: "Champions and Ascendants roll 1-2 random affixes from their
## eligible pool. Elite packs roll 1 affix from the pack pool. Normal
## enemies roll no affixes."
static func _roll_affixes(rarity: Constants.EnemyRarity) -> Array[EnemyAffix]:
	var result: Array[EnemyAffix] = []
	match rarity:
		Constants.EnemyRarity.ELITE:
			var pool := _affixes_for_category(EnemyAffix.AffixCategory.PACK)
			if pool.size() > 0:
				result.append(pool[randi() % pool.size()])
		Constants.EnemyRarity.CHAMPION:
			var pool := _affixes_for_category(EnemyAffix.AffixCategory.CHAMPION)
			pool.shuffle()
			result.append_array(pool.slice(0, min(randi_range(1, 2), pool.size())))
		Constants.EnemyRarity.ASCENDANT:
			var pool := _affixes_for_category(EnemyAffix.AffixCategory.ASCENDANT)
			pool.shuffle()
			result.append_array(pool.slice(0, min(randi_range(1, 2), pool.size())))
	return result

## Rolls a rarity + its affixes and attaches a real EnemyRarityComponent
## to `enemy` as a child named "EnemyRarityComponent" (matching the name
## every get_node_or_null("EnemyRarityComponent") lookup elsewhere in this
## patch expects). Call BEFORE `enemy` itself is added to the SceneTree -
## harmless either way (add_child() on an orphaned node works the same),
## but matches this component's own "attached dynamically at spawn" role.
static func roll_and_attach(enemy: Enemy) -> EnemyRarityComponent:
	var rarity := _roll_rarity()
	var component := EnemyRarityComponent.new()
	component.name = "EnemyRarityComponent"
	component.rarity = rarity
	component.affixes = _roll_affixes(rarity)
	enemy.add_child(component)
	return component
