extends RefCounted
class_name SlateRecombinator
## The Recombinator's two Slate operations.
## Split: one Slate with 2+ crafted modifiers becomes two copies of its base,
## the modifiers dealt between them (each gets at least one). Both are marked
## split and can't be split again.
## Recombine: two Slates of the same base become one, keeping a random share
## of their combined modifiers within the Rare limits. Both are consumed.

const SPLIT_COST := 150
const RECOMBINE_COST := 100
## Chance each candidate modifier survives a Recombine (at least one always does).
const KEEP_CHANCE := 0.65

static func split_error(slate: Slate) -> String:
	if slate.is_corrupted:
		return "Corrupted Slates can't be split."
	if slate.is_split:
		return "This Slate has already been split."
	if slate.explicits.size() < 2:
		return "Needs at least two crafted modifiers."
	if not slate.lenses.is_empty():
		return "Take its Lenses out first."
	return ""

static func recombine_error(a: Slate, b: Slate) -> String:
	if a == b or a.slate_id != b.slate_id:
		return "Needs two Slates of the same kind."
	if a.is_corrupted or b.is_corrupted:
		return "Corrupted Slates can't be recombined."
	if not a.lenses.is_empty() or not b.lenses.is_empty():
		return "Take their Lenses out first."
	return ""

## The two halves of `slate`. The original is left untouched.
static func split(slate: Slate, rng: RandomNumberGenerator = null) -> Array[Slate]:
	rng = _rng(rng)
	var mods := slate.explicits.duplicate()
	_shuffle(mods, rng)
	var cut := rng.randi_range(1, mods.size() - 1)
	var halves: Array[Slate] = []
	for part in [mods.slice(0, cut), mods.slice(cut)]:
		var half := slate.duplicate(true) as Slate
		half.explicits = _copy(part)
		half.is_split = true
		_fit_rarity(half)
		halves.append(half)
	return halves

## The Slate made from `a` and `b`. The originals are left untouched.
static func recombine(a: Slate, b: Slate, rng: RandomNumberGenerator = null) -> Slate:
	rng = _rng(rng)
	var result := (a if rng.randf() < 0.5 else b).duplicate(true) as Slate
	result.sockets = maxi(a.sockets, b.sockets)
	result.is_split = a.is_split or b.is_split
	# One line per modifier: a modifier both Slates have keeps its better roll.
	var by_key := {}
	for affix: ItemAffix in a.explicits + b.explicits:
		var k := affix.key()
		if not by_key.has(k) or affix.value > (by_key[k] as ItemAffix).value:
			by_key[k] = affix
	var pool: Array = by_key.values()
	_shuffle(pool, rng)
	var limits: Vector2i = Constants.AFFIX_LIMITS_SLATE[Constants.ItemRarity.RARE]
	var kept: Array[ItemAffix] = []
	var prefixes := 0
	var suffixes := 0
	for affix: ItemAffix in pool:
		var room: bool = prefixes < limits.x if affix.is_prefix else suffixes < limits.y
		if not room or (not kept.is_empty() and rng.randf() > KEEP_CHANCE):
			continue
		kept.append(affix.duplicate())
		if affix.is_prefix:
			prefixes += 1
		else:
			suffixes += 1
	result.explicits = kept
	_fit_rarity(result)
	return result

## Lowest rarity whose modifier limits hold the Slate's explicits.
static func _fit_rarity(slate: Slate) -> void:
	var prefixes := slate.explicits.filter(func(x: ItemAffix) -> bool: return x.is_prefix).size()
	var suffixes := slate.explicits.size() - prefixes
	if slate.rarity == Constants.SlateRarity.VERY_RARE or slate.rarity == Constants.SlateRarity.UNIQUE:
		return
	var target := CraftTarget.wrap(slate)
	for rarity in [Constants.ItemRarity.COMMON, Constants.ItemRarity.UNCOMMON, Constants.ItemRarity.RARE]:
		var limits: Vector2i = Constants.AFFIX_LIMITS_SLATE[rarity]
		if prefixes <= limits.x and suffixes <= limits.y:
			target.set_rarity(rarity)
			return

static func _copy(mods: Array) -> Array[ItemAffix]:
	var result: Array[ItemAffix] = []
	for m in mods:
		result.append((m as ItemAffix).duplicate())
	return result

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = swap

static func _rng(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng
