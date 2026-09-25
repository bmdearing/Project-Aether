extends RefCounted
class_name CraftingSystem
## Section 20 - Crafting System. Three distinct methods per the doc: The
## Cube (Brand combinations - craft_cube() below), Infusion/Shrivening
## Stone (infuse()/shrive()), and the Shard of Tharsis (corrupt(), now a
## thin wrapper around CorruptionSystem.gd - see its own header). Section
## 24 ("Deferred Design") explicitly defers Cube combination rules, Brand
## rarity tiers, and Corruption probability distribution to a future
## design pass the doc itself hasn't done yet - every number/priority
## rule below is this project's own invented placeholder for those
## explicitly-deferred specifics, same convention as every other flagged
## gap in this project (see README).
##
## Patch v3.6: category-Brand combinations (craft_cube()'s own
## _add_weighted_affix()) now consult BrandCombinationResolver.gd first
## for named pair/triple combos before falling back to the original
## weighted-any-present-tag pick - this is that "future design pass" for
## the Cube's own combination rules specifically.

const MAX_AFFIXES := 6  # Section 18's own "Rare: 0-6" ceiling, reused as the modifier cap Section 24 never pins down
const CUBE_CAPACITY := 8  # 3x3 grid minus 1 cell for the target item - this project's inventory is uniform 1x1 (README gap #6), so any item costs exactly one cell
const MAX_SAME_BRAND := 2  # doc-exact ("Maximum 2 of the same Brand per craft")

const CLEAVE_DESTROY_CHANCE := 0.2   # invented - 2nd Cleave attempt only
const SEVER_UNDO_CHANCE := 0.35      # invented - 2nd Sever attempt only
const REFINE_BOOST_PERCENT := 0.15   # invented - "improves... value ranges"

## User request: "Figments should be craftable to make them harder." A
## Figment's "affixes" are enemy/loot multipliers (FigmentRoller.
## AFFIX_POOL), not the flat_<stat>/damage-% pool the Cube's Brand system
## rolls against - the generic craft_cube() path doesn't apply to them
## semantically (a Figment is never equipped/placed, nothing reads its
## affixes as player stats), so this is its own dedicated action, gated
## by Gold rather than Brands since nothing else about Figments is doc-
## or design-brief-sourced either.
const EMPOWER_FIGMENT_GOLD_COST := 25

static func empower_figment(figment: FigmentItem) -> Dictionary:
	if figment == null:
		return {"success": false, "message": "No Figment selected."}
	figment.tier += 1
	FigmentRoller.strengthen(figment)
	return {"success": true, "message": "The Figment grows harder - now Tier %d." % figment.tier}
const RETAIN_CRAFTABLE_CHANCE := 0.2 # invented - Shard's "% chance to retain craftable/corruptible status"

## When multiple utility/special Brand functions are placed together in
## one craft (undefined by the doc - Section 24's "fixed vs variable
## slots" is explicitly unresolved), the first one found in this order
## governs the craft; the rest are still consumed (unless Binder saves
## them) but don't do anything extra this attempt.
const FUNCTION_PRIORITY: Array[Brand.BrandFunction] = [
	Brand.BrandFunction.SEVER, Brand.BrandFunction.CLEAVE, Brand.BrandFunction.EXCISE,
	Brand.BrandFunction.RECTIFY, Brand.BrandFunction.REFINE, Brand.BrandFunction.RENDER,
	Brand.BrandFunction.BORE,
]


## ---- The Cube --------------------------------------------------------

