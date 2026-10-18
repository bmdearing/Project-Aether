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
	# A dark band across the top with a gold rule under it; screens start
	# below AetherStyle.MENU_TOP.
	var band := Bar.new()
	band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = AetherStyle.MENU_TOP - 10
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(holder)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	holder.add_child(_row)
	var hint := AetherStyle.key_badge("Tab")
	hint.tooltip_text = "Tab / Shift+Tab cycles the screens"
	_row.add_child(hint)
	_row.add_child(Control.new())
	for i in SCREENS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 36)
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

class Bar extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), AetherStyle.GLASS_SOLID)
		draw_line(Vector2(0, size.y), Vector2(size.x, size.y), AetherStyle.GOLD_DIM, 1.0)
		draw_line(Vector2(0, size.y - 3), Vector2(size.x, size.y - 3), AetherStyle.GOLD_FAINT, 1.0)
		AetherStyle.diamond(self, Vector2(size.x / 2.0, size.y), 4.0, AetherStyle.GLASS_SOLID, AetherStyle.GOLD)
