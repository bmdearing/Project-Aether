extends CanvasLayer
class_name MapScreen
## M: the whole current Map seen from above (MapView), with fog over the
## cells you haven't been to yet, markers, and a side panel with the area,
## its level and mods and what's left to find. Hub and test scenes have no
## generated Map, so it says so there. Dispatched from PauseMenu.gd like the
## other screens.

const LEGEND := [
	["You", Color.WHITE],
	["Monster", MapView.ENEMY_COLOR],
	["Boss / Vault", MapView.VAULT_COLOR],
	["Portal", MapView.PORTAL_COLOR],
	["Chest", MapView.CHEST_COLOR],
	["Start", MapView.START_COLOR],
]

@onready var view: MapView = $CenterContainer/VBox/Body/MapPanel/MapView
@onready var no_data_label: Label = $CenterContainer/VBox/Body/MapPanel/NoDataLabel
@onready var close_button: Button = $CenterContainer/VBox/Footer/CloseButton
@onready var centre_button: Button = $CenterContainer/VBox/Footer/CentreButton
@onready var info: VBoxContainer = $CenterContainer/VBox/Body/Info
@onready var title_label: Label = $CenterContainer/VBox/TitleLabel

var _is_open: bool = false
## Cells the player has stood in this visit; the rest stay under fog.
var explored: Dictionary = {}

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER  # above the HUD
	AetherStyle.style_screen(self)
	($CenterContainer/VBox/Footer/HintLabel as Label).add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	AetherStyle.wrap_in_plate($CenterContainer/VBox, 24)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("map_screen")
	add_to_group("blocking_menu")
	close_button.pressed.connect(close)
	centre_button.pressed.connect(func(): view.centre_on_player())

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func close() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	var map := _map()
	if map == null or map.graph == null:
		return
	if _is_open:
		view.queue_redraw()
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var cell := Vector2i(roundi(player.global_position.x / map.cell_size), roundi(player.global_position.z / map.cell_size))
	if map.graph.rooms.has(cell):
		explored[cell] = true

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_SPACE:
		view.centre_on_player()
		get_viewport().set_input_as_handled()

func _map() -> GeneratedMap:
	var node: Node = self
	while node:
		if node is GeneratedMap:
			return node
		node = node.get_parent()
	return get_tree().current_scene as GeneratedMap

func _refresh() -> void:
	var map := _map()
	var has_data := map != null and map.graph != null
	view.visible = has_data
	no_data_label.visible = not has_data
	centre_button.disabled = not has_data
	for child in info.get_children():
		info.remove_child(child)
		child.queue_free()
	if not has_data:
		title_label.text = "Map"
		return
	view.setup(map, explored)
	_build_info(map)

func _build_info(map: GeneratedMap) -> void:
	var figment := GameState.active_map
	title_label.text = map.tileset.display_name if map.tileset and map.tileset.display_name != "" else "Map"
	if figment:
		_line("%s  -  Area Level %d" % ["Depth %d" % figment.depth if figment.is_levelling() else "Tier %d" % figment.tier, figment.area_level()], AetherStyle.GOLD)
	var living := map.get_living_enemy_count()
	_line("Monsters left: %d of %d" % [living, map.get_total_enemy_count()])
	var chests := get_tree().get_nodes_in_group("treasure_chest")
	var unopened := chests.filter(func(c): return not c.is_opened()).size()
	_line("Chests unopened: %d of %d" % [unopened, chests.size()])
	_line("Explored: %d of %d areas" % [explored.size(), map.graph.rooms.size()])
	if figment and not figment.affixes.is_empty():
		info.add_child(AetherStyle.section_header("Modifiers"))
		for affix in figment.affixes:
			var text: String = affix.description if affix.description != "" else FigmentMods.describe(affix.stat_key, affix.value, affix.damage_type)
			_line(text, AetherStyle.MOD_BLUE)
	info.add_child(AetherStyle.section_header("Legend"))
	for entry in LEGEND:
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = entry[1]
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var label := Label.new()
		label.text = "  " + String(entry[0])
		row.add_child(label)
		info.add_child(row)

func _line(text: String, color: Color = AetherStyle.TEXT) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 250
	label.add_theme_color_override("font_color", color)
	info.add_child(label)
