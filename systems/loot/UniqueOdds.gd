extends RefCounted
class_name UniqueOdds
## Drop odds for each UniqueCatalog entry, for the Compendium. Mirrors the
## real rolls: a kill's drop rolls (Loot.RANK_DROP_ROLLS x Item Quantity),
## the share of rolls that become gear (Enemy._roll_drop()'s category
## chances, taken in order), the gear's rarity (Loot.rarity_weights() with
## Item Rarity), then the weighted pick among that rarity's world drops
## (UniqueRoller). A Pinnacle boss's exclusive uniques use their own boss_chance.

## Where a unique comes from, for display.
static func source_text(def: Dictionary) -> String:
	if def.get("corrupted_only", false):
		return "Shard of Tharsis (Transcendent corruption)"
	if def.has("boss"):
		return "Pinnacle: %s" % Pinnacle.BOSSES.get(def["boss"], {}).get("name", def["boss"])
	return "World Drop"

static func is_world_drop(def: Dictionary) -> bool:
	return not def.get("corrupted_only", false) and not def.has("boss")

## Chance one drop roll becomes a gear item: every category before gear
## has to miss first.
static func gear_share_per_roll() -> float:
	var miss := 1.0
	for chance in [Enemy.TOME_DROP_CHANCE, Enemy.CURRENCY_DROP_CHANCE, Enemy.CRAFTING_CONSUMABLE_DROP_CHANCE,
			Enemy.SLATE_DROP_CHANCE, Enemy.FIGMENT_DROP_CHANCE, Enemy.JEWEL_DROP_CHANCE, Enemy.AMMO_DROP_CHANCE]:
		miss *= 1.0 - chance
	return miss * Enemy.BASE_LOOT_DROP_CHANCE

## Chance a gear drop rolls `rarity` at this Item Rarity multiplier.
static func rarity_chance(rarity: int, rarity_mult: float) -> float:
	var weights := Loot.rarity_weights(rarity_mult)
	var total := 0.0
	for w in weights.values():
		total += w
	return weights.get(rarity, 0.0) / total if total > 0.0 else 0.0

## Share of `def` among `pool` by weight.
static func _share(def: Dictionary, pool: Array) -> float:
	var total := 0.0
	for d in pool:
		total += float(d["weight"])
	return float(def["weight"]) / total if pool.has(def) and total > 0.0 else 0.0

## Chance one gear drop is this unique (0 if it isn't a world drop).
static func per_gear_drop(def: Dictionary, rarity_mult: float) -> float:
	if not is_world_drop(def):
		return 0.0
	return rarity_chance(def["rarity"], rarity_mult) * _share(def, UniqueRoller.droppable(def["rarity"]))

## Chance a kill of `rank` drops it at least once.
static func per_kill(def: Dictionary, rank: int, quantity_mult: float, rarity_mult: float) -> float:
	var rolls := Loot.base_drop_rolls(rank) * quantity_mult
	return 1.0 - pow(1.0 - gear_share_per_roll() * per_gear_drop(def, rarity_mult), rolls)

## Chance one kill of Pinnacle boss boss_id drops this boss-exclusive unique
## (its boss_chance). World uniques use per_kill() at Boss rank instead.
static func per_pinnacle_reward(def: Dictionary, boss_id: String) -> float:
	if def.get("corrupted_only", false) or def.get("boss", "") != boss_id:
		return 0.0
	return float(def.get("boss_chance", 0.0))

## "0.42% (1 in 238)", or "—" for zero.
static func format_chance(p: float) -> String:
	if p <= 0.0:
		return "—"
	var percent := p * 100.0
	var pct := "%.4f%%" % percent
	if percent >= 10.0:
		pct = "%.0f%%" % percent
	elif percent >= 1.0:
		pct = "%.1f%%" % percent
	elif percent >= 0.01:
		pct = "%.2f%%" % percent
	return "%s (1 in %s)" % [pct, _thousands(roundi(1.0 / p))]

static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out

## The character's Item Quantity / Item Rarity / Magic Find from gear: the
## live Player's when there is one, else the saved equipment (main menu).
static func character_bonuses() -> Dictionary:
	# The live Player's equipment, unless that Player is gone (back on the menu).
	var live: Variant = GameState.player_equipment
	var equipment := live as EquipmentComponent if is_instance_valid(live) else null
	if equipment and equipment.is_inside_tree():
		return equipment.compute_misc_bonuses()
	var refs: Array = GameState.equipment_refs.duplicate()
	if GameState.active_weapon_set < GameState.weapon_set_refs.size():
		refs.append_array(GameState.weapon_set_refs[GameState.active_weapon_set])
	var totals := {}
	for ref in refs:
		var item: Item = null
		if ref is String and ref != "":
			item = load(ref) as Item
		elif ref is Dictionary:
			item = ItemSerializer.from_dict(ref)
		if item == null:
			continue
		for affix in item.get_effective_affixes():
			if [Loot.QUANTITY_KEY, Loot.RARITY_KEY, Loot.MAGIC_FIND_KEY].has(affix.stat_key):
				totals[affix.stat_key] = totals.get(affix.stat_key, 0.0) + affix.value
	return totals
