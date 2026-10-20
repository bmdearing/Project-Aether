extends CanvasLayer
class_name SlateBenchScreen
## The Recombinator's and the Slate Splitter's screen: input boxes and output
## boxes on the left, your inventory on the right.
##   Recombine: two Slates of the same kind in, press the button, one out.
##   Split: one Slate in, press the button, its two halves out.
## Put a Slate in by dragging it onto a box or right-clicking it in your
## inventory; click a box to take its Slate back. Closing returns anything
## left on the bench (inventory first, then the stash). The rules and prices
## are SlateRecombinator's.

enum Mode { RECOMBINE, SPLIT }

const SLOT_SIZE := 132
const CELL := 36

var mode: Mode = Mode.RECOMBINE
var _is_open := false
var _inputs: Array[BenchSlot] = []
var _outputs: Array[BenchSlot] = []
var _title: Label
var _gold: Label
var _notice: Label
var _hint: Label
var _bench: HBoxContainer
var _craft_button: Button
var _inventory_view: InventoryGridView

## The scene's screen, created on first use.
static func open_for(tree: SceneTree, p_mode: Mode) -> SlateBenchScreen:
	var screen := tree.get_first_node_in_group("slate_bench_screen") as SlateBenchScreen
	if screen == null:
		screen = SlateBenchScreen.new()
		tree.current_scene.add_child(screen)
	screen.open(p_mode)
	return screen

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("slate_bench_screen")
	add_to_group("blocking_menu")
	_build()

func is_open() -> bool:
	return _is_open

func open(p_mode: Mode) -> void:
	mode = p_mode
	_build_bench()
	var split := mode == Mode.SPLIT
	_title.text = "Slate Splitter" if split else "Recombinator"
	_notice.text = ("Split a Slate with two or more crafted modifiers into two Slates, the modifiers dealt between them. Split Slates can't be split again." if split
		else "Merge two Slates of the same kind into one. A modifier both have keeps its better roll; each other modifier survives at %d%%." % roundi(SlateRecombinator.KEEP_CHANCE * 100.0))
	_inventory_view.set_inventory(GameState.inventory)
	_set_hint("Drag a Slate onto the bench, or right-click it in your inventory.")
	_refresh()
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	for slot in _inputs + _outputs:
		if slot.slate:
			_stow(slot.slate)
			slot.slate = null
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

## ---- Bench --------------------------------------------------------------

func cost() -> int:
	return SlateRecombinator.SPLIT_COST if mode == Mode.SPLIT else SlateRecombinator.RECOMBINE_COST

## Why the button can't be pressed right now, or "" when it can.
func craft_error() -> String:
	for slot in _outputs:
		if slot.slate:
			return "Take the finished Slate%s first." % ("s" if _outputs.size() > 1 else "")
	for slot in _inputs:
		if slot.slate == null:
			return "Place a Slate." if _inputs.size() == 1 else "Place two Slates of the same kind."
	var error := SlateRecombinator.split_error(_inputs[0].slate) if mode == Mode.SPLIT \
		else SlateRecombinator.recombine_error(_inputs[0].slate, _inputs[1].slate)
	if error != "":
		return error
	if GameState.gold < cost():
		return "Need %d Gold." % cost()
	return ""

func craft() -> bool:
	if craft_error() != "":
		return false
	GameState.gold -= cost()
	var results: Array[Slate] = []
	if mode == Mode.SPLIT:
		results = SlateRecombinator.split(_inputs[0].slate)
	else:
		results.append(SlateRecombinator.recombine(_inputs[0].slate, _inputs[1].slate))
	for slot in _inputs:
		slot.slate = null
	for i in results.size():
		_outputs[i].slate = results[i]
	_set_hint("Split in two." if mode == Mode.SPLIT else "Recombined.")
	_refresh()
	return true

## Moves a Slate from the inventory onto an input box (the first empty one
## when `index` is -1). A Slate already there goes back to the inventory.
func place(slate: Slate, index: int = -1) -> bool:
	if index < 0:
		for i in _inputs.size():
			if _inputs[i].slate == null:
				index = i
				break
	if index < 0 or index >= _inputs.size():
		_set_hint("The bench is full - click a box to take a Slate back.")
		return false
	if not GameState.remove_from_inventory(slate):
		return false
	var old := _inputs[index].slate
	_inputs[index].slate = slate
	if old:
		_stow(old)
	_set_hint("")
	_refresh()
	return true

## Takes a box's Slate back into the inventory.
func take(slot: BenchSlot) -> void:
	if slot.slate == null:
		return
	if not GameState.add_to_inventory(slot.slate):
		_set_hint("No room in your inventory.")
		return
	slot.slate = null
	_set_hint("")
	_refresh()

