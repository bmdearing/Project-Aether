extends Node
## Screenshots real UI states in the Hub for visual review.
## Run windowed: Godot --path . res://tests/ui_capture/capture_ui.tscn --resolution 1920x1080 -- <out.png> <mode>
## Modes: hud, inventory, inventory_icons, icons, character, abilities, fateboard, map, pause, shop, stash, card, sockets, uniques, death, craft_preview

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://ui.png"
	var mode: String = args[1] if args.size() > 1 else "hud"
	GameState.reset_to_defaults()
	GameState.gold = 12480
	var hub: Node = load("res://levels/hub/Hub.tscn").instantiate()
	get_tree().root.add_child(hub)
	await get_tree().create_timer(1.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Player
	_dress_player(player)
	await get_tree().create_timer(0.5).timeout
	match mode:
		"inventory":
			_screen("inventory_screen").open(true)
		"character":
			_screen("character_screen").open()
		"abilities":
			_screen("abilities_screen").open()
		"fateboard":
			for slate_id in ["ember_lattice", "frostfire_nexus"]:
				GameState.add_to_inventory(load("res://data/slates/instances/%s.tres" % slate_id).duplicate(true))
			if OS.get_cmdline_user_args().has("outlines"):
				FateBoardGrid.show_outlines = true
				var board: FateBoard = GameState.fate_board
				board.aether_capacity = 99
				for slate in GameState.get_inventory_items().filter(func(c): return c is Slate):
					for dx in range(-6, 7):
						if board.place_slate(slate, FateBoard.ANCHOR_CELL + Vector2i(dx, 1), 0, false, "", true) != "":
							GameState.remove_from_inventory(slate)
							break
			_screen("fate_board_editor").open()
		"map":
			_screen("map_screen").open()
		"pause":
			_find_pause(hub).open()
		"card":
			_show_card(player)
		"sockets":
			_show_sockets()
		"uniques":
			_show_uniques()
		"death":
			EventBus.player_died.emit()
		"icons":
			_show_icon_sheet()
		"stash", "stash_currency":
			_fill_stash(mode == "stash_currency")
		"spell_assign":
			var spells := _screen("abilities_screen") as AbilitiesScreen
			spells.open()
			await get_tree().process_frame
			spells._open_assign(spells._owned_abilities[0])
			spells._assign_panel.position = Vector2(700, 300)
		"spell_web":
			var spells := _screen("abilities_screen") as AbilitiesScreen
			spells.open()
			await get_tree().process_frame
			spells._open_web(spells._owned_abilities[0])
		"compare":
			_show_compare(player)
		"craft_preview":
			_show_craft_preview()
		"inventory_icons":
			_fill_icon_inventory()
			_screen("inventory_screen").open(false)
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()

func _fill_stash(currency: bool) -> void:
	var stash := GameState.stash
	for id in [&"quickening", &"grafting", &"tempering", &"brand_fire", &"edict_spell", &"maw_fragment_ash", &"crystallized_aether"]:
		stash.get_tab(GridInventory.Accepts.CURRENCY).add(id, randi_range(3, 4200))
	stash.get_tab(GridInventory.Accepts.CURRENCY).add(&"severance", 51000)
	for k in 10:
		stash.tabs[0].add(ItemRoller.roll(30, 3.0))
	var screen := _screen("stash_screen") as StashScreen
	screen.open()
	if currency:
		screen._select_tab(stash.tabs.find(stash.get_tab(GridInventory.Accepts.CURRENCY)))
	else:
		screen._search.text = "life"
		screen._apply_search()

## An inventory item's hover card beside the worn one.
func _show_compare(player: Player) -> void:
	var helmet: Item = null
	var worn: Item = null
	for i in 600:
		var item := ItemRoller.roll(40, 3.0)
		if item and item.equip_slot == Constants.EquipmentSlot.HELMET:
			if worn == null:
				worn = item
			elif helmet == null:
				helmet = item
				break
	player.equipment.equip(worn, true)
	var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
	card.compare_against = ItemCompare.equipped_for(helmet)
	card.display_item(helmet)
	var shown := ItemCompare.wrap(card, helmet)
	var layer := CanvasLayer.new()
	layer.layer = 100
	get_tree().root.add_child(layer)
	layer.add_child(shown)
	shown.position = Vector2(400, 120)

## Rare gear and a Lens as their cards show them with an Orb picked up:
## Severance under a Resistance Brand, Recasting under a Fire Brand.
func _show_craft_preview() -> void:
	var resolver := CraftingResolver.create_default()
	var bag := CurrencyBag.new()
	for id in [&"brand_resistance", &"brand_fire"]:
		bag.add_currency(id, 3)
	var rare: Item = null
	for i in 400:
		var item := ItemRoller.roll(70, 30.0)
		if item and not item is Weapon and item.rarity == Constants.ItemRarity.RARE and resolver.preview(item, &"severance", _active(bag, &"brand_resistance")).is_valid():
			rare = item
			break
	var lens := LensRoller.roll(80, 50.0)
	lens.rarity = Constants.ItemRarity.COMMON
	CraftTarget.wrap(lens).set_explicits([])
	resolver.apply(lens, &"forging")
	var layer := CanvasLayer.new()
	layer.layer = 100
	get_tree().root.add_child(layer)
	var x := 60.0
	for pair in [[rare, &"severance", &"brand_resistance"], [lens, &"recasting", &"brand_fire"], [lens, &"anchoring", &""]]:
		var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
		var orb: StringName = pair[1]
		var brand: StringName = pair[2]
		card.craft_preview_for = func(target: Resource) -> CraftPreview: return resolver.preview(target, orb, _active(bag, brand) if brand != &"" else null)
		layer.add_child(card)
		card.display_item(pair[0])
		card.position = Vector2(x, 80)
		x += 400.0

func _active(bag: CurrencyBag, id: StringName) -> ActiveBrands:
	var active := ActiveBrands.new(bag)
	active.activate(id)
	return active

func _screen(group: String) -> Node:
	return get_tree().get_first_node_in_group(group)

func _find_pause(root: Node) -> Node:
	return root.find_children("*", "PauseMenu", true, false)[0]

## Spells on the bar, a running cooldown, some damage and Ward, gear and loot.
func _dress_player(player: Player) -> void:
	var ids := ["cinder_lance", "ice_pulse", "stormcall", "black_hole"]
	for i in ids.size():
		var a := load("res://data/abilities/instances/%s.tres" % ids[i]) as Ability
		GameState.owned_ability_ids.append(a.ability_id)
		player.ability_loadout.equip(a, i)
	player.ability_cast._cooldowns[player.ability_loadout.get_equipped(2)] = 0.0
	var blink := load("res://data/abilities/instances/blink.tres") as Ability
	player.ability_cast._cooldowns[blink] = 2.0
	var greatsword := load("res://data/weapons/instances/crude_greatsword.tres") as Weapon
	if greatsword:
		player.equipment.equip(greatsword.duplicate(true))
	player.health.apply_damage(player.health.max_health * 0.25)
	player.ward.set_max_ward(60.0)
	player.ward.current_ward = 38.0
	player.ward.ward_changed.emit(player.ward.current_ward, player.ward.max_ward)
	player.mana.spend(player.mana.max_mana * 0.4)
	player.experience.add_xp(60.0)
	for k in 6:
		GameState.add_to_inventory(ItemRoller.roll(10, 3.0))
	GameState.inventory.add(&"quickening", 7)
	GameState.inventory.add(&"brand_fire", 2)
	GameState.inventory.add(&"elevation", 3)

func _show_card(player: Player) -> void:
	var item := ItemRoller.roll(30, 4.0)
	for k in 10:
		if item is Weapon and item.affixes.size() >= 3:
			break
		item = ItemRoller.roll(30, 4.0)
	var layer := CanvasLayer.new()
	layer.layer = 100
	get_tree().root.add_child(layer)
	var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
	card.display_item(item)
	layer.add_child(card)
	card.position = Vector2(1300, 140)
	var card2: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
	card2.display_ability(player.ability_loadout.get_equipped(0), player.stat_sheet)
	layer.add_child(card2)
	card2.position = Vector2(860, 140)

## Inventory with sockets always shown, jewels in the grid, and a socketed
## item's card in its normal and Alt forms.
func _show_sockets() -> void:
	GameState.always_show_sockets = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var socketed: Item = null
	for k in 4:
		var item := ItemRoller.roll(20, 3.0)
		item.max_sockets = maxi(ItemRoller.get_socket_cap(item), 2)
		item.sockets = item.max_sockets
		for j in mini(k + 1, item.sockets):
			item.socketed.append(JewelRoller.roll(20, 3.0, rng))
		GameState.add_to_inventory(item)
		socketed = item
	for k in 5:
		GameState.add_to_inventory(JewelRoller.roll(20, 1.5 + k * 0.3, rng))
	_screen("inventory_screen").open(false)
	var layer := CanvasLayer.new()
	layer.layer = 100
	get_tree().root.add_child(layer)
	for alt in [false, true]:
		var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
		layer.add_child(card)
		card.display_item(socketed)
		if alt:
			card._showing_alt = true
			card._render_alt_info()
		card.position = Vector2(40 + (380 if alt else 0), 120)

## Three unique cards and the Mythic, side by side.
func _show_uniques() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	get_tree().root.add_child(layer)
	var ids := ["the_pale_eye", "grevanes_accounting", "unmaking_of_solen_vrath", "hollowed_kings_mantle"]
	for i in ids.size():
		var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
		layer.add_child(card)
		card.display_item(UniqueRoller.build(UniqueCatalog.get_def(ids[i]), 80))
		card.position = Vector2(40 + i * 470, 60)

## Every IconArt key at its footprint: gear types, currency, Slates, Figments,
## then every spell at 80px.
func _show_icon_sheet() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	get_tree().root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var flow := HFlowContainer.new()
	flow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flow.offset_left = 8
	flow.offset_top = 8
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	layer.add_child(flow)
	var contents: Array = []
	for key in FootprintTable.get_instance().footprints.keys():
		contents.append(StringName(key))
	for key in ["helmet", "gloves", "boots", "shield", "gauntlet", "bow"]:
		contents.append(StringName(key))
	for key in CurrencyText.get_instance().names.keys():
		contents.append(StringName(key))
	for path in DirAccess.get_files_at("res://data/slates/instances"):
		if path.ends_with(".tres"):
			contents.append(load("res://data/slates/instances/" + path))
	for tier in [1, 4, 7, 10]:
		contents.append(FigmentRoller.roll(tier))
	for k in 3:
		contents.append(JewelRoller.roll(20, 1.0 + k * 2.0))
	for path in DirAccess.get_files_at("res://data/abilities/instances"):
		if path.ends_with(".tres"):
			contents.append(load("res://data/abilities/instances/" + path))
	var tome: SkillTome = load("res://data/abilities/skill_tome.gd").new()
	tome.ability_path = "res://data/abilities/instances/meteor.tres"
	contents.append(tome)
	for content in contents:
		var fp := GridInventory.footprint_of(content)
		if content is StringName:
			fp = FootprintTable.footprint_for_type(content)
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(fp) * (80.0 if content is Ability else 40.0)
		var icon := ItemIcon.fill(cell)
		icon.content = content
		icon.count = 7 if content is StringName and fp == Vector2i.ONE else 0
		flow.add_child(cell)

## Inventory holding one of everything the icon pass covers.
func _fill_icon_inventory() -> void:
	for id in [&"absolution", &"anchoring", &"ascendant", &"elevation", &"forging", &"grafting", &"opening", &"quickening", &"recasting", &"reckoning", &"severance", &"tempering", &"brand_cold", &"brand_lightning", &"brand_armor", &"brand_prefix", &"edict_spell", &"edict_suffix", &"infusion_stone", &"shrivening_stone", &"shard_of_tharsis", &"crystallized_aether"]:
		GameState.inventory.add(id, randi_range(1, 40))
	for id in Pinnacle.FRAGMENT_IDS:
		GameState.inventory.add(id, 1)
	for tier in [2, 5, 9]:
		GameState.add_to_inventory(FigmentRoller.roll(tier))
	for path in ["aetheric_conduit", "ember_lattice", "frostfire_nexus", "stormtouched_array"]:
		GameState.add_to_inventory(load("res://data/slates/instances/%s.tres" % path).duplicate(true))
	GameState.add_to_inventory(JewelRoller.roll(20, 3.0))
