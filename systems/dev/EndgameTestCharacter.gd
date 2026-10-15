extends RefCounted
class_name EndgameTestCharacter
## A level 90 character for testing the endgame without levelling there
## (main menu: New Game > Level 90 Test Character). Fills GameState after a
## reset: the levelling stage done, good item level 90 gear on, four spells
## at level 20, currency, Slates, a set of Maw Fragments and a Figment at
## each band's start and end. No Tier is marked cleared, so the Figment Tree
## and band progress start from zero.

const LEVEL := 90
const GEAR_ITEM_LEVEL := 90
## Item Rarity for the gear rolls: mostly Rares.
const GEAR_RARITY := 6.0
const SPELLS := ["thunder_javelin", "flame_jets", "stormcall", "frost_armor"]
const SPELL_LEVEL := 20
const FIGMENT_TIERS := [1, 7, 8, 14, 15, 21]
const GOLD := 50000
const ORBS_EACH := 20
const AETHER := 200
const SLATES := 8
const ARMOUR_SLOTS := [Constants.EquipmentSlot.HELMET, Constants.EquipmentSlot.BODY_ARMOUR, Constants.EquipmentSlot.GLOVES,
	Constants.EquipmentSlot.BOOTS, Constants.EquipmentSlot.AMULET, Constants.EquipmentSlot.BELT]

static func build(player_name: String = "Endgame Test") -> void:
	GameState.reset_to_defaults()
	SaveManager.load_shared_stash()
	GameState.player_name = player_name
	GameState.game_mode = GameState.GameMode.FRAGMENTED_REALITY
	GameState.player_level = LEVEL
	GameState.player_xp = 0.0
	GameState.depth_cleared = AreaLevel.DEPTHS
	GameState.gold = GOLD
	_equip_gear()
	_learn_spells()
	_stock_currency()
	for i in SLATES:
		var slate := SlateRoller.roll(GEAR_ITEM_LEVEL, GEAR_RARITY)
		if slate:
			GameState.add_to_inventory(slate)
	for id in Pinnacle.FRAGMENT_IDS:
		GameState.add_to_inventory(id)
	var figment_tab := GameState.stash.get_tab(GridInventory.Accepts.FIGMENT)
	for tier in FIGMENT_TIERS:
		var figment := FigmentRoller.roll(tier)
		if figment_tab == null or figment_tab.add(figment) != 0:
			GameState.add_to_inventory(figment)

static func _equip_gear() -> void:
	var refs: Array = []
	for slot in ARMOUR_SLOTS:
		var item := _roll(func(i: Item): return i.equip_slot == slot and not i is Weapon)
		if item:
			refs.append(ItemSerializer.to_dict(item))
	for ring in 2:
		var r := _roll(func(i: Item): return i.equip_slot == Constants.EquipmentSlot.RING)
		if r:
			refs.append(ItemSerializer.to_dict(r))
	GameState.equipment_refs = refs
	var melee := _roll(func(i: Item): return i is Weapon and not (i as Weapon).is_ranged and not (i as Weapon).is_conduit)
	var conduit := _roll(func(i: Item): return i is Weapon and (i as Weapon).is_conduit)
	GameState.weapon_set_refs = [[ItemSerializer.to_dict(melee)] if melee else [], [ItemSerializer.to_dict(conduit)] if conduit else []]
	GameState.active_weapon_set = 0

## A Rare (or better) of item level 90 matching `accept`.
static func _roll(accept: Callable) -> Item:
	var fallback: Item = null
	for i in 1500:
		var item := ItemRoller.roll(GEAR_ITEM_LEVEL, GEAR_RARITY)
		if item == null or not accept.call(item):
			continue
		if item.rarity >= Constants.ItemRarity.RARE:
			return item
		if fallback == null:
			fallback = item
	return fallback

static func _learn_spells() -> void:
	var paths: Array[String] = []
	for id in SPELLS:
		var path := "res://data/abilities/instances/%s.tres" % id
		if ResourceLoader.exists(path):
			paths.append(path)
			GameState.ability_levels[id] = SPELL_LEVEL
			if not GameState.owned_ability_ids.has(id):
				GameState.owned_ability_ids.append(id)
	while paths.size() < 4:
		paths.append("")
	GameState.ability_loadout_paths = paths

static func _stock_currency() -> void:
	var tab := GameState.stash.get_tab(GridInventory.Accepts.CURRENCY)
	var stock := {Ability.AETHER_CURRENCY: AETHER}
	for id in Constants.ORB_IDS:
		stock[id] = ORBS_EACH
	for id in Constants.CRAFTING_CONSUMABLE_IDS:
		stock[StringName(id)] = ORBS_EACH
	for id in stock:
		var left: int = tab.add(id, stock[id]) if tab else stock[id]
		if left > 0:
			GameState.add_to_inventory(id, left)
