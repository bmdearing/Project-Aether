extends Node
## Pinnacle readiness: the best character the game can build today, against
## Aurelia. A level PLAYER_LEVEL character gets, per archetype, the best
## base and every slot and jewel socket filled greedily with Tier 1 modifiers
## at their top value, each pick maximising DPS x sqrt(effective HP). Prints
## DPS after Aurelia's own mitigation, time to kill, the defences, and each of
## her abilities' hits against that character.
## Not covered: Slates, Uniques, skill-web points, offhands.
## Run: Godot --headless --path . res://tests/balance/probe_pinnacle.tscn --quit-after 60000

const PLAYER_LEVEL := 95
const ITEM_LEVEL := 95
const SPELL_LEVEL := 20
const ARMOUR_SLOTS := [Constants.EquipmentSlot.HELMET, Constants.EquipmentSlot.BODY_ARMOUR, Constants.EquipmentSlot.GLOVES,
	Constants.EquipmentSlot.BOOTS, Constants.EquipmentSlot.AMULET, Constants.EquipmentSlot.BELT, Constants.EquipmentSlot.RING]
## Spark hits on one stationary boss, measured at a 0.8s cast rhythm (each
## spark has its own hit cooldown); scaled by the actual cast rhythm.
const SPARK_HITS_PER_SEC_AT_08 := 26.4

var _player: Player
var _boss: Enemy
var _bases: Array[Item] = []
var _spells: Array[Ability] = []
var _mode := "melee"
var _spell: Ability
## Command-line knobs (after --): tier=N fills every modifier at Tier N's top
## value instead of Tier 1; nojewels leaves sockets empty; modes=melee,spark,spell,ranged
## (ranged: every gun and bow, aimed down sights, through magazines and reloads);
## gear prints each build's items.
var _tier := 1
var _jewels := true
var _modes: Array = ["melee", "spark", "spell"]
var _print_gear := false
## guns: ranged mode leaves out bows and crossbows.
var _guns_only := false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("tier="):
			_tier = int(arg.get_slice("=", 1))
		elif arg == "nojewels":
			_jewels = false
		elif arg.begins_with("modes="):
			_modes = Array(arg.get_slice("=", 1).split(","))
		elif arg == "guns":
			_guns_only = true
		elif arg == "gear":
			_print_gear = true
	SaveManager.slot_prefix = "user://probe_pinnacle_slot"
	GameState.reset_to_defaults()
	GameState.game_started = false
	var hub: Node = load("res://levels/hub/Hub.tscn").instantiate()
	add_child(hub)
	for i in 10:
		await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as Player
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	GameState.player_level = PLAYER_LEVEL
	_player._on_leveled_up(PLAYER_LEVEL)
	_boss = load("res://entities/enemies/aurelia/Aurelia.tscn").instantiate()
	hub.add_child(_boss)
	_boss.global_position = _player.global_position + Vector3(0, 0, 200)
	for i in 5:
		await get_tree().process_frame
	_boss.process_mode = Node.PROCESS_MODE_DISABLED
	_load_bases()
	for f in DirAccess.get_files_at("res://data/abilities/instances/"):
		f = f.trim_suffix(".remap")
		if f.ends_with(".tres"):
			var a := (load("res://data/abilities/instances/" + f) as Ability).duplicate() as Ability
			if a.deals_damage():
				a.level = SPELL_LEVEL
				_spells.append(a)
	print("PINNACLE Aurelia: %.0f Life + %.0f Ward, level %d; her ability base hit %.0f" % [_boss.health.max_health, _boss.get_ward_max(), _boss.level, _boss.get_ability_base_damage()])
	print("PINNACLE her mitigation (taken from a 1000 hit): %s" % _boss_mitigation_text())
	print("PINNACLE gear at Tier %d top values, jewels %s" % [_tier, "on" if _jewels else "off"])
	if _modes.has("melee"):
		await _archetype("melee", null)
	if _modes.has("ranged"):
		await _archetype("ranged", null)
	if _modes.has("spark"):
		await _archetype("spark", _spells.filter(func(a): return a.ability_id == "spark")[0])
	if not _modes.has("spell"):
		get_tree().quit()
		return
	# Best other spell: build for each and keep the strongest.
	var best: Array = []
	for a in _spells:
		if a.ability_id == "spark":
			continue
		var r := await _build("spell", a, false)
		if best.is_empty() or r["dps"] > best[1]:
			best = [a, r["dps"]]
	await _archetype("spell", best[0])
	get_tree().quit()

