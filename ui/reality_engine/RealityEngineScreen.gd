extends CanvasLayer
class_name RealityEngineScreen
## The Reality Engine's selection: grouped rows of everything it can open
## on the left (free run, carried and stashed Figments, Pinnacle bosses),
## the chosen one's card or requirements on the right, and one Enter button.
##
## Opened with RealityEngineScreen.open_for(tree, sections). sections:
## [{title, entries}], each entry {name, subtitle, color, icon (ItemIcon
## content), tag, tag_color, item (FigmentItem: shown as its ItemCard),
## fragments (true: shows the Maw Fragment set), description, button_label,
## on_buy (returning false keeps the screen open), fail_text}.

const LIST_WIDTH := 540.0
const DETAIL_WIDTH := 372.0
const BODY_HEIGHT := 520.0
const ROW_HEIGHT := 58.0

var _is_open := false
var _list: VBoxContainer
var _detail: VBoxContainer
var _enter: Button
var _hint: Label
var _group := ButtonGroup.new()
var _selected: Dictionary = {}

static func open_for(tree: SceneTree, sections: Array) -> RealityEngineScreen:
	var screen := tree.get_first_node_in_group("reality_engine_screen") as RealityEngineScreen
	if screen == null:
		screen = RealityEngineScreen.new()
		tree.current_scene.add_child(screen)
	screen.open_with(sections)
	return screen

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("reality_engine_screen")
	add_to_group("blocking_menu")
	_build()

func is_open() -> bool:
	return _is_open

func open_with(sections: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	_hint.text = ""
	var first: Button = null
	for section in sections:
		var entries: Array = section.get("entries", [])
		if entries.is_empty():
			continue
		_list.add_child(AetherStyle.section_header("%s  (%d)" % [section["title"], entries.size()] if entries.size() > 1 else String(section["title"]), 15))
		for entry in entries:
			var row := _row(entry)
			_list.add_child(row)
			if first == null:
				first = row
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if first:
		first.button_pressed = true
		_select(first.get_meta("entry"))

func close() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

## ---- Choosing -------------------------------------------------------------

func _select(entry: Dictionary) -> void:
	_selected = entry
	_hint.text = ""
	for child in _detail.get_children():
		child.queue_free()
	var accent: Color = entry.get("color", AetherStyle.GOLD)
	if entry.get("item"):
		var card: ItemCard = load("res://ui/item_card/ItemCard.tscn").instantiate()
		_detail.add_child(card)
		card.display_item(entry["item"])
	else:
		var name_label := _label(entry.get("name", ""), 22, accent)
		name_label.add_theme_font_override("font", AetherStyle.title())
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(name_label)
		_detail.add_child(AetherStyle.section_divider(true))
		var about := _label(entry.get("description", ""), 16, AetherStyle.TEXT)
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(about)
		if entry.get("fragments", false):
			_detail.add_child(_fragment_list())
	_enter.text = entry.get("button_label", "Enter")
	_enter.add_theme_stylebox_override("normal", AetherStyle.button_box(accent, AetherStyle.GLASS_LIGHT.lerp(accent.darkened(0.45), 0.25), 2))
	_enter.add_theme_stylebox_override("hover", AetherStyle.button_box(accent.lightened(0.25), AetherStyle.GLASS_LIGHT.lerp(accent.darkened(0.3), 0.35), 2, Color(accent, 0.45)))

func _confirm() -> void:
	if _selected.is_empty():
		return
	var on_buy: Callable = _selected.get("on_buy", Callable())
	if on_buy.is_valid() and on_buy.call() == false:
		_hint.text = _selected.get("fail_text", "It won't open")
		return
	# Entering a map may already have swapped the scene out.
	if _is_open and is_inside_tree():
		close()

## ---- UI -------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	center.add_child(root)

	var title := _label(AetherStyle.spaced("REALITY ENGINE"), 30, AetherStyle.GOLD_BRIGHT)
	title.add_theme_font_override("font", AetherStyle.title())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var subtitle := _label("Choose a memory and the Engine will give it form.", 17, AetherStyle.TEXT_DIM)
	subtitle.add_theme_font_override("font", AetherStyle.serif_italic())
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(subtitle)
	root.add_child(AetherStyle.section_divider())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	root.add_child(columns)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, BODY_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	var detail_frame := PanelContainer.new()
	detail_frame.custom_minimum_size = Vector2(DETAIL_WIDTH, BODY_HEIGHT)
	detail_frame.add_theme_stylebox_override("panel", AetherStyle.glass_box(AetherStyle.GOLD_FAINT, AetherStyle.GLASS, 1, 14.0))
	columns.add_child(detail_frame)
	var detail_col := VBoxContainer.new()
	detail_col.add_theme_constant_override("separation", 10)
	detail_frame.add_child(detail_col)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_col.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(_detail)
	_hint = _label("", 15, AetherStyle.DANGER)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_col.add_child(_hint)
	_enter = Button.new()
	_enter.text = "Enter"
	_enter.custom_minimum_size = Vector2(0, 46)
	_enter.add_theme_font_override("font", AetherStyle.title())
	_enter.add_theme_font_size_override("font_size", 19)
	_enter.add_theme_color_override("font_color", AetherStyle.GOLD_BRIGHT)
	_enter.add_theme_color_override("font_hover_color", Color.WHITE)
	_enter.pressed.connect(_confirm)
	detail_col.add_child(_enter)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	root.add_child(footer)
	var hints := AetherStyle.key_hints([["LMB", "Select, double-click to enter"], ["Esc", "Close"]])
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(hints)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	footer.add_child(close_button)
	AetherStyle.wrap_in_plate(root, 26)

## A selectable row: icon, name and details, and a tag on the right.
func _row(entry: Dictionary) -> Button:
	var accent: Color = entry.get("color", AetherStyle.GOLD)
	var row := Button.new()
	row.toggle_mode = true
	row.button_group = _group
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.focus_mode = Control.FOCUS_NONE
	row.set_meta("entry", entry)
	row.add_theme_stylebox_override("normal", _row_box(accent, 0))
	row.add_theme_stylebox_override("hover", _row_box(accent, 1))
	row.add_theme_stylebox_override("pressed", _row_box(accent, 2))
	row.add_theme_stylebox_override("hover_pressed", _row_box(accent, 2))
	row.toggled.connect(func(on: bool):
		if on:
			_select(entry))
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			_select(entry)
			_confirm.call_deferred())

	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -12
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)
	var icon_cell := Control.new()
	icon_cell.custom_minimum_size = Vector2(42, 42)
	icon_cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon_cell)
	ItemIcon.fill(icon_cell).content = entry.get("icon")
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text)
	var name_label := _label(entry.get("name", ""), 18, accent.lerp(Color.WHITE, 0.25))
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(name_label)
	var sub := _label(entry.get("subtitle", ""), 14, AetherStyle.TEXT_DIM)
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(sub)
	var tag: String = entry.get("tag", "")
	if tag != "":
		var tag_color: Color = entry.get("tag_color", AetherStyle.GOLD)
		var badge := PanelContainer.new()
		var badge_box := AetherStyle.glass_box(tag_color, Color(tag_color, 0.12), 1, 7.0)
		badge_box.content_margin_top = 1
		badge_box.content_margin_bottom = 1
		badge.add_theme_stylebox_override("panel", badge_box)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tag_label := _label(tag, 14, tag_color)
		tag_label.add_theme_font_override("font", AetherStyle.numbers())
		badge.add_child(tag_label)
		box.add_child(badge)
	for node in box.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row

