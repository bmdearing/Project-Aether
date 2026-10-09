extends Node
## Headless checks for Orbs on real loot (GearModifierPool/SlateModifierPool),
## old Cube Brand conversion, currency drops and pickups, and the Crafting
## screen inside the real Hub.
## Run: Godot --headless --path . res://tests/crafting/test_real_pools.tscn
## Exits 0 when every check passes. Never writes the save file.

const E := CraftResult.CraftError
const HUB := "res://levels/hub/Hub.tscn"
const LOOT_PICKUP := "res://entities/pickups/loot_pickup/LootPickup.tscn"
const ROLLS := 60

var _checks := 0
var _failures := 0
var _finished := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	_test_real_gear()
	_test_real_slates()
	_test_legacy_brands()
	_test_currency_drops()
	await _test_hub_crafting()
	_check(_finished == 5, "every test function ran to the end (%d/5)" % _finished)
	print("real pool tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _resolver() -> CraftingResolver:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	return CraftingResolver.create_default(rng)

func _explicits(target: Resource) -> Array[ItemAffix]:
	return CraftTarget.wrap(target).get_explicits()

func _within_limits(target: Resource) -> bool:
	var t := CraftTarget.wrap(target)
	var ex := t.get_explicits()
	var prefixes := ex.filter(func(a: ItemAffix): return a.is_prefix).size()
	var lim := t.get_affix_limits(t.get_rarity())
	return prefixes <= lim.x and ex.size() - prefixes <= lim.y

func _test_real_gear() -> void:
	var resolver := _resolver()
	var crafted := 0
	var weapons := 0
	var bad_preview := 0
	var bad_limits := 0
	var dup_groups := 0
	var missing_stat := 0
	var weapon_types_ok := true
	var mislabelled := 0
	for i in ROLLS:
		var item := ItemRoller.roll(30 + i % 50)
		if item == null:
			continue
		if not item is Weapon and item.rarity < Constants.ItemRarity.UNIQUE:
			for a in _explicits(item):
				if a.is_prefix == GearModifierPool._is_suffix(a.stat_key):
					mislabelled += 1
			if not _within_limits(item):
				bad_limits += 1
		item.tolerance = 500
		var start_rarity := item.rarity
		var orb := &"quickening" if start_rarity == Constants.ItemRarity.COMMON else &"absolution"
		if orb == &"absolution":
			resolver.apply(item, orb)
		var p := resolver.preview(item, &"forging")
		if p.is_valid() and absf(p.total_probability() - 1.0) > 0.000001:
			bad_preview += 1
		var r := resolver.apply(item, &"forging")
		if not r.success:
			continue
		crafted += 1
		if not _within_limits(item):
			bad_limits += 1
		var groups := _explicits(item).map(func(a: ItemAffix): return a.get_group())
		for g in groups:
			if groups.count(g) > 1:
				dup_groups += 1
		for a in r.added:
			if a.stat_key == "" or not a.description.contains("Tier"):
				missing_stat += 1
		if item is Weapon:
			weapons += 1
			var lib_ids := []
			for want_prefix in [true, false]:
				for source in ItemRoller._eligible_weapon_affixes(item, maxi(item.item_level, 1), want_prefix):
					lib_ids.append(StringName(source.affix_id if source.affix_id != "" else source.stat_key))
			for a in r.added:
				if not lib_ids.has(a.modifier_id):
					weapon_types_ok = false
		while resolver.apply(item, &"ascendant").success:
			pass
		if not _within_limits(item):
			bad_limits += 1
	_check(crafted > ROLLS / 2, "forging works on most real drops (%d/%d)" % [crafted, ROLLS])
	_check(weapons > 0 and weapon_types_ok, "weapons roll only their eligible library modifiers")
	_check(bad_preview == 0, "real-pool preview probabilities sum to 1")
	_check(bad_limits == 0, "real drops and crafts respect rarity limits")
	_check(mislabelled == 0, "dropped gear labels prefixes and suffixes the way Orbs do (%d wrong)" % mislabelled)
	_check(dup_groups == 0, "no duplicate modifier groups on real items")
	_check(missing_stat == 0, "rolled real modifiers have stat keys and descriptions")

	# Tag Brands steer real gear too.
	var ring := Item.new()
	ring.equip_slot = Constants.EquipmentSlot.RING
	ring.item_level = 50
	ring.tolerance = 100
	var bag := CurrencyBag.new()
	bag.add_currency(&"brand_fire", 5)
	var active := ActiveBrands.new(bag)
	active.activate(&"brand_fire")
	var r := resolver.apply(ring, &"quickening", active)
	_check(r.success and r.added[0].def.tags.has(&"fire"), "fire brand steers a real ring modifier")
	# Item level gates the best tiers.
	var low := Item.new()
	low.equip_slot = Constants.EquipmentSlot.RING
	low.item_level = 1
	low.tolerance = 100
	var p := resolver.preview(low, &"quickening")
	_check(p.is_valid() and p.outcomes.all(func(o): return o["tier"].tier >= ItemRoller.TIER_COUNT - 1), "low item level can't roll top tiers")
	# A pre-Orb rolled modifier gets its description refreshed by Reckoning.
	var legacy := ItemRoller.roll(40)
	while legacy == null or legacy is Weapon or _explicits(legacy).is_empty() or legacy.rarity >= Constants.ItemRarity.UNIQUE:
		legacy = ItemRoller.roll(40)
	legacy.tolerance = 100
	resolver.apply(legacy, &"reckoning")
	var after := _explicits(legacy)[0]
	var expected := "%s (Tier %d)" % [ItemRoller.describe_value(CraftingResolver._template_for(after), after.stat_key, after.value), after.tier]
	_check(CraftingResolver._template_for(after) != "" and after.description == expected, "reckoning redescribes pre-Orb modifiers")
	_finished += 1

func _test_real_slates() -> void:
	var resolver := _resolver()
	var ok := 0
	var on_tag := true
	for i in 30:
		var slate := SlateRoller.roll(10, 0.0)  # Item Rarity 0: always a Common drop
		_check(slate.rarity == Constants.SlateRarity.COMMON and slate.tolerance > 0, "slate drops start Common with tolerance")
		var r := resolver.apply(slate, &"forging")
		if not r.success:
			continue
		ok += 1
		var allowed := slate.get_slate_tags()
		for a in slate.explicits:
			if not a.def.tags.any(func(t): return allowed.has(t)):
				on_tag = false
		_check(_within_limits(slate) and slate.explicits.size() >= 3, "slate forging gives 3-4 within limits")
	_check(ok == 30, "forging works on every real slate drop (%d/30)" % ok)
	_check(on_tag, "slates only roll modifiers for their own tags")
	# Forging can add 4, so every tag needs 2 prefixes and 2 suffixes of its own.
	for tag in SlateRoller.REAL_DAMAGE_TYPES.map(func(t): return Constants.DAMAGE_TYPE_NAME[t].to_lower()) + ["spell"]:
		var pool := SlateAffixPool.get_pool_for_tag(tag)
		var prefixes := pool.filter(func(a: SlateAffix): return a.is_prefix).size()
		_check(prefixes >= 2 and pool.size() - prefixes >= 2, "%s Slates have 2+ prefixes and 2+ suffixes (%d/%d)" % [tag, prefixes, pool.size() - prefixes])
	var hybrid := Slate.new()
	hybrid.shape_cells = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 0)]
	hybrid.tag = Constants.DamageType.FIRE
	hybrid.is_hybrid = true
	hybrid.secondary_tag = Constants.DamageType.COLD
	CraftingResolver.roll_tolerance(hybrid)
	var hybrid_tags := SlateModifierPool.defs_for(hybrid).map(func(d: ModifierDef): return d.tags[0])
	_check(hybrid_tags.has(&"fire") and hybrid_tags.has(&"cold") and hybrid_tags.all(func(t): return t == &"fire" or t == &"cold"), "a Fire/Cold Hybrid rolls only Fire and Cold modifiers")
	var spell_slate := hybrid.duplicate(true) as Slate
	spell_slate.is_hybrid = false
	spell_slate.category_tag_override = "Spell"
	_check(SlateModifierPool.defs_for(spell_slate).all(func(d: ModifierDef): return d.tags[0] == &"spell"), "a Spell Slate rolls only Spell modifiers")
	_check(resolver.apply(spell_slate, &"forging").success, "forging works on a Spell Slate")
	var original := SlateRoller.roll(10, 20.0)
	var copy := SlateSerializer.from_dict(JSON.parse_string(JSON.stringify(SlateSerializer.to_dict(original))))
	_check(copy != null and copy.rarity == original.rarity and copy.explicits.size() == original.explicits.size(), "slate round trip keeps rarity and modifiers")
	_finished += 1

