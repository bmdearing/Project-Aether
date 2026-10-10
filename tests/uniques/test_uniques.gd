extends Node
## Uniques and Mythics: every catalog entry builds on a real base, they drop
## through the rarity roll, save, can't be Orb-crafted, the corrupted unique,
## each unique mechanic on a live player, and the item card.
## Run: Godot --headless --path . res://tests/uniques/test_uniques.tscn
## Exits 0 when every check passes. Never writes the save file.

const HUB := "res://levels/hub/Hub.tscn"
const ITEM_CARD := "res://ui/item_card/ItemCard.tscn"
const TEST_COUNT := 9

var _checks := 0
var _failures := 0
var _finished := 0
var _hub: Node
var _player: Player
var _equipment: EquipmentComponent
var _fx: UniqueEffects
var _enemy: Enemy

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	_hub = load(HUB).instantiate()
	add_child(_hub)
	await _frames(5)
	_player = get_tree().get_first_node_in_group("player") as Player
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	_equipment = _player.equipment
	_fx = _player.unique_effects
	var arena := Node3D.new()
	add_child(arena)
	_enemy = EnemyRoster.create_unit("hollowed_shambler")
	arena.add_child(_enemy)
	_enemy.global_position = Vector3(400, 0, 400)
	_enemy.set_physics_process(false)
	await _frames(2)

	_test_catalog()
	_test_drops()
	_test_saving_and_crafting()
	await _test_defensive_uniques()
	await _test_offensive_uniques()
	_test_corrupted_unique()
	_test_band_of_wishes()
	_test_card()
	await _test_sands_of_time()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("unique tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _unique(id: String, level: int = 80) -> Item:
	return UniqueRoller.build(UniqueCatalog.get_def(id), level)

## Equips item for the duration of body, then restores the old gear.
func _wearing(item: Item) -> Item:
	var old := _equipment.get_equipped(_slot_of(item))
	_equipment.equip(item, true)
	return old

func _slot_of(item: Item) -> Constants.EquipmentSlot:
	if item is Weapon:
		return Constants.EquipmentSlot.OFFHAND if (item as Weapon).is_offhand else Constants.EquipmentSlot.PRIMARY_WEAPON
	if item is Shield:
		return Constants.EquipmentSlot.OFFHAND
	return item.equip_slot

func _take_off(item: Item, old: Item) -> void:
	if old:
		_equipment.equip(old, true)
	else:
		var slot := _slot_of(item)
		var index := _equipment.rings.find(item) if slot == Constants.EquipmentSlot.RING else 0
		_equipment.unequip(slot, maxi(index, 0))

func _test_catalog() -> void:
	var ids := {}
	for def in UniqueCatalog.DEFS:
		_check(not ids.has(def["id"]), "%s: unique id" % def["id"])
		ids[def["id"]] = true
		if def.get("corrupted_only", false):
			continue
		var item := UniqueRoller.build(def, 80)
		_check(item != null, "%s builds on a real base" % def["id"])
		if item == null:
			continue
		_check(String(item.get_item_type()) == def["base_type"], "%s sits on a %s (got %s)" % [def["id"], def["base_type"], item.get_item_type()])
		_check(item.display_name == def["name"] and item.rarity == def["rarity"] and item.unique_id == def["id"] and item.flavor_text != "", "%s has its name, rarity and flavour" % def["id"])
		var explicit := item.affixes.filter(func(a: ItemAffix): return not a.is_implicit)
		_check(explicit.size() == def["mods"].size(), "%s has every fixed modifier" % def["id"])
		var texts_ok := explicit.all(func(a: ItemAffix): return a.description.find("%d") == -1)
		var values_ok := explicit.all(func(a: ItemAffix): return a.value >= a.value_min - 0.5 and a.value <= a.value_max + 0.5)
		_check(texts_ok and not explicit.any(func(a): return a.description.contains("--") or a.description.contains("+-")), "%s: modifier text is filled in" % def["id"])
		_check(values_ok, "%s: values roll inside their ranges" % def["id"])
	var solen := _unique("unmaking_of_solen_vrath") as Weapon
	_check(solen != null and solen.native_damage_type == Constants.DamageType.AETHERIC and solen.is_two_handed, "Solen Vrath is a two-handed Aetheric weapon")
	var base := UniqueRoller.base_for("claymore", 80) as Weapon
	_check(solen != null and base != null and solen.scaling_grade == maxi(base.scaling_grade - 1, 0), "the Mythic carries the Grade Equivalent Bonus")
	_check(UniqueRoller.base_for("claymore", 1).item_level <= UniqueRoller.base_for("claymore", 90).item_level, "higher drops sit on better bases")
	_finished += 1

func _test_drops() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var seen := {}
	for i in 40000:
		seen[Loot.roll_rarity(1.0, rng)] = true
	_check(seen.has(Constants.ItemRarity.UNIQUE) and seen.has(Constants.ItemRarity.MYTHIC), "the rarity roll can land Unique and Mythic")
	var unique := UniqueRoller.roll(Constants.ItemRarity.UNIQUE, 60)
	_check(unique != null and unique.rarity == Constants.ItemRarity.UNIQUE and not UniqueCatalog.get_def(unique.unique_id).get("corrupted_only", false), "a Unique drop is a droppable catalog unique")
	var mythic := UniqueRoller.roll(Constants.ItemRarity.MYTHIC, 60)
	_check(mythic != null and mythic.rarity == Constants.ItemRarity.MYTHIC, "a Mythic drop is a Mythic (%s)" % (mythic.unique_id if mythic else "none"))
	_check(UniqueRoller.droppable(Constants.ItemRarity.UNIQUE).all(func(d): return not d.get("corrupted_only", false)), "corrupted-only uniques never drop")
	var jewel_rng := RandomNumberGenerator.new()
	jewel_rng.seed = 8
	var jewels_ok := true
	for i in 3000:
		jewels_ok = jewels_ok and JewelRoller.roll(30, 50.0, jewel_rng).rarity <= Constants.ItemRarity.RARE
	_check(jewels_ok, "jewels top out at Rare")
	_finished += 1

func _test_saving_and_crafting() -> void:
	var eye := _unique("the_pale_eye")
	var copy := ItemSerializer.from_dict(JSON.parse_string(JSON.stringify(ItemSerializer.to_dict(eye))))
	_check(copy.unique_id == "the_pale_eye" and copy.rarity == Constants.ItemRarity.UNIQUE and copy.display_name == eye.display_name, "a unique survives a save")
	_check(copy.affixes.size() == eye.affixes.size() and copy.flavor_text == eye.flavor_text, "its modifiers and flavour survive too")
	var resolver := CraftingResolver.create_default()
	_check(not resolver.apply(eye, &"ascendant").success and not resolver.apply(eye, &"reckoning").success, "Orbs don't work on uniques")
	var solen := _unique("unmaking_of_solen_vrath") as Weapon
	_check(not CraftingSystem.infuse(solen)["success"] and solen.infused_damage_type == -1, "Solen Vrath can't be Infused")
	_finished += 1

func _test_defensive_uniques() -> void:
	# The Hollowed King's Mantle: Esoteric comes out of Mana, overflow hurts double.
	var mantle := _unique("hollowed_kings_mantle")
	var ward_before := _player.ward.max_ward
	var old := _wearing(mantle)
	_check(_fx.has(UniqueEffects.ESOTERIC_TO_MANA), "equipping a unique activates its mechanics")
	_check(_player.ward.max_ward >= ward_before, "the Mantle adds more Ward")
	_player.health.current_health = _player.health.max_health
	_player.mana.current_mana = 50.0
	var life := _player.health.current_health
	_player._take_damage_single(30.0, Constants.DamageType.AETHERIC)
	_check(is_equal_approx(_player.health.current_health, life), "Esoteric damage is taken from Mana, not Life")
	_check(_player.mana.current_mana < 50.0, "and Mana pays for it")
	_player.mana.current_mana = 0.0
	life = _player.health.current_health
	_player._take_damage_single(10.0, Constants.DamageType.AETHERIC)
	var lost := life - _player.health.current_health
	_check(lost > 0.0, "with Mana empty the overflow hits Life as Physical (%.1f)" % lost)
	_take_off(mantle, old)
	_check(not _fx.has(UniqueEffects.ESOTERIC_TO_MANA), "unequipping removes the mechanic")

	# The Pale Eye: no Ward recovery at all.
	var eye := _unique("the_pale_eye")
	old = _wearing(eye)
	await _frames(1)
	_check(_player.ward.recovery_blocked, "The Pale Eye blocks Ward recovery")
	_player.ward.max_ward = 100.0
	_player.ward.current_ward = 10.0
	_player.ward.restore(50.0)
	_check(is_equal_approx(_player.ward.current_ward, 10.0), "Ward doesn't restore under The Pale Eye")
	_take_off(eye, old)
	await _frames(1)
	_check(not _player.ward.recovery_blocked, "taking it off unblocks Ward")

	# Solen Vrath: 30% reduced Maximum Life.
	var life_max := _player.health.max_health
	var solen := _unique("unmaking_of_solen_vrath")
	old = _wearing(solen)
	_check(is_equal_approx(_player.health.max_health, life_max * 0.7), "Solen Vrath reduces Maximum Life by 30%% (%.0f -> %.0f)" % [life_max, _player.health.max_health])
	_take_off(solen, old)
	_check(is_equal_approx(_player.health.max_health, life_max), "Life comes back when it's taken off")

	# Hands of the Last Toll: no regen, Life on kill.
	var hands := _unique("hands_of_the_last_toll")
	old = _wearing(hands)
	_check(_player.health.regen_per_second == 0.0, "the Hands stop Life Regeneration")
	_player.health.current_health = _player.health.max_health * 0.5
	var before := _player.health.current_health
	EventBus.enemy_died.emit(null)
	_check(_player.health.current_health > before, "killing an enemy restores Life")
	_take_off(hands, old)

	# The Unpaid Wall: Ward on block, more Spell damage taken.
	var main_hand := _equipment.primary_weapon
	if main_hand and main_hand.is_two_handed:
		_equipment.unequip(Constants.EquipmentSlot.PRIMARY_WEAPON)
	var wall := _unique("the_unpaid_wall")
	old = _wearing(wall)
	_check(_equipment.offhand == wall, "the Wall equips")
	_player.ward.max_ward = 100.0
	_player.ward.current_ward = 0.0
	EventBus.hit_blocked.emit(_player)
	_check(is_equal_approx(_player.ward.current_ward, 10.0), "blocking restores 10%% of Ward (%.1f)" % _player.ward.current_ward)
	_check(is_equal_approx(_fx.damage_taken_multiplier(true), 1.2) and is_equal_approx(_fx.damage_taken_multiplier(false), 1.0), "the Wall makes Spells hit 20% harder")
	_take_off(wall, old)
	if main_hand and _equipment.primary_weapon == null:
		_equipment.equip(main_hand, true)
	_player.health.current_health = _player.health.max_health
	_finished += 1

func _enemy_life() -> float:
	return _enemy.health.current_health

func _reset_enemy() -> void:
	_enemy.health.current_health = _enemy.health.max_health
	_enemy._ward_current = 0.0
	_enemy.status_effects.clear_all_effects()

func _test_offensive_uniques() -> void:
	_enemy.health.max_health = 100000.0
	# Grevane's Accounting: Debt stacks, paid out standing still; weaker on the move.
	var belt := _unique("grevanes_accounting")
	var old := _wearing(belt)
	for i in 3:
		_player._take_damage_single(20.0, Constants.DamageType.KINETIC)
	_check(_fx.debt_stacks == 3, "every hit taken adds a Debt stack (%d)" % _fx.debt_stacks)
	_player.velocity = Vector3(5, 0, 0)
	_check(is_equal_approx(_fx.damage_multiplier(Constants.DamageType.KINETIC), 0.75), "Grevane's: 25% less damage while moving")
	_reset_enemy()
	EventBus.damage_dealt.emit(_player, _enemy, 10.0, Constants.DamageType.KINETIC, false, false)
	_check(_fx.debt_stacks == 3, "Debt isn't paid while moving")
	_player.velocity = Vector3.ZERO
	var life := _enemy_life()
	EventBus.damage_dealt.emit(_player, _enemy, 10.0, Constants.DamageType.KINETIC, false, false)
	_check(_fx.debt_stacks == 0 and _enemy_life() < life, "standing still, the next hit pays the Debt out (%.0f damage)" % (life - _enemy_life()))
	_take_off(belt, old)

	# The Pale Eye: crits apply Pallid, then crits on Pallid enemies hit harder.
	var eye := _unique("the_pale_eye")
	old = _wearing(eye)
	_check(_player.stat_sheet.get_gear_crit_chance_bonus() >= 0.4, "The Pale Eye adds Critical Strike Chance")
	_reset_enemy()
	EventBus.damage_dealt.emit(_player, _enemy, 50.0, Constants.DamageType.KINETIC, false, false)
	_check(not _enemy.status_effects.has_effect("pallid"), "a normal hit doesn't apply Pallid")
	EventBus.damage_dealt.emit(_player, _enemy, 50.0, Constants.DamageType.KINETIC, false, true)
	_check(_enemy.status_effects.has_effect("pallid"), "a Critical Strike applies Pallid")
	life = _enemy_life()
	EventBus.damage_dealt.emit(_player, _enemy, 50.0, Constants.DamageType.KINETIC, false, true)
	_check(_enemy_life() < life, "a crit on a Pallid enemy deals extra damage")
	_take_off(eye, old)

	# Solen Vrath: Aetheric hits echo as Entropic and apply Unraveling.
	var solen := _unique("unmaking_of_solen_vrath")
	old = _wearing(solen)
	_reset_enemy()
	life = _enemy_life()
	EventBus.damage_dealt.emit(_player, _enemy, 100.0, Constants.DamageType.AETHERIC, false, false)
	_check(_enemy_life() < life and _enemy.status_effects.has_effect("unraveling"), "an Aetheric hit echoes as Entropic and Unravels")
	_check(_fx.damage_multiplier(Constants.DamageType.AETHERIC) == 1.0, "the echo isn't a damage multiplier")
	_take_off(solen, old)

	# Stride, Seal, Widow's Patience: conditional damage.
	var boots := _unique("stride_of_the_unwound")
	old = _wearing(boots)
	_player.velocity = Vector3(5, 0, 0)
	_check(_fx.damage_multiplier(Constants.DamageType.KINETIC) >= 1.15, "Stride: more damage while moving")
	await _frames(1)
	_check(_player.ward.recovery_blocked, "Stride: no Ward recovery while moving")
	_player.velocity = Vector3.ZERO
	await _frames(1)
	_check(not _player.ward.recovery_blocked and is_equal_approx(_fx.damage_multiplier(Constants.DamageType.KINETIC), 1.0), "standing still is back to normal")
	_take_off(boots, old)

	var cold_before := _player.stat_sheet.get_resistance(Constants.DamageType.COLD)
	var seal := _unique("seal_of_the_lesser_sun")
	old = _wearing(seal)
	_check(_fx.damage_multiplier(Constants.DamageType.FIRE) >= 1.2 and _fx.damage_multiplier(Constants.DamageType.COLD) == 1.0, "Seal: more Fire damage only")
	_check(_player.stat_sheet.get_resistance(Constants.DamageType.COLD) < cold_before, "Seal: Cold Resistance goes down")
	_take_off(seal, old)

	var widow := _unique("widows_patience")
	old = _wearing(widow)
	_fx._last_hit_msec = -100000
	_check(_fx.damage_multiplier(Constants.DamageType.PIERCING) >= 1.4, "Widow's Patience: a patient shot hits harder")
	EventBus.damage_dealt.emit(_player, _enemy, 1.0, Constants.DamageType.PIERCING, false, false)
	_check(is_equal_approx(_fx.damage_multiplier(Constants.DamageType.PIERCING), 1.0), "but not right after another hit")
	_take_off(widow, old)

	var crown := _unique("crown_of_the_ninth_bell")
	old = _wearing(crown)
	var spark := load("res://data/abilities/instances/spark.tres") as Ability
	if spark:
		_check(spark.get_mana_cost(_player.stat_sheet) > spark.resource_cost, "Crown: spells cost more Mana")
	_take_off(crown, old)
	_enemy.health.max_health = 100.0
	_finished += 1

func _test_corrupted_unique() -> void:
	var ring := Item.new()
	ring.equip_slot = Constants.EquipmentSlot.RING
	ring.display_name = "Plain Band"
	CorruptionOutcome.Transcendent.new().apply(ring, 10)
	_check(ring.unique_id == "debt_of_tharsis" and ring.rarity == Constants.ItemRarity.UNIQUE, "the Shard's Transcendent outcome makes a corrupted unique (%s)" % ring.unique_id)
	_check(ring.affixes.any(func(a: ItemAffix): return a.stat_key == "magic_find"), "with its modifiers")
	_finished += 1

func _card_text(node: Node) -> String:
	var out := ""
	for child in node.find_children("*", "", true, false):
		if child is Label:
			out += child.text + "\n"
		elif child is RichTextLabel:
			out += child.get_parsed_text() + "\n"
	return out

func _test_card() -> void:
	var card: ItemCard = load(ITEM_CARD).instantiate()
	add_child(card)
	card.display_item(_unique("hands_of_the_last_toll"))
	var text := _card_text(card)
	_check(text.contains(AetherStyle.spaced("UNIQUE")) and text.contains("Hands of the Last Toll") and text.contains("Paid in full"), "a unique's card shows the badge, name and flavour")
	card._showing_alt = true
	card._render_alt_info()
	_check(_card_text(card).contains("(3-5)") or _card_text(card).contains("(8-12)"), "Alt shows a unique modifier's range")
	card.display_item(_unique("unmaking_of_solen_vrath"))
	_check(_card_text(card).contains(AetherStyle.spaced("MYTHIC")), "a Mythic's card says MYTHIC")
	card.queue_free()
	_finished += 1

func _ring(stat_key: String, value: float) -> Item:
	var ring := Item.new()
	ring.equip_slot = Constants.EquipmentSlot.RING
	ring.display_name = "Test Ring"
	var a := ItemAffix.new()
	a.stat_key = stat_key
	a.value = value
	a.description = "+%d %s" % [value, stat_key]
	ring.affixes.append(a)
	return ring

func _test_band_of_wishes() -> void:
	var old_rings := _equipment.rings.duplicate()
	_equipment.unequip(Constants.EquipmentSlot.RING, 0)
	_equipment.unequip(Constants.EquipmentSlot.RING, 1)
	var band := _unique("band_of_wishes")
	_check(band.rarity == Constants.ItemRarity.MYTHIC and band.affixes.size() == 1, "the Band of Wishes is a Mythic ring with only its reflection")
	var strength := func() -> float: return _equipment.compute_stat_bonuses().get(Constants.Stat.STRENGTH, 0.0)
	_equipment.equip(band, true)
	_check(is_equal_approx(strength.call(), 0.0), "alone, the Band reflects nothing")
	var other := _ring("flat_strength", 10.0)
	other.socketed.append(Jewel.new())
	other.sockets = 1
	var jewel_mod := ItemAffix.new()
	jewel_mod.stat_key = "flat_strength"
	jewel_mod.value = 5.0
	other.socketed[0].affixes.append(jewel_mod)
	_equipment.equip(other, true)
	_check(is_equal_approx(strength.call(), 30.0), "the Band copies the other ring, jewels included (%.0f)" % strength.call())
	var card: ItemCard = load(ITEM_CARD).instantiate()
	add_child(card)
	card.display_item(band)
	_check(_card_text(card).contains("Reflecting Test Ring"), "the Band's card lists what it reflects")
	card.queue_free()
	var seal := _unique("seal_of_the_lesser_sun")
	_equipment.unequip(Constants.EquipmentSlot.RING, _equipment.rings.find(other))
	_check(band.reflect_source == null and is_equal_approx(strength.call(), 0.0), "taking the other ring off stops the reflection")
	_equipment.equip(seal, true)
	var once: float = seal.affixes.filter(func(a): return a.stat_key == UniqueEffects.MORE_FIRE_DAMAGE)[0].value
	_check(is_equal_approx(_fx.value(UniqueEffects.MORE_FIRE_DAMAGE), once * 2.0), "it reflects unique mechanics too")
	_equipment.unequip(Constants.EquipmentSlot.RING, _equipment.rings.find(seal))
	var band2 := _unique("band_of_wishes")
	_equipment.equip(band2, true)
	_check(band.reflect_source == null and band2.reflect_source == null, "two Bands reflect nothing")
	_equipment.unequip(Constants.EquipmentSlot.RING, 0)
	_equipment.unequip(Constants.EquipmentSlot.RING, 1)
	_check(band.get_effective_affixes().size() == 1, "an unequipped Band keeps only its own modifier")
	for r in old_rings:
		if r:
			_equipment.equip(r, true)
	_finished += 1

## Sands of Time: an Ataras-only Mythic wand whose stance stops time.
func _test_sands_of_time() -> void:
	var def := UniqueCatalog.get_def("sands_of_time")
	_check(def.get("boss") == "ataras" and is_equal_approx(UniqueOdds.per_pinnacle_reward(def, "ataras"), 0.02), "Sands of Time drops only from Ataras, 2% per kill")
	var wand := _unique("sands_of_time") as Weapon
	_check(wand != null and wand.rarity == Constants.ItemRarity.MYTHIC and wand.is_conduit and not wand.is_offhand, "it's a Mythic main-hand conduit")
	_check(StanceInfo.for_conduit(wand).get("name") == "Time Stop" and not wand.affixes.any(func(a): return a.stat_key == "unique_time_stop"), "the wand's own stance is Time Stop, not Spell Library")
	var old := _wearing(wand)
	_player.weapon_stance.set_stance_page(WeaponStance.StancePage.A)
	await _frames(2)
	_check(_player.caster_stance.get_kind() == "time_stop", "its stance is Time Stop")
	_enemy.process_mode = Node.PROCESS_MODE_INHERIT
	_check(_player.caster_stance.try_time_stop(), "Time Stop starts")
	_check(_enemy.process_mode == Node.PROCESS_MODE_DISABLED, "enemies freeze")
	_check(not _player.caster_stance.try_time_stop(), "then it's on cooldown")
	var life := _enemy.health.current_health
	_enemy.take_damage(10.0, Constants.DamageType.KINETIC)
	_check(_enemy.health.current_health < life or _enemy._ward_current >= 0.0, "frozen enemies still take hits")
	await get_tree().create_timer(TimeStop.DURATION + 0.3).timeout
	_check(_enemy.process_mode != Node.PROCESS_MODE_DISABLED and not TimeStop.is_running(), "time runs again after 4 seconds")
	_take_off(wand, old)
	_finished += 1
