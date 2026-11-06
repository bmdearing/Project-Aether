extends RefCounted
class_name CraftingResolver
## The Siphon (Crafting Rev 3): crafts paid in residue. preview() has no side
## effects. begin() validates everything first (a failed craft spends nothing),
## then pays, counts the craft on the item and simulates the outcomes; the
## CraftSession it returns applies one (choose) or none (decline). apply() is
## begin + choose(0) with the default payment.
##
## family: a modifier tag (CRAFT_FAMILIES) for add/recast/bleed/settle, a
## damage type name for retype, a boss id for vestige_add; &"" = unfocused.
## choice: the explicit's index for anchor.

const E := CraftResult.CraftError
const PREFIX := ModifierDef.AffixType.PREFIX
const SUFFIX := ModifierDef.AffixType.SUFFIX

const CRAFT_IDS: Array[StringName] = [&"add", &"recast", &"bleed", &"absolve", &"settle", &"anchor", &"sockets", &"retype", &"restore_type", &"vestige_add"]
const FAMILY_CRAFTS: Array[StringName] = [&"add", &"recast", &"bleed", &"settle"]
## Crafts a Figment takes (on its map mods, unfocused, any pool).
const FIGMENT_CRAFTS: Array[StringName] = [&"add", &"recast", &"bleed", &"absolve", &"settle"]
const VESTIGE_PREFIX := "vestige_"
## UniqueEffects.NO_INFUSION, inlined: referencing UniqueEffects here pulls the
## Player and projectile scripts into the item loading chain (a preload cycle).
const NO_INFUSION_KEY := "unique_no_infusion"

var rng: RandomNumberGenerator
var pools: Dictionary = {}  # pool_id -> ModifierPool (Vestige pools)

func _init(p_rng: RandomNumberGenerator = null) -> void:
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()

static func create_default(p_rng: RandomNumberGenerator = null) -> CraftingResolver:
	return CraftingResolver.new(p_rng)

func register_pool(pool: ModifierPool) -> void:
	pools[pool.pool_id] = pool

## Always null now: modifiers are matched to their pools by id or stat.
static func find_def(_id: StringName) -> ModifierDef:
	return null

## ---- Cost and payment -----------------------------------------------------

func cost_of(item: Resource, craft_id: StringName, _family: StringName = &"", outcomes: int = 1) -> int:
	var count := _craft_count(item)
	var mult := minf(pow(Constants.CRAFT_COST_GROWTH, count), Constants.CRAFT_COST_MULT_CAP)
	var foresight := 1.0 + Constants.FORESIGHT_EXTRA_COST * (clampi(outcomes, 1, Constants.FORESIGHT_MAX_OUTCOMES) - 1)
	return ceili(float(Constants.CRAFT_BASE_COST.get(craft_id, 0)) * mult * foresight)

## The item's current cost multiplier, for the UI.
static func cost_multiplier(item: Resource) -> float:
	return minf(pow(Constants.CRAFT_COST_GROWTH, _craft_count(item)), Constants.CRAFT_COST_MULT_CAP)

## Pools allowed to pay: one typed pool, the boss pool, or any regular pool.
static func payment_pools(craft_id: StringName, family: StringName) -> Array[StringName]:
	if craft_id == &"vestige_add":
		return [Residue.BOSS] as Array[StringName]
	if craft_id == &"retype":
		var type := _damage_type_named(family)
		return [Residue.pool_for_damage_type(type)] as Array[StringName] if type != -1 else [] as Array[StringName]
	if FAMILY_CRAFTS.has(craft_id) and family != &"":
		var pool: StringName = Constants.CRAFT_FAMILIES.get(family, &"")
		if pool != &"":
			return [pool] as Array[StringName]
	return Residue.REGULAR.duplicate()