func _test_legacy_brands() -> void:
	var inv := GridInventory.new()
	var data := inv.to_dict()
	data["entries"] = [
		{"x": 0, "y": 0, "count": 1, "item": {"class": "Brand", "item_id": "calcine", "display_name": "Calcine"}},
		{"x": 1, "y": 0, "count": 1, "item": {"class": "Brand", "item_id": "cleave", "display_name": "Cleave"}},
		{"x": 2, "y": 0, "count": 1, "item": {"class": "Brand", "item_id": "unknown_brand"}},
	]
	var loaded := GridInventory.from_dict(data)
	_check(loaded.count_of(&"brand_fire") == 1 and loaded.count_of(&"anchoring") == 1 and loaded.get_entries().size() == 2, "old Brands convert to Rev2 currency on load")
	for id in ItemSerializer.LEGACY_BRAND_CURRENCY.values():
		_check(CurrencyText.name_of(id) != String(id), "legacy mapping target %s is real currency" % id)
	var parsed := {"owned_loot": [{"class": "Brand", "item_id": "binder"}, {"class": "Brand", "item_id": "binder"}]}
	GameState.inventory = GridInventory.new()
	GameState.equipment_refs = []
	GameState.weapon_set_refs = [[], []]
	GameState.fate_board_placements = []
	SaveManager._migrate_legacy_inventory(parsed)
	_check(GameState.inventory.count_of(&"brand_preservation") == 2, "pre-grid saves convert old Brands too")
	_finished += 1

