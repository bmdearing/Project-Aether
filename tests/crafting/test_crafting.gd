extends Node
## Headless checks for Orb crafting (CraftingResolver).
## Run: Godot --headless --path . res://tests/crafting/test_crafting.tscn
## Exits 0 when every check passes.

const E := CraftResult.CraftError
const P := ModifierDef.AffixType.PREFIX
const S := ModifierDef.AffixType.SUFFIX
const GEAR_TYPE := &"test_sword"

var _checks := 0
var _failures := 0
var _resolver: CraftingResolver
var _bag: CurrencyBag
var _failed_signals := 0
var _completed_signals := 0
## Each test function bumps this as its last line, so a script error that
## aborts one midway shows up as a failure.
var _finished := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _run() -> void:
	EventBus.craft_failed.connect(func(_i, _e, _m): _failed_signals += 1)
	EventBus.craft_completed.connect(func(_i, _r): _completed_signals += 1)
	_test_progression()
	_test_forging()
	_test_tag_brands()
	_test_removal_brands()
	_test_positional_and_preservation()
	_test_slate_category_brands()
	_test_vestige()
	_test_anchoring()
	_test_edicts()
	_test_tolerance()
	_test_opening()
	_test_tempering()
	_test_corrupted()
	_test_preview()
	_test_signals_and_text()
	_check(_finished == 15, "every test function ran to the end (%d/15)" % _finished)
	print("crafting tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

## ---- Fixtures ----------------------------------------------------------

func _setup(seed_value: int = 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_resolver = CraftingResolver.create_default(rng)
	_resolver.register_pool(_gear_pool())
	_resolver.register_pool(_slate_pool())
	_resolver.register_pool(_vestige_pool())
	var vestige := BrandDef.new()
	vestige.id = &"vestige_test_boss"
	vestige.vestige_pool = &"vestige_test_boss"
	vestige.applies_to_orbs = [&"ascendant", &"recasting"]
	_resolver.register_brand(vestige)
	_bag = CurrencyBag.new()
	for id in Constants.ORB_IDS:
		_bag.add_currency(id, 1000)
	for id in _resolver.brand_defs:
		_bag.add_currency(id, 100)
	for id in _resolver.edict_defs:
		_bag.add_currency(id, 100)
	_resolver.currency = _bag

func _mod(id: String, type: int, tags: Array, item_types: Array = []) -> ModifierDef:
	var def := ModifierDef.new()
	def.id = StringName(id)
	def.group = StringName(id)
	def.affix_type = type
	for t in tags:
		def.tags.append(StringName(t))
	for t in item_types:
		def.item_types.append(StringName(t))
	def.stat_key = "test_" + id
	def.text = "+%d " + id
	var ranges := [[30.0, 40.0, 10], [20.0, 29.0, 30], [10.0, 19.0, 60]]
	for i in ranges.size():
		var tier := ModifierTier.new()
		tier.tier = i + 1
		tier.value_min = ranges[i][0]
		tier.value_max = ranges[i][1]
		tier.weight = ranges[i][2]
		def.tiers.append(tier)
	return def

func _gear_pool() -> ModifierPool:
	var pool := ModifierPool.new()
	pool.pool_id = &"gear"
	pool.modifiers = [
		_mod("fire_dmg", P, ["fire"]), _mod("cold_dmg", P, ["cold"]),
		_mod("lightning_dmg", P, ["lightning"]), _mod("firecold_dmg", P, ["fire", "cold"]),
		_mod("phys_dmg", P, ["kinetic"]), _mod("spell_dmg", P, ["spell"]),
		_mod("attack_dmg", P, ["attack"]), _mod("armor", P, ["armor"]),
		_mod("life", P, []), _mod("axe_only", P, ["kinetic"], ["test_axe"]),
		_mod("fire_res", S, ["fire", "resistance"]), _mod("cold_res", S, ["cold", "resistance"]),
		_mod("lightning_res", S, ["lightning", "resistance"]), _mod("attack_speed", S, ["attack", "speed"]),
		_mod("cast_speed", S, ["spell", "speed"]), _mod("mana", S, ["mana"]),
		_mod("evasion", S, ["evasion"]), _mod("ward", S, ["ward"]),
		_mod("firecold_res", S, ["fire", "cold", "resistance"]), _mod("move_speed", S, ["speed"]),
	]
	return pool

func _slate_pool() -> ModifierPool:
	var pool := ModifierPool.new()
	pool.pool_id = &"slate"
	pool.modifiers = [
		_mod("slate_fire_p", P, ["fire"]), _mod("slate_fire_s", S, ["fire"]),
		_mod("slate_cold_p", P, ["cold"]), _mod("slate_cold_s", S, ["cold"]),
		_mod("slate_firecold_p", P, ["fire", "cold"]), _mod("slate_spell_p", P, ["spell"]),
		_mod("slate_spell_s", S, ["spell"]), _mod("slate_generic_p", P, []),
		_mod("slate_generic_s", S, []), _mod("slate_lightning_s", S, ["lightning"]),
	]
	return pool

func _vestige_pool() -> ModifierPool:
	var pool := ModifierPool.new()
	pool.pool_id = &"vestige_test_boss"
	pool.modifiers = [
		_mod("vestige_p1", P, ["vestige"]), _mod("vestige_p2", P, ["vestige"]),
		_mod("vestige_s1", S, ["vestige"]),
	]
	return pool

func _gear(rarity: int = Constants.ItemRarity.COMMON) -> Weapon:
	var w := Weapon.new()
	w.item_type = GEAR_TYPE
	w.rarity = rarity
	w.max_sockets = 3
	w.tolerance = 1000
	w.tolerance_max = 1000
	return w

func _slate(tag: int = Constants.DamageType.FIRE, hybrid: bool = false) -> Slate:
	var s := Slate.new()
	s.tag = tag
	s.is_hybrid = hybrid
	s.secondary_tag = Constants.DamageType.COLD
	s.rarity = Constants.SlateRarity.COMMON
	s.tolerance = 1000
	s.tolerance_max = 1000
	return s

func _rare_gear() -> Weapon:
	var w := _gear()
	_resolver.apply(w, &"forging")
	return w

func _brands(ids: Array) -> ActiveBrands:
	var active := ActiveBrands.new(_bag)
	for id in ids:
		active.activate(StringName(id))
	return active

func _explicits(target: Resource) -> Array[ItemAffix]:
	return CraftTarget.wrap(target).get_explicits()

func _counts(target: Resource) -> Vector2i:
	var ex := _explicits(target)
	var prefixes := ex.filter(func(a: ItemAffix): return a.is_prefix).size()
	return Vector2i(prefixes, ex.size() - prefixes)

func _within_limits(target: Resource) -> bool:
	var t := CraftTarget.wrap(target)
	var c := _counts(target)
	var lim := t.get_affix_limits(t.get_rarity())
	return c.x <= lim.x and c.y <= lim.y

func _no_duplicate_groups(target: Resource) -> bool:
	var groups := _explicits(target).map(func(a: ItemAffix): return a.get_group())
	for g in groups:
		if groups.count(g) > 1:
			return false
	return true

func _has_tags(affix: ItemAffix, tags: Array) -> bool:
	return tags.all(func(t): return affix.def.tags.has(StringName(t)))

## ---- Tests -------------------------------------------------------------

func _test_progression() -> void:
	for seed_value in 20:
		_setup(seed_value)
		for target in [_gear(), _slate()]:
			var label := "slate" if target is Slate else "gear"
			var max_mods := 4 if target is Slate else 6
			var r := _resolver.apply(target, &"quickening")
			_check(r.success and CraftTarget.wrap(target).get_rarity() == Constants.ItemRarity.UNCOMMON and _explicits(target).size() == 1, "%s quickening -> uncommon+1" % label)
			_check(_resolver.apply(target, &"quickening").error == E.INVALID_TARGET, "%s quickening rejects uncommon" % label)
			_check(_resolver.apply(target, &"grafting").success and _explicits(target).size() == 2, "%s grafting adds 1" % label)
			_check(_resolver.apply(target, &"grafting").error == E.NO_OPEN_AFFIX, "%s grafting full uncommon" % label)
			_check(_within_limits(target), "%s uncommon limits" % label)
			_check(_resolver.apply(target, &"ascendant").error == E.INVALID_TARGET, "%s ascendant rejects uncommon" % label)
			r = _resolver.apply(target, &"elevation")
			_check(r.success and CraftTarget.wrap(target).get_rarity() == Constants.ItemRarity.RARE and _explicits(target).size() == 3, "%s elevation -> rare+1" % label)
			while _explicits(target).size() < max_mods:
				var before := _explicits(target).size()
				_check(_resolver.apply(target, &"ascendant").success and _explicits(target).size() == before + 1, "%s ascendant adds 1" % label)
				_check(_within_limits(target), "%s rare limits" % label)
				if _explicits(target).size() == before:
					break
			_check(_counts(target) == (Vector2i(2, 2) if target is Slate else Vector2i(3, 3)), "%s full rare split" % label)
			_check(_resolver.apply(target, &"ascendant").error == E.NO_OPEN_AFFIX, "%s ascendant on full rare" % label)
			_check(_no_duplicate_groups(target), "%s no duplicate groups" % label)
			_check(not _explicits(target).any(func(a: ItemAffix): return a.modifier_id == &"axe_only"), "%s item_type filter" % label)
	var unique := _gear(Constants.ItemRarity.UNIQUE)
	for orb in Constants.ORB_IDS:
		_check(_resolver.apply(unique, orb).error == E.INVALID_TARGET, "unique rejects %s" % orb)
	_finished += 1

func _test_forging() -> void:
	_setup(7)
	var slate_counts := {}
	for i in 50:
		var g := _gear()
		_check(_resolver.apply(g, &"forging").success and _explicits(g).size() == 4 and g.rarity == Constants.ItemRarity.RARE, "forging gear -> rare with 4")
		_check(_within_limits(g) and _no_duplicate_groups(g), "forging gear limits")
		var s := _slate()
		_check(_resolver.apply(s, &"forging").success and s.rarity == Constants.SlateRarity.RARE, "forging slate -> rare")
		var n := _explicits(s).size()
		slate_counts[n] = true
		_check(n == 3 or n == 4, "forging slate gives 3-4 (got %d)" % n)
		_check(_within_limits(s), "forging slate limits")
	_check(slate_counts.has(3) and slate_counts.has(4), "forging slate produces both 3 and 4")
	_check(_resolver.apply(_gear(Constants.ItemRarity.UNCOMMON), &"forging").error == E.INVALID_TARGET, "forging rejects uncommon")
	_finished += 1

func _test_tag_brands() -> void:
	_setup(3)
	for i in 30:
		var g := _gear()
		var active := _brands(["brand_fire", "brand_cold"])
		var r := _resolver.apply(g, &"quickening", active)
		_check(r.success and _has_tags(r.added[0], ["fire", "cold"]), "fire+cold adds a dual-tag modifier")
	var g := _gear()
	var active := _brands(["brand_fire", "brand_lightning"])
	var orb_before := _bag.count_of(&"quickening")
	var fire_before := _bag.count_of(&"brand_fire")
	var r := _resolver.apply(g, &"quickening", active)
	_check(r.error == E.NO_VALID_OUTCOME, "fire+lightning with no dual-tag modifier fails")
	_check(_bag.count_of(&"quickening") == orb_before and _bag.count_of(&"brand_fire") == fire_before, "failed craft consumes no orb or brand")
	_check(active.is_active(&"brand_fire") and active.is_active(&"brand_lightning"), "failed craft leaves brands active")
	_check(g.tolerance == 1000 and g.rarity == Constants.ItemRarity.COMMON and _explicits(g).is_empty(), "failed craft leaves item untouched")
	_finished += 1

## A rare with one fire prefix, one cold prefix and one fire suffix: the
## fixture for Brands narrowing removal, replacement and anchoring.
func _branded_rare() -> Weapon:
	var g := _gear()
	_resolver.apply(g, &"quickening", _brands(["brand_fire", "brand_prefix", "brand_preservation"]))
	_resolver.apply(g, &"elevation", _brands(["brand_cold", "brand_prefix"]))
	_resolver.apply(g, &"ascendant", _brands(["brand_fire", "brand_suffix"]))
	return g

func _fire_count(target: Resource) -> int:
	return _explicits(target).filter(func(a: ItemAffix): return a.def.tags.has(&"fire")).size()

func _test_removal_brands() -> void:
	_setup(29)
	var fixture := _branded_rare()
	_check(_explicits(fixture).size() == 3 and _fire_count(fixture) >= 2, "branded rare fixture")
	for i in 20:
		var g := _branded_rare()
		var non_fire := _explicits(g).filter(func(a: ItemAffix): return not a.def.tags.has(&"fire"))
		var active := _brands(["brand_fire"])
		var fire_before := _bag.count_of(&"brand_fire")
		var r := _resolver.apply(g, &"severance", active)
		_check(r.success and r.removed.size() == 1 and r.removed[0].def.tags.has(&"fire"), "fire brand severance removes a fire modifier")
		_check(non_fire.all(func(a: ItemAffix): return _explicits(g).has(a)), "fire brand severance keeps non-fire modifiers")
		_check(_bag.count_of(&"brand_fire") == fire_before - 1 and r.consumed_brands.has(&"brand_fire"), "removal consumes the brand")

	for i in 20:
		var g := _branded_rare()
		var r := _resolver.apply(g, &"recasting", _brands(["brand_fire"]))
		_check(r.success and r.removed[0].def.tags.has(&"fire") and r.added[0].def.tags.has(&"fire"), "fire brand recasting replaces fire with fire")

	var g := _branded_rare()
	var keep := _explicits(g).filter(func(a: ItemAffix): return not a.def.tags.has(&"fire"))
	var r := _resolver.apply(g, &"absolution", _brands(["brand_fire"]))
	_check(r.success and _fire_count(g) == 0 and _explicits(g).size() == keep.size() and keep.all(func(a: ItemAffix): return _explicits(g).has(a)), "fire brand absolution strips only fire modifiers")

	# Brands combine: fire + suffix picks only the fire suffix.
	g = _branded_rare()
	var p := _resolver.preview(g, &"severance", _brands(["brand_fire", "brand_suffix"]))
	_check(p.is_valid() and p.affected.size() == 1 and not p.affected[0]["affix"].is_prefix, "fire+suffix narrows to the fire suffix")

	# Nothing matches: the craft fails and consumes nothing.
	g = _branded_rare()
	var active := _brands(["brand_ward"])
	var ward_before := _bag.count_of(&"brand_ward")
	var orb_before := _bag.count_of(&"severance")
	r = _resolver.apply(g, &"severance", active)
	_check(r.error == E.NOTHING_TO_REMOVE and _bag.count_of(&"brand_ward") == ward_before and _bag.count_of(&"severance") == orb_before, "unmatched brand blocks severance at no cost")
	_check(_resolver.preview(g, &"severance", active).error == E.NOTHING_TO_REMOVE, "preview agrees")

	# Anchoring with a Brand anchors a matching modifier.
	for i in 10:
		g = _branded_rare()
		r = _resolver.apply(g, &"anchoring", _brands(["brand_cold"]))
		_check(r.success and r.anchored.def.tags.has(&"cold"), "cold brand anchors the cold modifier")

	# Preview marks exactly what can be touched.
	g = _branded_rare()
	p = _resolver.preview(g, &"severance", _brands(["brand_fire"]))
	_check(p.affected.size() == _fire_count(g) and p.affected.all(func(e): return e["effect"] == &"remove"), "severance preview marks the fire modifiers")
	p = _resolver.preview(g, &"absolution")
	_check(p.affected.size() == 3 and p.affected.all(func(e): return is_equal_approx(e["probability"], 1.0)), "absolution marks everything at 100%")
	p = _resolver.preview(g, &"reckoning")
	_check(p.affected.size() == 3 and p.affected[0]["effect"] == &"reroll", "reckoning marks rerolls")
	p = _resolver.preview(g, &"recasting")
	_check(p.affected.all(func(e): return e["effect"] == &"replace"), "recasting marks replacements")

	# An active Brand that's no longer carried drops out.
	var bag := CurrencyBag.new()
	bag.add_currency(&"brand_fire", 1)
	var stale := ActiveBrands.new(bag)
	stale.activate(&"brand_fire")
	bag.remove_currency(&"brand_fire", 1)
	_check(not stale.is_active(&"brand_fire") and stale.get_ids().is_empty(), "a brand no longer carried isn't active")
	_finished += 1

func _test_positional_and_preservation() -> void:
	_setup(5)
	var g := _gear()
	var active := _brands(["brand_prefix", "brand_suffix"])
	var pre := _bag.count_of(&"brand_prefix")
	var suf := _bag.count_of(&"brand_suffix")
	var r := _resolver.apply(g, &"quickening", active)
	_check(r.success, "prefix+suffix cancel and resolve")
	_check(_bag.count_of(&"brand_prefix") == pre - 1 and _bag.count_of(&"brand_suffix") == suf - 1, "prefix+suffix both consumed")
	_check(not active.is_active(&"brand_prefix") and not active.is_active(&"brand_suffix"), "prefix+suffix deactivated")

	for i in 20:
		g = _gear()
		active = _brands(["brand_suffix"])
		r = _resolver.apply(g, &"quickening", active)
		_check(r.success and not r.added[0].is_prefix, "suffix brand adds a suffix")

	g = _gear()
	active = _brands(["brand_fire", "brand_prefix", "brand_preservation"])
	var fire := _bag.count_of(&"brand_fire")
	pre = _bag.count_of(&"brand_prefix")
	var keep := _bag.count_of(&"brand_preservation")
	r = _resolver.apply(g, &"quickening", active)
	_check(r.success and r.added[0].is_prefix and _has_tags(r.added[0], ["fire"]), "preserved brands still steer the orb")
	_check(_bag.count_of(&"brand_fire") == fire and _bag.count_of(&"brand_prefix") == pre, "preservation keeps other brands")
	_check(_bag.count_of(&"brand_preservation") == keep - 1 and not active.is_active(&"brand_preservation"), "preservation itself consumed")
	_check(active.is_active(&"brand_fire") and active.is_active(&"brand_prefix"), "preserved brands stay active")

	# Positional Brands restrict removal.
	for i in 10:
		var rare := _rare_gear()
		var suffixes_before := _counts(rare).y
		active = _brands(["brand_prefix"])
		_check(_resolver.apply(rare, &"severance", active).success and _counts(rare).y == suffixes_before, "prefix brand severance removes a prefix")

	var activate_unowned := ActiveBrands.new(CurrencyBag.new())
	_check(not activate_unowned.activate(&"brand_fire"), "can't activate a brand that isn't carried")
	_finished += 1

func _test_slate_category_brands() -> void:
	_setup(11)
	var s := _slate(Constants.DamageType.FIRE)
	_check(_resolver.apply(s, &"quickening", _brands(["brand_cold"])).error == E.NO_VALID_OUTCOME, "off-tag brand on slate fails")
	_check(_resolver.apply(s, &"quickening", _brands(["brand_armor"])).error == E.NO_VALID_OUTCOME, "defensive brand on fire slate fails")
	var r := _resolver.apply(s, &"quickening", _brands(["brand_fire"]))
	_check(r.success and _has_tags(r.added[0], ["fire"]), "on-tag brand on slate works")
	for brand in ["brand_fire", "brand_cold"]:
		var hybrid := _slate(Constants.DamageType.FIRE, true)
		r = _resolver.apply(hybrid, &"quickening", _brands([brand]))
		_check(r.success and _has_tags(r.added[0], [brand.trim_prefix("brand_")]), "hybrid slate accepts %s" % brand)
	var hybrid := _slate(Constants.DamageType.FIRE, true)
	r = _resolver.apply(hybrid, &"quickening", _brands(["brand_fire", "brand_cold"]))
	_check(r.success and r.added[0].modifier_id == &"slate_firecold_p", "hybrid slate accepts both tags")
	_check(_resolver.apply(_slate(), &"quickening", _brands(["brand_lightning"])).error == E.NO_VALID_OUTCOME, "lightning brand on fire slate fails")
	for i in 20:
		var plain := _slate()
		_resolver.apply(plain, &"forging")
		_check(_explicits(plain).all(func(a: ItemAffix): return a.modifier_id.begins_with("slate_")), "slates roll only slate modifiers")
		var g := _rare_gear()
		_check(not _explicits(g).any(func(a: ItemAffix): return a.modifier_id.begins_with("slate_")), "gear never rolls slate modifiers")
	_finished += 1

func _test_vestige() -> void:
	_setup(13)
	var g := _gear()
	_resolver.apply(g, &"quickening")
	_resolver.apply(g, &"elevation")
	var active := _brands(["vestige_test_boss"])
	var r := _resolver.apply(g, &"ascendant", active)
	_check(r.success and r.added[0].modifier_id.begins_with("vestige_"), "vestige replaces the pool for ascendant")
	_check(not active.is_active(&"vestige_test_boss"), "vestige consumed")
	g = _gear()
	active = _brands(["vestige_test_boss"])
	r = _resolver.apply(g, &"quickening", active)
	_check(r.success and not r.added[0].modifier_id.begins_with("vestige_") and active.is_active(&"vestige_test_boss"), "vestige ignored by orbs it doesn't apply to")
	_finished += 1

func _test_anchoring() -> void:
	_setup(17)
	var g := _gear()
	_resolver.apply(g, &"quickening")
	_resolver.apply(g, &"grafting")
	_check(_resolver.apply(g, &"anchoring").error == E.TOO_FEW_MODIFIERS, "anchoring fails below 3 modifiers")
	for i in 10:
		g = _rare_gear()
		var r := _resolver.apply(g, &"anchoring")
		_check(r.success and r.anchored != null and r.anchored.anchored, "anchoring locks a modifier")
		var anchored_group := r.anchored.get_group()
		_check(_resolver.apply(g, &"anchoring").error == E.ALREADY_ANCHORED, "second anchoring rejected")
		for j in 5:
			_resolver.apply(g, &"recasting")
		_check(_explicits(g).any(func(a: ItemAffix): return a.anchored and a.get_group() == anchored_group), "anchored survives recasting")
		while _resolver.apply(g, &"severance").success:
			pass
		_check(_explicits(g).size() == 1 and _explicits(g)[0].anchored, "anchored survives severance")
		_check(_resolver.apply(g, &"severance").error == E.NOTHING_TO_REMOVE, "severance with only anchored left")
		g = _rare_gear()
		_resolver.apply(g, &"anchoring")
		_check(_resolver.apply(g, &"absolution").success, "absolution resolves")
		_check(_explicits(g).size() == 1 and _explicits(g)[0].anchored, "anchored survives absolution")
		_check(g.rarity == Constants.ItemRarity.UNCOMMON, "absolution leaves anchored item uncommon")
	g = _rare_gear()
	_resolver.apply(g, &"absolution")
	_check(g.rarity == Constants.ItemRarity.COMMON and _explicits(g).is_empty(), "absolution without anchor -> common")
	_finished += 1

func _test_edicts() -> void:
	_setup(19)
	var g := _rare_gear()
	_check(_resolver.apply_edict(g, &"edict_spell").success and g.active_edict != null, "edict applied")
	_check(_resolver.apply_edict(g, &"edict_prefix").error == E.INVALID_TARGET, "one edict per item")
	_check(_resolver.apply(g, &"quickening").error == E.INVALID_TARGET and g.active_edict != null, "edict survives an unresolved craft")
	_check(_resolver.apply(g, &"reckoning").success and g.active_edict == null, "edict cleared after a resolved craft")

	var spell_item := _gear()
	_resolver.apply_edict(spell_item, &"edict_spell")
	_check(_resolver.apply(spell_item, &"quickening", _brands(["brand_spell"])).error == E.NO_VALID_OUTCOME, "spell edict blocks spell modifiers")
	_check(spell_item.active_edict != null, "edict kept after a failed craft")
	for i in 20:
		var cand := _gear()
		_resolver.apply_edict(cand, &"edict_attack")
		var r := _resolver.apply(cand, &"forging")
		_check(r.success and not _explicits(cand).any(func(a: ItemAffix): return a.def.tags.has(&"attack")), "attack edict excludes attack modifiers")

	for i in 10:
		g = _rare_gear()
		var prefixes := _explicits(g).filter(func(a: ItemAffix): return a.is_prefix)
		_resolver.apply_edict(g, &"edict_prefix")
		_check(_resolver.apply(g, &"absolution").success, "absolution under prefix edict resolves")
		_check(_explicits(g).size() == prefixes.size() and prefixes.all(func(a): return _explicits(g).has(a)) and g.rarity == _expected_rarity(prefixes.size()), "prefix edict keeps prefixes through absolution")

	g = _rare_gear()
	var values := _explicits(g).map(func(a: ItemAffix): return [a.is_prefix, a.value])
	_resolver.apply_edict(g, &"edict_suffix")
	_resolver.apply(g, &"reckoning")
	var after := _explicits(g)
	var suffixes_unchanged := true
	for i in after.size():
		if not after[i].is_prefix and after[i].value != values[i][1]:
			suffixes_unchanged = false
	_check(suffixes_unchanged, "suffix edict stops reckoning from changing suffixes")
	_finished += 1

func _expected_rarity(prefix_count: int) -> int:
	if prefix_count == 0:
		return Constants.ItemRarity.COMMON
	return Constants.ItemRarity.UNCOMMON if prefix_count <= 1 else Constants.ItemRarity.RARE

func _test_tolerance() -> void:
	_setup(23)
	var s := _slate()
	s.tolerance = 3
	var r := _resolver.apply(s, &"forging")
	_check(r.success and s.tolerance == 0 and r.tolerance_spent == 3, "over-cost slate craft resolves and drops tolerance to 0")
	_check(_resolver.apply(s, &"ascendant").error == E.NO_TOLERANCE, "next slate craft returns NO_TOLERANCE")
	_check(_resolver.apply(s, &"absolution").error == E.NO_TOLERANCE and s.tolerance == 0, "absolution at 0 tolerance fails")
	s = _slate()
	_resolver.apply(s, &"forging")
	var before := s.tolerance
	_check(_resolver.apply(s, &"absolution").success and s.tolerance < before, "absolution spends rather than restores tolerance")
	var g := _gear()
	g.tolerance = 0
	r = _resolver.apply(g, &"forging")
	_check(r.success and r.tolerance_spent == 0 and _resolver.apply(g, &"ascendant").success, "gear has no tolerance budget")
	var failed := _slate()
	_resolver.apply(failed, &"grafting")
	_check(failed.tolerance == 1000, "failed craft spends no tolerance")
	var dropped := _slate()
	CraftingResolver.roll_tolerance(dropped)
	var range_: Vector2i = Constants.STARTING_TOLERANCE_BY_ITEM_TYPE.get(CraftTarget.wrap(dropped).get_item_type(), Constants.STARTING_TOLERANCE_DEFAULT)
	_check(dropped.tolerance >= range_.x and dropped.tolerance <= range_.y and dropped.tolerance_max == dropped.tolerance, "slate tolerance rolled in range")
	var dropped_gear := _gear()
	dropped_gear.tolerance = 0
	CraftingResolver.roll_tolerance(dropped_gear)
	_check(dropped_gear.tolerance == 0, "gear gets no tolerance")
	_finished += 1

func _test_opening() -> void:
	_setup(29)
	var g := _gear()
	var r := _resolver.apply(g, &"opening")
	_check(r.success and g.sockets_rolled and g.sockets >= 0 and g.sockets <= g.max_sockets, "opening rolls sockets")
	_check(_resolver.apply(g, &"opening").error == E.SOCKETS_ALREADY_ROLLED, "opening works once")
	var zero := _gear()
	zero.max_sockets = 0
	r = _resolver.apply(zero, &"opening")
	_check(r.success and zero.sockets == 0 and zero.sockets_rolled, "roll of 0 counts")
	_check(_resolver.apply(zero, &"opening").error == E.SOCKETS_ALREADY_ROLLED, "roll of 0 uses the one opening")
	var socketed := _gear()
	socketed.sockets = 2
	_check(_resolver.apply(socketed, &"opening").error == E.SOCKETS_ALREADY_ROLLED, "opening rejects an item that already has sockets")
	_check(_resolver.apply(_slate(), &"opening").error == E.INVALID_TARGET, "opening rejects slates")
	var seen := {}
	for i in 200:
		var o := _gear()
		_resolver.apply(o, &"opening")
		seen[o.sockets] = true
	_check(seen.size() == 4, "opening covers 0..max")
	_finished += 1

func _test_tempering() -> void:
	_setup(31)
	var g := _gear()
	var guard := 0
	while _resolver.apply(g, &"tempering").success and guard < 50:
		guard += 1
		_check(g.quality <= Constants.QUALITY_CAP, "quality never exceeds cap")
	_check(g.quality == Constants.QUALITY_CAP, "tempering reaches cap")
	_check(_resolver.apply(g, &"tempering").error == E.QUALITY_CAPPED, "tempering caps at 20")
	var armour := Armor.new()
	armour.tolerance = 100
	_check(_resolver.apply(armour, &"tempering").success and armour.quality >= 2 and armour.quality <= 4, "tempering works on armour, +2..4")
	var ring := Item.new()
	ring.equip_slot = Constants.EquipmentSlot.RING
	ring.tolerance = 100
	_check(_resolver.apply(ring, &"tempering").error == E.INVALID_TARGET, "tempering rejects a ring")
	_check(_resolver.apply(_slate(), &"tempering").error == E.INVALID_TARGET, "tempering rejects slates")
	_finished += 1

func _test_corrupted() -> void:
	_setup(37)
	for orb in Constants.ORB_IDS:
		var g := _rare_gear()
		g.is_corrupted = true
		var r := _resolver.apply(g, orb)
		if orb == &"opening" or orb == &"tempering":
			_check(r.success, "corrupted allows %s" % orb)
		else:
			_check(r.error == E.CORRUPTED, "corrupted rejects %s" % orb)
	var s := _slate()
	s.is_corrupted = true
	_check(_resolver.apply(s, &"quickening").error == E.CORRUPTED, "corrupted slate rejects quickening")
	_finished += 1

func _test_preview() -> void:
	_setup(41)
	var cases := []
	cases.append([_gear(), &"quickening", []])
	cases.append([_gear(), &"forging", ["brand_fire"]])
	cases.append([_slate(Constants.DamageType.FIRE, true), &"quickening", ["brand_cold"]])
	var uncommon := _gear()
	_resolver.apply(uncommon, &"quickening")
	cases.append([uncommon, &"grafting", []])
	cases.append([uncommon, &"elevation", ["brand_suffix"]])
	var rare := _rare_gear()
	cases.append([rare, &"recasting", []])
	cases.append([rare, &"recasting", ["brand_prefix", "brand_fire"]])
	var anchored := _rare_gear()
	_resolver.apply(anchored, &"anchoring")
	cases.append([anchored, &"recasting", []])
	var partial := _gear()
	_resolver.apply(partial, &"quickening")
	_resolver.apply(partial, &"elevation")
	cases.append([partial, &"ascendant", ["vestige_test_boss"]])

	for c in cases:
		var item: Resource = c[0]
		var active := _brands(c[2])
		var snapshot := ItemSerializer.to_dict(item) if item is Item else SlateSerializer.to_dict(item)
		var bag_before := _bag.counts.duplicate()
		var p := _resolver.preview(item, c[1], active)
		_check(p.is_valid(), "preview %s valid" % c[1])
		_check(absf(p.total_probability() - 1.0) < 0.000001, "preview %s probabilities sum to 1 (%f)" % [c[1], p.total_probability()])
		var after := ItemSerializer.to_dict(item) if item is Item else SlateSerializer.to_dict(item)
		_check(after == snapshot and _bag.counts == bag_before and active.get_ids().size() == c[2].size(), "preview %s has no side effects" % c[1])
		if c[1] == &"recasting":
			var removal_total := 0.0
			for rem in p.removals:
				removal_total += rem["probability"]
			_check(absf(removal_total - 1.0) < 0.000001, "recasting removal probabilities sum to 1")

	# Preview probabilities match observed apply frequencies.
	var p := _resolver.preview(_gear(), &"quickening", _brands(["brand_fire"]))
	var expected := {}
	for o in p.outcomes:
		var key := "%s:%d" % [o["def"].id, o["tier"].tier]
		expected[key] = expected.get(key, 0.0) + o["probability"]
	_bag.add_currency(&"brand_fire", 4000)
	_bag.add_currency(&"quickening", 4000)
	var observed := {}
	var trials := 4000
	for i in trials:
		var r := _resolver.apply(_gear(), &"quickening", _brands(["brand_fire"]))
		var key := "%s:%d" % [r.added[0].modifier_id, r.added[0].tier]
		observed[key] = observed.get(key, 0) + 1
	var close := true
	for key in expected:
		if absf(observed.get(key, 0) / float(trials) - expected[key]) > 0.03:
			close = false
	_check(close and observed.keys().all(func(k): return expected.has(k)), "apply frequencies match preview")
	_check(_resolver.preview(_gear(), &"quickening", _brands(["brand_fire", "brand_lightning"])).error == E.NO_VALID_OUTCOME, "preview reports no valid outcome")
	_finished += 1

func _test_signals_and_text() -> void:
	_setup(43)
	_failed_signals = 0
	_completed_signals = 0
	_resolver.apply(_gear(), &"quickening")
	_resolver.apply(_gear(), &"grafting")
	_check(_completed_signals == 1 and _failed_signals == 1, "craft_completed/craft_failed emitted")
	var empty := CurrencyBag.new()
	_resolver.currency = empty
	_check(_resolver.apply(_gear(), &"quickening").error == E.MISSING_CURRENCY, "missing orb rejected")
	for code in E.values():
		if code != E.NONE:
			_check(CurrencyText.error_message(CraftResult.error_name(code)) != CraftResult.error_name(code), "error text for %s" % CraftResult.error_name(code))
	for id in Constants.ORB_IDS:
		_check(CurrencyText.name_of(id) != String(id), "name for %s" % id)
	for id in _resolver.brand_defs:
		if id != &"vestige_test_boss":
			_check(CurrencyText.name_of(id) != String(id), "name for %s" % id)
	# Save round trip keeps crafting state.
	_resolver.currency = _bag
	var g := _rare_gear()
	_resolver.apply(g, &"anchoring")
	_resolver.apply(g, &"opening")
	_resolver.apply_edict(g, &"edict_prefix")
	var copy := ItemSerializer.from_dict(ItemSerializer.to_dict(g))
	_check(copy.tolerance == g.tolerance and copy.sockets_rolled and copy.sockets == g.sockets and copy.active_edict != null and copy.active_edict.id == &"edict_prefix", "item crafting state survives save")
	_check(_explicits(copy).filter(func(a: ItemAffix): return a.anchored).size() == 1, "anchored flag survives save")
	var s := _slate()
	_resolver.apply(s, &"forging")
	var s_copy := SlateSerializer.from_dict(SlateSerializer.to_dict(s))
	_check(s_copy.explicits.size() == s.explicits.size() and s_copy.tolerance == s.tolerance, "slate crafting state survives save")
	var legacy := ItemSerializer.to_dict(_gear())
	legacy.erase("tolerance")
	_check(ItemSerializer.from_dict(legacy).tolerance == 0, "legacy gear save gets no tolerance")
	_finished += 1
