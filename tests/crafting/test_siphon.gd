extends Node
## Crafting Rev 3: residue pools and the Siphon (CraftingResolver).
## Run: Godot --headless --path . res://tests/crafting/test_siphon.tscn
## Exits 0 when every check passes. Never writes the save file.

const E := CraftResult.CraftError
const GLOVES := "res://data/armor/instances/gen_gloves_aegis_gauntlets.tres"
const DAGGER := "res://data/weapons/instances/gen_dagger_assassins_blade.tres"
const RING := "res://data/items/instances/ember_ring.tres"

var _checks := 0
var _failures := 0
var _resolver: CraftingResolver

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_resolver = CraftingResolver.create_default(rng)
	_resolver.register_pool(_vestige_pool())
	_test_pools()
	_test_families_and_payment()
	_test_rarity()
	_test_anchor()
	_test_cost()
	_test_sockets_and_type()
	_test_restrictions()
	_test_sessions()
	_test_tempering()
	_test_slates_figments_lenses()
	_test_legacy()
	print("siphon tests: %d checks, %d failures" % [_checks, _failures])
	print("SIPHON_TESTS_DONE")
	get_tree().quit(1 if _failures > 0 else 0)

func _fill(amount: int = 4000) -> void:
	for pool in Residue.REGULAR:
		GameState.residue[pool] = amount
	GameState.residue[Residue.BOSS] = 1000

func _item(path: String, rarity: int = Constants.ItemRarity.COMMON) -> Item:
	var item := (load(path) as Item).duplicate(true) as Item
	item.item_level = 85
	item.rarity = rarity
	item.affixes = item.affixes.filter(func(a: ItemAffix): return a.is_implicit)
	return item

func _explicits(item: Item) -> Array[ItemAffix]:
	return item.affixes.filter(func(a: ItemAffix): return not a.is_implicit)

func _pool_total() -> int:
	return Residue.amount(Residue.PHYSICAL) + Residue.amount(Residue.ELEMENTAL) + Residue.amount(Residue.ESOTERIC)

func _vestige_pool() -> ModifierPool:
	var pool := ModifierPool.new()
	pool.pool_id = &"vestige_test_boss"
	var def := ModifierDef.new()
	def.id = &"vestige_test_line"
	def.group = &"vestige_test_line"
	def.stat_key = "flat_life"
	def.text = "+%d to maximum Life (Vestige)"
	def.affix_type = ModifierDef.AffixType.PREFIX
	var tier := ModifierTier.new()
	tier.tier = 1
	tier.value_min = 50.0
	tier.value_max = 60.0
	tier.weight = 1
	def.tiers = [tier] as Array[ModifierTier]
	pool.modifiers = [def] as Array[ModifierDef]
	return pool

## ---- Phase 1 ---------------------------------------------------------------

func _test_pools() -> void:
	GameState.residue = {}
	var gained := Residue.add(Residue.ELEMENTAL, 12)
	_check(gained == 12 and Residue.amount(Residue.ELEMENTAL) == 12, "residue adds to its pool")
	Residue.add(Residue.ELEMENTAL, Constants.RESIDUE_POOL_CAP)
	_check(Residue.amount(Residue.ELEMENTAL) == Constants.RESIDUE_POOL_CAP, "pools hold at their cap")
	_check(Residue.pool_for_damage_type(Constants.DamageType.FIRE) == Residue.ELEMENTAL and Residue.pool_for_damage_type(Constants.DamageType.PALE) == Residue.ESOTERIC and Residue.pool_for_damage_type(Constants.DamageType.PIERCING) == Residue.PHYSICAL, "damage categories pick the pool")

## ---- Phase 2 ---------------------------------------------------------------

