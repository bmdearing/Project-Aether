extends RefCounted
class_name CraftingResolver
## Orb crafting (Crafting & Inventory Rev2, Parts 1-5). preview() has no side
## effects; apply() validates everything first, so a failed craft consumes
## nothing - no Orb, no Brands, no tolerance - and leaves the Edict in place.

const E := CraftResult.CraftError
const PREFIX := ModifierDef.AffixType.PREFIX
const SUFFIX := ModifierDef.AffixType.SUFFIX

enum OrbKind { ADD, RECAST, REMOVE, OTHER }

const POOLS_DIR := "res://data/crafting/pools/"
const BRANDS_DIR := "res://data/crafting/brands/"
const EDICTS_DIR := "res://data/crafting/edicts/"

var rng: RandomNumberGenerator
## Crafting currency source: anything with count_of(id) / remove_currency(id, n).
## Null skips the ownership check and consumption of the Orb.
var currency: Object
var pools: Dictionary = {}        # pool_id -> ModifierPool
var brand_defs: Dictionary = {}   # id -> BrandDef
var edict_defs: Dictionary = {}   # id -> EdictDef

func _init(p_rng: RandomNumberGenerator = null) -> void:
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()

static func create_default(p_rng: RandomNumberGenerator = null) -> CraftingResolver:
	var resolver := CraftingResolver.new(p_rng)
	for res in _load_dir(POOLS_DIR):
		if res is ModifierPool:
			resolver.register_pool(res)
	for res in _load_dir(BRANDS_DIR):
		if res is BrandDef:
			resolver.register_brand(res)
	for res in _load_dir(EDICTS_DIR):
		if res is EdictDef:
			resolver.register_edict(res)
	return resolver

func register_pool(pool: ModifierPool) -> void:
	pools[pool.pool_id] = pool

func register_brand(def: BrandDef) -> void:
	brand_defs[def.id] = def

func register_edict(def: EdictDef) -> void:
	edict_defs[def.id] = def

static var _def_cache: Dictionary = {}

## Looks up a shipped ModifierDef by id (for restoring saved modifiers).
static func find_def(id: StringName) -> ModifierDef:
	if id == &"":
		return null
	if _def_cache.is_empty():
		for res in _load_dir(POOLS_DIR):
			if res is ModifierPool:
				for def in res.modifiers:
					_def_cache[def.id] = def
	return _def_cache.get(id)

static func roll_tolerance(target: Resource, p_rng: RandomNumberGenerator = null) -> void:
	var t := CraftTarget.wrap(target)
	if t == null or not t.uses_tolerance():
		return
	var range_: Vector2i = Constants.STARTING_TOLERANCE_BY_ITEM_TYPE.get(t.get_item_type(), Constants.STARTING_TOLERANCE_DEFAULT)
	var value := p_rng.randi_range(range_.x, range_.y) if p_rng != null else randi_range(range_.x, range_.y)
	target.tolerance = value
	target.tolerance_max = value

## ---- Public API ------------------------------------------------------

func preview(item: Resource, orb_id: StringName, active_brands: ActiveBrands = null) -> CraftPreview:
	var p := CraftPreview.new()
	p.orb_id = orb_id
	var t := CraftTarget.wrap(item)
	if t == null:
		p.error = E.INVALID_TARGET
		return p
	var ctx := _resolve_brands(orb_id, active_brands)
	p.applied_brands = ctx["applied"]
	p.consumed_brands = ctx["consumed"]
	var edict := t.get_active_edict()
	p.error = _check(t, orb_id, ctx, edict)
	if p.error != E.NONE:
		return p

	var explicits := t.get_explicits()
	var rarity := t.get_rarity()
	match _kind(orb_id):
		OrbKind.ADD:
			var cands := _candidates(t, explicits, _rarity_after(orb_id, rarity), ctx, edict)
			if cands.is_empty():
				p.error = E.NO_VALID_OUTCOME
				return p
			_merge_outcomes(p.outcomes, cands, 1.0)
			p.add_count = _add_count_range(t, orb_id).y
		OrbKind.RECAST:
			var branches := _recast_branches(t, explicits, rarity, ctx, edict)
			if branches.is_empty():
				p.error = E.NO_VALID_OUTCOME
				return p
			var share := 1.0 / branches.size()
			for branch in branches:
				p.removals.append({"affix": branch["affix"], "probability": share})
				_merge_outcomes(p.outcomes, branch["candidates"], share)
			p.add_count = 1
		OrbKind.REMOVE:
			var removable := _removable(explicits, ctx, edict)
			var chance := 1.0 if orb_id == &"absolution" else 1.0 / removable.size()
			for affix in removable:
				p.removals.append({"affix": affix, "probability": chance})
	return p