## Takes from the fullest allowed pool first. Empty when it can't be afforded.
func auto_payment(item: Resource, craft_id: StringName, family: StringName = &"", outcomes: int = 1) -> Dictionary:
	var left := cost_of(item, craft_id, family, outcomes)
	var allowed := payment_pools(craft_id, family)
	allowed.sort_custom(func(a: StringName, b: StringName) -> bool: return Residue.amount(a) > Residue.amount(b))
	var payment := {}
	for pool in allowed:
		if left <= 0:
			break
		var take := mini(left, Residue.amount(pool))
		if take > 0:
			payment[pool] = take
			left -= take
	return payment if left <= 0 else {}

func _payment_error(item: Resource, craft_id: StringName, family: StringName, payment: Dictionary, outcomes: int) -> int:
	var allowed := payment_pools(craft_id, family)
	var total := 0
	for pool in payment:
		if not allowed.has(StringName(pool)) or int(payment[pool]) < 0:
			return E.INVALID_PAYMENT
		total += int(payment[pool])
	if total != cost_of(item, craft_id, family, outcomes):
		return E.INVALID_PAYMENT
	if not Residue.can_pay(payment):
		return E.CANT_AFFORD
	return E.NONE

## ---- Public API -----------------------------------------------------------

func preview(item: Resource, craft_id: StringName, family: StringName = &"", choice: int = -1) -> CraftPreview:
	var p := CraftPreview.new()
	p.craft_id = craft_id
	p.family = family
	var t := CraftTarget.wrap(item)
	if t == null:
		p.error = E.INVALID_TARGET
		return p
	p.cost = cost_of(item, craft_id, family)
	p.error = _check(t, craft_id, family, choice)
	if p.error != E.NONE or t.resource is FigmentItem:
		return p
	var explicits := t.get_explicits()
	match craft_id:
		&"add":
			var add := _add_candidates(t, explicits, family, craft_id)
			_merge_outcomes(p.outcomes, add["candidates"], 1.0)
			p.add_count = 1
		&"recast":
			var branches := _recast_branches(t, explicits, family)
			var share := 1.0 / branches.size()
			for branch in branches:
				p.removals.append({"affix": branch["affix"], "probability": share})
				p.affected.append({"affix": branch["affix"], "effect": &"replace", "probability": share})
				_merge_outcomes(p.outcomes, branch["candidates"], share)
			p.add_count = 1
		&"bleed", &"absolve":
			var removable := _removable(t, explicits, family if craft_id == &"bleed" else &"")
			var chance := 1.0 if craft_id == &"absolve" else 1.0 / removable.size()
			for affix in removable:
				p.removals.append({"affix": affix, "probability": chance})
				p.affected.append({"affix": affix, "effect": &"remove", "probability": chance})
		&"settle":
			for affix in _settleable(t, explicits, family):
				p.affected.append({"affix": affix, "effect": &"reroll", "probability": 1.0})
		&"anchor":
			p.affected.append({"affix": explicits[choice], "effect": &"anchor", "probability": 1.0})
	return p

func begin(item: Resource, craft_id: StringName, family: StringName, payment: Dictionary, outcomes: int = 1, choice: int = -1) -> CraftSession:
	var session := CraftSession.new()
	session.resolver = self
	session.target = item
	session.craft_id = craft_id
	var t := CraftTarget.wrap(item)
	var error: int = E.INVALID_TARGET if t == null else _check(t, craft_id, family, choice)
	outcomes = clampi(outcomes, 1, Constants.FORESIGHT_MAX_OUTCOMES)
	if error == E.NONE:
		error = _payment_error(item, craft_id, family, payment, outcomes)
	if error != E.NONE:
		session.error = error
		_fail(item, craft_id, error)
		return session
	Residue.pay(payment)
	session.paid = payment.duplicate()
	t.set_craft_count(t.get_craft_count() + 1)
	for i in outcomes:
		session.outcomes.append(_simulate(t, craft_id, family, choice))
	return session