func _test_families_and_payment() -> void:
	_fill()
	var gloves := _item(GLOVES)
	var before := Residue.amount(Residue.ELEMENTAL)
	var r := _resolver.apply(gloves, &"add", &"fire")
	var added := _explicits(gloves)
	_check(r.success and added.size() == 1 and _resolver.affix_tags(CraftTarget.wrap(gloves), added[0]).has(&"fire"), "a Fire add only adds a Fire modifier")
	_check(Residue.amount(Residue.ELEMENTAL) < before and Residue.amount(Residue.PHYSICAL) == 4000, "a Fire craft pays from Elemental only")
	var ring := _item(RING)
	var cost := _resolver.cost_of(ring, &"add")
	var split := {Residue.PHYSICAL: cost - 5, Residue.ESOTERIC: 5}
	var session := _resolver.begin(ring, &"add", &"", split)
	_check(session.error == E.NONE, "an unfocused craft takes a split payment")
	session.choose(0)
	var boss_pay := {Residue.BOSS: _resolver.cost_of(ring, &"add")}
	_check(_resolver.begin(ring, &"add", &"", boss_pay).error == E.INVALID_PAYMENT, "boss residue can't pay a regular craft")
	var count := ring.craft_count
	_check(_resolver.begin(ring, &"add", &"", {Residue.PHYSICAL: 1}).error == E.INVALID_PAYMENT and ring.craft_count == count, "a wrong payment spends nothing and doesn't count")
	GameState.residue[Residue.ELEMENTAL] = 0
	_check(_resolver.begin(gloves, &"add", &"cold", {Residue.ELEMENTAL: _resolver.cost_of(gloves, &"add")}).error == E.CANT_AFFORD, "an unaffordable craft fails")
	_fill()
	var vest := _item(RING)
	_check(_resolver.apply(vest, &"vestige_add", &"ataras").error == E.NOT_UNLOCKED, "Vestige needs the boss killed")
	GameState.killed_bosses.append("ataras")
	var boss_before := Residue.amount(Residue.BOSS)
	var lines := _explicits(vest).size()
	var vr := _resolver.apply(vest, &"vestige_add", &"ataras")
	_check(vr.success and vest.perks.has("falling_sun") and _explicits(vest).size() == lines and vest.rarity >= Constants.ItemRarity.UNCOMMON and Residue.amount(Residue.BOSS) < boss_before, "Vestige adds the boss perk (an MI), paid in boss residue")
	_check(_resolver.apply(vest, &"vestige_add", &"ataras").error == E.HAS_BOSS_PERK, "one boss perk per item")

func _test_rarity() -> void:
	_fill()
	var item := _item(GLOVES)
	_resolver.apply(item, &"add")
	_check(item.rarity == Constants.ItemRarity.UNCOMMON, "add on Common makes it Uncommon")
	_resolver.apply(item, &"add")
	_check(item.rarity == Constants.ItemRarity.UNCOMMON and _explicits(item).size() == 2, "a second add fits Uncommon (1+1)")
	_resolver.apply(item, &"add")
	_check(item.rarity == Constants.ItemRarity.RARE, "a third add raises to Rare")
	_resolver.apply(item, &"add")
	_check(_resolver.apply(item, &"add").error == E.NO_OPEN_AFFIX, "a full 2/2 item takes no more")
	var count := _explicits(item).size()
	_resolver.apply(item, &"bleed")
	_check(_explicits(item).size() == count - 1 and item.rarity == Constants.ItemRarity.RARE, "bleed removes one and keeps rarity")
	_resolver.apply(item, &"absolve")
	_check(_explicits(item).is_empty() and item.rarity == Constants.ItemRarity.COMMON, "absolve clears and drops rarity to fit")

func _test_anchor() -> void:
	_fill()
	var item := _item(GLOVES)
	for i in 3:
		_resolver.apply(item, &"add")
	_check(_resolver.apply(item, &"anchor", &"", 1).success and _explicits(item)[1].anchored, "the chosen modifier is anchored")
	var kept: String = _explicits(item)[1].description
	for craft: StringName in [&"recast", &"bleed", &"absolve", &"settle"]:
		_resolver.apply(item, craft)
	_check(_explicits(item).any(func(a: ItemAffix): return a.anchored and a.description == kept), "the anchor survives recast, bleed, absolve and settle")
	var thin := _item(GLOVES)
	_resolver.apply(thin, &"add")
	_check(_resolver.apply(thin, &"anchor", &"", 0).error == E.TOO_FEW_MODIFIERS, "anchor needs enough modifiers")
	for i in 3:
		_resolver.apply(item, &"add")
	var other := -1
	var explicits := _explicits(item)
	for i in explicits.size():
		if not explicits[i].anchored:
			other = i
	_check(_resolver.apply(item, &"anchor", &"", other).error == E.ALREADY_ANCHORED, "only MAX_ANCHORED_MODIFIERS can be anchored")

