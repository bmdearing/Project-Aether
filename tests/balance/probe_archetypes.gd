extends Node
## Defence archetypes against on-level map mobs, for comparing Life, Armour,
## Evasion and Ward builds. At each Area Level the player wears the best base
## of the archetype's defence type in every armour slot (and a shield), each
## with the archetype's modifiers at the best tier that item level allows
## (mid-roll, slot rules and 3 prefix / 3 suffix respected), plus jewellery.
## Slates are stood in for by a bonus to the archetype's attribute, scaled
## from ATTRIBUTE_AT_89 down with Area Level.
## Prints Life, Ward, Armour, Evasion and dodge, then what one standard /
## heavy / elite hit takes from Life + Ward after defences (dodge and
## deflection as expected values) and how many such hits the pool lasts.
## Regeneration and Ward recharge are left out.
## Run: Godot --headless --path . res://tests/balance/probe_archetypes.tscn --quit-after 200000 -- [attribute at 89]

const LEVELS := [1, 19, 40, 67, 79, 89]
const ATTRIBUTE_AT_89 := 250.0
const MOBS := {"standard": "unchartered_brigand", "heavy": "unchartered_enforcer", "elite": "unchartered_chieftain"}
const ARMOUR_SLOTS := [Constants.EquipmentSlot.HELMET, Constants.EquipmentSlot.BODY_ARMOUR, Constants.EquipmentSlot.GLOVES,
	Constants.EquipmentSlot.BOOTS, Constants.EquipmentSlot.OFFHAND]
const JEWELLERY := [Constants.EquipmentSlot.AMULET, Constants.EquipmentSlot.BELT, Constants.EquipmentSlot.RING, Constants.EquipmentSlot.RING]

## name -> defence pattern ("a", "e", "w" letters present), attribute, and
## modifiers in priority order for armour pieces and for jewellery.
const ARCHETYPES := {
	"Life + Armour": {"pattern": "a", "stat": Constants.Stat.STRENGTH,
		"armour": ["flat_life", "life_increased", "flat_armor", "increased_armor", "flat_strength", "reduced_physical_taken"],
		"jewellery": ["flat_life", "life_increased", "flat_strength", "flat_armor"]},
	"Life + Evasion": {"pattern": "e", "stat": Constants.Stat.STRENGTH,
		"armour": ["flat_life", "life_increased", "flat_evasion", "increased_evasion", "flat_strength", "flat_agility"],
		"jewellery": ["flat_life", "life_increased", "flat_strength", "flat_evasion"]},
	"Life + Armour/Evasion": {"pattern": "ae", "stat": Constants.Stat.STRENGTH,
		"armour": ["flat_life", "life_increased", "increased_armor", "increased_evasion", "flat_strength", "reduced_physical_taken"],
		"jewellery": ["flat_life", "life_increased", "flat_strength", "flat_armor"]},
	"Ward stacker": {"pattern": "w", "stat": Constants.Stat.INTELLECT,
		"armour": ["flat_ward", "increased_ward", "flat_intellect", "ward_recovery_increased", "flat_life"],
		"jewellery": ["flat_ward", "flat_intellect", "flat_life"]},
	"Ward + Armour": {"pattern": "aw", "stat": Constants.Stat.INTELLECT,
		"armour": ["flat_ward", "increased_ward", "increased_armor", "flat_intellect", "flat_armor"],
		"jewellery": ["flat_ward", "flat_intellect", "flat_armor"]},
	"Ward + Evasion": {"pattern": "ew", "stat": Constants.Stat.INTELLECT,
		"armour": ["flat_ward", "increased_ward", "increased_evasion", "flat_intellect", "flat_evasion"],
		"jewellery": ["flat_ward", "flat_intellect", "flat_evasion"]},
}

var _player: Player
var _hub: Node
var _bases: Array[Item] = []
var _attribute_at_89 := ATTRIBUTE_AT_89

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_attribute_at_89 = float(args[0])
	SaveManager.slot_prefix = "user://probe_archetypes_slot"
	GameState.reset_to_defaults()
	GameState.game_started = false
	_hub = load("res://levels/hub/Hub.tscn").instantiate()
	add_child(_hub)
	for i in 10:
		await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as Player
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_load_bases()
	print("ARCH attribute from Slates: %.0f at AL89, scaled down with level" % _attribute_at_89)
	for level in LEVELS:
		await _measure_level(level)
	print("ARCH done")
	get_tree().quit()

func _load_bases() -> void:
	for dir_path in ["res://data/armor/instances/", "res://data/shields/instances/"]:
		for file in DirAccess.get_files_at(dir_path):
			if file.ends_with(".tres"):
				var item := load(dir_path + file) as Item
				if item and item.base_line_id != "":
					_bases.append(item)

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
	var tier_text := " T%d" % (level - AreaLevel.ENDGAME_BASE) if level > AreaLevel.ENDGAME_BASE else ""
	print("ARCH ---- AL%d%s  std hit %.0f  heavy %.0f  elite %.0f" % [level, tier_text,
		(mobs["standard"] as Enemy).get_ability_base_damage(), (mobs["heavy"] as Enemy).get_ability_base_damage(), (mobs["elite"] as Enemy).get_ability_base_damage()])
	for arch_name in ARCHETYPES:
		_measure_archetype(arch_name, ARCHETYPES[arch_name], level, mobs)
	for e in mobs.values():
		e.queue_free()
	GameState.active_map = null

