extends Node
## Map mobs against an on-level character, for tuning AreaLevel's curves.
## At each Area Level the player is that level in Rare gear of that item
## level (EndgameTestCharacter's roll: Item Rarity x6) with spells at the
## level SPELL_LEVEL gives. Prints the best single-target DPS (melee, or
## EndgameTestCharacter's spells from a Conduit) and, per mob size, its Life,
## seconds to kill after its own mitigation, and one hit's share of the
## player's Life + Ward after the player's defences.
## Run: Godot --headless --path . res://tests/balance/probe_map_mobs.tscn --quit-after 200000

## Area Level -> spell level (Depths reach 67, Tiers 69-89).
const SPELL_LEVEL := {1: 1, 19: 6, 40: 11, 67: 16, 69: 17, 79: 19, 89: 20}
const TRIALS := 6
const MOBS := {"standard": "unchartered_brigand", "heavy": "unchartered_enforcer", "elite": "unchartered_chieftain"}
const ARMOUR_SLOTS := [Constants.EquipmentSlot.HELMET, Constants.EquipmentSlot.BODY_ARMOUR, Constants.EquipmentSlot.GLOVES,
	Constants.EquipmentSlot.BOOTS, Constants.EquipmentSlot.AMULET, Constants.EquipmentSlot.BELT]

var _player: Player
var _hub: Node
var _spells: Array[Ability] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	SaveManager.slot_prefix = "user://probe_map_mobs_slot"
	GameState.reset_to_defaults()
	GameState.game_started = false
	_hub = load("res://levels/hub/Hub.tscn").instantiate()
	add_child(_hub)
	for i in 10:
		await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as Player
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	for id in EndgameTestCharacter.SPELLS:
		var a := (load("res://data/abilities/instances/%s.tres" % id) as Ability).duplicate() as Ability
		if a.deals_damage():
			_spells.append(a)
	for level in SPELL_LEVEL:
		await _measure_level(level)
	get_tree().quit()

func _measure_level(level: int) -> void:
	GameState.active_map = _figment_at(level)
	GameState.player_level = level
	_player._on_leveled_up(level)
	var mobs := {}
	for size in MOBS:
		var e := EnemyRoster.create_unit(MOBS[size])
		_hub.add_child(e)
		e.global_position = _player.global_position + Vector3(0, 0, 300 + mobs.size() * 20)
		mobs[size] = e
	for i in 3:
		await get_tree().process_frame
	for e in mobs.values():
		e.process_mode = Node.PROCESS_MODE_DISABLED
	var sums := {}
	for t in TRIALS:
		var r := _trial(level, mobs)
		for k in r:
			sums[k] = sums.get(k, 0.0) + r[k] / TRIALS
	print("MOBS AL%-3d spell L%-2d  dps %9.0f (melee %8.0f, spell %8.0f)  Life+Ward %6.0f  Armour %6.0f  res %3.0f%%" % [level, SPELL_LEVEL[level],
		maxf(sums["melee"], sums["spell"]), sums["melee"], sums["spell"], sums["pool"], sums["armour"], sums["res"]])
	for size in MOBS:
		var e: Enemy = mobs[size]
		print("MOBS        %-8s life %9.0f  hit %7.0f  kill %6.2fs  hit takes %5.1f%%" % [size, e.health.max_health, e.get_ability_base_damage(),
			sums[size + "_ttk"], sums[size + "_hit"] * 100.0])
		e.queue_free()
	GameState.active_map = null

