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
signal throwable_used(throwable_type: String)

## Patch v3.6 - Cube/Corruption. Only signals with a real emit site are
## added (CraftingSystem.gd/CorruptionSystem.gd) - the brief's own
## *_selection_requested/item_reroll_requested signals assumed a signal-
## driven UI flow that doesn't match this project's actual CraftingScreen
## (which already handles affix selection directly via
## _selected_affix_index, and rerolls in place rather than requesting one
## asynchronously), so they're skipped as dead additions nothing would
## ever listen to.
signal brand_consumed(brand_id: String)
## Patch v3.8c - Hub Brand Shop. No listener exists yet for either (same
## "real emit site, no consumer required" footing brand_consumed itself
## started from) - BrandShop.gd is the one real emit site for both.
signal brand_purchased(brand_id: String)
signal gold_spent(amount: int)
signal item_quality_changed(item: Item)
signal item_rarity_changed(item: Item)  # Patch v3.9 - fired by CraftingSystem._update_item_rarity() when affix-count-driven rarity actually changes
signal item_sockets_changed(item: Item)
signal item_stats_changed(item: Item)
signal affix_upgraded(item: Item, affix: ItemAffix)
signal corruption_applied(item: Item, outcome_name: String, tier: int)
signal item_transcended(item: Item)
signal item_unmade(item: Item)
signal grade_ascended(item: Item, stat: String, new_grade: int)

## Patch v3.7 Section 2 - CastTimeHandler.
signal cast_started(ability: Ability, cast_time: float)
signal cast_interrupted()

## Implementation Brief v4.2 - ranged ammo/reload. ammo_changed fires on any
## reserve change AND after every shot (the HUD re-reads the magazine then).
signal reload_started(weapon: Weapon)
signal reload_finished(weapon: Weapon)
signal reload_interrupted(weapon: Weapon)
signal ammo_changed(ammo_type: int, reserve_count: int)

## Patch v4.3 - a melee hit stopped by the defender's shield.
signal hit_blocked(defender: Node)

## Patch v4.6 - a player weapon attack fully avoided by an enemy's evasion_value.
signal enemy_hit_dodged(enemy: Node)

## Patch v4.4 - Evasion. Dodged: an attack hit fully negated. Deflected: a hit
## reduced by Deflection Mitigation (still lands).
signal hit_dodged(defender: Node)
signal hit_deflected(defender: Node)
