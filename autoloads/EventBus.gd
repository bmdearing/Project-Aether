extends Node
## Global signal bus. Systems emit here instead of holding direct references
## to each other - keeps FateBoard, Combat, and UI decoupled.

signal damage_dealt(source: Node, target: Node, amount: float, damage_type: int, is_more_multiplier_applied: bool, is_critical: bool)
## Implementation Brief v3.3 Section 5/"Files to Modify" - fired once per
## landed melee hit alongside (not instead of) damage_dealt above; carries
## motion_value so a future consumer (combat log, audio) can tell a light
## jab apart from a charged thrust without re-deriving it from damage_dealt's
## own amount, which damage_dealt alone can't do.
signal melee_attack_executed(source: Node, final_damage: float, damage_type: int, motion_value: float)
## Fired once per PLAYER-landed hit (melee or ranged), consumed by
## PlayerHUD's HitMarker. Redesigned 2026-08-31 (user reference image) from
## the original 2-bool "3 states only" version to carry all 3 independent
## facts a marker needs to distinguish - is_critical (a roll crit),
## is_critical_spot (a weakpoint/headshot hit), is_kill (this hit killed
## the target) - see HitMarker.show_hit() for how they combine into 8
## distinct glyphs.
signal hit_landed(is_critical: bool, is_critical_spot: bool, is_kill: bool)
## Implementation Brief v3.4 Section 4 - fired by WeaponStance.
## toggle_stance_page() alongside its own local stance_page_changed signal,
## for UI (StanceIndicator) that doesn't hold a direct WeaponStance reference.
signal stance_page_changed(page: int)
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
