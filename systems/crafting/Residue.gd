extends RefCounted
class_name Residue
## Residue pools (Crafting Rev 3): kills fill the pool of the enemy's damage
## category, bosses also fill the shared boss pool, and the Siphon spends them.
## The totals live on GameState.residue. Numbers are placeholders in Constants.

const PHYSICAL := &"residue_physical"
const ELEMENTAL := &"residue_elemental"
const ESOTERIC := &"residue_esoteric"
const BOSS := &"residue_boss"
const REGULAR: Array[StringName] = [PHYSICAL, ELEMENTAL, ESOTERIC]
const ALL: Array[StringName] = [PHYSICAL, ELEMENTAL, ESOTERIC, BOSS]

const POOL_BY_CATEGORY := {
	Constants.DamageCategory.PHYSICAL: PHYSICAL,
	Constants.DamageCategory.ELEMENTAL: ELEMENTAL,
	Constants.DamageCategory.ESOTERIC: ESOTERIC,
}

static func amount(pool: StringName) -> int:
	return int(GameState.residue.get(pool, 0))

static func cap(pool: StringName) -> int:
	return Constants.RESIDUE_BOSS_POOL_CAP if pool == BOSS else Constants.RESIDUE_POOL_CAP

## Adds to a pool up to its cap (the rest is lost). Returns what was added.
static func add(pool: StringName, gain: int) -> int:
	var before := amount(pool)
	var after := mini(before + maxi(gain, 0), cap(pool))
	GameState.residue[pool] = after
	if after != before:
		EventBus.residue_changed.emit(pool, after - before, after)
	return after - before

static func can_pay(payment: Dictionary) -> bool:
	for pool in payment:
		if int(payment[pool]) < 0 or amount(pool) < int(payment[pool]):
			return false
	return true

static func pay(payment: Dictionary) -> void:
	for pool in payment:
		var spent := int(payment[pool])
		if spent > 0:
			GameState.residue[pool] = amount(pool) - spent
			EventBus.residue_changed.emit(pool, -spent, amount(pool))
	EventBus.residue_spent.emit(payment)

## The pool a kill of this damage type fills (Physical when there is none).
static func pool_for_damage_type(damage_type: int) -> StringName:
	return POOL_BY_CATEGORY.get(Constants.DAMAGE_TYPE_CATEGORY.get(damage_type, Constants.DamageCategory.PHYSICAL), PHYSICAL)

## Residue for killing `enemy`, credited to the pools.
static func grant_for_kill(enemy: Enemy) -> void:
	if enemy == null or enemy.definition == null:
		return
	var category: String = enemy.definition.archetype_category
	var rarity: int = enemy.rarity_component.rarity if enemy.rarity_component else Constants.EnemyRarity.NORMAL
	var gain := float(Constants.RESIDUE_PER_KILL.get(category, 1)) * float(Constants.RESIDUE_RARITY_MULT.get(rarity, 1.0)) * enemy._reward_mult("currency")
	add(pool_for_damage_type(enemy.residue_damage_type()), maxi(1, roundi(gain)))
	if enemy.rank == Constants.EnemyRank.BOSS:
		add(BOSS, Constants.RESIDUE_BOSS_PER_KILL)
		var id := enemy.definition.resource_path.get_file().get_basename()
		if id != "" and not GameState.killed_bosses.has(id):
			GameState.killed_bosses.append(id)