## 0 resting, 1 hovered, 2 selected: an accent bar on the left, brighter
## border and tint as it's picked.
func _row_box(accent: Color, state: int) -> StyleBoxFlat:
	var border := [Color(accent, 0.35), Color(accent, 0.7), accent][state] as Color
	var box := AetherStyle.glass_box(border, AetherStyle.GLASS_LIGHT.lerp(accent.darkened(0.45), [0.06, 0.14, 0.24][state]), 1, 8.0)
	box.border_width_left = 4
	box.shadow_color = Color(accent, 0.3) if state == 2 else Color(0, 0, 0, 0)
	box.shadow_size = 6 if state == 2 else 0
	return box

## The four Maw Fragments, each lit if carried.
func _fragment_list() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.add_child(AetherStyle.section_header("Maw Fragments", 14))
	for id in Pinnacle.FRAGMENT_IDS:
		var have := GameState.inventory.count_of(id) > 0
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(32, 32)
		cell.modulate = Color.WHITE if have else Color(1, 1, 1, 0.3)
		ItemIcon.fill(cell).content = id
		line.add_child(cell)
		var label := _label(CurrencyText.name_of(id), 16, AetherStyle.TEXT if have else AetherStyle.TEXT_DIM)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		line.add_child(_label("Held" if have else "Missing", 15, AetherStyle.AETHER if have else AetherStyle.DANGER))
		col.add_child(line)
	if Pinnacle.free_entry:
		col.add_child(_label("Testing: opens without Fragments.", 14, AetherStyle.GOLD))
	return col

func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label