## Runs one Cube craft attempt against `item`, consuming `brands` per the
## rules in each Brand's own doc comment. `target_affix_index` is only
## consulted by Cleave (which affix to lock) and Excise (which affix to
## remove) - CraftingScreen collects it from the player before calling
## this when a placed Brand needs it. Returns {success, message,
## destroyed, consumed: Array[Brand]} - `consumed` is what the caller
## should actually remove from GameState.owned_loot; Binder's presence
## leaves everything but itself un-consumed.
static func craft_cube(item: Item, brands: Array[Brand], power_level: int = 1, target_affix_index: int = -1) -> Dictionary:
	if item == null or brands.is_empty():
		return {"success": false, "message": "Place an item and at least one Brand.", "destroyed": false, "consumed": []}
	if not item.is_craftable:
		return {"success": false, "message": "This item was corrupted beyond further crafting.", "destroyed": false, "consumed": []}
	if brands.size() > CUBE_CAPACITY:
		return {"success": false, "message": "Too many Brands for the Cube (max %d)." % CUBE_CAPACITY, "destroyed": false, "consumed": []}
	if not _under_same_brand_limit(brands):
		return {"success": false, "message": "Maximum %d of the same Brand per craft." % MAX_SAME_BRAND, "destroyed": false, "consumed": []}

	var has_binder := false
	for b in brands:
		if b.brand_function == Brand.BrandFunction.BINDER:
			has_binder = true
			break
	var category_brands: Array[Brand] = []
	for b in brands:
		if b.brand_function in [Brand.BrandFunction.DAMAGE_TYPE, Brand.BrandFunction.DEFENSIVE_TYPE, Brand.BrandFunction.UMBRELLA]:
			category_brands.append(b)
	var utility_brand := _governing_utility_brand(brands)

	var message := ""
	var destroyed := false

	if utility_brand == null:
		if category_brands.is_empty():
			return {"success": false, "message": "Nothing for this Brand combination to do.", "destroyed": false, "consumed": []}
		message = _add_weighted_affix(item, category_brands, power_level)
	else:
		match utility_brand.brand_function:
			Brand.BrandFunction.RENDER:
				message = _render(item, power_level)
			Brand.BrandFunction.RECTIFY:
				message = _rectify(item)
			Brand.BrandFunction.REFINE:
				message = _refine(item)
			Brand.BrandFunction.EXCISE:
				message = _excise(item, target_affix_index)
			Brand.BrandFunction.BORE:
				message = _bore(item)
			Brand.BrandFunction.SEVER:
				message = _sever(item, category_brands, has_binder)
			Brand.BrandFunction.CLEAVE:
				var result := _cleave(item, power_level, target_affix_index)
				message = result["message"]
				destroyed = result["destroyed"]

	var consumed: Array[Brand] = []
	if has_binder:
		for b in brands:
			if b.brand_function == Brand.BrandFunction.BINDER:
				consumed.append(b)
	else:
		consumed = brands.duplicate()
	for b in consumed:
		EventBus.brand_consumed.emit(b.item_id)
	if not destroyed:
		_update_item_rarity(item)
		# One refresh for every Brand path (a few also emit internally; the
		# listener is idempotent). Player re-applies it if the item is equipped.
		EventBus.item_stats_changed.emit(item)
	return {"success": true, "message": message, "destroyed": destroyed, "consumed": consumed}

## Patch v3.9 - rarity tracks affix count (Section 18: Common 0, Uncommon
## 1-2, Rare 3+ - reusing the same 0/1-2/3+ bands ItemRoller.roll()'s own
## affix_count-by-rarity-roll already uses, just inverted). Called once
## per successful craft_cube() (covers every affix add/remove/reroll
## uniformly - _bore()/_sever() don't change affix count, but recomputing
## is a harmless no-op for them) rather than from each individual _render/
## _rectify/_excise/_cleave/_add_weighted_affix helper. Unique/Mythic
## items and anything still `is_corrupted` never get reclassified.
static func _update_item_rarity(item: Item) -> void:
	if item.rarity == Constants.ItemRarity.UNIQUE:
		return
	if item.rarity == Constants.ItemRarity.MYTHIC:
		return
	if item.is_corrupted:
		return

	var affix_count := item.get_prefix_count() + item.get_suffix_count()
	var new_rarity: Constants.ItemRarity
	if affix_count == 0:
		new_rarity = Constants.ItemRarity.COMMON
	elif affix_count <= 2:
		new_rarity = Constants.ItemRarity.UNCOMMON
	else:
		new_rarity = Constants.ItemRarity.RARE

	if new_rarity != item.rarity:
		item.rarity = new_rarity
		EventBus.item_rarity_changed.emit(item)

static func _under_same_brand_limit(brands: Array[Brand]) -> bool:
	var counts := {}
	for b in brands:
		counts[b.item_id] = counts.get(b.item_id, 0) + 1
		if counts[b.item_id] > MAX_SAME_BRAND:
			return false
	return true

static func _governing_utility_brand(brands: Array[Brand]) -> Brand:
	for func_id in FUNCTION_PRIORITY:
		for b in brands:
			if b.brand_function == func_id:
				return b
	return null

## tier_cap: -1 for no cap, otherwise the WORST tier the roll is allowed
## to land on (Tier 1 is best in this project's convention) - Patch v3.6's
## "same Brand x3" bonus via BrandCombinationResolver.same_brand_tier_cap().
## exclude_keys: stat_keys already on the item (or already picked earlier
## in the same batch, for _render()'s full-reroll case) - bug fix
## (2026-09-07, user-reported): this had no duplicate-avoidance at all,
## so both a single Cube add and a full Render reroll could put the same
## stat_key on an item twice (e.g. three separate "+Strength" rolls).
static func _random_affix_for(item: Item, pool: Array, power_level: int, tier_cap: int = -1, exclude_keys: Array = []) -> ItemAffix:
	var candidates: Array = pool.filter(func(entry): return not exclude_keys.has(entry["stat_key"]))
	if candidates.is_empty():
		return null
	var entry: Dictionary = candidates[randi() % candidates.size()]
	var rolled_tier: int = ItemRoller._roll_tier(power_level)
	if tier_cap != -1:
		rolled_tier = min(rolled_tier, tier_cap)
	var value_range: Vector2 = ItemRoller._tier_range(entry["tier1_min"], entry["tier1_max"], rolled_tier)
	var value: float = randf_range(value_range.x, value_range.y)
	var affix := ItemAffix.new()
	affix.stat_key = entry["stat_key"]
	affix.value = value
	affix.value_min = value_range.x
	affix.value_max = value_range.y
	affix.tier = rolled_tier
	affix.description = "%s (Tier %d)" % [ItemRoller.format_desc(entry["desc"], value), rolled_tier]
	affix.is_prefix = item.affixes.size() % 2 == 0
	return affix

