extends CanvasLayer
class_name MenuTabStrip
## The overall menu's tab strip: shown across the top while any of the main
## screens (Inventory, Character, Spells, Fate Board, Map, Figment Tree) is open. Click a
## tab to switch; Tab / Shift+Tab cycle (PauseMenu handles the key).

signal tab_chosen(index: int)

## [group, label, open action] per screen, in cycling order.
const SCREENS := [
	["inventory_screen", "Inventory", "open_inventory"],
	["character_screen", "Character", "open_character"],
	["abilities_screen", "Spells", "open_abilities"],
	["fate_board_editor", "Fate Board", "open_fate_board"],
	["map_screen", "Map", "open_map"],
	["figment_tree_screen", "Figment Tree", "open_figment_tree"],
]

var _buttons: Array[Button] = []
var _row: HBoxContainer

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER + 1
	AetherStyle.style_screen(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	holder.offset_bottom = 30
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 2)
	holder.add_child(_row)
	var hint := Label.new()
	hint.text = "Tab "
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	_row.add_child(hint)
	for i in SCREENS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size = Vector2(104, 26)
		b.pressed.connect(func(): tab_chosen.emit(i))
		_row.add_child(b)
		_buttons.append(b)

## Index of the open screen in SCREENS, or -1.
static func open_index(tree: SceneTree) -> int:
	for i in SCREENS.size():
		var screen := tree.get_first_node_in_group(SCREENS[i][0])
		# The inventory counts only while its grid half is up; its sheet half
		# is the Character tab.
		if screen and (screen.is_showing_items() if screen is InventoryScreen else screen.is_open()):
			return i
	return -1

func _process(_delta: float) -> void:
	var active := open_index(get_tree())
	visible = active >= 0
	if not visible:
		return
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == active)
		_buttons[i].text = "%s (%s)" % [SCREENS[i][1], key_name(SCREENS[i][2])]

## The key bound to an action, as a label ("K").
static func key_name(action: String) -> String:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key:
			return OS.get_keycode_string(key.keycode if key.keycode != KEY_NONE else key.physical_keycode)
	return "-"
