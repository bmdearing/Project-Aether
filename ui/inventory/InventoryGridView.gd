extends Control
class_name InventoryGridView
## Draws one GridInventory: the cells plus one button per entry sized to its
## footprint. Supports drag and drop within and between views; hovering an
## item or Slate shows its ItemCard.

signal changed
signal entry_clicked(view: InventoryGridView, entry: GridInventory.Entry)
signal entry_right_clicked(view: InventoryGridView, entry: GridInventory.Entry)
signal entry_hovered(view: InventoryGridView, entry: GridInventory.Entry)
signal drop_failed

const ITEM_CARD_SCENE := preload("res://ui/item_card/ItemCard.tscn")
const CELL_COLOR := Color(0.18, 0.18, 0.2)
const LINE_COLOR := Color(0.3, 0.3, 0.34)
const CURRENCY_COLOR := Color(0.62, 0.5, 0.22)

@export var cell_size: int = 36
var inventory: GridInventory
## Optional (entry) -> Color: a coloured border marks an active Brand or the
## currency waiting to be used. Transparent = no border.
var highlight: Callable
## Optional (entry) -> String: usage hint at the bottom of a currency tooltip.
var currency_hint: Callable

func set_inventory(inv: GridInventory) -> void:
	inventory = inv
	refresh()

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	if inventory == null:
		return
	custom_minimum_size = Vector2(inventory.width, inventory.height) * cell_size
	for entry in inventory.get_entries():
		add_child(_make_block(entry))
	queue_redraw()

func _draw() -> void:
	if inventory == null:
		return
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), CELL_COLOR)
	for x in inventory.width + 1:
		draw_line(Vector2(x * cell_size, 0), Vector2(x * cell_size, inventory.height * cell_size), LINE_COLOR)
	for y in inventory.height + 1:
		draw_line(Vector2(0, y * cell_size), Vector2(inventory.width * cell_size, y * cell_size), LINE_COLOR)

func _make_block(entry: GridInventory.Entry) -> EntryBlock:
	var block := EntryBlock.new()
	block.view = self
	block.entry = entry
	block.position = Vector2(entry.position) * cell_size + Vector2.ONE
	block.size = Vector2(entry.size) * cell_size - Vector2(2, 2)
	block.clip_text = true
	block.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_theme_font_size_override("font_size", 11)
	block.text = _label_for(entry)
	block.tooltip_text = describe(entry)
	var border: Color = highlight.call(entry) if highlight.is_valid() else Color.TRANSPARENT
	_style(block, _color_for(entry), border)
	if not entry.is_currency() and entry.content is Item and entry.content.icon_path != "":
		var icon := TextureRect.new()
		icon.texture = load(entry.content.icon_path)
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(icon)
		block.text = "" if entry.count <= 1 else str(entry.count)
	block.pressed.connect(func(): entry_clicked.emit(self, entry))
	block.mouse_entered.connect(func(): entry_hovered.emit(self, entry))
	return block

static func describe(entry: GridInventory.Entry) -> String:
	if entry.is_currency():
		var text := "%s x%d" % [CurrencyText.name_of(entry.content), entry.count]
		var desc := CurrencyText.description_of(entry.content)
		return text if desc == "" else "%s\n%s" % [text, desc]
	var lines: Array[String] = [entry.content.display_name]
	var t := CraftTarget.wrap(entry.content)
	if t != null:
		if t.uses_tolerance():
			lines.append("Tolerance %d/%d" % [t.get_tolerance(), entry.content.tolerance_max])
		if not t.is_slate:
			lines.append("Quality %d  Sockets %d%s" % [t.get_quality(), t.get_sockets(), " (opened)" if t.sockets_rolled() else ""])
		if t.get_active_edict() != null:
			lines.append("Edict: %s" % CurrencyText.name_of(t.get_active_edict().id))
		for a in t.get_explicits():
			lines.append(("[Anchored] " if a.anchored else "") + a.description)
	return "\n".join(lines)

func _label_for(entry: GridInventory.Entry) -> String:
	if entry.is_currency():
		return "%s\n%d" % [CurrencyText.name_of(entry.content).replace("Orb of ", ""), entry.count]
	return entry.content.display_name

func _color_for(entry: GridInventory.Entry) -> Color:
	if entry.is_currency():
		return CURRENCY_COLOR
	if entry.content is Slate:
		return Constants.SLATE_RARITY_COLOR.get(entry.content.rarity, Color.GRAY)
	return Constants.ITEM_RARITY_COLOR.get(entry.content.rarity, Color.GRAY)

func _style(button: Button, color: Color, border: Color = Color.TRANSPARENT) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = color.lightened(0.15) if state == "hover" else color
		box.set_corner_radius_all(3)
		if border.a > 0.0:
			box.border_color = border
			box.set_border_width_all(3)
		button.add_theme_stylebox_override(state, box)
	var text_color := Constants.get_contrasting_text_color(color)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, text_color)

## Top-left cell for a drag that grabbed the block at grab_offset.
func cell_for(local_pos: Vector2, grab_offset: Vector2) -> Vector2i:
	var p := local_pos - grab_offset + Vector2(cell_size, cell_size) * 0.5
	return Vector2i(floori(p.x / cell_size), floori(p.y / cell_size))

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("grid_entry")

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var source: InventoryGridView = data["view"]
	var cell := cell_for(at_position, data["grab_offset"])
	if source.inventory.transfer(data["grid_entry"], inventory, cell):
		source.refresh()
		if source != self:
			refresh()
		changed.emit()
		if source != self:
			source.changed.emit()
	else:
		drop_failed.emit()

class EntryBlock extends Button:
	var view: InventoryGridView
	var entry: GridInventory.Entry

	func _get_drag_data(at_position: Vector2) -> Variant:
		var preview := ColorRect.new()
		preview.color = Color(1, 1, 1, 0.35)
		preview.size = size
		preview.position = -at_position
		var holder := Control.new()
		holder.add_child(preview)
		set_drag_preview(holder)
		return {"grid_entry": entry, "view": view, "grab_offset": at_position}

	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		return view._can_drop_data(at_position + position, data)

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		view._drop_data(at_position + position, data)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			view.entry_right_clicked.emit(view, entry)
			accept_event()

	func _make_custom_tooltip(_for_text: String) -> Object:
		var card: ItemCard = ITEM_CARD_SCENE.instantiate()
		if entry.is_currency():
			card.display_currency(entry.content, entry.count, view.currency_hint.call(entry) if view.currency_hint.is_valid() else "")
			return card
		if entry.content is Slate:
			card.display_slate(entry.content)
		else:
			card.display_item(entry.content)
		return card