func apply(item: Resource, orb_id: StringName, active_brands: ActiveBrands = null) -> CraftResult:
	var result := CraftResult.new()
	result.orb_id = orb_id
	var t := CraftTarget.wrap(item)
	if t == null:
		return _fail(item, result, E.INVALID_TARGET)
	var ctx := _resolve_brands(orb_id, active_brands)
	var edict := t.get_active_edict()
	var error := _check(t, orb_id, ctx, edict)
	if error != E.NONE:
		return _fail(item, result, error)
	if currency != null and currency.count_of(orb_id) < 1:
		return _fail(item, result, E.MISSING_CURRENCY)

	var sim := _simulate(t, orb_id, ctx, edict)
	if sim["error"] != E.NONE:
		return _fail(item, result, sim["error"])

	if t.uses_tolerance():
		var cost_range: Vector2i = Constants.TOLERANCE_COST.get(orb_id, Vector2i.ONE)
		var cost := rng.randi_range(cost_range.x, cost_range.y)
		result.tolerance_spent = mini(cost, t.get_tolerance())
		t.set_tolerance(maxi(0, t.get_tolerance() - cost))

	t.set_explicits(sim["explicits"])
	var rarity_changed: bool = t.get_rarity() != sim["rarity"]
	t.set_rarity(sim["rarity"])
	if orb_id == &"tempering":
		t.set_quality(sim["quality"])
	elif orb_id == &"opening":
		t.set_sockets(sim["sockets"])
		result.sockets_rolled_to = sim["sockets"]
	result.added = sim["added"]
	result.removed = sim["removed"]
	result.anchored = sim["anchored"]
	result.quality_gained = sim["quality_gained"]

	if currency != null:
		currency.remove_currency(orb_id, 1)
	for id in ctx["consumed"]:
		active_brands.consume(id)
	result.consumed_brands = ctx["consumed"]
	t.set_active_edict(null)

	result.success = true
	if item is Item:
		EventBus.item_stats_changed.emit(item)
		if rarity_changed:
			EventBus.item_rarity_changed.emit(item)
	EventBus.craft_completed.emit(item, result)
	return result

## Places an Edict on an item. Not a craft: costs no tolerance and doesn't
## clear anything.
func apply_edict(item: Resource, edict_id: StringName) -> CraftResult:
	var result := CraftResult.new()
	result.orb_id = edict_id
	var t := CraftTarget.wrap(item)
	var def: EdictDef = edict_defs.get(edict_id)
	if t == null or def == null or t.get_rarity() >= Constants.ItemRarity.UNIQUE or t.get_active_edict() != null:
		return _fail(item, result, E.INVALID_TARGET)
	if t.is_corrupted():
		return _fail(item, result, E.CORRUPTED)
	if currency != null and not currency.remove_currency(edict_id, 1):
		return _fail(item, result, E.MISSING_CURRENCY)
	t.set_active_edict(def)
	result.success = true
	return result

## ---- Validation --------------------------------------------------------

func _check(t: CraftTarget, orb_id: StringName, ctx: Dictionary, edict: EdictDef) -> int:
	if not Constants.ORB_IDS.has(orb_id):
		return E.INVALID_TARGET
	var rarity := t.get_rarity()
	if rarity >= Constants.ItemRarity.UNIQUE:
		return E.INVALID_TARGET
	if t.is_corrupted() and orb_id != &"opening" and orb_id != &"tempering":
		return E.CORRUPTED
	if t.uses_tolerance() and t.get_tolerance() <= 0:
		return E.NO_TOLERANCE
	var explicits := t.get_explicits()
	var positional: int = ctx["positional"]
	match orb_id:
		&"quickening", &"forging":
			if rarity != Constants.ItemRarity.COMMON:
				return E.INVALID_TARGET
		&"elevation":
			if rarity != Constants.ItemRarity.UNCOMMON:
				return E.INVALID_TARGET
		&"grafting", &"ascendant":
			var needed := Constants.ItemRarity.UNCOMMON if orb_id == &"grafting" else Constants.ItemRarity.RARE
			if rarity != needed:
				return E.INVALID_TARGET
			if _open_types(t, explicits, rarity, positional).is_empty():
				return E.NO_OPEN_AFFIX
		&"recasting":
			if rarity != Constants.ItemRarity.RARE:
				return E.INVALID_TARGET
			if _removable(explicits, ctx, edict).is_empty():
				return E.NOTHING_TO_REMOVE
		&"severance", &"absolution":
			if _removable(explicits, ctx, edict).is_empty():
				return E.NOTHING_TO_REMOVE
		&"anchoring":
			if explicits.size() < Constants.ANCHORING_MIN_MODIFIERS:
				return E.TOO_FEW_MODIFIERS
			if explicits.filter(func(a: ItemAffix): return a.anchored).size() >= Constants.MAX_ANCHORED_MODIFIERS:
				return E.ALREADY_ANCHORED
		&"tempering":
			if t.is_slate or not t.can_temper():
				return E.INVALID_TARGET
			if t.get_quality() >= Constants.QUALITY_CAP:
				return E.QUALITY_CAPPED
		&"opening":
			if t.is_slate or t.resource is Jewel:
				return E.INVALID_TARGET
			if t.sockets_rolled() or t.get_sockets() > 0:
				return E.SOCKETS_ALREADY_ROLLED
		&"reckoning":
			if explicits.is_empty():
				return E.TOO_FEW_MODIFIERS
			if not explicits.any(func(a: ItemAffix): return not _locked(a, edict)):
				return E.NO_VALID_OUTCOME
	return E.NONE