## ---- Archetypes -----------------------------------------------------------

func _archetype(mode: String, spell: Ability) -> void:
	var r := await _build(mode, spell, true)
	var title: String = mode if spell == null else "%s (%s)" % [mode, spell.display_name]
	var total := _boss.health.max_health + _boss.get_ward_max()
	print("\nPINNACLE === %s ===" % title)
	print("PINNACLE weapon %s  |  raw DPS %.0f  |  vs Aurelia %.0f  |  kill %s" % [r["weapon"], r["raw_dps"], r["dps"], _duration(total / maxf(r["dps"], 0.001))])
	print("PINNACLE Life %.0f  Ward %.0f  Armour %.0f  Evasion %.0f  Res F/C/L/E %.0f/%.0f/%.0f/%.0f  EHP vs her %.0f" % [
		_player.health.max_health, _player.ward.max_ward, _player.equipment.get_total_armor(), _player.stat_sheet.get_total_evasion(_player.equipment),
		_res(Constants.DamageType.FIRE), _res(Constants.DamageType.COLD), _res(Constants.DamageType.LIGHTNING), _res(Constants.DamageType.AETHERIC), r["ehp"]])
	if mode == "melee":
		print("PINNACLE breakdown: ", _melee_breakdown())
	for line in _her_hits():
		print("PINNACLE   ", line)
	if not _print_gear:
		return
	print("PINNACLE gear:")
	for item in _player.equipment.get_all_equipped_items():
		if item == null:
			continue
		var lines: Array = item.get_effective_affixes().map(func(a: ItemAffix): return a.description if a.description != "" else "%s %.0f" % [a.stat_key, a.value])
		print("PINNACLE   %-24s %s" % [item.display_name, "; ".join(lines)])

## Equips the best base and fills every slot greedily; returns the score parts.
func _build(mode: String, spell: Ability, verbose: bool) -> Dictionary:
	_mode = mode
	_spell = spell
	var eq := _player.equipment
	for slot in ARMOUR_SLOTS + [Constants.EquipmentSlot.PRIMARY_WEAPON, Constants.EquipmentSlot.OFFHAND]:
		eq.unequip(slot)
	eq.unequip(Constants.EquipmentSlot.RING, 1)
	# Weapon: try every candidate base bare, keep the top few, then fill each.
	var candidates: Array = _bases.filter(func(b: Item): return b is Weapon and _weapon_fits(b as Weapon))
	var bare: Array = []
	for b in candidates:
		var w := _fresh(b)
		eq.equip(w, true)
		_refresh()
		bare.append([b, _dps()])
	bare.sort_custom(func(x, y): return x[1] > y[1])
	var best_weapon: Item = null
	var best_score := -1.0
	for pair in bare.slice(0, 3):
		var w := _fresh(pair[0])
		eq.equip(w, true)
		_fill(w)
		_refresh()
		if _dps() > best_score:
			best_score = _dps()
			best_weapon = w
	eq.equip(best_weapon, true)
	# Armour and jewellery: the base with the most of its defence, then fill.
	for slot in ARMOUR_SLOTS:
		for copy in (2 if slot == Constants.EquipmentSlot.RING else 1):
			var item := _best_base_for(slot)
			if item:
				eq.equip(item, true)
				_fill(item)
	# Second pass: refill the weapon now that the rest of the build exists.
	best_weapon.affixes = best_weapon.affixes.filter(func(a: ItemAffix): return a.is_implicit)
	best_weapon.socketed.clear()
	_fill(best_weapon)
	_refresh()
	if verbose:
		await get_tree().process_frame
	return {"weapon": best_weapon.display_name, "raw_dps": _raw_dps(), "dps": _dps(), "ehp": _ehp()}

