extends Node
## Headless checks for Phase 3 portals: leave a map with enemies killed and
## loot on the ground, come back through the portal, and compare. Also the
## Hub return portal and the Hub stash.
## Run: Godot --headless --path . res://tests/portal/test_portal.tscn
## Exits 0 when every check passes. Never writes the save file.

const MAP := "res://levels/generated_map/GeneratedMap.tscn"
const HUB := "res://levels/hub/Hub.tscn"
const LOOT_PICKUP := "res://entities/pickups/loot_pickup/LootPickup.tscn"
const GOLD_PICKUP := "res://entities/pickups/gold_pickup/GoldPickup.tscn"
const ROUNDS := 3

var _checks := 0
var _failures := 0
var _finished := 0
var _opened := 0
var _returned := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false  # keeps SaveManager.save_game() a no-op
	EventBus.portal_opened.connect(func(_p): _opened += 1)
	EventBus.portal_returned.connect(func(): _returned += 1)
	for round_index in ROUNDS:
		await _test_round_trip(round_index)
	await _test_fresh_entry_and_death()
	await _test_hub()
	_check(_finished == ROUNDS + 2, "every test function ran to the end (%d/%d)" % [_finished, ROUNDS + 2])
	print("portal tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

## spawn_index -> {key, pos} for every enemy in the map, read right after
## spawning (before anything has moved).
func _snapshot_enemies(map: GeneratedMap) -> Dictionary:
	var result := {}
	for child in map.get_children():
		if child is Enemy and not child.is_queued_for_deletion():
			var rarity := child.get_node_or_null("EnemyRarityComponent") as EnemyRarityComponent
			var affixes := []
			if rarity:
				for a in rarity.affixes:
					affixes.append(a.affix_id)
			var key := "%s|%s|%s|%s" % [child.scene_file_path, child.definition.display_name if child.definition else "", rarity.rarity if rarity else -1, ",".join(affixes)]
			result[int(child.get_meta(&"spawn_index"))] = {"key": key, "pos": child.global_position}
	return result

func _loot_keys(map: GeneratedMap) -> Array:
	var keys := []
	for child in map.get_children():
		if child.is_queued_for_deletion():
			continue
		var pos := ""
		if child is LootPickup or child is GoldPickup:
			pos = "%.2f,%.2f,%.2f" % [child.position.x, child._base_y, child.position.z]
		if child is LootPickup and child.currency_id != &"":
			keys.append("%s x%d|%s" % [child.currency_id, child.currency_count, pos])
		elif child is LootPickup:
			keys.append("%s|%s" % [child.slate.display_name if child.slate else child.item.display_name, pos])
		elif child is GoldPickup:
			keys.append("gold %d|%s" % [child.amount, pos])
	keys.sort()
	return keys

func _test_round_trip(round_index: int) -> void:
	GameState.active_map = FigmentRoller.roll(2)
	var tier := GameState.active_map.tier
	var map: GeneratedMap = load(MAP).instantiate()
	add_child(map)
	var spawned := _snapshot_enemies(map)
	var rooms := map.graph.rooms.keys()
	var original_seed := map.map_seed
	await _frames(5)
	_check(spawned.size() >= 2, "round %d: map spawned enemies" % round_index)

	var killed: Array[int] = []
	for index in spawned.keys().slice(0, 2):
		for child in map.get_children():
			if child is Enemy and int(child.get_meta(&"spawn_index")) == index:
				child.health.apply_damage(1.0e9)
				killed.append(index)
	await _frames(3)

	var sword := Weapon.new()
	sword.weapon_type = "Greatsword"
	sword.display_name = "Portal Test Sword %d" % round_index
	var pickup: LootPickup = load(LOOT_PICKUP).instantiate()
	pickup.item = sword
	pickup.position = Vector3(3, 0.5, 2)
	map.add_child(pickup)
	var slate_pickup: LootPickup = load(LOOT_PICKUP).instantiate()
	slate_pickup.slate = Slate.new()
	slate_pickup.slate.display_name = "Portal Test Slate"
	slate_pickup.position = Vector3(-2, 0.5, 1)
	map.add_child(slate_pickup)
	var orbs: LootPickup = load(LOOT_PICKUP).instantiate()
	orbs.currency_id = &"forging"
	orbs.currency_count = 3
	orbs.position = Vector3(2, 0.5, -1)
	map.add_child(orbs)
	var gold: GoldPickup = load(GOLD_PICKUP).instantiate()
	gold.amount = 37
	gold.position = Vector3(1, 0.1, -2)
	map.add_child(gold)
	await _frames(2)
	var loot_before := _loot_keys(map)

	_opened = 0
	var before_count := GameState.portals_opened
	for i in 5:
		_check(map.open_portal(), "round %d: portal %d opens (unlimited)" % [round_index, i])
	await _frames(1)
	var portals := map.get_children().filter(func(c): return c is Portal and not c.is_queued_for_deletion())
	_check(portals.size() == 1 and portals[0].destination == Portal.Destination.HUB, "round %d: one portal to the hub" % round_index)
	_check(_opened == 5 and GameState.portals_opened == before_count + 5, "round %d: portal_opened emitted per portal" % round_index)
	var portal_pos: Vector3 = portals[0].global_position

	var state: Dictionary = JSON.parse_string(JSON.stringify(map.capture_state()))
	_check(state["dead"].size() == killed.size(), "round %d: defeated enemies recorded" % round_index)
	map.queue_free()
	await _frames(2)

	GameState.portal_map_state = state
	GameState.returning_through_portal = true
	GameState.active_map = null
	_returned = 0
	var back: GeneratedMap = load(MAP).instantiate()
	add_child(back)
	var restored := _snapshot_enemies(back)
	_check(back.map_seed == original_seed and back.graph.rooms.keys() == rooms, "round %d: same layout" % round_index)
	var expected_alive := spawned.keys().filter(func(i): return not killed.has(i))
	expected_alive.sort()
	var alive := restored.keys()
	alive.sort()
	_check(alive == expected_alive, "round %d: defeated enemies stay defeated (%d alive, expected %d)" % [round_index, alive.size(), expected_alive.size()])
	var same := true
	for i in expected_alive:
		if not restored.has(i) or restored[i]["key"] != spawned[i]["key"] or restored[i]["pos"].distance_to(spawned[i]["pos"]) > 0.01:
			same = false
	_check(same, "round %d: surviving enemies are the same units in the same spots" % round_index)
	_check(back._living_enemies.size() == expected_alive.size(), "round %d: enemy counter matches" % round_index)
	await _frames(2)
	_check(_loot_keys(back) == loot_before, "round %d: loot on the ground restored (%d items)" % [round_index, loot_before.size()])
	var back_portals := back.get_children().filter(func(c): return c is Portal)
	_check(back_portals.size() == 1 and back_portals[0].global_position.distance_to(portal_pos) < 0.01, "round %d: portal back to the hub where it was" % round_index)
	var player := get_tree().get_first_node_in_group("player") as Player
	_check(player != null and player.global_position.distance_to(GeneratedMap._array_to_vec(state["player"])) < 0.5, "round %d: player returns where they opened the portal" % round_index)
	_check(_returned == 1, "round %d: portal_returned emitted" % round_index)
	_check(GameState.active_map != null and GameState.active_map.tier == tier, "round %d: figment restored" % round_index)
	_check(not GameState.returning_through_portal, "round %d: return flag consumed" % round_index)
	back.queue_free()
	await _frames(2)
	_finished += 1

func _test_fresh_entry_and_death() -> void:
	GameState.portal_map_state = {"seed": 5}
	GameState.returning_through_portal = false
	var map: GeneratedMap = load(MAP).instantiate()
	add_child(map)
	_check(GameState.portal_map_state.is_empty() and GameState.portals_opened == 0, "entering a new map discards the old run")
	map.queue_free()
	await _frames(2)
	GameState.portal_map_state = {"seed": 5}
	EventBus.player_died.emit()
	_check(GameState.portal_map_state.is_empty(), "dying ends the open run")
	await _frames(1)
	_finished += 1

func _test_hub() -> void:
	GameState.portal_map_state = {}
	var hub: Node = load(HUB).instantiate()
	add_child(hub)
	await _frames(2)
	var spot: Node3D = hub.get_node("HubPortalSpot")
	_check(spot.get_children().is_empty(), "no return portal without an open run")
	hub.queue_free()
	await _frames(2)

	GameState.portal_map_state = {"seed": 5}
	hub = load(HUB).instantiate()
	add_child(hub)
	await _frames(2)
	spot = hub.get_node("HubPortalSpot")
	var portal := spot.get_child(0) as Portal if spot.get_child_count() > 0 else null
	_check(portal != null and portal.destination == Portal.Destination.MAP, "return portal appears in the hub")

	var chest: StashChest = hub.get_node("StashChest")
	var screen: StashScreen = chest._get_stash_screen()
	_check(screen != null, "stash chest finds the stash screen")
	screen.open()
	_check(screen.is_open() and not get_tree().paused, "stash opens without pausing")
	GameState.inventory.add(&"grafting", 3)
	var sword := Weapon.new()
	sword.weapon_type = "Rapier"
	GameState.inventory.add(sword)
	for entry in GameState.inventory.get_entries():
		var target: GridInventory = GameState.stash.get_tab(GridInventory.Accepts.CURRENCY) if entry.is_currency() else GameState.stash.tabs[0]
		StashScreen.send(GameState.inventory, entry, target)
	_check(GameState.inventory.get_entries().is_empty(), "items sent to the stash leave the inventory")
	_check(GameState.stash.tabs[0].has_content(sword) and GameState.stash.get_tab(GridInventory.Accepts.CURRENCY).count_of(&"grafting") == 3, "items land in the right stash tabs")
	var entry: GridInventory.Entry = GameState.stash.tabs[0].get_entries()[0]
	screen._active_tab = 0
	screen._on_entry_right_clicked(screen._stash_view, entry)
	_check(GameState.inventory.has_content(sword) and not GameState.stash.tabs[0].has_content(sword), "right-click brings an item back")
	screen.close()
	hub.queue_free()
	await _frames(2)
	GameState.portal_map_state = {}
	_finished += 1
