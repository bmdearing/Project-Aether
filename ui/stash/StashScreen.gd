extends CanvasLayer
class_name StashScreen
## Hub stash: carried inventory on the left, stash tabs on the right. Drag
## between them, or right-click an entry to send it to the other side.
## Doesn't pause the game.

const CELL := 44

var _is_open := false
var _active_tab := 0
var _carried_view: InventoryGridView
var _stash_view: InventoryGridView
var _tab_bar: HBoxContainer
var _status: Label

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER  # above the HUD
	AetherStyle.style_screen(self)
	visible = false
	add_to_group("stash_screen")
	add_to_group("blocking_menu")
	_build()

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = ""
	_refresh()

func close() -> void:
	_is_open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	root.add_child(columns)

	var left := VBoxContainer.new()
	columns.add_child(left)
	left.add_child(_label("Inventory", 20))
	_carried_view = _make_view()
	left.add_child(_carried_view)

	var right := VBoxContainer.new()
	columns.add_child(right)
	right.add_child(_label("Stash", 20))
	_tab_bar = HBoxContainer.new()
	right.add_child(_tab_bar)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(Constants.STASH_TAB_SIZE.x * CELL + 14, 10 * CELL)
	right.add_child(scroll)
	_stash_view = _make_view()
	scroll.add_child(_stash_view)

	_status = _label("", 14)
	root.add_child(_status)
	var hint := _label("Drag to move items. Right-click sends an item to the other side. E or Esc closes.", 12)
	hint.modulate = Color(1, 1, 1, 0.6)
	root.add_child(hint)

func _make_view() -> InventoryGridView:
	var view := InventoryGridView.new()
	view.cell_size = CELL
	view.drop_failed.connect(func(): _status.text = "That doesn't fit there.")
	view.changed.connect(func(): _status.text = "")
	view.entry_right_clicked.connect(_on_entry_right_clicked)
	return view

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l

func _refresh() -> void:
	_carried_view.set_inventory(GameState.inventory)
	var tabs := GameState.stash.tabs
	_active_tab = clampi(_active_tab, 0, tabs.size() - 1)
	for child in _tab_bar.get_children():
		child.queue_free()
	for i in tabs.size():
		var b := Button.new()
		b.text = _tab_name(tabs[i], i)
		b.disabled = i == _active_tab
		b.pressed.connect(_select_tab.bind(i))
		_tab_bar.add_child(b)
	_stash_view.set_inventory(tabs[_active_tab])

func _tab_name(tab: GridInventory, index: int) -> String:
	match tab.accepts:
		GridInventory.Accepts.CURRENCY:
			return "Currency"
		GridInventory.Accepts.SLATE:
			return "Slates"
	return "Tab %d" % (index + 1)

func _select_tab(index: int) -> void:
	_active_tab = index
	_refresh()

func _on_entry_right_clicked(view: InventoryGridView, entry: GridInventory.Entry) -> void:
	var from := view.inventory
	var to: GridInventory = GameState.stash.tabs[_active_tab] if view == _carried_view else GameState.inventory
	if view == _carried_view and not to.accepts_content(entry.content):
		to = _first_tab_accepting(entry.content)
	if to == null or not send(from, entry, to):
		_status.text = "No room for that."
	_refresh()

## Moves an entry into the first free space of another grid. Currency
## stacks move as much as fits.
static func send(from: GridInventory, entry: GridInventory.Entry, to: GridInventory) -> bool:
	var leftover := to.add(entry.content, entry.count)
	if leftover == entry.count:
		return false
	entry.count = leftover
	if entry.count == 0:
		from.remove(entry)
	return true

func _first_tab_accepting(content) -> GridInventory:
	for tab in GameState.stash.tabs:
		if tab.accepts_content(content) and tab.find_space(GridInventory.footprint_of(content)) != GridInventory.NO_SPACE:
			return tab
	return null