## One craft with the default payment (fullest pool first), outcome applied.
func apply(item: Resource, craft_id: StringName, family: StringName = &"", choice: int = -1) -> CraftResult:
	var payment := auto_payment(item, craft_id, family)
	if payment.is_empty():
		var t := CraftTarget.wrap(item)
		var error: int = E.INVALID_TARGET if t == null else _check(t, craft_id, family, choice)
		var failed := CraftResult.new()
		failed.craft_id = craft_id
		failed.error = error if error != E.NONE else E.CANT_AFFORD
		_fail(item, craft_id, failed.error)
		return failed
	var session := begin(item, craft_id, family, payment, 1, choice)
	if session.error != E.NONE:
		var failed := CraftResult.new()
		failed.craft_id = craft_id
		failed.error = session.error
		return failed
	return session.choose(0)

## ---- Validation -----------------------------------------------------------

func _check(t: CraftTarget, craft_id: StringName, family: StringName, choice: int) -> int:
	if not CRAFT_IDS.has(craft_id):
		return E.INVALID_TARGET
	if t.resource is FigmentItem:
		return _check_figment(t.resource as FigmentItem, craft_id)
	var rarity := t.get_rarity()
	if rarity >= Constants.ItemRarity.UNIQUE and craft_id != &"sockets":
		return E.INVALID_TARGET
	if t.is_corrupted() and craft_id != &"sockets":
		return E.CORRUPTED
	if not t.is_corrupted() and t.resource is Item and not (t.resource as Item).is_craftable:
		return E.UNCRAFTABLE
	if FAMILY_CRAFTS.has(craft_id) and family != &"":
		if not Constants.CRAFT_FAMILIES.has(family):
			return E.INVALID_TARGET
		var slate_tags := t.get_slate_tags()
		if t.is_slate and Constants.CRAFT_FAMILIES[family] != &"" and not slate_tags.has(family):
			return E.NO_VALID_OUTCOME
	var explicits := t.get_explicits()
	match craft_id:
		&"vestige_add":
			var perk := PerkCatalog.boss_perk(String(family))
			if perk == &"" or not GameState.killed_bosses.has(String(family)):
				return E.NOT_UNLOCKED
			var gear := t.resource as Item
			if t.is_slate or gear == null or not PerkCatalog.fits(perk, gear):
				return E.INVALID_TARGET
			if gear.perks.keys().any(func(id): return PerkCatalog.is_boss(StringName(id))):
				return E.HAS_BOSS_PERK
			if gear.perks.size() >= MonsterInfrequent.MAX_PERKS:
				return E.PERK_LIMIT
		&"add":
			var limits := t.get_affix_limits(Constants.ItemRarity.RARE)
			if explicits.size() > t.get_total_limit(Constants.ItemRarity.RARE) or _prefix_count(explicits) > limits.x or explicits.size() - _prefix_count(explicits) > limits.y:
				return E.OVER_LINE_LIMIT
			var add := _add_candidates(t, explicits, family, craft_id)
			if add["open"] == false:
				return E.NO_OPEN_AFFIX
			if (add["candidates"] as Array).is_empty():
				return E.NO_VALID_OUTCOME
		&"recast":
			if _removable(t, explicits, family).is_empty():
				return E.NOTHING_TO_REMOVE
			if _recast_branches(t, explicits, family).is_empty():
				return E.NO_VALID_OUTCOME
		&"bleed":
			if _removable(t, explicits, family).is_empty():
				return E.NOTHING_TO_REMOVE
		&"absolve":
			if _removable(t, explicits, &"").is_empty():
				return E.NOTHING_TO_REMOVE
		&"settle":
			if _settleable(t, explicits, family).is_empty() and not (family == &"" and _lens_radius_range(t).y > _lens_radius_range(t).x):
				return E.NO_VALID_OUTCOME
		&"anchor":
			if explicits.size() < Constants.ANCHORING_MIN_MODIFIERS:
				return E.TOO_FEW_MODIFIERS
			if explicits.filter(func(a: ItemAffix): return a.anchored).size() >= Constants.MAX_ANCHORED_MODIFIERS:
				return E.ALREADY_ANCHORED
			if choice < 0 or choice >= explicits.size() or explicits[choice].anchored:
				return E.NO_VALID_OUTCOME
		&"sockets":
			if t.is_slate or t.resource is Jewel or not t.resource is Item:
				return E.INVALID_TARGET
			var item := t.resource as Item
			if item.fixed_sockets() > 0 or item.max_sockets < 1:
				return E.INVALID_TARGET
			# Jewels can't come out, so a full item has nothing to reroll.
			if item.socketed.size() >= item.max_sockets:
				return E.NO_VALID_OUTCOME
		&"retype":
			var weapon := t.resource as Weapon
			if weapon == null or weapon.get_all_affixes().any(func(a: ItemAffix): return a.stat_key == NO_INFUSION_KEY):
				return E.INVALID_TARGET
			var type := _damage_type_named(family)
			if type == -1 or type == weapon.get_damage_type():
				return E.NO_VALID_OUTCOME
		&"restore_type":
			var weapon := t.resource as Weapon
			if weapon == null or weapon.infused_damage_type == -1:
				return E.NO_VALID_OUTCOME
	return E.NONE