static func _redescribe(affix: ItemAffix) -> void:
	for entry in ItemRoller.AFFIX_POOL:
		if entry["stat_key"] == affix.stat_key:
			affix.description = "%s (Tier %d)" % [ItemRoller.format_desc(entry["desc"], affix.value), affix.tier]
			return

## No utility/special Brand present - category Brands add ONE new affix.
## Patch v3.6: a recognized combination (BrandCombinationResolver, e.g.
## Calcine+Galvanic+Quench for an Elemental-flavored roll) draws
## from the UNION of every tag in that combination instead of picking
## just one; same Brand x3 also caps the roll at Tier 3 or better. Any
## other combination falls back to the original behavior - weighted by
## which categories are present, a Brand placed twice just doubles that
## category's odds (covers "max 2 of the same Brand" without a separate
## stacking rule).
static func _add_weighted_affix(item: Item, category_brands: Array[Brand], power_level: int) -> String:
	if item.affixes.size() >= MAX_AFFIXES:
		return "Already at the maximum of %d modifiers - nothing added." % MAX_AFFIXES
	var brand_ids: Array[String] = []
	var weighted_tags: Array[String] = []
	for b in category_brands:
		brand_ids.append(b.item_id)
		if b.category_tag != "" and not item.sealed_tags.has(b.category_tag):
			weighted_tags.append(b.category_tag)
	if weighted_tags.is_empty():
		return "Every tag those Brands direct toward is sealed on this item - nothing added."

	var tier_cap := BrandCombinationResolver.same_brand_tier_cap(brand_ids)
	var combo_tags := BrandCombinationResolver.resolve_tags(brand_ids, weighted_tags)
	var existing_keys: Array = item.affixes.map(func(a: ItemAffix): return a.stat_key)
	var affix: ItemAffix
	var combo_note := ""
	if not combo_tags.is_empty():
		var combo_pool: Array = []
		for tag in combo_tags:
			if not item.sealed_tags.has(tag):
				combo_pool.append_array(ItemRoller._pool_for_brand_tag(item, tag))
		affix = _random_affix_for(item, combo_pool, power_level, tier_cap, existing_keys)
		combo_note = " (%s combination)" % " + ".join(combo_tags)
	else:
		var tag: String = weighted_tags[randi() % weighted_tags.size()]
		var pool := ItemRoller._pool_for_brand_tag(item, tag)
		affix = _random_affix_for(item, pool, power_level, tier_cap, existing_keys)

	if affix == null:
		return "No modifier exists for that category on this item type (or every eligible one is already on it) - nothing added."
	item.affixes.append(affix)
	EventBus.item_stats_changed.emit(item)
	return "Added: %s%s" % [affix.description, combo_note]

static func _render(item: Item, power_level: int) -> String:
	if item.affixes.is_empty():
		return "This item has no modifiers to reroll."
	var pool := ItemRoller._pool_for(item)
	var new_affixes: Array[ItemAffix] = []
	var used_keys: Array = []
	for i in range(item.affixes.size()):
		var affix := _random_affix_for(item, pool, power_level, -1, used_keys)
		if affix:
			new_affixes.append(affix)
			used_keys.append(affix.stat_key)
	item.affixes = new_affixes
	return "Rerolled all %d modifier(s)." % new_affixes.size()

static func _rectify(item: Item) -> String:
	if item.affixes.is_empty():
		return "This item has no modifiers to rerandomize."
	for affix in item.affixes:
		if affix.value_max > affix.value_min:
			affix.value = randf_range(affix.value_min, affix.value_max)
			_redescribe(affix)
	return "Rerandomized %d modifier value(s) within their existing ranges." % item.affixes.size()

static func _refine(item: Item) -> String:
	if item.affixes.is_empty():
		return "This item has no modifiers to improve."
	for affix in item.affixes:
		affix.value *= 1.0 + REFINE_BOOST_PERCENT
		affix.value_min *= 1.0 + REFINE_BOOST_PERCENT
		affix.value_max *= 1.0 + REFINE_BOOST_PERCENT
		_redescribe(affix)
	return "Improved %d modifier(s) by %d%%." % [item.affixes.size(), round(REFINE_BOOST_PERCENT * 100.0)]

