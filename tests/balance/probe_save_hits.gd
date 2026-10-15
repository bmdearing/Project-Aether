extends Node
## A real character against every regular monster: loads a copy of a save
## (user://probe_save_slot<N>.json, never the real slot) and prints, per
## Area Level, each unit's hit before and after the character's defences.
## Run: Godot --headless --path . res://tests/balance/probe_save_hits.tscn --quit-after 20000 -- <slot>

const LEVELS := [16, 19, 22, 25, 28]

var _player: Player

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	SaveManager.slot_prefix = "user://probe_save_slot"
	SaveManager.slot = int(args[0]) if args.size() > 0 else 3
	GameState.reset_to_defaults()
	SaveManager.load_game()
	GameState.game_started = false
	var hub: Node = load("res://levels/hub/Hub.tscn").instantiate()
	add_child(hub)
	for i in 10:
		await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as Player
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	var ev := _player.stat_sheet.get_total_evasion(_player.equipment)
	print("PLAYER %s L%d  Life %.0f  Ward %.0f  Armour %.0f  Evasion %.0f (dodge %.0f%%, deflect %.0f%% x%.0f%%)  res F%.0f C%.0f L%.0f" % [GameState.player_name, GameState.player_level,
		_player.health.max_health, _player.ward.max_ward, _player.equipment.get_total_armor(), ev,
		DamageCalculator.dodge_chance(ev) * 100.0, DamageCalculator.deflection_chance(ev) * 100.0, DamageCalculator.deflection_mitigation(ev) * 100.0,
		_player.stat_sheet.get_effective_resistance(Constants.DamageType.FIRE, 0.0), _player.stat_sheet.get_effective_resistance(Constants.DamageType.COLD, 0.0), _player.stat_sheet.get_effective_resistance(Constants.DamageType.LIGHTNING, 0.0)])
	for item in _player.equipment.get_all_equipped_items():
		print("  worn: %s (ilvl %d)" % [item.display_name, item.item_level])
	for level in LEVELS:
		var f := FigmentItem.new()
		f.depth = (level + AreaLevel.LEVELS_PER_DEPTH - 1) / AreaLevel.LEVELS_PER_DEPTH
		GameState.active_map = f
		print("AL %d (Depth %d)" % [AreaLevel.of_figment(f), f.depth])
		for file in DirAccess.get_files_at("res://data/enemies/definitions/"):
			if not file.ends_with(".tres"):
				continue
			var def := load("res://data/enemies/definitions/" + file) as EnemyDefinition
			if def == null or def.archetype_category == "boss" or def.archetype_category == "elite" and file.begins_with("aurelia"):
				continue
			var e := EnemyRoster.create_unit(file.get_basename())
			add_child(e)
			e.process_mode = Node.PROCESS_MODE_DISABLED
			var attack: Node = e.get_node_or_null("MeleeAttack")
			if attack == null:
				attack = e.get_node_or_null("RangedAttack")
			if attack == null:
				e.queue_free()
				continue
			var raw: float = attack.damage_amount * e.get_outgoing_damage_multiplier() * AreaLevel.gap_damage_multiplier(e.level, GameState.player_level)
			var dtype: int = e.convert_attack_type(attack.damage_type)
			var taken := _taken(raw, dtype)
			var pool := _player.health.max_health + _player.ward.max_ward
			print("  %-26s %-8s %-9s raw %6.0f  taken %6.0f  = %5.1f%% of Life+Ward  (every %.1fs)" % [file.get_basename(), def.archetype_category,
				Constants.DAMAGE_TYPE_NAME.get(dtype, "?"), raw, taken, taken / pool * 100.0, def.attack_cooldown])
			e.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _taken(amount: float, damage_type: int) -> float:
	var h := _player.health
	var w := _player.ward
	h.current_health = h.max_health
	w.current_ward = w.max_ward
	_player._take_damage_single(amount, damage_type, null)
	var lost := (h.max_health - h.current_health) + (w.max_ward - w.current_ward)
	h.current_health = h.max_health
	w.current_ward = w.max_ward
	return lost