func _test_cost() -> void:
	_fill(8000)
	var item := _item(GLOVES)
	var base: int = Constants.CRAFT_BASE_COST[&"add"]
	_check(_resolver.cost_of(item, &"add") == base, "the first craft costs the base")
	item.craft_count = 5
	_check(_resolver.cost_of(item, &"add") == ceili(base * pow(Constants.CRAFT_COST_GROWTH, 5)), "cost grows per craft")
	item.craft_count = 200
	_check(_resolver.cost_of(item, &"add") == ceili(base * Constants.CRAFT_COST_MULT_CAP), "cost holds at the cap")
	item.craft_count = 3
	_resolver.apply(item, &"add")
	_resolver.apply(item, &"absolve")
	_check(item.craft_count == 5, "every craft counts and absolve doesn't reset it")
	var ok := true
	for id: StringName in Constants.CRAFT_BASE_COST:
		var worst: float = Constants.CRAFT_BASE_COST[id] * Constants.CRAFT_COST_MULT_CAP * (1.0 + Constants.FORESIGHT_EXTRA_COST * (Constants.FORESIGHT_MAX_OUTCOMES - 1))
		var cap := Constants.RESIDUE_BOSS_POOL_CAP if id == &"vestige_add" else Constants.RESIDUE_POOL_CAP
		ok = ok and worst <= cap
	_check(ok, "no craft, even with full foresight at the cap, costs more than a full pool")

func _test_sockets_and_type() -> void:
	_fill()
	var gloves := _item(GLOVES)
	gloves.max_sockets = maxi(gloves.max_sockets, 2)
	_check(_resolver.apply(gloves, &"sockets").success and gloves.sockets >= 1, "sockets roll 1 or more")
	_check(_resolver.apply(gloves, &"sockets").success, "sockets can be rerolled")
	gloves.max_sockets = 2
	gloves.socketed = [Jewel.new()] as Array[Item]
	_check(_resolver.apply(gloves, &"sockets").success and gloves.sockets >= 1 and gloves.socketed.size() == 1, "sockets reroll around a jewel and keep it")
	gloves.socketed.append(Jewel.new())
	_check(_resolver.apply(gloves, &"sockets").error == E.NO_VALID_OUTCOME, "sockets refuse an item whose sockets are all filled")
	_check(_resolver.apply(Jewel.new(), &"sockets").error == E.INVALID_TARGET, "sockets refuse jewels")
	var dagger := _item(DAGGER) as Weapon
	var native := dagger.get_damage_type()
	_check(_resolver.apply(dagger, &"retype", StringName(String(Constants.DAMAGE_TYPE_NAME[native]).to_lower())).error == E.NO_VALID_OUTCOME, "retype refuses the current type")
	var before := Residue.amount(Residue.ELEMENTAL)
	_check(_resolver.apply(dagger, &"retype", &"fire").success and dagger.get_damage_type() == Constants.DamageType.FIRE, "retype changes the damage type")
	_check(Residue.amount(Residue.ELEMENTAL) < before, "retype to Fire pays from Elemental")
	_check(_resolver.apply(dagger, &"restore_type").success and dagger.infused_damage_type == -1, "restore_type clears the infusion")

func _test_restrictions() -> void:
	_fill()
	var corrupt := _item(GLOVES, Constants.ItemRarity.RARE)
	corrupt.is_corrupted = true
	corrupt.max_sockets = 2
	_check(_resolver.apply(corrupt, &"add").error == E.CORRUPTED and _resolver.apply(corrupt, &"sockets").success, "corrupted items take only sockets")
	var unique := _item(GLOVES, Constants.ItemRarity.UNIQUE)
	unique.max_sockets = 2
	_check(_resolver.apply(unique, &"add").error == E.INVALID_TARGET and _resolver.apply(unique, &"sockets").success, "Uniques take only sockets")

