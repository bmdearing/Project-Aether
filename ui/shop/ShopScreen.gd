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
	layer = AetherStyle.SCREEN_LAYER  # above the HUD
	AetherStyle.style_screen(self)
	AetherStyle.wrap_in_plate($CenterContainer/VBox, 24)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("shop_screen")
	add_to_group("blocking_menu")
	close_button.pressed.connect(close)

func is_open() -> bool:
	return _is_open

## entries: Array[Dictionary], each {label, cost (0 = free), color, on_buy,
## item/ability (optional, for the ItemCard hover tooltip), repeatable
## (optional, default false - unlimited-quantity
## rows stay buyable after a purchase instead of permanently disabling,
## unlike GearShop's one-of-each rolled stock)}. action (optional): {label,
## cost, on_action} - a single button above the list for something that
## isn't "buy an item" (GearShop's "Reroll Stock"). sell_entries (optional):
## [{label, price, color, item, on_sell}] - the player's own items, listed
## under a "Sell" header; on_sell returning false leaves the row unsold.
func open_with(title: String, entries: Array, action: Dictionary = {}, sell_entries: Array = []) -> void:
	title_label.text = title
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_list(entries)
	if not sell_entries.is_empty():
		_build_sell_list(sell_entries)
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

func _section_header(text: String) -> Label:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 17)
	header.add_theme_color_override("font_color", Color(0.85, 0.72, 0.4))
	return header

func _build_sell_list(sell_entries: Array) -> void:
	list.add_child(HSeparator.new())
	list.add_child(_section_header("Sell from your inventory"))
	for entry in sell_entries:
		var row := _build_row(entry)
		var price: int = entry.get("price", 0)
		var price_label: Label = row.get_child(1)
		price_label.text = "+%d Gold" % price
		var sell_button: Button = row.get_child(2)
		sell_button.text = "Sell"
		for c in sell_button.pressed.get_connections():
			sell_button.pressed.disconnect(c["callable"])
		sell_button.pressed.connect(_on_sell_pressed.bind(entry, sell_button, price_label))
		list.add_child(row)

func _on_sell_pressed(entry: Dictionary, sell_button: Button, price_label: Label) -> void:
	if sell_button.disabled:
		return
	var on_sell: Callable = entry.get("on_sell", Callable())
	if on_sell.is_valid() and on_sell.call() == false:
		price_label.text = "Can't sell"
		return
	GameState.gold += entry.get("price", 0)
	sell_button.disabled = true
	sell_button.text = "Sold"
	_refresh_gold_label()

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
	var accent: Color = entry.get("color", AetherStyle.GOLD)
	AetherStyle.style_slot_button(icon, accent)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		icon.add_theme_color_override(state, accent.lerp(Color.WHITE, 0.3))
	row.add_child(icon)

	var cost: int = entry.get("cost", 0)
	var cost_label := Label.new()
	cost_label.text = entry.get("cost_text", "Free" if cost <= 0 else "%d Gold" % cost)
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
	# An on_buy that returns false (e.g. no inventory room) is refunded.
	if on_buy.is_valid() and on_buy.call() == false:
		GameState.gold += cost
		cost_label.text = entry.get("fail_text", "No room")
		_refresh_gold_label()
		return
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
