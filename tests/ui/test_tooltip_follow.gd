extends Control
## TooltipFollow: placement beside the cursor (edge flips, never covering the
## cursor), and the live tooltip driven by pushed mouse motion (instant show, follow,
## swap between controls, refresh, hide).
## Also checks every item slot builds its card.
## Run: Godot --headless --path . res://tests/ui/test_tooltip_follow.tscn --quit-after 2000
## Exits 0 when every check passes.

var _checks := 0
var _failures := 0
var _finished := 0
const TEST_COUNT := 3

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
	_test_placement()
	await _test_follow()
	_test_every_slot_builds_a_card()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("tooltip follow tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _covers(pos: Vector2, tip: Vector2, point: Vector2) -> bool:
	return Rect2(pos, tip).has_point(point)

func _test_placement() -> void:
	var view := Vector2(1920, 1080)
	var tip := Vector2(300, 400)
	var mouse := Vector2(500, 300)
	var pos := TooltipFollow.place(mouse, tip, view)
	_check(pos == mouse + TooltipFollow.OFFSET, "tooltip sits below-right of the cursor")
	pos = TooltipFollow.place(Vector2(1800, 300), tip, view)
	_check(pos.x + tip.x <= 1800 and not _covers(pos, tip, Vector2(1800, 300)), "flips left near the right edge without covering the cursor")
	pos = TooltipFollow.place(Vector2(500, 1000), tip, view)
	_check(pos.y + tip.y <= 1000 and not _covers(pos, tip, Vector2(500, 1000)), "flips up near the bottom edge without covering the cursor")
	pos = TooltipFollow.place(Vector2(1900, 1060), tip, view)
	_check(Rect2(Vector2.ZERO, view).encloses(Rect2(pos, tip)), "stays on screen in the corner")
	pos = TooltipFollow.place(Vector2(500, 300), Vector2(400, 1200), view)
	_check(pos.y >= 0.0, "a card taller than the screen pins to the top")
	_finished += 1

func _test_follow() -> void:
	var a := Button.new()
	a.text = "A"
	a.tooltip_text = "first tooltip"
	a.position = Vector2(100, 100)
	a.size = Vector2(200, 60)
	add_child(a)
	var b := Button.new()
	b.text = "B"
	b.tooltip_text = "second tooltip"
	b.position = Vector2(100, 300)
	b.size = Vector2(200, 60)
	add_child(b)
	await _frames(2)
	for target in [Vector2(150, 120), Vector2(260, 140)]:
		_move(target)
		await _frames(3)
		var tip := TooltipFollow.current()
		_check(tip != null and _tip_text(tip) == "first tooltip", "a hovered control's tooltip shows with no delay")
		if tip:
			var expected := TooltipFollow.place(target, tip.size, get_tree().root.get_visible_rect().size)
			_check(tip.position.distance_to(expected) < 1.5, "tooltip follows the cursor to %s (at %s)" % [target, tip.position])
	_move(Vector2(150, 320))
	await _frames(3)
	var tip2 := TooltipFollow.current()
	_check(tip2 != null and _tip_text(tip2) == "second tooltip", "moving onto another control swaps the tooltip at once")
	b.tooltip_text = "changed"
	await _frames(int(TooltipFollow.REFRESH_SEC * 60.0) + 30)
	tip2 = TooltipFollow.current()
	_check(tip2 != null and _tip_text(tip2) == "changed", "a showing tooltip picks up changed content")
	_move(Vector2(900, 900))
	await _frames(2)
	_check(TooltipFollow.current() == null, "the tooltip hides when nothing with a tooltip is hovered")
	a.queue_free()
	b.queue_free()
	_finished += 1

func _move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	get_viewport().push_input(e, true)

func _tip_text(tip: Control) -> String:
	var label := tip.find_child("*", true, false) as Label
	return label.text if label else ""

func _test_every_slot_builds_a_card() -> void:
	var card_scene := load("res://ui/item_card/ItemCard.tscn") as PackedScene
	for slot in Constants.EquipmentSlot.values():
		var item := Item.new()
		item.display_name = "Slot Test"
		item.equip_slot = slot
		var card: ItemCard = card_scene.instantiate()
		card.display_item(item)
		var subtitle := ""
		for child in card._content().get_children():
			if child is Label and child.text != "" and child.text != "ITEM" and child.text != "Slot Test":
				subtitle = child.text
				break
		_check(subtitle != "" and not subtitle.is_valid_int(), "a %s card names its slot (%s)" % [Constants.EquipmentSlot.find_key(slot), subtitle])
		card.free()
	_finished += 1