func _weapon_fits(w: Weapon) -> bool:
	if w.item_level > ITEM_LEVEL or w.is_offhand:
		return false
	if _mode == "melee":
		return not w.is_ranged and not w.is_conduit
	if _mode == "ranged":
		return w.is_ranged and not w.is_conduit and (not _guns_only or not [Constants.AmmoType.ARROW, Constants.AmmoType.CROSSBOW_BOLT].has(w.ammo_type))
	return w.is_conduit

func _best_base_for(slot: int) -> Item:
	var best: Item = null
	var best_score := -1.0
	for b in _bases:
		if b is Weapon or b.equip_slot != slot or b.item_level > ITEM_LEVEL:
			continue
		var score := float(b.get("armor_value") if b.get("armor_value") != null else 0.0) + float(b.get("evasion_value") if b.get("evasion_value") != null else 0.0) * 0.5 + float(b.get("ward_value") if b.get("ward_value") != null else 0.0) * 2.0 + b.item_level
		if score > best_score:
			best_score = score
			best = b
	return _fresh(best) if best else null

func _fresh(base: Item) -> Item:
	var item := base.duplicate(true) as Item
	item.item_level = ITEM_LEVEL
	item.rarity = Constants.ItemRarity.RARE
	item.affixes = item.affixes.filter(func(a: ItemAffix): return a.is_implicit)
	item.quality = item.get_quality_cap()
	item.sockets = item.max_sockets
	return item

## Greedy: add the Tier 1 modifier that most raises the score until the
## item's prefixes and suffixes are full, then its sockets' jewels likewise.
func _fill(item: Item) -> void:
	_fill_affixes(item, GearModifierPool.defs_for(item))
	item.socketed.clear()
	if not _jewels:
		return
	for s in item.sockets:
		var jewel := Jewel.new()
		jewel.item_level = ITEM_LEVEL
		jewel.rarity = Constants.ItemRarity.RARE
		item.socketed.append(jewel)
		_fill_affixes(jewel, GearModifierPool.defs_for(jewel))

func _fill_affixes(item: Item, defs: Array[ModifierDef]) -> void:
	var limits := item.get_affix_limits()
	while true:
		var used_groups := item.affixes.map(func(a: ItemAffix): return a.group if a.group != &"" else StringName(a.key()))
		var room_prefix := item.get_prefix_count() < limits.x
		var room_suffix := item.get_suffix_count() < limits.y
		if not room_prefix and not room_suffix:
			return
		var best: ItemAffix = null
		var best_score := _score()
		for def in defs:
			if def.tiers.is_empty() or used_groups.has(def.group):
				continue
			var prefix := def.affix_type == ModifierDef.AffixType.PREFIX
			if (prefix and not room_prefix) or (not prefix and not room_suffix):
				continue
			var affix := _top_affix(def)
			item.affixes.append(affix)
			_refresh()
			var s := _score()
			item.affixes.erase(affix)
			if s > best_score:
				best_score = s
				best = affix
		if best == null:
			return
		item.affixes.append(best)
		_refresh()

func _top_affix(def: ModifierDef) -> ItemAffix:
	# Tier _tier, or the closest one the modifier has.
	var tier: ModifierTier = def.tiers[0]
	for t in def.tiers:
		if absi(t.tier - _tier) < absi(tier.tier - _tier) or (absi(t.tier - _tier) == absi(tier.tier - _tier) and t.tier < tier.tier):
			tier = t
	var affix := ItemAffix.new()
	affix.def = def
	affix.modifier_id = def.id
	affix.group = def.group
	affix.stat_key = def.stat_key
	affix.tier = tier.tier
	affix.value_min = tier.value_min
	affix.value_max = tier.value_max
	affix.value = roundf(tier.value_max) if ItemRoller.has_levelled_tiers(def.stat_key) else tier.value_max
	affix.is_prefix = def.affix_type == ModifierDef.AffixType.PREFIX
	affix.affix_id = String(def.id)
	affix.damage_type = def.damage_type
	affix.is_generic = def.is_generic
	affix.is_local = def.is_local
	affix.description = "%s (T%d)" % [ItemRoller.describe_value(def.text, def.stat_key, affix.value), tier.tier]
	return affix

func _refresh() -> void:
	_player._on_equipment_changed()
	_player._apply_derived_stats()

