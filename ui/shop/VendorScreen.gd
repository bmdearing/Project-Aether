extends CanvasLayer
class_name VendorScreen
## The standard NPC shop: the vendor's stock as a grid on the left, your
## inventory on the right. Right-click stock to buy it, right-click your
## items to sell them. What you sell goes into the stock at the price you
## got (buyback) until the shop closes. Nothing can be dragged between the
## two grids.
##
## A vendor opens it with VendorScreen.open_for(tree, config). config:
##   title: String
##   stock: GridInventory - the vendor's goods, kept by the vendor between visits
##   buy_price: Callable(content) -> int - Gold to buy one
##   sell_price: Callable(content) -> int - Gold paid for it; 0 = won't buy it
##   on_bought: Callable(content) (optional) - after a purchase
##   action: {label, cost, on_action} (optional) - one button under the stock (e.g. Reroll)
##   notice: String (optional) - a line under the Gold total

const STOCK_CELL := 36

var config: Dictionary = {}
var _is_open := false
var _title: Label
var _gold: Label
var _notice: Label
var _hint: Label
var _stock_view: InventoryGridView
var _inventory_view: InventoryGridView
var _action_button: Button
## Sold this visit: content -> the price it sold for (its buyback price).
var _buyback: Dictionary = {}

## The scene's VendorScreen, created on first use.
static func open_for(tree: SceneTree, p_config: Dictionary) -> VendorScreen:
	var screen := tree.get_first_node_in_group("vendor_screen") as VendorScreen
	if screen == null:
		screen = VendorScreen.new()
		tree.current_scene.add_child(screen)
	screen.open_with(p_config)
	return screen

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("vendor_screen")
	add_to_group("blocking_menu")
	_build()

func is_open() -> bool:
	return _is_open

func open() -> void:
	if not config.is_empty():
		open_with(config)

func open_with(p_config: Dictionary) -> void:
	config = p_config
	_buyback.clear()
	_title.text = config.get("title", "Shop")
	_stock_view.set_inventory(config["stock"])
	_inventory_view.set_inventory(GameState.inventory)
	set_notice(config.get("notice", ""))
	_set_hint("")
	_build_action()
	_refresh_gold()
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	# Unsold buyback leaves with the vendor.
	var stock: GridInventory = config.get("stock")
	if stock:
		for content in _buyback:
			stock.remove_content(content)
	_buyback.clear()
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func set_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = text != ""

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

## ---- Prices ---------------------------------------------------------------

func price_to_buy(content) -> int:
	if _buyback.has(content):
		return _buyback[content]
	var price: Callable = config.get("buy_price", Callable())
	return price.call(content) if price.is_valid() else 0

func price_to_sell(content) -> int:
	if content is Item and (content as Item).mark == Item.Mark.FAVORED:
		return 0
	var price: Callable = config.get("sell_price", Callable())
	return price.call(content) if price.is_valid() else 0

## ---- Buying and selling ---------------------------------------------------

func buy(entry: GridInventory.Entry) -> bool:
	var stock: GridInventory = config["stock"]
	var content = entry.content
	var price := price_to_buy(content)
	if GameState.gold < price:
		_set_hint("Need %d Gold" % price)
		return false
	if entry.is_currency():
		if not GameState.add_to_inventory(content, 1):
			_set_hint("No room in your inventory")
			return false
		stock.remove_currency(content, 1)
	else:
		if not GameState.add_to_inventory(content):
			_set_hint("No room in your inventory")
			return false
		stock.remove(entry)
	GameState.gold -= price
	_buyback.erase(content)
	var on_bought: Callable = config.get("on_bought", Callable())
	if on_bought.is_valid():
		on_bought.call(content)
	_set_hint("Bought for %d Gold" % price)
	_after_trade()
	return true

func sell(entry: GridInventory.Entry) -> bool:
	var content = entry.content
	if entry.is_currency():
		_set_hint("The vendor doesn't buy currency")
		return false
	var price := price_to_sell(content)
	if price <= 0:
		_set_hint("Favored - unmark it to sell" if content is Item and content.mark == Item.Mark.FAVORED else "The vendor won't buy that")
		return false
	GameState.inventory.remove(entry)
	GameState.gold += price
	var stock: GridInventory = config["stock"]
	if stock.add(content) == 0:
		_buyback[content] = price
	_set_hint("Sold for %d Gold" % price)
	_after_trade()
	return true

func _after_trade() -> void:
	_stock_view.refresh()
	_inventory_view.refresh()
	_refresh_gold()

## ---- UI -------------------------------------------------------------------

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

	_title = _label("Shop", 24, AetherStyle.GOLD_BRIGHT)
	_title.add_theme_font_override("font", AetherStyle.title())
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title)
	_gold = _label("", 16, AetherStyle.GOLD)
	_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_gold)
	_notice = _label("", 14, AetherStyle.GOLD)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_notice)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	root.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)
	left.add_child(_label("For sale - right-click to buy", 15, AetherStyle.TEXT))
	_stock_view = InventoryGridView.new()
	_stock_view.cell_size = STOCK_CELL
	_stock_view.allow_drag = false
	_stock_view.allow_drop = false
	_stock_view.price_text = func(entry: GridInventory.Entry) -> String: return "%d g" % price_to_buy(entry.content)
	_stock_view.entry_right_clicked.connect(func(_v, entry): buy(entry))
	_stock_view.entry_hovered.connect(func(_v, entry): _set_hint("Right-click to buy: %d Gold%s" % [price_to_buy(entry.content), " (buyback)" if _buyback.has(entry.content) else ""]))
	left.add_child(_stock_view)
	_action_button = Button.new()
	_action_button.visible = false
	left.add_child(_action_button)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)
	right.add_child(_label("Your inventory - right-click to sell", 15, AetherStyle.TEXT))
	_inventory_view = InventoryGridView.new()
	_inventory_view.cell_size = STOCK_CELL
	_inventory_view.allow_drop = true
	_inventory_view.entry_right_clicked.connect(func(_v, entry): sell(entry))
	_inventory_view.entry_hovered.connect(_hover_own)
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

func _hover_own(_view: InventoryGridView, entry: GridInventory.Entry) -> void:
	if entry.is_currency():
		_set_hint("The vendor doesn't buy currency")
		return
	var price := price_to_sell(entry.content)
	_set_hint("Right-click to sell: +%d Gold" % price if price > 0 else ("Favored - unmark it to sell" if entry.content is Item and entry.content.mark == Item.Mark.FAVORED else "The vendor won't buy that"))

func _build_action() -> void:
	for c in _action_button.pressed.get_connections():
		_action_button.pressed.disconnect(c["callable"])
	var action: Dictionary = config.get("action", {})
	_action_button.visible = not action.is_empty()
	if action.is_empty():
		return
	var cost: int = action.get("cost", 0)
	_action_button.text = "%s (%d Gold)" % [action.get("label", "Action"), cost] if cost > 0 else action.get("label", "Action")
	_action_button.pressed.connect(func():
		if GameState.gold < cost:
			_set_hint("Need %d Gold" % cost)
			return
		GameState.gold -= cost
		var on_action: Callable = action.get("on_action", Callable())
		if on_action.is_valid():
			on_action.call()
		_stock_view.refresh()
		_refresh_gold())

func _refresh_gold() -> void:
	_gold.text = "Your Gold: %d" % GameState.gold

func _set_hint(text: String) -> void:
	_hint.text = text

func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label