func _check_figment(figment: FigmentItem, craft_id: StringName) -> int:
	if not FIGMENT_CRAFTS.has(craft_id):
		return E.INVALID_TARGET
	var count := figment.affixes.size()
	if craft_id == &"add" and count >= CraftingSystem.figment_mod_cap(figment):
		return E.NO_OPEN_AFFIX
	if craft_id != &"add" and count == 0:
		return E.NOTHING_TO_REMOVE
	return E.NONE

## ---- Simulation -----------------------------------------------------------

## The post-craft state, without touching the item.
func _simulate(t: CraftTarget, craft_id: StringName, family: StringName, choice: int) -> Dictionary:
	if t.resource is FigmentItem:
		var copy := (t.resource as FigmentItem).duplicate(true) as FigmentItem
		CraftingSystem.figment_craft(copy, craft_id)
		return {"figment": copy}
	var explicits := t.get_explicits()
	var rarity := t.get_rarity()
	var added: Array[ItemAffix] = []
	var removed: Array[ItemAffix] = []
	var out := {"explicits": explicits, "rarity": rarity, "added": added, "removed": removed, "anchored": null}
	match craft_id:
		&"vestige_add":
			# The boss's perk makes the item a Monster Infrequent (Uncommon at least).
			var perk := PerkCatalog.boss_perk(String(family))
			out["perk"] = [perk, PerkCatalog.roll_value(perk, rng)]
			rarity = maxi(rarity, Constants.ItemRarity.UNCOMMON)
		&"add":
			var add := _add_candidates(t, explicits, family, craft_id)
			var affix := _roll_affix(_pick(add["candidates"]))
			explicits.append(affix)
			added.append(affix)
			rarity = maxi(rarity, add["rarity"])
		&"recast":
			var branches := _recast_branches(t, explicits, family)
			var branch: Dictionary = branches[rng.randi_range(0, branches.size() - 1)]
			explicits.erase(branch["affix"])
			removed.append(branch["affix"])
			var affix := _roll_affix(_pick(branch["candidates"]))
			explicits.append(affix)
			added.append(affix)
		&"bleed":
			var removable := _removable(t, explicits, family)
			var chosen: ItemAffix = removable[rng.randi_range(0, removable.size() - 1)]
			explicits.erase(chosen)
			removed.append(chosen)
		&"absolve":
			for affix in _removable(t, explicits, &""):
				explicits.erase(affix)
				removed.append(affix)
			rarity = _fitting_rarity(t, explicits)
		&"settle":
			for affix in _settleable(t, explicits, family):
				var copy := affix.duplicate() as ItemAffix
				copy.value = rng.randf_range(copy.value_min, copy.value_max)
				if ItemRoller.has_levelled_tiers(copy.stat_key):
					copy.value = roundf(copy.value)
				_describe(copy)
				explicits[explicits.find(affix)] = copy
			var range_ := _lens_radius_range(t)
			if family == &"" and range_.y > range_.x:
				out["radius_value"] = roundf(rng.randf_range(range_.x, range_.y))
		&"anchor":
			var copy := explicits[choice].duplicate() as ItemAffix
			copy.anchored = true
			explicits[choice] = copy
			out["anchored"] = copy
		&"sockets":
			var item := t.resource as Item
			out["sockets"] = rng.randi_range(maxi(1, item.socketed.size()), item.max_sockets)
		&"retype":
			out["infused"] = _damage_type_named(family)
		&"restore_type":
			out["infused"] = -1
	out["rarity"] = rarity
	return out