func _melee_breakdown() -> String:
	var w := _player.equipment.primary_weapon
	var s := _player.stat_sheet
	var hit := w._base_hit(w.get_base_damage(), _player.melee_attack._effective_motion_value(w), s)
	return "avg base %.0f, Str x%.2f, local x%.2f, quality x%.2f, MV %.2f, increased %%%.0f, more x%.2f, crit %.0f%% x%.2f, action speed x%.2f, swing %.2fs, Str %.0f, hit %.0f" % [w.get_base_damage(), 1.0 + s.get_strength_weapon_multiplier(), w.get_local_multiplier("local_increased_weapon_damage"), w.get_quality_multiplier(), _player.melee_attack._effective_motion_value(w), s.get_increased_damage_percent(w.get_damage_type(), true) + s.get_chain_bonus(w.get_damage_type()) * 100.0, s.outgoing_more_multiplier(w.get_damage_type()), hit["crit_chance"] * 100.0, hit["crit_damage_multiplier"], _player.get_action_speed_multiplier(), PlayerMeleeAttack.swing_seconds(w.weapon_type), s.get_stat(Constants.Stat.STRENGTH), hit["base_damage"]]

## ---- Measures ---------------------------------------------------------------

func _score() -> float:
	return _dps() * sqrt(maxf(_ehp(), 1.0))

## Single-target damage per second before Aurelia's mitigation.
func _raw_dps() -> float:
	var sheet := _player.stat_sheet
	if _mode == "melee":
		var w := _player.equipment.primary_weapon
		if w == null:
			return 0.0
		var mv: float = _player.melee_attack._effective_motion_value(w)
		return w.predict_damage(mv, sheet) / (PlayerMeleeAttack.swing_seconds(w.weapon_type) / _player.get_action_speed_multiplier())
	if _mode == "ranged":
		return _ranged_dps(_player.equipment.primary_weapon)
	var hit := _spell.predict_damage(sheet)
	if _spell.ability_id == "spark":
		return hit * SPARK_HITS_PER_SEC_AT_08 * 0.8 / maxf(_spell.get_cast_time(sheet), 0.05)
	var interval := maxf(maxf(_spell.get_cast_time(sheet), _spell.base_recovery_time / maxf(_player.get_action_speed_multiplier(), 0.01)), _spell.get_effective_cooldown(sheet))
	return hit / maxf(interval, 0.05)

## Aimed shots through a full magazine and its reload, as PlayerRangedAttack
## fires: attack speed shortens the fire cooldown and full-auto interval, not
## cycling (bolt/lever/pump/single-action), bow draws or reloads. Extra arrows
## each hit in full.
func _ranged_dps(w: Weapon) -> float:
	if w == null:
		return 0.0
	var speed := _player.get_action_speed_multiplier()
	var interval := PlayerRangedAttack.BASE_FIRE_COOLDOWN / speed
	if w.fire_mode == Constants.FireMode.FULL_AUTO and w.fire_rate > 0.0:
		interval = 1.0 / w.fire_rate / speed
	elif w.fire_mode != Constants.FireMode.SEMI_AUTO:
		interval = maxf(interval, w.cycle_time)
	else:
		interval = maxf(interval, w.get_draw_time())
	var shot := w.predict_damage(PlayerRangedAttack.AIMED_DAMAGE_MULTIPLIER, _player.stat_sheet) * (1 + w.get_local_count("local_additional_arrows"))
	if w.magazine_size <= 0:
		return shot / interval
	var reload := w.cycle_time * w.magazine_size if w.reload_per_shell else w.reload_time
	return shot * w.magazine_size / (w.magazine_size * interval + reload)

func _damage_type() -> int:
	if _mode == "melee" or _mode == "ranged":
		var w := _player.equipment.primary_weapon
		return w.get_damage_type() if w else Constants.DamageType.KINETIC
	return _spell.damage_type

func _hit_size() -> float:
	if _mode == "ranged":
		var g := _player.equipment.primary_weapon
		return g.predict_damage(PlayerRangedAttack.AIMED_DAMAGE_MULTIPLIER, _player.stat_sheet) / maxi(g.pellet_count, 1) if g else 0.0
	if _mode == "melee":
		var w := _player.equipment.primary_weapon
		return w.predict_damage(_player.melee_attack._effective_motion_value(w), _player.stat_sheet) if w else 0.0
	return _spell.predict_damage(_player.stat_sheet)

