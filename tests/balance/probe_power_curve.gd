extends Node
## Reference-build power curve, for tuning monster scaling by Area Level.
## At each level: the player is that level and wears freshly rolled gear of
## that item level in every slot (a melee weapon, no shield), averaged over
## TRIALS rolls. "typical" rolls at Item Rarity x1 (what drops); "good" at
## x6 (mostly Rares). Prints melee DPS, Life, Armour, Evasion and average
## elemental Resistance, then the monster curve those imply.
## Run: Godot --headless --path . res://tests/balance/probe_power_curve.tscn --quit-after 20000

const LEVELS := [1, 10, 20, 30, 40, 50, 60, 70, 80, 89]
const TRIALS := 8
const ARMOUR_SLOTS := [Constants.EquipmentSlot.HELMET, Constants.EquipmentSlot.BODY_ARMOUR, Constants.EquipmentSlot.GLOVES,
	Constants.EquipmentSlot.BOOTS, Constants.EquipmentSlot.AMULET, Constants.EquipmentSlot.BELT]

var _player: Player

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_to_defaults()
	var hub: Node = load("res://levels/hub/Hub.tscn").instantiate()
	add_child(hub)
	for i in 10:
		await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as Player
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	for quality in [["typical", 1.0], ["good", 6.0]]:
		print("POWER %s gear" % quality[0])
		for level in LEVELS:
			var sums := {"dps": 0.0, "life": 0.0, "armour": 0.0, "evasion": 0.0, "res": 0.0}
			for t in TRIALS:
				var r := _measure(level, quality[1])
				for k in sums:
					sums[k] += r[k] / TRIALS
			print("POWER L%-3d dps %8.1f  life %7.1f  armour %7.1f  evasion %7.1f  ele res %5.1f%%" % [level, sums["dps"], sums["life"], sums["armour"], sums["evasion"], sums["res"]])
	get_tree().quit()

func _measure(level: int, rarity_mult: float) -> Dictionary:
	GameState.player_level = level
	_player._on_leveled_up(level)
	var eq := _player.equipment
	for slot in ARMOUR_SLOTS + [Constants.EquipmentSlot.PRIMARY_WEAPON, Constants.EquipmentSlot.OFFHAND]:
		eq.unequip(slot)
	for ring in 2:
		eq.unequip(Constants.EquipmentSlot.RING, ring)
	for slot in ARMOUR_SLOTS:
		var item := _roll_for(level, rarity_mult, func(i: Item): return i.equip_slot == slot and not i is Weapon)
		if item:
			eq.equip(item, true)
	for ring in 2:
		var r := _roll_for(level, rarity_mult, func(i: Item): return i.equip_slot == Constants.EquipmentSlot.RING)
		if r:
			eq.equip(r, true)
	var weapon := _roll_for(level, rarity_mult, func(i: Item): return i is Weapon and not (i as Weapon).is_ranged and not (i as Weapon).is_conduit) as Weapon
	if weapon:
		eq.equip(weapon, true)
	_player._apply_derived_stats()
	var sheet := _player.stat_sheet
	var dps := 0.0
	if weapon:
		var mv: float = _player.melee_attack._effective_motion_value(weapon)
		dps = weapon.predict_damage(mv, sheet) / PlayerMeleeAttack.swing_seconds(weapon.weapon_type)
	var res := 0.0
	for t in [Constants.DamageType.FIRE, Constants.DamageType.COLD, Constants.DamageType.LIGHTNING]:
		res += sheet.get_resistance(t) / 3.0
	return {"dps": dps, "life": _player.health.max_health, "armour": eq.get_total_armor(), "evasion": sheet.get_total_evasion(eq), "res": res}

func _roll_for(level: int, rarity_mult: float, accept: Callable) -> Item:
	for i in 400:
		var item := ItemRoller.roll(level, rarity_mult)
		if item and accept.call(item):
			return item
	return null
