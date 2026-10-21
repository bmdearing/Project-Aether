extends Node
## Fate Board Stars: the circular board, Stars as solid roots, reaching a
## Star, Lenses in Stars lighting bonus sites, claiming them, stat totals,
## and old square-board saves moving onto the circle.
## Run: Godot --headless --path . res://tests/stars/test_stars.tscn
## Exits 0 when every check passes.

const HUB := "res://levels/hub/Hub.tscn"
const A := FateBoard.ANCHOR_CELL

var _checks := 0
var _failures := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	_test_board()
	await _test_restore()
	print("star tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _slate(tag: int) -> Slate:
	var s := Slate.new()
	s.slate_id = "test_%d" % randi()
	s.display_name = "Test Slate"
	s.tag = tag
	s.aether_cost = 1
	return s

func _lens(mod: String, radius: int, tag: int = -1) -> Lens:
	var l := Lens.new()
	l.item_id = "lens_test_%s_%d" % [mod, radius]
	l.display_name = "Test Lens"
	l.radius = radius
	l.radius_mod = mod
	l.radius_tag = tag
	return l

func _test_board() -> void:
	var board := FateBoard.new()
	board.aether_capacity = 10000
	var fire := Constants.DamageType.FIRE
	_check(board._placement_failure_reason(_slate(fire), A + Vector2i(FateBoard.BOARD_RADIUS + 1, 0), 0, false) == "off_board", "cells off the circle are refused")
	var north: Vector2i = FateStars.cells()[1]
	_check(board.reached_stars() == [0], "only the Centre Star starts reached")
	_check(board.set_star_lens(1, _lens("cheap", 2)) == "star_unreached", "an unreached Star refuses a Lens")
	for y in range(1, FateBoard.STAR_DISTANCE):
		board.place_slate(_slate(fire), A + Vector2i(0, -y))
	_check(board.placements.size() == FateBoard.STAR_DISTANCE - 1, "a column of Slates reaches toward the North Star")
	_check(board._placement_failure_reason(_slate(fire), north, 0, false) == "anchor_cell", "Stars are solid")
	_check(board.is_star_reached(1), "the North Star is reached")
	# A reached Star is a root: any tag can hang off it.
	_check(board._placement_failure_reason(_slate(Constants.DamageType.COLD), north + Vector2i(1, 0), 0, false) == "", "a reached Star lets any tag connect")
	var lens := _lens("amplify_tag", 3, fire)
	_check(board.set_star_lens(1, lens) == "", "a reached Star takes a Lens")
	var sites := board.lit_sites()
	_check(sites.size() == FateStars.SITES_BY_RADIUS[3], "a Medium Lens lights 6 sites (%d)" % sites.size())
	_check(sites.all(func(s: FateStars.Site) -> bool: return FateBoard.in_board(s.cell) and FateStars.star_at(s.cell) < 0), "sites are on the board and off the Stars")
	_check(FateStars.site_cells(1) == FateStars.site_cells(1), "sites are fixed places")
	_check(board.claimed_sites().is_empty(), "nothing claimed yet")
	# Claim one by covering it (restore-style placement skips the connection rule).
	var site: FateStars.Site = sites[0]
	board.place_slate(_slate(fire), site.cell, 0, false, "", true)
	_check(board.claimed_sites().size() == 1, "a Slate on a site claims it")
	var totals := FateStars.totals(board)
	var key: String = site.bonus["key"]
	var value: float = site.bonus["value"]
	var got := 0.0
	if key == "type_damage":
		got = totals["misc"].get(StatKeys.type_damage_key(fire), 0.0)
	elif key == "mastery":
		got = totals["mastery"].get(fire, 0.0) * 100.0
	else:
		got = totals["misc"].get(key, 0.0)
	_check(is_equal_approx(got, value), "the claimed bonus counts (%s %.1f = %.1f)" % [key, value, got])
	# Cutting the chain unlights the Star.
	var link: String = board.get_occupied_cells()[A + Vector2i(0, -10)]
	_check(board.removal_breaks_chain(link), "Slates past the cut still block removal")
	_check(board.take_star_lens(1) == lens and board.lit_sites().is_empty(), "the Lens comes back out")
	# Every pool has text and Lens card lines.
	for mod in LensRoller.RADIUS_MODS:
		_check(FateStars.POOLS.has(mod), "radius modifier %s has a Star pool" % mod)
	var cheap := FateBoard.new()
	_check(cheap.set_star_lens(0, _lens("cheap", 4)) == "" and cheap.lit_sites().size() == 8, "the Centre takes a Lens at once; a Large one lights 8")
	_test_lodestar(board)

## The Lodestar: North Star only, never in a Slate; each Slate within its
## radius of the North Star gains one gift.
func _test_lodestar(board: FateBoard) -> void:
	var lodestar := Pinnacle.make_maw_lens(80) as Lens
	_check(lodestar != null and lodestar.radius_text() != "", "the Herald drops the Lodestar")
	_check(board.set_star_lens(0, lodestar) == "wrong_star", "the Lodestar refuses the Centre Star")
	_check(board.socket_lens(board.placements.keys()[0], lodestar) == "star_only", "the Lodestar refuses a Slate")
	_check(board.set_star_lens(1, lodestar) == "", "the Lodestar fits the North Star")
	var north: Vector2i = FateStars.cells()[1]
	var in_radius := board.placements.values().filter(func(d: FateBoard.PlacedSlateData) -> bool:
		return d.cells.any(func(c: Vector2i) -> bool: return Vector2(c - north).length() <= Pinnacle.LODESTAR_RADIUS + 0.01))
	var gifts := board.claimed_sites().filter(func(s: FateStars.Site) -> bool: return s.star == 1)
	_check(in_radius.size() > 0 and gifts.size() == in_radius.size(), "every Slate in radius gains one gift (%d / %d)" % [gifts.size(), in_radius.size()])
	var keys := {}
	var expected := {}
	for s in gifts:
		keys[s.bonus["key"]] = true
		if s.bonus["key"] == "increased_defences":
			expected["increased_armor"] = expected.get("increased_armor", 0.0) + 2.0
	_check(keys.size() > 1, "Slates roll different gifts")
	var again := board.star_sites(1)
	_check(again.size() == gifts.size() and again[0].bonus["key"] == gifts[0].bonus["key"], "the gifts don't change between calls")
	var misc: Dictionary = FateStars.totals(board)["misc"]
	for k in expected:
		_check(is_equal_approx(misc.get(k, 0.0), expected[k]), "gift totals count (%s %.1f = %.1f)" % [k, expected[k], misc.get(k, 0.0)])
	board.take_star_lens(1)

func _test_restore() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	var slate := _slate(Constants.DamageType.FIRE)
	var lens := _lens("cheap", 2)
	var site_cell: Vector2i = FateStars.sites_for(0, lens)[0].cell
	var old_origin := site_cell - FateBoard.LEGACY_SHIFT
	GameState.fate_board_placements = [{"slate_ref": SlateSerializer.to_dict(slate), "origin": [old_origin.x, old_origin.y], "rotation_steps": 0, "flipped": false, "designated_ability_id": "", "aether_paid": 1}]
	GameState.fate_board_layout = 1
	GameState.fate_board_star_lenses = {"0": ItemSerializer.to_dict(lens)}
	var hub: Node = load(HUB).instantiate()
	add_child(hub)
	for i in 5:
		await get_tree().process_frame
	var board: FateBoard = GameState.fate_board
	var placed: Array = board.placements.values()
	_check(placed.size() == 1 and (placed[0] as FateBoard.PlacedSlateData).origin == site_cell, "an old square-board Slate moves onto the circle")
	_check(board.star_lenses.has(0), "the Centre Star's Lens is restored")
	_check(GameState.fate_board_layout == FateBoard.LAYOUT_VERSION and GameState.fate_board_star_lenses.has("0"), "the save is rewritten in the new layout")
	var player := get_tree().get_first_node_in_group("player") as Player
	var site: FateStars.Site = FateStars.sites_for(0, lens)[0]
	var key: String = site.bonus["key"]
	if player and key != "flat_aether" and EquipmentComponent.is_misc_key(key):
		_check(is_equal_approx(player.stat_sheet.get_misc_bonus(key), site.bonus["value"]), "the claimed bonus reaches the player's stats")
	elif player and key == "flat_aether":
		_check(board.aether_capacity == FateBoard.capacity_for_level(GameState.player_level) + int(site.bonus["value"]), "a claimed Aether site raises the budget by its value")
	hub.queue_free()
