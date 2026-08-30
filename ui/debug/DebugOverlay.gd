extends CanvasLayer
class_name DebugOverlay
## Numeric overlay for validating the damage formula and Fate Board chain
## math before any art exists. Toggle via GameState.debug_overlay_enabled.
## Renders fine over a 3D viewport - CanvasLayer is compositing-agnostic.

@onready var label: Label = $Label

func _ready() -> void:
	EventBus.aether_budget_changed.connect(_on_aether_changed)
	EventBus.chain_recalculated.connect(_on_chain_recalculated)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.parry_successful.connect(_on_parry_successful)
	EventBus.stance_damaged.connect(_on_stance_damaged)
	EventBus.composure_broken.connect(_on_composure_broken)
	EventBus.riposte_executed.connect(_on_riposte_executed)
	EventBus.counter_hit.connect(_on_counter_hit)
	EventBus.status_effect_applied.connect(_on_status_effect_applied)
	EventBus.status_effect_expired.connect(_on_status_effect_expired)
	EventBus.enemy_attack_resolved.connect(_on_enemy_attack_resolved)
	EventBus.ability_cast.connect(_on_ability_cast)
	EventBus.ability_cast_failed.connect(_on_ability_cast_failed)
	EventBus.loot_dropped.connect(_on_loot_dropped)
	EventBus.slate_dropped.connect(_on_slate_dropped)
	EventBus.player_leveled_up.connect(_on_player_leveled_up)
	EventBus.tome_picked_up.connect(_on_tome_picked_up)
	EventBus.gold_picked_up.connect(_on_gold_picked_up)
	visible = GameState.debug_overlay_enabled
	label.text = "Project Aether — Debug Overlay\nAether: 0/0\n(Esc to release mouse)"
	if GameState.active_map:
		var m := GameState.active_map
		_append_line("Active Map: %s (dmg x%.2f, life x%.2f, qty x%.2f, rarity x%.2f)" % [
			m.display_name, m.enemy_damage_multiplier, m.enemy_health_multiplier,
			m.loot_quantity_multiplier, m.loot_rarity_multiplier,
		])

func _on_aether_changed(used: int, capacity: int) -> void:
	_append_line("Aether: %d/%d" % [used, capacity])

func _on_chain_recalculated(chain_id: int, tile_count: int, bonus_percent: float) -> void:
	_append_line("Chain %d: %d tiles, +%.2f%% bonus" % [chain_id, tile_count, bonus_percent * 100.0])

## Distinguishes player-dealt hits ("YOU dealt...") from everything else,
## so it's actually possible to tell from this overlay whether an attack
## landed on an enemy vs. one landing on the player - the flat "Dmg: X"
## line before this didn't record direction at all.
func _on_damage_dealt(source: Node, target: Node, amount: float, damage_type: int, more_applied: bool, is_critical: bool) -> void:
	var type_name: String = Constants.DAMAGE_TYPE_NAME.get(damage_type, "?")
	var target_name: String = target.name if target else "?"
	var tag: String = " [More applied]" if more_applied else ""
	tag += " [CRIT]" if is_critical else ""
	if source is Player:
		_append_line("YOU dealt %.1f %s dmg to %s%s" % [amount, type_name, target_name, tag])
	else:
		var source_name: String = source.name if source else "?"
		_append_line("%s dealt %.1f %s dmg to %s%s" % [source_name, amount, type_name, target_name, tag])

func _on_parry_successful(player: Node, enemy: Node) -> void:
	_append_line("Parry! Stance damage dealt to %s" % enemy.name)

func _on_stance_damaged(enemy: Node, amount: float, remaining: float) -> void:
	_append_line("Stance: %s at %.0f (-%.0f)" % [enemy.name, remaining, amount])

func _on_composure_broken(enemy: Node) -> void:
	_append_line("COMPOSURE BROKEN: %s - Riposte available!" % enemy.name)

func _on_riposte_executed(source: Node, target: Node) -> void:
	_append_line("RIPOSTE! %s executed on %s" % [source.name if source else "?", target.name if target else "?"])

func _on_counter_hit(source: Node, target: Node) -> void:
	_append_line("COUNTER! %s hit %s mid-attack (+15%% dmg)" % [source.name if source else "?", target.name if target else "?"])

func _on_status_effect_applied(target: Node, effect_id: String, _stacks: int) -> void:
	var target_name: String = "YOU" if target is Player else (target.name if target else "?")
	_append_line("%s: %s applied" % [target_name, Constants.STATUS_EFFECT_NAME.get(effect_id, effect_id)])

func _on_status_effect_expired(target: Node, effect_id: String) -> void:
	var target_name: String = "YOU" if target is Player else (target.name if target else "?")
	_append_line("%s: %s expired" % [target_name, Constants.STATUS_EFFECT_NAME.get(effect_id, effect_id)])

func _on_enemy_attack_resolved(enemy: Node, target: Node, hit: bool, parried: bool) -> void:
	if parried:
		return  # already covered by _on_parry_successful
	_append_line("%s's attack landed on %s" % [enemy.name, target.name])

func _on_ability_cast(caster: Node, ability: Ability) -> void:
	var caster_name: String = "YOU" if caster is Player else (caster.name if caster else "?")
	_append_line("%s cast %s" % [caster_name, ability.display_name])

func _on_ability_cast_failed(caster: Node, ability: Ability, reason: String) -> void:
	if caster is Player:
		_append_line("Can't cast %s: %s" % [ability.display_name, reason])

func _on_loot_dropped(item: Item, _at_position: Vector3) -> void:
	_append_line("Loot dropped: %s (%s)" % [item.display_name, Constants.ItemRarity.keys()[item.rarity]])

func _on_slate_dropped(slate: Slate, _at_position: Vector3) -> void:
	_append_line("Slate dropped: %s (%d tiles, %s)" % [slate.display_name, slate.get_size(), Constants.SlateRarity.keys()[slate.rarity]])

func _on_player_leveled_up(new_level: int) -> void:
	_append_line("LEVEL UP! Now level %d" % new_level)

func _on_tome_picked_up(tome: SkillTome) -> void:
	_append_line("Learned: %s" % tome.display_name)

func _on_gold_picked_up(amount: int) -> void:
	_append_line("Picked up %d Gold" % amount)

func _append_line(text: String) -> void:
	label.text += "\n" + text
