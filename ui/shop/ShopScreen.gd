extends CanvasLayer
class_name ShopScreen
## Generic purchase-list screen shared by the Hub's GearShop (real Gold
## cost) and SpellTestShop (every ability, free, testing-only) - both
## interactables populate this via open_with() rather than each building
## its own list UI.
##
## Unlike Inventory/Abilities/Character/Map, this isn't a hotkey screen -
## only reachable by walking up to a shop interactable and pressing
## `interact` (E), same as the Map Device.

@onready var title_label: Label = $CenterContainer/VBox/TitleLabel
@onready var gold_label: Label = $CenterContainer/VBox/GoldLabel
@onready var list: VBoxContainer = $CenterContainer/VBox/Scroll/List
@onready var action_button: Button = $CenterContainer/VBox/ActionButton
@onready var close_button: Button = $CenterContainer/VBox/CloseButton

var _is_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("shop_screen")
	add_to_group("blocking_menu")
	close_button.pressed.connect(close)

func is_open() -> bool:
	return _is_open

## entries: Array[Dictionary], each {label, cost (0 = free), color, on_buy,
## item/ability (optional, for the ItemCard hover tooltip), repeatable
## (optional, default false - Patch v3.8c: Brand Shop's unlimited-quantity
## rows stay buyable after a purchase instead of permanently disabling,
## unlike GearShop's one-of-each rolled stock)}. action (optional): {label,
## cost, on_action} - a single button above the list for something that
## isn't "buy an item" (GearShop's "Reroll Stock").
func open_with(title: String, entries: Array, action: Dictionary = {}) -> void:
	title_label.text = title
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_list(entries)
	_build_action(action)
	_refresh_gold_label()

func close() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _build_list(entries: Array) -> void:
	for child in list.get_children():
		child.queue_free()
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Nothing here right now."
		list.add_child(empty_label)
		return
	for entry in entries:
		list.add_child(_build_row(entry))

func _build_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon := ItemSlotButton.new()
	icon.custom_minimum_size = Vector2(220, 40)
	icon.clip_text = true
	icon.text = entry.get("label", "")
	icon.tooltip_text = entry.get("label", " ")  # non-empty so the ItemCard hover hook actually fires (see ItemSlotButton._make_custom_tooltip)
	if entry.get("item"):
		icon.item = entry["item"]
	elif entry.get("ability"):
		icon.ability = entry["ability"]
	var box := StyleBoxFlat.new()
	box.bg_color = entry.get("color", Color.WHITE)
	box.set_corner_radius_all(4)
	icon.add_theme_stylebox_override("normal", box)
	icon.add_theme_stylebox_override("hover", box)
	icon.add_theme_stylebox_override("pressed", box)
	var text_color := Constants.get_contrasting_text_color(box.bg_color)
	icon.add_theme_color_override("font_color", text_color)
	icon.add_theme_color_override("font_hover_color", text_color)
	icon.add_theme_color_override("font_pressed_color", text_color)
	row.add_child(icon)

	var cost: int = entry.get("cost", 0)
	var cost_label := Label.new()
	cost_label.text = "Free" if cost <= 0 else "%d Gold" % cost
	cost_label.custom_minimum_size = Vector2(90, 0)
	row.add_child(cost_label)

	var buy_button := Button.new()
	buy_button.text = entry.get("button_label", "Take" if cost <= 0 else "Buy")
	buy_button.pressed.connect(_on_buy_pressed.bind(entry, buy_button, cost_label))
	row.add_child(buy_button)

	return row

func _on_buy_pressed(entry: Dictionary, buy_button: Button, cost_label: Label) -> void:
	var cost: int = entry.get("cost", 0)
	if cost > 0 and GameState.gold < cost:
		cost_label.text = "Need %d Gold" % cost
		return
	if cost > 0:
		GameState.gold -= cost
	var on_buy: Callable = entry.get("on_buy", Callable())
	if on_buy.is_valid():
		on_buy.call()
	_refresh_gold_label()
	if not entry.get("repeatable", false):
		buy_button.disabled = true
		buy_button.text = "Bought" if cost > 0 else "Taken"

func _refresh_gold_label() -> void:
	gold_label.text = "Your Gold: %d" % GameState.gold

func _build_action(action: Dictionary) -> void:
	if action_button.pressed.is_connected(_on_action_pressed):
		action_button.pressed.disconnect(_on_action_pressed)
	if action.is_empty():
		action_button.visible = false
		return
	action_button.visible = true
	var cost: int = action.get("cost", 0)
	var label: String = action.get("label", "Action")
	action_button.text = "%s (%d Gold)" % [label, cost] if cost > 0 else label
	action_button.pressed.connect(_on_action_pressed.bind(action))

func _on_action_pressed(action: Dictionary) -> void:
	var cost: int = action.get("cost", 0)
	if cost > 0 and GameState.gold < cost:
		return
	if cost > 0:
		GameState.gold -= cost
	var on_action: Callable = action.get("on_action", Callable())
	if on_action.is_valid():
		on_action.call()
	_refresh_gold_label()