## ---- Simulation --------------------------------------------------------

## Computes the post-craft state without touching the item.
func _simulate(t: CraftTarget, orb_id: StringName, ctx: Dictionary, edict: EdictDef) -> Dictionary:
	var explicits := t.get_explicits()
	var rarity := t.get_rarity()
	var added: Array[ItemAffix] = []
	var removed: Array[ItemAffix] = []
	var out := {
		"error": E.NONE, "explicits": explicits, "rarity": rarity,
		"added": added, "removed": removed, "anchored": null,
		"quality": t.get_quality(), "quality_gained": 0, "sockets": t.get_sockets(),
	}
	match _kind(orb_id):
		OrbKind.ADD:
			rarity = _rarity_after(orb_id, rarity)
			var range_ := _add_count_range(t, orb_id)
			for i in rng.randi_range(range_.x, range_.y):
				var cands := _candidates(t, explicits, rarity, ctx, edict)
				if cands.is_empty():
					out["error"] = E.NO_VALID_OUTCOME
					return out
				var affix := _roll_affix(_pick(cands))
				explicits.append(affix)
				out["added"].append(affix)
		OrbKind.RECAST:
			var branches := _recast_branches(t, explicits, rarity, ctx, edict)
			if branches.is_empty():
				out["error"] = E.NO_VALID_OUTCOME
				return out
			var branch: Dictionary = branches[rng.randi_range(0, branches.size() - 1)]
			explicits.erase(branch["affix"])
			out["removed"].append(branch["affix"])
			var affix := _roll_affix(_pick(branch["candidates"]))
			explicits.append(affix)
			out["added"].append(affix)
		OrbKind.REMOVE:
			var removable := _removable(explicits, ctx, edict)
			if orb_id == &"severance":
				var chosen: ItemAffix = removable[rng.randi_range(0, removable.size() - 1)]
				removable.clear()
				removable.append(chosen)
			for affix in removable:
				explicits.erase(affix)
				out["removed"].append(affix)
			if orb_id == &"absolution":
				rarity = _fitting_rarity(t, explicits)
		OrbKind.OTHER:
			match orb_id:
				&"anchoring":
					var options := explicits.filter(func(a: ItemAffix): return not a.anchored)
					var chosen: ItemAffix = options[rng.randi_range(0, options.size() - 1)]
					var copy := chosen.duplicate() as ItemAffix
					copy.anchored = true
					explicits[explicits.find(chosen)] = copy
					out["anchored"] = copy
				&"tempering":
					var gain := rng.randi_range(Constants.TEMPERING_QUALITY_GAIN.x, Constants.TEMPERING_QUALITY_GAIN.y)
					out["quality"] = mini(Constants.QUALITY_CAP, t.get_quality() + gain)
					out["quality_gained"] = out["quality"] - t.get_quality()
				&"opening":
					out["sockets"] = rng.randi_range(0, t.get_max_sockets())
				&"reckoning":
					for i in explicits.size():
						var affix: ItemAffix = explicits[i]
						if _locked(affix, edict) or affix.value_max <= affix.value_min:
							continue
						var copy := affix.duplicate() as ItemAffix
						copy.value = rng.randf_range(copy.value_min, copy.value_max)
						_describe(copy)
						explicits[i] = copy
	out["rarity"] = rarity
	return out

## ---- Brands ------------------------------------------------------------

