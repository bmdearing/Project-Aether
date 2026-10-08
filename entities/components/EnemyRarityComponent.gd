extends Node
class_name EnemyRarityComponent
## Enemy rarity: stat multipliers, rolled affixes, drop bonuses and visuals.
## Attached at spawn (GeneratedMap), so it may be absent.
##
## Only exposes queries: Enemy applies the scaling itself, because this
## child's _ready() runs before the parent has set its base health.

@export var rarity: Constants.EnemyRarity = Constants.EnemyRarity.NORMAL
@export var affixes: Array[EnemyAffix] = []

func get_health_multiplier() -> float:
	return Constants.ENEMY_RARITY_HEALTH_MULT.get(rarity, 1.0)

func get_damage_multiplier() -> float:
	return Constants.ENEMY_RARITY_DAMAGE_MULT.get(rarity, 1.0)

func get_name_color() -> Color:
	return Constants.ENEMY_RARITY_NAME_COLOR.get(rarity, Color.WHITE)

## Summed across every rolled affix.
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
	# Placeholder aura light.
	if rarity >= Constants.EnemyRarity.CHAMPION:
		_spawn_aura_placeholder()

func _spawn_aura_placeholder() -> void:
	var light := OmniLight3D.new()
	light.light_color = get_name_color()
	light.light_energy = 0.8
	light.omni_range = 3.0
	# Deferred: the parent is still busy setting up children.
	get_parent().add_child.call_deferred(light)

## --- Spawn-time helpers (static) ---------------------------------------
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

## Champion/Ascendant: 1-2 affixes. Elite: 1. Normal: none.
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

## Rolls a rarity and affixes and attaches the component as
## "EnemyRarityComponent", the name other code looks up.
static func roll_and_attach(enemy: Enemy) -> EnemyRarityComponent:
	var rarity := _roll_rarity()
	var component := EnemyRarityComponent.new()
	component.name = "EnemyRarityComponent"
	component.rarity = rarity
	component.affixes = _roll_affixes(rarity)
	enemy.add_child(component)
	return component