## Inventory first, then the stash's Slate tab, then any stash tab.
func _stow(slate: Slate) -> void:
	if GameState.add_to_inventory(slate):
		return
	var slate_tab := GameState.stash.get_tab(GridInventory.Accepts.SLATE)
	if slate_tab and slate_tab.add(slate) == 0:
		return
	for tab in GameState.stash.tabs:
		if tab.add(slate) == 0:
			return
	push_warning("SlateBenchScreen: nowhere to put %s" % slate.display_name)

func _refresh() -> void:
	_inventory_view.refresh()
	_gold.text = "Your Gold: %d" % GameState.gold
	var error := craft_error()
	_craft_button.text = "%s (%d Gold)" % ["Split" if mode == Mode.SPLIT else "Recombine", cost()]
	_craft_button.disabled = error != ""
	_craft_button.tooltip_text = error
	for slot in _inputs + _outputs:
		slot.refresh_caption()

## ---- UI -----------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	_title = _label("", 26, AetherStyle.GOLD_BRIGHT)
	_title.add_theme_font_override("font", AetherStyle.title())
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title)
	_gold = _label("", 16, AetherStyle.GOLD)
	_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_gold)
	_notice = _label("", 14, AetherStyle.TEXT_DIM)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size = Vector2(760, 0)
	root.add_child(_notice)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	root.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 18)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.custom_minimum_size = Vector2(540, 0)
	columns.add_child(left)
	_bench = HBoxContainer.new()
	_bench.alignment = BoxContainer.ALIGNMENT_CENTER
	_bench.add_theme_constant_override("separation", 14)
	left.add_child(_bench)
	_craft_button = Button.new()
	_craft_button.custom_minimum_size = Vector2(260, 46)
	_craft_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_craft_button.add_theme_font_size_override("font_size", 19)
	_craft_button.pressed.connect(craft)
	left.add_child(_craft_button)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)
	right.add_child(_label("Your inventory - right-click a Slate to place it", 15, AetherStyle.TEXT))
	_inventory_view = InventoryGridView.new()
	_inventory_view.cell_size = CELL
	_inventory_view.allow_drop = true
	_inventory_view.entry_right_clicked.connect(func(_v, entry: GridInventory.Entry):
		if entry.content is Slate:
			place(entry.content)
		else:
			_set_hint("Only Slates go on the bench."))
	_inventory_view.entry_hovered.connect(func(_v, entry: GridInventory.Entry):
		_set_hint("Right-click or drag to place it" if entry.content is Slate else ""))
	right.add_child(_inventory_view)

	_hint = _label("", 15, AetherStyle.TEXT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.custom_minimum_size = Vector2(0, 22)
	root.add_child(_hint)
	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	root.add_child(close_button)
	AetherStyle.wrap_in_plate(root, 24)

## Recombine: [in] + [in] -> [out]. Split: [in] -> [out] [out].
func _build_bench() -> void:
	for child in _bench.get_children():
		child.queue_free()
	_inputs.clear()
	_outputs.clear()
	var in_count := 1 if mode == Mode.SPLIT else 2
	var out_count := 2 if mode == Mode.SPLIT else 1
	for i in in_count:
		if i > 0:
			_bench.add_child(_glyph("+"))
		_inputs.append(_add_slot(false, i))
	_bench.add_child(_glyph("→"))
	for i in out_count:
		_outputs.append(_add_slot(true, i))

func _add_slot(output: bool, index: int) -> BenchSlot:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var slot := BenchSlot.new()
	slot.bench = self
	slot.is_output = output
	slot.index = index
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	AetherStyle.style_slot_button(slot, AetherStyle.GOLD if output else AetherStyle.TEXT_DIM)
	column.add_child(slot)
	slot.caption = _label("", 13, AetherStyle.TEXT_DIM)
	slot.caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.caption.custom_minimum_size = Vector2(SLOT_SIZE, 0)
	slot.caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(slot.caption)
	_bench.add_child(column)
	return slot

func _glyph(text: String) -> Label:
	var label := _label(text, 34, AetherStyle.GOLD)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label

func _set_hint(text: String) -> void:
	_hint.text = text

func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label

## One box on the bench: shows its Slate (with the card on hover), takes
## Slates dragged from the inventory (inputs only), and gives its Slate back
## when clicked.
class BenchSlot extends ItemSlotButton:
	var bench: SlateBenchScreen
	var is_output := false
	var index := 0
	var caption: Label

	func _init() -> void:
		tooltip_text = " "
		focus_mode = Control.FOCUS_NONE
		pressed.connect(func(): bench.take(self))

	func refresh_caption() -> void:
		if slate:
			caption.text = slate.display_name
			caption.add_theme_color_override("font_color", Constants.SLATE_RARITY_COLOR.get(slate.rarity, Color.WHITE))
		else:
			caption.text = "Result" if is_output else "Slate"
			caption.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
			bench.take(self)
			accept_event()

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return not is_output and data is Dictionary and data.has("grid_entry") \
			and (data["grid_entry"] as GridInventory.Entry).content is Slate

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		bench.place((data["grid_entry"] as GridInventory.Entry).content, index)
