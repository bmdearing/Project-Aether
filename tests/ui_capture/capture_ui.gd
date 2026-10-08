extends Node
## Screenshots real UI states in the Hub for visual review.
## Run windowed: Godot --path . res://tests/ui_capture/capture_ui.tscn --resolution 1920x1080 -- <out.png> <mode>
## Modes: hud, inventory, character, abilities, fateboard, map, pause, shop, stash, card, sockets, uniques, death

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
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()

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