func _trial(level: int, mobs: Dictionary) -> Dictionary:
	var eq := _player.equipment
	for slot in ARMOUR_SLOTS + [Constants.EquipmentSlot.PRIMARY_WEAPON, Constants.EquipmentSlot.OFFHAND]:
		eq.unequip(slot)
	for ring in 2:
		eq.unequip(Constants.EquipmentSlot.RING, ring)
	for slot in ARMOUR_SLOTS:
		var item := _roll(level, func(i: Item): return i.equip_slot == slot and not i is Weapon)
		if item:
			eq.equip(item, true)
	for ring in 2:
		var r := _roll(level, func(i: Item): return i.equip_slot == Constants.EquipmentSlot.RING)
		if r:
			eq.equip(r, true)
	var out := {}
	# Melee first, then the spells from a Conduit.
	var melee := _roll(level, func(i: Item): return i is Weapon and not (i as Weapon).is_ranged and not (i as Weapon).is_conduit) as Weapon
	var melee_dps := 0.0
	var melee_type := Constants.DamageType.KINETIC
	if melee:
		eq.equip(melee, true)
		_player._apply_derived_stats()
		var mv: float = _player.melee_attack._effective_motion_value(melee)
		melee_dps = melee.predict_damage(mv, _player.stat_sheet) / (PlayerMeleeAttack.swing_seconds(melee.weapon_type) / _player.get_action_speed_multiplier())
		melee_type = melee.get_damage_type()
		eq.unequip(Constants.EquipmentSlot.PRIMARY_WEAPON)
	var conduit := _roll(level, func(i: Item): return i is Weapon and (i as Weapon).is_conduit)
	if conduit:
		eq.equip(conduit, true)
	_player._apply_derived_stats()
	var sheet := _player.stat_sheet
	var spell_dps := 0.0
	var spell_type := Constants.DamageType.LIGHTNING
	for a in _spells:
		a.level = SPELL_LEVEL[level]
		var interval := maxf(maxf(a.get_cast_time(sheet), a.base_recovery_time / maxf(_player.get_action_speed_multiplier(), 0.01)), a.get_effective_cooldown(sheet))
		var dps := a.predict_damage(sheet) / maxf(interval, 0.05)
		if dps > spell_dps:
			spell_dps = dps
			spell_type = a.damage_type
	var use_spell := spell_dps > melee_dps
	var dps := spell_dps if use_spell else melee_dps
	var type: int = spell_type if use_spell else melee_type
	var pool := _player.health.max_health + _player.ward.max_ward
	out["melee"] = melee_dps
	out["spell"] = spell_dps
	out["pool"] = pool
	out["armour"] = eq.get_total_armor()
	var res := 0.0
	for t in [Constants.DamageType.FIRE, Constants.DamageType.COLD, Constants.DamageType.LIGHTNING]:
		res += sheet.get_resistance(t) / 3.0
	out["res"] = res
	for size in mobs:
		var e: Enemy = mobs[size]
		var effective := dps * _enemy_taken(e, type, use_spell)
		out[size + "_ttk"] = (e.health.max_health + e.get_ward_max()) / maxf(effective, 0.001)
		out[size + "_hit"] = _player_taken(e.get_ability_base_damage(), e.get_ability_damage_type()) / pool
	return out

func _enemy_taken(e: Enemy, damage_type: int, is_spell: bool) -> float:
	var h := e.health
	var keep_ward := e._ward_current
	e._ward_current = 0.0
	h.current_health = h.max_health
	e.take_damage(100.0, damage_type, is_spell, false)
	var lost := h.max_health - h.current_health
	h.current_health = h.max_health
	e._ward_current = keep_ward
	return lost / 100.0

func _player_taken(amount: float, damage_type: int) -> float:
	var h := _player.health
	var w := _player.ward
	h.current_health = h.max_health
	w.current_ward = w.max_ward
	_player._take_damage_single(amount, damage_type, null)
	var lost := (h.max_health - h.current_health) + (w.max_ward - w.current_ward)
	h.current_health = h.max_health
	w.current_ward = w.max_ward
	var evasion := _player.stat_sheet.get_total_evasion(_player.equipment)
	return lost * (1.0 - DamageCalculator.player_deflection_chance(evasion) * DamageCalculator.player_deflection_mitigation(evasion))

func _figment_at(level: int) -> FigmentItem:
	var f := FigmentItem.new()
	if level > AreaLevel.ENDGAME_BASE:
		f.tier = level - AreaLevel.ENDGAME_BASE
	else:
		f.depth = (level + AreaLevel.LEVELS_PER_DEPTH - 1) / AreaLevel.LEVELS_PER_DEPTH
	return f

func _roll(level: int, accept: Callable) -> Item:
	var fallback: Item = null
	for i in 1500:
		var item := ItemRoller.roll(level, EndgameTestCharacter.GEAR_RARITY)
		if item == null or not accept.call(item):
			continue
		if item.rarity >= Constants.ItemRarity.RARE:
			return item
		if fallback == null:
			fallback = item
	return fallback