## Which active Brands apply to this Orb, what they restrict, and which of
## them the craft consumes.
func _resolve_brands(orb_id: StringName, active: ActiveBrands) -> Dictionary:
	var applied: Array[StringName] = []
	var categories: Array[BrandDef] = []
	var vestige_pools: Array[StringName] = []
	var has_prefix := false
	var has_suffix := false
	var preservation: BrandDef = null
	var kind := _kind(orb_id)
	if active != null and kind != OrbKind.OTHER:
		for id in active.get_ids():
			var def: BrandDef = brand_defs.get(id)
			if def == null:
				continue
			if def.is_preservation:
				preservation = def
				continue
			if def.is_vestige():
				if kind != OrbKind.REMOVE and def.applies_to_orbs.has(orb_id):
					applied.append(id)
					vestige_pools.append(def.vestige_pool)
				continue
			var used := false
			if def.positional == BrandDef.Positional.PREFIX_ONLY:
				has_prefix = true
				used = true
			elif def.positional == BrandDef.Positional.SUFFIX_ONLY:
				has_suffix = true
				used = true
			if def.is_category() and kind != OrbKind.REMOVE:
				categories.append(def)
				used = true
			if used:
				applied.append(id)

	var positional := BrandDef.Positional.NONE
	if has_prefix and not has_suffix:
		positional = BrandDef.Positional.PREFIX_ONLY
	elif has_suffix and not has_prefix:
		positional = BrandDef.Positional.SUFFIX_ONLY

	var consumed: Array[StringName] = applied.duplicate()
	if preservation != null and not applied.is_empty():
		applied.append(preservation.id)
		consumed.clear()
		consumed.append(preservation.id)
	return {
		"applied": applied, "consumed": consumed, "categories": categories,
		"positional": positional, "vestige_pools": vestige_pools,
	}

## ---- Candidate filter --------------------------------------------------

func _candidates(t: CraftTarget, explicits: Array[ItemAffix], rarity: int, ctx: Dictionary, edict: EdictDef) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var open := _open_types(t, explicits, rarity, ctx["positional"])
	if open.is_empty():
		return result

	var slate_tags := t.get_slate_tags()
	var required: Array[StringName] = []
	for brand: BrandDef in ctx["categories"]:
		if t.is_slate and not brand.tags.any(func(tag: StringName): return slate_tags.has(tag)):
			return result
		for tag in brand.tags:
			if not required.has(tag):
				required.append(tag)
	var excluded: Array[StringName] = []
	if edict != null:
		excluded = edict.excludes_tags
	var present_groups := explicits.map(func(a: ItemAffix): return a.get_group())
	var tier_cap: int = Constants.SLATE_TIER_CAP_BY_SIZE.get(t.get_slate_size(), 0) if t.is_slate else 0
	var item_type := t.get_item_type()

	for def in _pool_defs(t, ctx["vestige_pools"]):
		if not def.item_types.is_empty() and not def.item_types.has(item_type):
			continue
		if not open.has(def.affix_type):
			continue
		if not required.all(func(tag: StringName): return def.tags.has(tag)):
			continue
		if def.tags.any(func(tag: StringName): return excluded.has(tag)):
			continue
		if present_groups.has(def.group):
			continue
		for tier in def.tiers:
			if tier.tier < tier_cap or tier.weight <= 0:
				continue
			result.append({"def": def, "tier": tier, "weight": tier.weight})
	return result

func _pool_defs(t: CraftTarget, vestige_pools: Array[StringName]) -> Array[ModifierDef]:
	var ids: Array[StringName] = vestige_pools.duplicate()
	if ids.is_empty():
		ids.append(&"slate" if t.is_slate else &"gear")
	var defs: Array[ModifierDef] = []
	for id in ids:
		var pool: ModifierPool = pools.get(id)
		if pool == null and id == &"gear" and t.resource is Item:
			defs.append_array(GearModifierPool.defs_for(t.resource))
			continue
		if pool == null and id == &"slate" and t.is_slate:
			defs.append_array(SlateModifierPool.defs_for(t.resource))
			continue
		if pool == null:
			continue
		for def in pool.modifiers:
			if not defs.has(def):
				defs.append(def)
	return defs

func _open_types(t: CraftTarget, explicits: Array[ItemAffix], rarity: int, positional: int) -> Array[int]:
	var limits := t.get_affix_limits(rarity)
	var prefixes := explicits.filter(func(a: ItemAffix): return a.is_prefix).size()
	var suffixes := explicits.size() - prefixes
	var open: Array[int] = []
	if prefixes < limits.x and positional != BrandDef.Positional.SUFFIX_ONLY:
		open.append(PREFIX)
	if suffixes < limits.y and positional != BrandDef.Positional.PREFIX_ONLY:
		open.append(SUFFIX)
	return open