func _measure_archetype(arch_name: String, arch: Dictionary, level: int, mobs: Dictionary) -> void:
	var eq := _player.equipment
	for slot in ARMOUR_SLOTS + [Constants.EquipmentSlot.PRIMARY_WEAPON, Constants.EquipmentSlot.AMULET, Constants.EquipmentSlot.BELT]:
		eq.unequip(slot)
	for ring in 2:
		eq.unequip(Constants.EquipmentSlot.RING, ring)
	var bases_used: Array[String] = []
	for slot in ARMOUR_SLOTS:
		var base := _best_base(slot, arch["pattern"], level)
		if base == null:
			bases_used.append("-")
			continue
		bases_used.append(base.display_name)
		var item := base.duplicate(true) as Item
		_add_mods(item, arch["armour"], level)
		eq.equip(item, true)
	for slot in JEWELLERY:
		var item := Item.new()
		item.equip_slot = slot
		item.item_level = level
		item.rarity = Constants.ItemRarity.RARE
		item.display_name = "Probe jewellery"
		_add_mods(item, arch["jewellery"], level)
		eq.equip(item, true)
	var attribute := _attribute_at_89 * float(level) / 89.0
	_player.stat_sheet.set_slate_bonus({arch["stat"]: attribute})
	_player._apply_derived_stats()
	var life := _player.health.max_health
	var ward := _player.ward.max_ward
	var pool := life + ward
	var armour := eq.get_total_armor()
	var evasion := _player.stat_sheet.get_total_evasion(eq)
	var dodge := DamageCalculator.player_dodge_chance(evasion)
	var line := "ARCH %-22s Life %5.0f  Ward %5.0f  Armour %5.0f  Evasion %5.0f (dodge %2.0f%%)" % [arch_name, life, ward, armour, evasion, dodge * 100.0]
	for size in MOBS:
		var e: Enemy = mobs[size]
		var taken := _player_taken(e.get_ability_base_damage(), e.get_ability_damage_type(), evasion)
		line += "  %s %5.1f%% (%4.1f hits)" % [size, taken / pool * 100.0, pool / maxf(taken, 0.001)]
	print(line)
	print("ARCH                        bases: %s" % ", ".join(bases_used))

## The highest-level base of `pattern` for the slot that the level allows,
## strongest primary defence first.
func _best_base(slot: int, pattern: String, level: int) -> Item:
	var best: Item = null
	for base in _bases:
		var base_slot: int = Constants.EquipmentSlot.OFFHAND if base is Shield else base.equip_slot
		if base_slot != slot or base.item_level > level or _pattern_of(base) != pattern:
			continue
		if best == null or base.item_level > best.item_level or (base.item_level == best.item_level and _defence_sum(base) > _defence_sum(best)):
			best = base
	return best

static func _pattern_of(item: Item) -> String:
	var p := ""
	if float(item.get("armor_value")) > 0.0:
		p += "a"
	if float(item.get("evasion_value")) > 0.0:
		p += "e"
	if float(item.get("ward_value")) > 0.0:
		p += "w"
	return p

static func _defence_sum(item: Item) -> float:
	return float(item.get("armor_value")) + float(item.get("evasion_value")) + float(item.get("ward_value"))

## Adds each wanted modifier the item's pool allows, at the best tier its
## level reaches (mid-roll), until 3 prefixes and 3 suffixes are used.
func _add_mods(item: Item, wanted: Array, level: int) -> void:
	item.affixes = item.affixes.filter(func(a: ItemAffix) -> bool: return a.is_implicit)
	var pool := ItemRoller._pool_for(item)
	var sides := {true: 0, false: 0}
	for key in wanted:
		var entry := {}
		for candidate in pool:
			if candidate["stat_key"] == key:
				entry = candidate
				break
		if entry.is_empty():
			continue
		var is_prefix := not GearModifierPool._is_suffix(key)
		if sides[is_prefix] >= 3:
			continue
		var value_range := Vector2.ZERO
		var tier := 1
		if ItemRoller.has_levelled_tiers(key):
			var rows := ItemRoller.levelled_tiers_for(key, level)
			if rows.is_empty():
				rows = [ItemRoller.levelled_table(key)[-1]]
			var row: Array = rows[0]
			value_range = Vector2(row[1], row[2])
			tier = ItemRoller.levelled_table(key).find(row) + 1
		else:
			tier = ItemRoller.best_tier_for_level(level)
			var t2 := ItemRoller.entry_tiers(entry, item.equip_slot)
			value_range = ItemRoller._tier_range(t2.x, t2.y, tier)
		var affix := ItemAffix.new()
		affix.stat_key = key
		affix.value = (value_range.x + value_range.y) / 2.0
		affix.value_min = value_range.x
		affix.value_max = value_range.y
		affix.tier = tier
		affix.is_prefix = is_prefix
		item.affixes.append(affix)
		sides[is_prefix] += 1

## One hit's expected loss of Life + Ward: mitigation as the game applies it,
## then dodge and deflection as expected values (attacks).
func _player_taken(amount: float, damage_type: int, evasion: float) -> float:
	var h := _player.health
	var w := _player.ward
	h.current_health = h.max_health
	w.current_ward = w.max_ward
	_player._take_damage_single(amount, damage_type, null)
	var lost := (h.max_health - h.current_health) + (w.max_ward - w.current_ward)
	h.current_health = h.max_health
	w.current_ward = w.max_ward
	var dodge := DamageCalculator.player_dodge_chance(evasion)
	var deflect := DamageCalculator.player_deflection_chance(evasion) * DamageCalculator.player_deflection_mitigation(evasion)
	return lost * (1.0 - dodge) * (1.0 - deflect)

func _figment_at(level: int) -> FigmentItem:
	var f := FigmentItem.new()
	if level > AreaLevel.ENDGAME_BASE:
		f.tier = level - AreaLevel.ENDGAME_BASE
	else:
		f.depth = (level + AreaLevel.LEVELS_PER_DEPTH - 1) / AreaLevel.LEVELS_PER_DEPTH
	return f