## Applies a simulated outcome to the item (CraftSession.choose()).
func commit(item: Resource, craft_id: StringName, outcome: Dictionary) -> CraftResult:
	var result := CraftResult.new()
	result.craft_id = craft_id
	if outcome.has("figment"):
		var figment := item as FigmentItem
		var done := outcome["figment"] as FigmentItem
		figment.affixes = done.affixes
		figment.rarity = done.rarity
		FigmentRoller._finish(figment)
	else:
		var t := CraftTarget.wrap(item)
		var rarity_changed: bool = t.get_rarity() != outcome["rarity"]
		t.set_explicits(outcome["explicits"])
		t.set_rarity(outcome["rarity"])
		if outcome.has("sockets"):
			(item as Item).sockets = outcome["sockets"]
			result.sockets_rolled_to = outcome["sockets"]
		if outcome.has("infused"):
			(item as Weapon).infused_damage_type = outcome["infused"]
		if outcome.has("radius_value") and item is Lens:
			(item as Lens).radius_value = outcome["radius_value"]
		if outcome.has("perk"):
			(item as Item).perks[String(outcome["perk"][0])] = float(outcome["perk"][1])
			result.perk_added = outcome["perk"][0]
			result.perk_value = outcome["perk"][1]
		result.added = outcome["added"]
		result.removed = outcome["removed"]
		result.anchored = outcome["anchored"]
		if item is Item and rarity_changed:
			EventBus.item_rarity_changed.emit(item)
	result.success = true
	if item is Item:
		EventBus.item_stats_changed.emit(item)
	EventBus.craft_completed.emit(item, result)
	return result

## ---- Candidates -----------------------------------------------------------

## {"candidates", "rarity" it needs, "open": false when no line is free even
## at Rare}. Add raises Common -> Uncommon -> Rare only as far as needed.
func _add_candidates(t: CraftTarget, explicits: Array[ItemAffix], family: StringName, _craft_id: StringName) -> Dictionary:
	var top := t.max_craft_rarity()
	var rarity := mini(maxi(t.get_rarity(), Constants.ItemRarity.UNCOMMON), top)
	var open := _open_types(t, explicits, rarity)
	while open.is_empty() and rarity < top:
		rarity += 1
		open = _open_types(t, explicits, rarity)
	if open.is_empty():
		return {"candidates": [] as Array[Dictionary], "rarity": rarity, "open": false}
	return {"candidates": _candidates(t, explicits, open, family), "rarity": rarity, "open": true}

