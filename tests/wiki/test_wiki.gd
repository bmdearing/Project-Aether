extends Node
## Unique wiki and Unique stash tab: drop odds (UniqueOdds) against the real
## roll weights, Magic Find moving them, sources, the main menu Wiki panel,
## and storing/taking/saving uniques in the stash's Unique tab.
## Run: Godot --headless --path . res://tests/wiki/test_wiki.tscn
## Exits 0 when every check passes. Never writes the save file.

const HUB := "res://levels/hub/Hub.tscn"
const MAIN_MENU := "res://ui/main_menu/MainMenu.tscn"
const TEST_COUNT := 8

var _checks := 0
var _failures := 0
var _finished := 0

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
	GameState.game_started = false
	_test_odds()
	_test_stash_model()
	await _test_wiki_panel()
	await _test_main_menu()
	await _test_stash_screen()
	await _test_modifier_pages()
	await _test_corruption_page()
	await _test_status_and_monster_pages()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("wiki tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _world_defs() -> Array:
	return UniqueCatalog.DEFS.filter(func(d): return UniqueOdds.is_world_drop(d))

func _test_odds() -> void:
	var total := 0.0
	for def in _world_defs():
		total += UniqueOdds.per_gear_drop(def, 1.0)
	var expected := UniqueOdds.rarity_chance(Constants.ItemRarity.UNIQUE, 1.0) + UniqueOdds.rarity_chance(Constants.ItemRarity.MYTHIC, 1.0)
	_check(is_equal_approx(total, expected), "per-drop odds of every world unique add up to the Unique + Mythic rarity chance")
	var mantle := UniqueCatalog.get_def("hollowed_kings_mantle")
	_check(UniqueOdds.per_gear_drop(mantle, 3.0) > UniqueOdds.per_gear_drop(mantle, 1.0), "Item Rarity raises a unique's odds")
	_check(UniqueOdds.per_kill(mantle, Constants.EnemyRank.NORMAL, 2.0, 1.0) > UniqueOdds.per_kill(mantle, Constants.EnemyRank.NORMAL, 1.0, 1.0), "Item Quantity raises the per-kill odds")
	_check(UniqueOdds.per_kill(mantle, Constants.EnemyRank.BOSS, 1.0, 1.0) > UniqueOdds.per_kill(mantle, Constants.EnemyRank.NORMAL, 1.0, 1.0), "bosses are likelier to drop it than normal monsters")
	var pinnacle_total := 0.0
	for def in _world_defs():
		pinnacle_total += UniqueOdds.per_pinnacle_reward(def, "lord_of_the_elements")
	_check(is_equal_approx(pinnacle_total, 1.0), "Pinnacle reward odds add up to 100%")
	var debt := UniqueCatalog.get_def("debt_of_tharsis")
	_check(UniqueOdds.per_gear_drop(debt, 1.0) == 0.0 and UniqueOdds.source_text(debt).begins_with("Shard of Tharsis"), "corrupted-only uniques never drop and name their source")
	_check(UniqueOdds.source_text(mantle) == "World Drop", "ordinary uniques are World Drops")
	var exclusive := {"id": "x", "name": "X", "rarity": Constants.ItemRarity.UNIQUE, "base_type": "ring", "weight": 100.0, "boss": "lord_of_the_elements", "mods": []}
	_check(UniqueOdds.source_text(exclusive) == "Pinnacle: Lord of the Elements" and UniqueOdds.per_gear_drop(exclusive, 1.0) == 0.0, "boss-only uniques name the boss and aren't world drops")
	_check(UniqueOdds.per_pinnacle_reward(exclusive, "herald_of_the_maw") == 0.0, "a boss-only unique never comes from the other boss")
	_check(UniqueRoller.droppable(Constants.ItemRarity.UNIQUE).all(func(d): return not d.has("boss")), "the world pool has no boss-only uniques")
	_check(UniqueRoller.range_text(mantle["mods"][0]) == "(40-50)% more Ward", "modifier ranges read like '(40-50)% more Ward'")
	_check(UniqueOdds.format_chance(0.0025) == "0.25% (1 in 400)" and UniqueOdds.format_chance(0.0) == "—", "chance text")
	_finished += 1

func _unique(id: String) -> Item:
	return UniqueRoller.build(UniqueCatalog.get_def(id), 40)

func _test_stash_model() -> void:
	var stash := Stash.create_default()
	var band := _unique("band_of_wishes")
	_check(stash.store_unique(band) and stash.uniques["band_of_wishes"] == band, "a unique goes into its own slot")
	_check(not stash.store_unique(_unique("band_of_wishes")), "a filled slot refuses a second copy")
	_check(not stash.store_unique(Item.new()), "ordinary items don't go in the Unique tab")
	var loaded := Stash.from_dict(JSON.parse_string(JSON.stringify(stash.to_dict())))
	_check(loaded.uniques.has("band_of_wishes") and loaded.uniques["band_of_wishes"].display_name == "Band of Wishes", "the Unique tab saves and loads")
	_check(loaded.tabs.size() == stash.tabs.size(), "regular tabs survive alongside it")
	_check(stash.take_unique("band_of_wishes") == band and stash.uniques.is_empty(), "taking empties the slot")
	_finished += 1

func _gear_odds_text(wiki: UniqueWiki, id: String) -> String:
	return wiki._odds_labels[id]["gear"].text

func _test_wiki_panel() -> void:
	GameState.stash = Stash.create_default()
	GameState.stash.store_unique(_unique("the_pale_eye"))
	var wiki := UniqueWiki.new()
	add_child(wiki)
	await _frames(1)
	_check(wiki.listed_ids().size() == UniqueCatalog.DEFS.size(), "the wiki lists every Unique and Mythic")
	_check(UniqueCatalog.get_def(wiki.listed_ids()[0])["rarity"] == Constants.ItemRarity.MYTHIC, "Mythics come first")
	wiki.set_magic_find(0.0)
	var before := _gear_odds_text(wiki, "hollowed_kings_mantle")
	wiki.set_magic_find(100.0)
	var mults := wiki.multipliers()
	_check(is_equal_approx(mults["rarity"], 3.0) and is_equal_approx(mults["quantity"], 1.5), "100 Magic Find = +200% Item Rarity, +50% Item Quantity")
	_check(_gear_odds_text(wiki, "hollowed_kings_mantle") != before, "the odds update with Magic Find")
	var shown := UniqueOdds.format_chance(UniqueOdds.per_gear_drop(UniqueCatalog.get_def("hollowed_kings_mantle"), 3.0))
	_check(_gear_odds_text(wiki, "hollowed_kings_mantle").contains(shown), "the shown odds are UniqueOdds' numbers")
	var labels := wiki.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	_check(labels.any(func(t): return t.contains("In your Unique tab")), "collected uniques are marked")
	_check(labels.has("World Drop") and labels.any(func(t): return t.begins_with("Shard of Tharsis")), "sources are shown")
	wiki.filter = UniqueWiki.Filter.MYTHIC
	wiki._rebuild_list()
	_check(not wiki.listed_ids().is_empty() and wiki.listed_ids().all(func(id): return UniqueCatalog.get_def(id)["rarity"] == Constants.ItemRarity.MYTHIC), "the Mythic filter shows only Mythics")
	wiki.queue_free()
	GameState.stash = Stash.create_default()
	await _frames(1)
	_finished += 1

func _test_main_menu() -> void:
	var menu: MainMenu = load(MAIN_MENU).instantiate()
	add_child(menu)
	await _frames(2)
	var button := menu.find_child("WikiButton", true, false) as Button
	_check(button != null, "the main menu has a Wiki button")
	if button:
		button.pressed.emit()
		await _frames(1)
		_check(menu.wiki_panel.visible and not menu.main_panel.visible, "Wiki opens its panel")
		menu.wiki.back_pressed.emit()
		_check(menu.main_panel.visible and not menu.wiki_panel.visible, "Back returns to the menu")
	menu.queue_free()
	await _frames(1)
	_finished += 1

func _test_stash_screen() -> void:
	var hub: Node = load(HUB).instantiate()
	add_child(hub)
	await _frames(5)
	var screen := get_tree().get_first_node_in_group("stash_screen") as StashScreen
	screen.open()
	screen._select_tab(GameState.stash.tabs.size())
	await _frames(1)
	_check(screen.is_unique_tab_open() and screen._unique_view.visible and not screen._stash_scroll.visible, "the last tab is the Unique tab")
	_check(screen._unique_view.get_child_count() == UniqueCatalog.DEFS.size(), "it has a slot per Unique and Mythic")
	var eye := _unique("the_pale_eye")
	GameState.add_to_inventory(eye)
	var entry: GridInventory.Entry = GameState.inventory.get_entries().filter(func(e): return e.content == eye)[0]
	screen._on_entry_right_clicked(screen._carried_view, entry)
	_check(GameState.stash.uniques.get("the_pale_eye") == eye and not GameState.inventory.has_content(eye), "right-clicking a unique stores it in its slot")
	var second := _unique("the_pale_eye")
	GameState.add_to_inventory(second)
	var second_entry: GridInventory.Entry = GameState.inventory.get_entries().filter(func(e): return e.content == second)[0]
	screen._on_entry_right_clicked(screen._carried_view, second_entry)
	_check(GameState.inventory.has_content(second) and screen._status.text.contains("already holds"), "a second copy stays in the inventory")
	GameState.remove_from_inventory(second)
	screen._withdraw_unique("the_pale_eye")
	_check(GameState.inventory.has_content(eye) and not GameState.stash.uniques.has("the_pale_eye"), "clicking a filled slot takes it back")
	GameState.remove_from_inventory(eye)
	screen.close()
	hub.queue_free()
	await _frames(1)
	_finished += 1

func _test_modifier_pages() -> void:
	for group in WikiCatalog.GROUPS:
		_check(not WikiCatalog.types_in(group).is_empty(), "%s has base types" % group)
	var names := WikiCatalog.all_types().map(func(t): return t["name"])
	_check(names.has("Greatsword") and names.has("Ring") and names.has("Jewel") and names.has("Fire Slate"), "groups list weapons, accessories, jewels and slates")
	_check(not names.any(func(n): return String(n).contains("Grenade") or String(n).contains("Knife")), "throwables aren't listed")
	var sword: Dictionary = WikiCatalog.types_in("Melee").filter(func(t): return t["name"] == "Greatsword")[0]
	var rows := WikiCatalog.modifier_rows(sword["base"], 80)
	var total := 0.0
	for r in rows:
		total += r["chance"]
	_check(is_equal_approx(total, 1.0), "Orb chances on a blank item add up to 100% (%.3f)" % total)
	var dmg: Array = rows.filter(func(r): return r["def"].stat_key == "local_increased_weapon_damage")
	_check(dmg.size() == 1 and dmg[0]["tiers"].size() == 8 and dmg[0]["tiers"][0]["level"] == 80 and is_equal_approx(dmg[0]["tiers"][0]["max"], 190.0), "Weapon Damage shows its 8 tiers, Tier 1 at item level 80 up to 190%")
	var low := WikiCatalog.modifier_rows(sword["base"], 1)
	var low_dmg: Array = low.filter(func(r): return r["def"].stat_key == "local_increased_weapon_damage")[0]["tiers"]
	_check(low_dmg.filter(func(t): return t["chance"] > 0.0).size() == 1, "at item level 1 only the lowest tier can roll")
	_check(rows.all(func(r): return r["tiers"].all(func(t): return t["level"] >= 1 and t["level"] <= 80)), "every tier names the item level it needs")
	var kinetic := low.filter(func(r): return r["def"].stat_key == "increased_kinetic_damage")
	_check(not kinetic.is_empty() and kinetic[0]["chance"] > 0.0, "library mods roll below their Tier 1 level (Kinetic damage at item level 1)")
	var index := WikiCatalog.modifier_index()
	var fire_res: Array = index.filter(func(r): return String(r["text"]).contains("Fire Resistance"))
	_check(fire_res.size() == 1, "one Fire Resistance modifier, not two from different patches")
	var wiki := Wiki.new()
	add_child(wiki)
	await _frames(1)
	wiki.show_page("Modifiers")
	wiki.modifiers.show_type("Accessories", "Amulet", 80)
	await _frames(1)
	_check(wiki.modifiers.rows.any(func(r): return String(r["text"]).contains("to level of all")), "the By item view lists the amulet's modifiers")
	wiki.modifiers.by_modifier = true
	wiki.modifiers._search.text = "Attack Speed"
	wiki.modifiers.refresh()
	_check(not wiki.modifiers.rows.is_empty() and wiki.modifiers.rows.all(func(r): return String(r["text"]).contains("Attack Speed")), "By modifier search filters")
	wiki.queue_free()
	await _frames(1)
	_finished += 1

func _test_corruption_page() -> void:
	var tiers := WikiCatalog.corruption_tiers()
	var total := 0.0
	for t in tiers:
		for o in t["outcomes"]:
			total += o["chance"]
			_check(o["text"] != "", "%s is described" % o["name"])
	_check(is_equal_approx(total, 1.0), "outcome chances add up to 100%")
	var ascendant: Dictionary = tiers[2]["outcomes"].filter(func(o): return o["name"] == "Ascendant")[0]
	_check(ascendant["slots"][0] and not ascendant["slots"].slice(1).any(func(s): return s), "Ascendant only lights the weapon slot")
	var page := CorruptionWiki.new()
	add_child(page)
	await _frames(1)
	_check(page.shown.size() == total_outcomes(), "the page lists every outcome")
	page.queue_free()
	await _frames(1)
	_finished += 1

func total_outcomes() -> int:
	var n := 0
	for tier in 4:
		n += CorruptionSystem.outcomes_in_tier(tier + 1).size()
	return n

## Status Effects and Monsters pages: every effect and every monster affix.
func _test_status_and_monster_pages() -> void:
	var rows := WikiCatalog.status_effects()
	_check(rows.all(func(r): return r["text"] != "" and r["name"] != ""), "every status effect is named and described")
	var unravel: Dictionary = rows.filter(func(r): return r["id"] == "unraveling")[0]
	_check(unravel["ailment"] and unravel["types"] == ["Entropic"], "Unraveling is an ailment caused by Entropic damage")
	var page := StatusWiki.new()
	add_child(page)
	await _frames(1)
	_check(page.shown.size() == rows.size() and page.shown.has("bleed") and page.shown.has("intimidated"), "the Status Effects page lists every effect (%d)" % page.shown.size())
	page.queue_free()
	var tiers := WikiCatalog.monster_tiers()
	_check(tiers.size() == 4, "four monster tiers")
	var affix_count := 0
	for t in tiers:
		affix_count += (t["affixes"] as Array).size()
	var monsters := MonsterWiki.new()
	add_child(monsters)
	await _frames(1)
	_check(monsters.shown.size() == affix_count and affix_count >= 20 and monsters.shown.has("pack_volatile") and monsters.shown.has("ascendant_blink"), "the Monsters page lists every affix (%d)" % monsters.shown.size())
	monsters.queue_free()
	await _frames(1)
	_finished += 1
