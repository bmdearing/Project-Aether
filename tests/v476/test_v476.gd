extends Node
## Headless checks for v4.76: three save slots (save, summary, select,
## delete, isolation between slots) and the Level 90 Test Character (its
## state, its gear and spells on the live player, and a save round trip).
## Uses a test-only slot prefix, so real saves are never touched.
## Run: Godot --headless --path . res://tests/v476/test_v476.tscn --quit-after 6000

const TEST_PREFIX := "user://test_v476_slot"

var _checks := 0
var _failures := 0
var _finished := 0
const TEST_COUNT := 2
var _real_prefix: String
var _real_slot: int

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _run() -> void:
	_real_prefix = SaveManager.slot_prefix
	_real_slot = SaveManager.slot
	SaveManager.slot_prefix = TEST_PREFIX
	for n in range(1, SaveManager.SLOT_COUNT + 1):
		SaveManager.delete_save(n)
	_test_slots()
	await _test_character()
	for n in range(1, SaveManager.SLOT_COUNT + 1):
		SaveManager.delete_save(n)
	DirAccess.remove_absolute(TEST_PREFIX + "_meta.cfg")
	for suffix in ["", ".bak"]:
		DirAccess.remove_absolute(TEST_PREFIX + "_stash.json" + suffix)
	SaveManager.slot_prefix = _real_prefix
	SaveManager.slot = _real_slot
	GameState.game_started = false
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("v4.76 tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_slots() -> void:
	_check(SaveManager.SLOT_COUNT == 3, "three slots")
	_check(not SaveManager.has_any_save(), "test slots start empty")
	SaveManager.select_slot(2)
	GameState.player_name = "Aria"
	GameState.player_level = 37
	GameState.depth_cleared = 9
	GameState.game_started = true
	SaveManager.save_game()
	_check(SaveManager.slot_has_save(2) and not SaveManager.slot_has_save(1) and not SaveManager.slot_has_save(3), "saving writes only the current slot")
	var s := SaveManager.slot_summary(2)
	_check(s.get("name") == "Aria" and s.get("level") == 37 and s.get("depth") == 9 and int(s.get("saved_at", 0)) > 0, "the slot summary reads name, level, progress and time (%s)" % s)
	_check(SaveSlotPanel.describe(2, s).contains("Aria") and SaveSlotPanel.describe(1, {}).contains("Empty"), "slot rows describe filled and empty slots")
	SaveManager.select_slot(3)
	_check(GameState.player_name == "" and GameState.player_level == 1, "an empty slot loads fresh defaults")
	GameState.player_name = "Bram"
	GameState.game_started = true
	SaveManager.save_game()
	SaveManager.select_slot(2)
	_check(GameState.player_name == "Aria" and GameState.player_level == 37 and GameState.depth_cleared == 9, "selecting a slot loads that slot")
	_check(SaveManager._last_slot() == 2, "the last-used slot is remembered")
	SaveManager.delete_save(3)
	_check(not SaveManager.slot_has_save(3) and SaveManager.slot_has_save(2), "deleting one slot leaves the others")
	_finished += 1

func _test_character() -> void:
	SaveManager.select_slot(1)
	EndgameTestCharacter.build()
	_check(GameState.player_level == 90 and FigmentProgress.levelling_complete(), "level 90 with the levelling stage done")
	_check(GameState.equipment_refs.size() == 8, "armour, jewellery and rings on (%d)" % GameState.equipment_refs.size())
	_check(GameState.weapon_set_refs[0].size() == 1 and GameState.weapon_set_refs[1].size() == 1, "a melee weapon and a conduit")
	var tiers: Array[int] = []
	for f in GameState.stash.get_figments():
		tiers.append(f.tier)
	tiers.sort()
	_check(tiers == [1, 7, 8, 14, 15, 21], "Figments at each band's start and end (%s)" % [tiers])
	_check(Pinnacle.has_full_set(GameState.inventory), "a full set of Maw Fragments")
	_check(FigmentProgress.points_earned() == 0, "no Tier cleared yet: the tree starts from zero")
	_check(GameState.ability_levels.get("thunder_javelin", 0) == 20, "spells at level 20")
	GameState.game_started = true
	SaveManager.save_game()
	GameState.reset_to_defaults()
	SaveManager.select_slot(1)
	_check(GameState.player_level == 90 and GameState.equipment_refs.size() == 8 and GameState.depth_cleared == AreaLevel.DEPTHS, "the test character survives a save")
	GameState.game_started = false  # the Hub below must not save
	var hub: Node = load("res://levels/hub/Hub.tscn").instantiate()
	add_child(hub)
	for i in 10:
		await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player") as Player
	_check(player != null and player.equipment.primary_weapon != null, "the live player wields the generated weapon")
	if player:
		var rares := 0
		for item in player.equipment.get_all_equipped_items():
			if item.rarity >= Constants.ItemRarity.RARE:
				rares += 1
		_check(rares >= 6, "most of the gear is Rare or better (%d)" % rares)
		_check(player.health.max_health > 166.0, "gear raises Life (%.0f)" % player.health.max_health)
		_check(player.ability_loadout.get_all_paths().filter(func(p): return p != "").size() == 4, "four spells on the bar")
	hub.queue_free()
	for i in 3:
		await get_tree().process_frame
	_finished += 1