func _test_currency_drops() -> void:
	var seen := {}
	for i in 2000:
		seen[Constants.roll_currency_drop()] = true
	_check(seen.keys().all(func(id): return Constants.CURRENCY_DROP_WEIGHTS.has(id) and CurrencyText.name_of(id) != String(id)), "currency drops are real currency ids")
	_check(seen.size() >= 30, "currency drops cover the table (%d ids)" % seen.size())
	_finished += 1

func _test_hub_crafting() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	var hub: Node = load(HUB).instantiate()
	add_child(hub)
	await _frames(3)
	var player := get_tree().get_first_node_in_group("player") as Player

	var pickup: LootPickup = load(LOOT_PICKUP).instantiate()
	pickup.currency_id = &"quickening"
	pickup.currency_count = 3
	hub.add_child(pickup)
	pickup._on_body_entered(player)
	_check(GameState.inventory.count_of(&"quickening") == 3 and pickup.is_queued_for_deletion(), "currency pickup goes into the grid")
	var saved := GameState.inventory
	GameState.inventory = GridInventory.new(1, 1)
	GameState.inventory.add(&"quickening", 99)
	var partial: LootPickup = load(LOOT_PICKUP).instantiate()
	partial.currency_id = &"quickening"
	partial.currency_count = 5
	hub.add_child(partial)
	partial._on_body_entered(player)
	_check(GameState.inventory.count_of(&"quickening") == 100 and partial.currency_count == 4 and not partial.is_queued_for_deletion(), "full stack leaves the rest on the ground")
	GameState.inventory = saved

	var ring := Item.new()
	ring.equip_slot = Constants.EquipmentSlot.RING
	ring.display_name = "Craft Test Ring"
	ring.item_level = 50
	ring.tolerance = 100
	GameState.inventory.add(ring)
	GameState.inventory.add(&"brand_cold", 2)
	var screen: InventoryScreen = hub.get_node("InventoryScreen")
	screen.open()
	var ring_entry: GridInventory.Entry = null
	var brand_entry: GridInventory.Entry = null
	var orb_entry: GridInventory.Entry = null
	for e in GameState.inventory.get_entries():
		if not e.is_currency() and e.content == ring:
			ring_entry = e
		elif e.is_currency() and e.content == &"brand_cold":
			brand_entry = e
		elif e.is_currency() and e.content == &"quickening":
			orb_entry = e
	screen._on_entry_right_clicked(screen.inventory_grid, brand_entry)
	_check(screen._active_brands.is_active(&"brand_cold") and screen._highlight_for(brand_entry) == InventoryScreen.ACTIVE_BRAND_BORDER, "right-clicking a brand activates it with a red border")
	screen._on_entry_right_clicked(screen.inventory_grid, orb_entry)
	_check(screen._armed == &"quickening", "right-clicking an orb picks it up")
	screen._on_entry_hovered(screen.inventory_grid, ring_entry)
	_check(screen.status_label.text.contains("Brands used"), "hovering an item with an orb picked up shows the preview")
	screen._on_entry_clicked(screen.inventory_grid, ring_entry)
	_check(ring.rarity == Constants.ItemRarity.UNCOMMON and _explicits(ring)[0].def.tags.has(&"cold"), "clicking an item applies the orb with the active brand")
	_check(GameState.inventory.count_of(&"quickening") == 2 and GameState.inventory.count_of(&"brand_cold") == 1, "crafting consumes from the grid")
	GameState.inventory.add(&"edict_spell")
	screen._armed = &"edict_spell"
	screen._on_entry_right_clicked(screen.inventory_grid, ring_entry)
	_check(ring.active_edict != null and GameState.inventory.count_of(&"edict_spell") == 0 and screen._armed == &"", "right-clicking an item with an edict picked up applies it")
	screen.close()
	_check(not hub.has_node("BrandShop"), "brand shop removed from the hub")
	hub.queue_free()
	await _frames(2)
	_finished += 1