func _dps() -> float:
	return _raw_dps() * _boss_taken(_damage_type(), _mode != "melee" and _mode != "ranged", maxf(_hit_size(), 1.0))

## Share of a hit of `amount` Aurelia actually loses (Armour depends on its size).
func _boss_taken(damage_type: int, is_spell: bool, amount: float = 1000.0) -> float:
	var h := _boss.health
	var keep_hp := h.current_health
	var keep_ward := _boss._ward_current
	_boss._ward_current = 0.0
	h.current_health = h.max_health
	_boss.take_damage(amount, damage_type, is_spell, false)
	var lost := h.max_health - h.current_health
	h.current_health = keep_hp
	_boss._ward_current = keep_ward
	return lost / amount

func _boss_mitigation_text() -> String:
	var parts: Array[String] = []
	for t in [Constants.DamageType.KINETIC, Constants.DamageType.FIRE, Constants.DamageType.COLD, Constants.DamageType.LIGHTNING, Constants.DamageType.AETHERIC]:
		parts.append("%s %.0f" % [Constants.DAMAGE_TYPE_NAME[t], _boss_taken(t, true) * 1000.0])
	return ", ".join(parts)

func _her_abilities() -> Array:
	return _boss.abilities().filter(func(f): return f.get("damage_mult", 0.0) > 0.0)

## What one of her hits takes from Life + Ward, Deflection's average included.
func _player_taken(amount: float, damage_type: int) -> float:
	var h := _player.health
	var w := _player.ward
	var keep_h := h.current_health
	var keep_w := w.current_ward
	h.current_health = h.max_health
	w.current_ward = w.max_ward
	_player._take_damage_single(amount, damage_type, null)
	var lost := (h.max_health - h.current_health) + (w.max_ward - w.current_ward)
	h.current_health = keep_h
	w.current_ward = keep_w
	var evasion := _player.stat_sheet.get_total_evasion(_player.equipment)
	var deflect := DamageCalculator.deflection_chance(evasion) * DamageCalculator.deflection_mitigation(evasion)
	var dodge := DamageCalculator.dodge_chance(evasion) * _player.stat_sheet.get_misc_bonus("evasion_to_spells") / 100.0
	return lost * (1.0 - deflect) * (1.0 - dodge)

## Pool divided by the average share her abilities take.
func _ehp() -> float:
	var pool := _player.health.max_health + _player.ward.max_ward
	var base := _boss.get_ability_base_damage()
	var ratio := 0.0
	var abilities := _her_abilities()
	for f in abilities:
		var raw: float = base * f["damage_mult"]
		ratio += _player_taken(raw, f["damage_type"]) / raw / abilities.size()
	return pool / maxf(ratio, 0.001)

func _her_hits() -> Array[String]:
	var pool := _player.health.max_health + _player.ward.max_ward
	var base := _boss.get_ability_base_damage()
	var lines: Array[String] = []
	for f in _her_abilities():
		var raw: float = base * f["damage_mult"]
		var taken := _player_taken(raw, f["damage_type"])
		lines.append("%-18s %-9s raw %6.0f  taken %6.0f  = %5.0f%% of Life+Ward" % [f["display_name"], Constants.DAMAGE_TYPE_NAME[f["damage_type"]], raw, taken, taken / pool * 100.0])
	return lines

func _res(t: int) -> float:
	return _player.stat_sheet.get_resistance(t)

func _duration(seconds: float) -> String:
	if seconds < 120.0:
		return "%.0fs" % seconds
	if seconds < 7200.0:
		return "%.1f min" % (seconds / 60.0)
	return "%.1f h" % (seconds / 3600.0)

func _load_bases() -> void:
	if ItemRoller._candidate_meta_cache.is_empty():
		ItemRoller._build_candidate_meta_cache()
	for path in ItemRoller._candidate_meta_cache:
		var item := load(path) as Item
		if item and item.is_equipment():
			_bases.append(item)
