extends Node
## Global signal bus. Systems emit here instead of holding direct references
## to each other - keeps FateBoard, Combat, and UI decoupled.

signal damage_dealt(source: Node, target: Node, amount: float, damage_type: int, is_more_multiplier_applied: bool, is_critical: bool)
## Per landed melee hit, alongside damage_dealt; adds the motion value.
signal melee_attack_executed(source: Node, final_damage: float, damage_type: int, motion_value: float)
## Per player-landed hit, for the HUD HitMarker. is_critical_spot = headshot.
signal hit_landed(is_critical: bool, is_critical_spot: bool, is_kill: bool)
## Mirrors WeaponStance.stance_page_changed for UI without a direct reference.
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
## A Lens was set into a Slate already on the Fate Board.
signal slate_lenses_changed(placement_id: String)

signal ward_depleted(target: Node)
signal ward_restored(target: Node, amount: float)

signal player_died

signal ability_cast(caster: Node, ability: Ability)
signal ability_cast_failed(caster: Node, ability: Ability, reason: String)
signal stance_on_cooldown(player: Node, remaining: float)

signal weapon_swapped(player: Node)

signal player_leveled_up(new_level: int)

signal figment_completed(figment: FigmentItem)

signal loot_dropped(item: Item, at_position: Vector3)
signal loot_picked_up(item: Item)
## A pickup stayed on the ground because the carried inventory had no room.
signal inventory_full(content: Resource)
signal slate_dropped(slate: Slate, at_position: Vector3)
signal slate_picked_up(slate: Slate)
signal tome_picked_up(tome: SkillTome)
signal gold_picked_up(amount: int)
signal throwable_used(throwable_type: String)

## Crafting and corruption.
signal gold_spent(amount: int)
signal item_quality_changed(item: Item)
signal item_rarity_changed(item: Item)  # an Orb changed an item's rarity (CraftingResolver.apply())
signal item_sockets_changed(item: Item)
signal item_stats_changed(item: Item)
signal affix_upgraded(item: Item, affix: ItemAffix)
signal corruption_applied(item: Item, outcome_name: String, tier: int)
signal item_transcended(item: Item)
signal item_unmade(item: Item)
signal grade_ascended(item: Item, stat: String, new_grade: int)

## CastTimeHandler.
signal cast_started(ability: Ability, cast_time: float)
signal cast_interrupted()

## Ranged ammo/reload. ammo_changed fires on any
## reserve change AND after every shot (the HUD re-reads the magazine then).
signal reload_started(weapon: Weapon)
signal reload_finished(weapon: Weapon)
signal reload_interrupted(weapon: Weapon)
signal ammo_changed(ammo_type: int, reserve_count: int)

## A melee hit stopped by the defender's shield.
signal hit_blocked(defender: Node)

## A player weapon attack dodged by an enemy's evasion_value.
signal enemy_hit_dodged(enemy: Node)

## GeneratedMap counts spawns/deaths and emits enemy_count_changed for the HUD.
signal enemy_died(enemy: Node)
signal warcry_used(user: Node)  # a Warcry skill went off (ruptures Earthquake fields)
signal boss_phase_changed(boss: Node, phase: int)  # BossBrain crossed a health threshold
signal enemy_count_changed(remaining: int, total: int)

## Evasion. Dodged: an attack hit fully negated. Deflected: a hit
## reduced by Deflection Mitigation (still lands).
signal hit_dodged(defender: Node)
signal hit_deflected(defender: Node)

## Orb crafting (CraftingResolver). item is an Item or a Slate.
signal craft_completed(item: Resource, result: CraftResult)
signal craft_failed(item: Resource, error: int, message: String)

## Portals (GeneratedMap). opened: the T-key portal appeared in a map;
## returned: the player came back into a saved map through the Hub portal.
signal portal_opened(position: Vector3)
signal portal_returned

## GameSettings.apply() ran - live nodes (Player camera/mouse) re-read GameState.
signal settings_changed
