extends Node
## PlayerStatusRow: the player's effects and buffs show as top-left icons with
## a countdown, appear and disappear with the effects, count down, refresh,
## stack, and buffs (incl. ones with no timer) come first.
## Run: Godot --headless --path . res://tests/ui/test_status_row.tscn --quit-after 3000
## Windowed with `-- <out.png>` it also saves a screenshot of the HUD with a spread of icons.
## Exits 0 when every check passes.

var _checks := 0
var _failures := 0
var _finished := 0
const TEST_COUNT := 4

var _player: Player
var _row: PlayerStatusRow

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _entry(id: String) -> Dictionary:
	for e in _row.entries():
		if e["id"] == id:
			return e
	return {}

func _ids() -> Array:
	return _row.entries().map(func(e: Dictionary): return e["id"])

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.debug_overlay_enabled = false
	var hub: Node = load("res://levels/hub/Hub.tscn").instantiate()
	get_tree().root.add_child(hub)
	await _wait(1.0)
	_player = get_tree().get_first_node_in_group("player") as Player
	for node in get_tree().root.find_children("*", "PlayerStatusRow", true, false):
		_row = node as PlayerStatusRow
	_check(_row != null and _row.player == _player, "the HUD has a status row bound to the player")
	if _row == null:
		get_tree().quit(1)
		return
	_player.health.max_health = 1000000.0
	_player.health.current_health = 1000000.0
	_player.status_effects.clear_all_effects()
	_test_icons_and_format()
	await _test_countdown_refresh_expire()
	await _test_stacks_and_freeze()
	await _test_buffs()
	var out_args := OS.get_cmdline_user_args()
	if out_args.size() > 0:
		await _screenshot(out_args[0])
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("status row tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_icons_and_format() -> void:
	_check(_row.entries().is_empty(), "nothing shows with no effects")
	_check(StatusIcons.def_of("not_a_real_effect") == StatusIcons.PLACEHOLDER, "an effect with no icon gets the placeholder")
	_check(StatusIcons.is_buff("aura:meager") and StatusIcons.def_of("aura:meager")[0] == StatusIcons.DEFS["meager"][0], "a Hex Aura uses its curse's glyph as a buff")
	_check(StatusIcons.is_buff("stone_skin") and not StatusIcons.is_buff("ignite"), "Stone Skin is a buff, Ignite isn't")
	_check(PlayerStatusRow.time_text(3.04) == "3.0" and PlayerStatusRow.time_text(12.2) == "13", "tenths under 10 s, whole seconds above")
	_finished += 1

func _test_countdown_refresh_expire() -> void:
	var fx := _player.status_effects
	fx.apply_effect("ignite", null, 1.0)
	var e := _entry("ignite")
	_check(not e.is_empty() and absf(float(e["left"]) - StatusEffectComponent.IGNITE_DURATION) < 0.1, "Ignite shows with its full duration")
	await _wait(1.0)
	e = _entry("ignite")
	var left: float = e.get("left", -1.0)
	_check(left > StatusEffectComponent.IGNITE_DURATION - 1.3 and left < StatusEffectComponent.IGNITE_DURATION - 0.7, "Ignite counts down (%.2f left after 1 s)" % left)
	fx.apply_effect("ignite", null, 1.0)
	e = _entry("ignite")
	_check(absf(float(e.get("left", -1.0)) - StatusEffectComponent.IGNITE_DURATION) < 0.1, "re-applying Ignite refreshes the countdown")
	fx.apply_effect("shock")
	await _wait(0.2)
	var ids := _ids()
	_check(ids.has("ignite") and ids.has("shock"), "two effects show side by side")
	await _wait(StatusEffectComponent.SHOCK_DURATION)
	_check(not _ids().has("ignite") and not _ids().has("shock"), "icons go away when the effects expire")
	_finished += 1

func _test_stacks_and_freeze() -> void:
	var fx := _player.status_effects
	fx.apply_effect("chill")
	fx.apply_effect("chill")
	var e := _entry("chill")
	_check(int(e.get("stacks", 0)) == 2, "Chill shows its stack count")
	fx.apply_effect("chill")
	await _wait(0.1)
	_check(_ids().has("freeze") and not _ids().has("chill"), "the third Chill turns into Freeze on the row")
	e = _entry("freeze")
	_check(float(e.get("left", 0.0)) <= StatusEffectComponent.FREEZE_DURATION and float(e.get("left", 0.0)) > 0.8, "Freeze shows its own duration")
	await _wait(StatusEffectComponent.FREEZE_DURATION + 0.1)
	_check(_row.entries().is_empty(), "Freeze clears off the row")
	for i in 3:
		fx.apply_effect("scorch")
	_check(int(_entry("scorch").get("stacks", 0)) == 3, "Scorch stacks show")
	fx.clear_all_effects()
	_check(_row.entries().is_empty(), "clear_all_effects empties the row")
	_finished += 1

func _test_buffs() -> void:
	var fx := _player.status_effects
	fx.apply_effect("bleed", null, 1.0)
	_player.unique_effects.add_timed_more(&"battle_cry", 20.0, 6.0)
	fx.apply_timed_effect("stone_skin", 5.0)
	GameState.death_shroud_on = true
	await _wait(0.1)
	var ids := _ids()
	_check(ids.has("battle_cry") and ids.has("stone_skin") and ids.has("death_shroud") and ids.has("bleed"), "buffs show alongside effects (%s)" % [ids])
	_check(ids.find("bleed") > ids.find("battle_cry") and ids.find("bleed") > ids.find("stone_skin") and ids.find("bleed") > ids.find("death_shroud"), "buffs come before debuffs")
	_check(float(_entry("death_shroud").get("left", 0.0)) < 0.0, "an aura has no timer")
	var cry: float = _entry("battle_cry").get("left", 0.0)
	_check(cry > 5.5 and cry <= 6.0, "Battle Cry counts down from its duration (%.2f)" % cry)
	GameState.death_shroud_on = false
	fx.clear_all_effects()
	_player.unique_effects.timed_more.clear()
	await _wait(0.1)
	_check(_row.entries().is_empty(), "buffs go away when they end")
	_finished += 1

func _screenshot(path: String) -> void:
	var fx := _player.status_effects
	_player.unique_effects.add_timed_more(&"battle_cry", 20.0, 14.0)
	fx.apply_timed_effect("stone_skin", 5.0)
	GameState.death_shroud_on = true
	fx.apply_effect("ignite", null, 1.0)
	fx.apply_effect("chill")
	fx.apply_effect("chill")
	fx.apply_effect("bleed", null, 1.0)
	for i in 3:
		fx.apply_effect("scorch")
	fx.apply_effect("shock")
	fx.apply_curse("meager", null, 8.0, 1.0)
	fx.apply_timed_effect("not_a_real_effect", 3.0)
	await _wait(1.3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	GameState.death_shroud_on = false
	fx.clear_all_effects()