func _candidates(t: CraftTarget, explicits: Array[ItemAffix], open: Array[int], family: StringName, pool_ids: Array[StringName] = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var present_groups := explicits.map(func(a: ItemAffix): return a.get_group())
	var tier_cap: int = Constants.SLATE_TIER_CAP_BY_SIZE.get(t.get_slate_size(), 0) if t.is_slate else 0
	var item_type := t.get_item_type()
	for def in _pool_defs(t, pool_ids):
		if not def.item_types.is_empty() and not def.item_types.has(item_type):
			continue
		if not open.has(def.affix_type):
			continue
		if family != &"" and not def.tags.has(family):
			continue
		if present_groups.has(def.group):
			continue
		for tier in def.tiers:
			if tier.tier < tier_cap or tier.weight <= 0:
				continue
			result.append({"def": def, "tier": tier, "weight": tier.weight})
	return result

func _pool_defs(t: CraftTarget, pool_ids: Array[StringName] = []) -> Array[ModifierDef]:
	var defs: Array[ModifierDef] = []
	if pool_ids.is_empty():
		if t.is_slate:
			defs.append_array(SlateModifierPool.defs_for(t.resource))
		elif t.resource is Item:
			defs.append_array(GearModifierPool.defs_for(t.resource))
		return defs
	for id in pool_ids:
		var pool: ModifierPool = pools.get(id)
		if pool:
			defs.append_array(pool.modifiers)
	return defs

func _open_types(t: CraftTarget, explicits: Array[ItemAffix], rarity: int) -> Array[int]:
	var limits := t.get_affix_limits(rarity)
	var prefixes := _prefix_count(explicits)
	var suffixes := explicits.size() - prefixes
	var open: Array[int] = []
	if explicits.size() >= t.get_total_limit(rarity):
		return open
	if prefixes < limits.x:
		open.append(PREFIX)
	if suffixes < limits.y:
		open.append(SUFFIX)
	return open

func _prefix_count(explicits: Array[ItemAffix]) -> int:
	return explicits.filter(func(a: ItemAffix): return a.is_prefix).size()

## Non-anchored explicits in the family (all of them when unfocused).
func _removable(t: CraftTarget, explicits: Array[ItemAffix], family: StringName) -> Array[ItemAffix]:
	var result: Array[ItemAffix] = []
	for a in explicits:
		if not a.anchored and (family == &"" or affix_tags(t, a).has(family)):
			result.append(a)
	return result

func _settleable(t: CraftTarget, explicits: Array[ItemAffix], family: StringName) -> Array[ItemAffix]:
	return _removable(t, explicits, family).filter(func(a: ItemAffix) -> bool: return a.value_max > a.value_min)

## Recast removes only when something in the family can be added back.
func _recast_branches(t: CraftTarget, explicits: Array[ItemAffix], family: StringName) -> Array[Dictionary]:
	var branches: Array[Dictionary] = []
	for affix in _removable(t, explicits, family):
		var rest := explicits.duplicate()
		rest.erase(affix)
		var cands := _candidates(t, rest, _open_types(t, rest, t.get_rarity()), family)
		if not cands.is_empty():
			branches.append({"affix": affix, "candidates": cands})
	return branches

## A rolled modifier's family tags. Modifiers from drops or saves have no def,
## so they're matched to the pool's def by id or stat.
func affix_tags(t: CraftTarget, affix: ItemAffix) -> Array[StringName]:
	if affix.def != null:
		return affix.def.tags
	var key := StringName(affix.key())
	for def in _pool_defs(t):
		if def.id == affix.modifier_id or (affix.affix_id != "" and String(def.id) == affix.affix_id) or def.id == StringName(affix.stat_key) or def.group == key:
			return def.tags
	var source_tags: Array = []
	for entry in ItemRoller.AFFIX_POOL:
		if entry["stat_key"] == affix.stat_key:
			source_tags = entry["brand_tags"]
	var tags := GearModifierPool._tags(source_tags, affix.stat_key)
	if affix.damage_type != -1:
		tags.append(StringName(String(Constants.DAMAGE_TYPE_NAME.get(affix.damage_type, "")).to_lower()))
	return tags

## A Lens's radius modifier value range (unfocused settle rerolls it); zero otherwise.
func _lens_radius_range(t: CraftTarget) -> Vector2:
	if not t.resource is Lens:
		return Vector2.ZERO
	var def: Dictionary = LensRoller.RADIUS_MODS.get((t.resource as Lens).radius_mod, {})
	return Vector2(def.get("min", 0.0), def.get("max", 0.0))

## ---- Helpers --------------------------------------------------------------

static func _craft_count(item: Resource) -> int:
	return int(item.get("craft_count")) if item != null and item.get("craft_count") != null else 0

static func _damage_type_named(name: StringName) -> int:
	for type in Constants.DAMAGE_TYPE_NAME:
		if String(Constants.DAMAGE_TYPE_NAME[type]).to_lower() == String(name).to_lower():
			return type
	return -1

## Lowest rarity whose limits still fit the remaining modifiers.
func _fitting_rarity(t: CraftTarget, explicits: Array[ItemAffix]) -> int:
	if explicits.is_empty():
		return Constants.ItemRarity.COMMON
	var prefixes := _prefix_count(explicits)
	var suffixes := explicits.size() - prefixes
	var limits := t.get_affix_limits(Constants.ItemRarity.UNCOMMON)
	if prefixes <= limits.x and suffixes <= limits.y and explicits.size() <= t.get_total_limit(Constants.ItemRarity.UNCOMMON):
		return Constants.ItemRarity.UNCOMMON
	return Constants.ItemRarity.RARE

func _pick(cands: Array[Dictionary]) -> Dictionary:
	var total := 0
	for c in cands:
		total += c["weight"]
	var roll := rng.randi_range(0, total - 1)
	for c in cands:
		roll -= c["weight"]
		if roll < 0:
			return c
	return cands.back()

func _merge_outcomes(outcomes: Array[Dictionary], cands: Array[Dictionary], share: float) -> void:
	var total := 0.0
	for c in cands:
		total += c["weight"]
	for c in cands:
		var probability: float = share * c["weight"] / total
		var existing := outcomes.filter(func(o): return o["def"] == c["def"] and o["tier"] == c["tier"])
		if existing.is_empty():
			outcomes.append({"def": c["def"], "tier": c["tier"], "probability": probability})
		else:
			existing[0]["probability"] += probability

func _roll_affix(cand: Dictionary) -> ItemAffix:
	var def: ModifierDef = cand["def"]
	var tier: ModifierTier = cand["tier"]
	var affix := ItemAffix.new()
	affix.def = def
	affix.modifier_id = def.id
	affix.group = def.group
	affix.stat_key = def.stat_key
	affix.tier = tier.tier
	affix.value_min = tier.value_min
	affix.value_max = tier.value_max
	affix.value = rng.randf_range(tier.value_min, tier.value_max)
	if ItemRoller.has_levelled_tiers(def.stat_key):
		affix.value = roundf(affix.value)
	affix.is_prefix = def.affix_type == PREFIX
	affix.affix_id = String(def.id)
	affix.damage_type = def.damage_type
	affix.is_generic = def.is_generic
	affix.is_local = def.is_local
	_describe(affix)
	return affix

func _describe(affix: ItemAffix) -> void:
	var text := _template_for(affix)
	if text == "":
		return
	affix.description = "%s (Tier %d)" % [ItemRoller.describe_value(text, affix.stat_key, affix.value), affix.tier]

## The line's format string: from its ModifierDef, else from the AFFIX_POOL
## entry / weapon library affix it came from.
static func _template_for(affix: ItemAffix) -> String:
	if affix.def != null:
		return affix.def.text if affix.def.text != "" else String(affix.def.id)
	for entry in ItemRoller.AFFIX_POOL:
		if entry["stat_key"] == affix.stat_key:
			return entry["desc"]
	for entry in ItemRoller.AFFIX_POOL:
		if StatKeys.canonical(entry["stat_key"]) == affix.key():
			return entry["desc"]
	if ItemRoller._weapon_affix_cache.is_empty():
		ItemRoller._build_weapon_affix_cache()
	for source in ItemRoller._weapon_affix_cache:
		if source.affix_id != "" and source.affix_id == affix.affix_id:
			return source.description
	return ""

func _fail(item: Resource, _craft_id: StringName, code: int) -> void:
	EventBus.craft_failed.emit(item, code, CurrencyText.error_message(CraftResult.error_name(code)))
