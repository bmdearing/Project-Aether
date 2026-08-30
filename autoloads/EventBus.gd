extends Node
## Global signal bus. Systems emit here instead of holding direct references
## to each other - keeps FateBoard, Combat, and UI decoupled.

signal damage_dealt(source: Node, target: Node, amount: float, damage_type: int, is_more_multiplier_applied: bool, is_critical: bool)
signal status_effect_applied(target: Node, effect_id: String, stacks: int)
signal status_effect_expired(target: Node, effect_id: String)

signal stance_damaged(enemy: Node, amount: float, remaining: float)
signal composure_broken(enemy: Node)
signal parry_successful(player: Node, enemy: Node)
signal riposte_window_opened(target: Node)
signal riposte_executed(source: Node, target: Node)
signal counter_hit(source: Node, target: Node)

signal enemy_attack_telegraphed(enemy: Node)
signal enemy_attack_resolved(enemy: Node, target: Node, hit: bool, parried: bool)

signal slate_placed(slate_id: String, grid_position: Vector2i)
signal slate_removed(slate_id: String, grid_position: Vector2i)
signal chain_recalculated(chain_id: int, tile_count: int, bonus_percent: float)
signal aether_budget_changed(used: int, capacity: int)

signal ward_depleted(target: Node)
signal ward_restored(target: Node, amount: float)

signal player_died

signal ability_cast(caster: Node, ability: Ability)
signal ability_cast_failed(caster: Node, ability: Ability, reason: String)

signal weapon_swapped(player: Node)

signal player_leveled_up(new_level: int)

signal figment_completed(figment: FigmentItem)

signal loot_dropped(item: Item, at_position: Vector3)
signal loot_picked_up(item: Item)
signal slate_dropped(slate: Slate, at_position: Vector3)
signal slate_picked_up(slate: Slate)
signal tome_picked_up(tome: SkillTome)
signal gold_picked_up(amount: int)