static func _excise(item: Item, target_affix_index: int) -> String:
	if target_affix_index < 0 or target_affix_index >= item.affixes.size():
		return "Choose a modifier to Excise."
	var removed: ItemAffix = item.affixes[target_affix_index]
	item.affixes.remove_at(target_affix_index)
	EventBus.item_stats_changed.emit(item)
	return "Removed: %s" % removed.description

static func _bore(item: Item) -> String:
	var cap: int = ItemRoller.get_socket_cap(item)
	if cap <= 0:
		return "This item type has no sockets to Bore."
	if item.max_sockets >= cap:
		return "Already at maximum sockets."
	item.max_sockets = cap
	EventBus.item_sockets_changed.emit(item)
	return "Sockets increased to %d." % cap

static func _cleave(item: Item, power_level: int, target_affix_index: int) -> Dictionary:
	if target_affix_index < 0 or target_affix_index >= item.affixes.size():
		return {"message": "Choose a modifier to lock before Cleaving.", "destroyed": false}
	item.cleave_count += 1
	if item.cleave_count >= 2 and randf() < CLEAVE_DESTROY_CHANCE:
		return {"message": "The item couldn't withstand a second Cleave - it was destroyed.", "destroyed": true}
	var locked: ItemAffix = item.affixes[target_affix_index]
	var pool := ItemRoller._pool_for(item)
	var new_affixes: Array[ItemAffix] = [locked]
	for i in range(item.affixes.size()):
		if i == target_affix_index:
			continue
		var affix := _random_affix_for(item, pool, power_level)
		if affix:
			new_affixes.append(affix)
	item.affixes = new_affixes
	return {"message": "Locked %s, rerolled the rest." % locked.description, "destroyed": false}

static func _sever(item: Item, category_brands: Array[Brand], has_binder: bool) -> String:
	if category_brands.is_empty():
		return "Sever needs a Damage Type/Defensive Type/Umbrella Brand alongside it to know which tag to seal."
	var tag: String = category_brands[0].category_tag
	if item.sealed_tags.has(tag):
		if has_binder:
			return "Binder protected the seal on \"%s\" - it held." % tag
		if randf() < SEVER_UNDO_CHANCE:
			item.sealed_tags.erase(tag)
			return "The seal on \"%s\" was undone." % tag
		return "The seal on \"%s\" held." % tag
	item.sealed_tags.append(tag)
	return "\"%s\" is now permanently sealed on this item." % tag

## ---- Infusion / Shrivening Stone ---------------------------------

## Rerolls a weapon's damage-type identity to a random type other than
## its own native one - Weapon.infused_damage_type already existed,
## unused before this (see README).
static func infuse(weapon: Weapon) -> Dictionary:
	if weapon == null:
		return {"success": false, "message": "Choose a weapon to infuse."}
	var options: Array = Constants.DamageType.values().filter(func(t): return t != weapon.native_damage_type)
	weapon.infused_damage_type = options[randi() % options.size()]
	EventBus.item_stats_changed.emit(weapon)
	return {"success": true, "message": "Infused with %s." % Constants.DAMAGE_TYPE_NAME.get(weapon.infused_damage_type, "?")}

static func shrive(weapon: Weapon) -> Dictionary:
	if weapon == null:
		return {"success": false, "message": "Choose a weapon to shrive."}
	if weapon.infused_damage_type == -1:
		return {"success": false, "message": "This weapon has no infusion to remove."}
	var native_name: String = Constants.DAMAGE_TYPE_NAME.get(weapon.native_damage_type, "?")
	weapon.infused_damage_type = -1
	EventBus.item_stats_changed.emit(weapon)
	return {"success": true, "message": "The infusion is stripped away - back to native %s." % native_name}

## ---- Shard of Tharsis (Corruption) --------------------------------

## Patch v3.6: the real outcome logic now lives in CorruptionSystem.gd/
## CorruptionOutcome.gd (a 4-tier x named-outcome model, replacing the
## flat 8-outcome weighted list this used to roll directly) - this stays
## a thin wrapper so CraftingScreen.gd's Dictionary-based call site
## (result["success"]/["message"]) needs no changes.
static func corrupt(item: Item, power_level: int = 1) -> Dictionary:
	var outcome := CorruptionSystem.corrupt(item, power_level)
	if not outcome.success:
		return {"success": false, "message": outcome.reason, "destroyed": false}
	var message := "%s (Tier %d)" % [outcome.outcome_name, outcome.tier]
	if not item.is_craftable:
		message += " This item can no longer be crafted or corrupted."
	EventBus.item_stats_changed.emit(item)
	return {"success": true, "message": message, "destroyed": false}