func _test_sessions() -> void:
	_fill()
	var item := _item(GLOVES)
	var before := _pool_total()
	var session := _resolver.begin(item, &"add", &"", _resolver.auto_payment(item, &"add"))
	session.decline()
	_check(_explicits(item).is_empty() and item.craft_count == 1 and _pool_total() < before, "a declined session spends, counts and leaves the item alone")
	var four := _resolver.begin(item, &"add", &"", _resolver.auto_payment(item, &"add", &"", 4), 4)
	_check(four.outcomes.size() == 4 and four.outcomes.all(func(o: Dictionary): return (o["added"] as Array).size() == 1), "four outcomes, each valid")
	four.choose(2)
	_check(_explicits(item).size() == 1 and item.craft_count == 2, "choosing applies one outcome and counts once")
	var fresh := _item(GLOVES)
	_check(_resolver.cost_of(fresh, &"add", &"", 4) == ceili(Constants.CRAFT_BASE_COST[&"add"] * 1.75), "a 4-outcome craft costs x1.75")
	var p := _resolver.preview(fresh, &"add")
	_check(absf(p.total_probability() - 1.0) < 0.001, "preview odds sum to 1")

func _test_tempering() -> void:
	var gloves := _item(GLOVES)
	var base := gloves.get_local_defence("armor") + gloves.get_local_defence("evasion") + gloves.get_local_defence("ward")
	for i in 20:
		CraftingSystem.temper(gloves)
	_check(gloves.quality == Constants.QUALITY_CAP, "tempering caps at 25")
	var raised := gloves.get_local_defence("armor") + gloves.get_local_defence("evasion") + gloves.get_local_defence("ward")
	_check(raised > base * 1.2, "quality raises armour defences")
	var dagger := (load(DAGGER) as Item).duplicate(true) as Item
	_check(CraftingSystem.temper(dagger)["success"], "tempering works on weapons")
	_check(not CraftingSystem.temper(_item(RING))["success"], "tempering refuses jewellery")

func _test_slates_figments_lenses() -> void:
	_fill()
	var slate := SlateRoller.roll(80)
	slate.explicits = [] as Array[ItemAffix]
	slate.rarity = Constants.SlateRarity.COMMON
	var tags := slate.get_slate_tags()
	var off: StringName = &"pale" if not tags.has(&"pale") else &"fire"
	if not tags.has(off):
		_check(_resolver.apply(slate, &"add", off).error == E.NO_VALID_OUTCOME, "an off-tag family fails on a Slate")
	_check(_resolver.apply(slate, &"add").success, "an unfocused add works on a Slate")
	var lens := LensRoller.roll(80)
	var lens_ok := _resolver.apply(lens, &"settle").success or _resolver.apply(lens, &"add").success
	_check(lens_ok, "Lenses take Siphon crafts")
	var figment := FigmentRoller.roll_for_drop()
	if figment:
		figment.affixes = [] as Array[ItemAffix]
		_check(_resolver.apply(figment, &"add").success and figment.affixes.size() == 1, "Figments take an add at the Siphon")

func _test_legacy() -> void:
	GameState.residue = {}
	GridInventory.legacy_currency_found = {}
	var d := {"width": 12, "height": 6, "entries": [
		{"x": 0, "y": 0, "count": 3, "currency": "quickening"},
		{"x": 1, "y": 0, "count": 2, "currency": "brand_fire"},
		{"x": 2, "y": 0, "count": 4, "currency": "tempering"},
	]}
	var inv := GridInventory.from_dict(d)
	_check(inv.count_of(&"quickening") == 0 and inv.count_of(&"brand_fire") == 0 and inv.count_of(&"tempering") == 4, "old Orbs and Brands are stripped; Tempering stays")
	SaveManager._refund_legacy_currency()
	_check(Residue.amount(Residue.PHYSICAL) == 5 * Constants.LEGACY_CURRENCY_REFUND and Residue.amount(Residue.ESOTERIC) == 5 * Constants.LEGACY_CURRENCY_REFUND, "each removed item refunds every regular pool")
