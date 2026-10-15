extends Node
## Character sheet Advanced view: every stat gear and Slates change, with
## sources that add up to the totals the game uses, and an explanation and
## a source breakdown on hover.
## Run: Godot --headless --path . res://tests/character/test_stat_details.tscn --quit-after 2000
## Exits 0 when every check passes. Never writes the save file.

const HUB := "res://levels/hub/Hub.tscn"

var _checks := 0
var _failures := 0

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

func _affix(key: String, value: float) -> ItemAffix:
	var a := ItemAffix.new()
	a.stat_key = key
	a.value = value
	return a

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false  # keeps SaveManager.save_game() a no-op
	var hub: Node = load(HUB).instantiate()
	add_child(hub)
	await _frames(5)
	var player := get_tree().get_first_node_in_group("player") as Player
	var screen: InventoryScreen = hub.get_node("InventoryScreen")

	var helm := Armor.new()
	helm.equip_slot = Constants.EquipmentSlot.HELMET
	helm.display_name = "Test Helm"
	helm.affixes = [_affix("flat_life", 50.0), _affix("fire_resistance", 20.0), _affix("all_elemental_resistance", 5.0), _affix("attack_speed", 10.0), _affix("flat_strength", 7.0)]
	GameState.player_equipment.equip(helm, true)
	var slate := Slate.new()
	slate.display_name = "Test Slate"
	slate.aether_cost = 1
	var mod := SlateModifier.new()
	mod.stat_key = "flat_life"
	mod.value = 30.0
	slate.modifiers = [mod]
	GameState.fate_board.place_slate(slate, FateBoard.ANCHOR_CELL + Vector2i(1, 0), 0, false, "", true)
	await _frames(2)

	var rows := StatSources.collect(player)
	var by_key := {}
	for row in rows:
		by_key[row["key"]] = row
	var life: Dictionary = by_key.get("flat_life", {})
	_check(not life.is_empty() and is_equal_approx(life["total"], player.stat_sheet.get_misc_bonus("flat_life")), "flat Life shows the total the game uses")
	_check(not life.is_empty() and life["sources"].size() == 2, "flat Life lists the helmet and the Slate")
	for row in rows:
		var sum := 0.0
		for s in row["sources"]:
			sum += s[1]
		_check(absf(sum - row["total"]) < 0.06, "%s sources add up to its total" % row["name"])
		_check(StatGlossary.explain(row["key"]) != "", "%s has an explanation" % row["name"])
	var fire: Dictionary = by_key.get("fire_resistance", {})
	_check(not fire.is_empty() and is_equal_approx(fire["total"], 25.0) and fire["sources"].size() == 2, "Fire Resistance counts its own line and all Elemental")
	var strength: Dictionary = by_key.get("strength", {})
	_check(not strength.is_empty() and strength["sources"].any(func(s): return s[0] == "Base") and strength["sources"].any(func(s): return String(s[0]).begins_with("Test Helm")), "Strength lists its base and the helmet")
	_check(StatGlossary.name_of("attack_speed") == "Increased Attack Speed", "names come from affix templates (%s)" % StatGlossary.name_of("attack_speed"))
	_check(StatGlossary.format("attack_speed", 10.0) == "+10%" and StatGlossary.format("flat_life", 50.0) == "+50", "percent and flat stats format differently")

	screen.open(true, false)
	var panel := screen._stat_details
	_check(panel != null and not panel.visible, "the sheet opens on the Basic view")
	screen._advanced_tab.pressed.emit()
	await _frames(2)
	_check(panel.visible and not screen._stats_scroll.visible, "Advanced swaps the stat columns for the details")
	var values: Array = panel.find_children("*", "Label", true, false).filter(func(l): return (l as Label).tooltip_text.contains("Test Helm"))
	_check(not values.is_empty(), "hovering a value shows its sources")
	screen._basic_tab.pressed.emit()
	_check(not panel.visible and screen._stats_scroll.visible, "Basic swaps back")
	screen.close()
	print("stat details tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