func _removable(explicits: Array[ItemAffix], ctx: Dictionary, edict: EdictDef) -> Array[ItemAffix]:
	var positional: int = ctx["positional"]
	var result: Array[ItemAffix] = []
	for a in explicits:
		if a.anchored or _locked(a, edict):
			continue
		if positional == BrandDef.Positional.PREFIX_ONLY and not a.is_prefix:
			continue
		if positional == BrandDef.Positional.SUFFIX_ONLY and a.is_prefix:
			continue
		result.append(a)
	return result

## Recasting only removes a modifier when something can be added back, so
## each branch is a removable modifier plus the candidates left after it goes.
func _recast_branches(t: CraftTarget, explicits: Array[ItemAffix], rarity: int, ctx: Dictionary, edict: EdictDef) -> Array[Dictionary]:
	var branches: Array[Dictionary] = []
	for affix in _removable(explicits, ctx, edict):
		var rest := explicits.duplicate()
		rest.erase(affix)
		var cands := _candidates(t, rest, rarity, ctx, edict)
		if not cands.is_empty():
			branches.append({"affix": affix, "candidates": cands})
	return branches

func _locked(affix: ItemAffix, edict: EdictDef) -> bool:
	if edict == null:
		return false
	return (edict.locks == EdictDef.Lock.PREFIX and affix.is_prefix) or (edict.locks == EdictDef.Lock.SUFFIX and not affix.is_prefix)

## ---- Helpers -----------------------------------------------------------

func _kind(orb_id: StringName) -> OrbKind:
	match orb_id:
		&"quickening", &"grafting", &"elevation", &"forging", &"ascendant":
			return OrbKind.ADD
		&"recasting":
			return OrbKind.RECAST
		&"severance", &"absolution":
			return OrbKind.REMOVE
	return OrbKind.OTHER

func _rarity_after(orb_id: StringName, rarity: int) -> int:
	match orb_id:
		&"quickening":
			return Constants.ItemRarity.UNCOMMON
		&"elevation", &"forging":
			return Constants.ItemRarity.RARE
	return rarity

func _add_count_range(t: CraftTarget, orb_id: StringName) -> Vector2i:
	if orb_id != &"forging":
		return Vector2i.ONE
	if t.is_slate:
		return Constants.FORGING_MODIFIERS_SLATE
	return Vector2i(Constants.FORGING_MODIFIERS_GEAR, Constants.FORGING_MODIFIERS_GEAR)

## Lowest rarity whose limits still fit the remaining modifiers.
func _fitting_rarity(t: CraftTarget, explicits: Array[ItemAffix]) -> int:
	if explicits.is_empty():
		return Constants.ItemRarity.COMMON
	var prefixes := explicits.filter(func(a: ItemAffix): return a.is_prefix).size()
	var suffixes := explicits.size() - prefixes
	var limits := t.get_affix_limits(Constants.ItemRarity.UNCOMMON)
	if prefixes <= limits.x and suffixes <= limits.y:
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
	affix.description = "%s (Tier %d)" % [ItemRoller.format_desc(text, affix.value), affix.tier]

## The line's format string: from its ModifierDef, or for a modifier rolled
## before Orbs existed, from the AFFIX_POOL entry / weapon library affix it
## came from.
static func _template_for(affix: ItemAffix) -> String:
	if affix.def != null:
		return affix.def.text if affix.def.text != "" else String(affix.def.id)
	for entry in ItemRoller.AFFIX_POOL:
		if entry["stat_key"] == affix.stat_key:
			return entry["desc"]
	if ItemRoller._weapon_affix_cache.is_empty():
		ItemRoller._build_weapon_affix_cache()
	for source in ItemRoller._weapon_affix_cache:
		if source.affix_id != "" and source.affix_id == affix.affix_id:
			return source.description
	return ""

func _fail(item: Resource, result: CraftResult, code: int) -> CraftResult:
	result.error = code
	EventBus.craft_failed.emit(item, code, result.get_message())
	return result

static func _load_dir(path: String) -> Array[Resource]:
	var found: Array[Resource] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var file_name := dir.get_next().trim_suffix(".remap")
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res := load(path + file_name)
			if res:
				found.append(res)
		file_name = dir.get_next().trim_suffix(".remap")
	dir.list_dir_end()
	return found
