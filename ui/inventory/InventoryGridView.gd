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
const CELL_COLOR := Color(0.03, 0.035, 0.06, 0.85)
const LINE_COLOR := Color(0.55, 0.45, 0.28, 0.28)
const CURRENCY_COLOR := Color(0.62, 0.5, 0.22)

@export var cell_size: int = 36
var inventory: GridInventory
## Optional (entry) -> Color: a coloured border marks an active Brand or the
## currency waiting to be used. Transparent = no border.
var highlight: Callable
## Optional (entry) -> String: usage hint at the bottom of a currency tooltip.
var currency_hint: Callable
var _blocks: Dictionary = {}  # GridInventory.Entry -> EntryBlock

func set_inventory(inv: GridInventory) -> void:
	inventory = inv
	refresh()

## Updates the blocks in place: an entry that's still there keeps its block
## (restyled, moved, new icon/count), so the one under the cursor keeps its
## hover and tooltip through a craft instead of being torn down and rebuilt.
func refresh() -> void:
	if inventory == null:
		for block in _blocks.values():
			block.queue_free()
		_blocks.clear()
		return
	custom_minimum_size = Vector2(inventory.width, inventory.height) * cell_size
	var live := {}
	for entry in inventory.get_entries():
		var block: EntryBlock = _blocks.get(entry)
		if block == null or not is_instance_valid(block):
			block = _make_block(entry)
			add_child(block)
			_blocks[entry] = block
		else:
			_update_block(block)
		live[entry] = true
	for entry in _blocks.keys():
		if not live.has(entry):
			_blocks[entry].queue_free()
			_blocks.erase(entry)
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
	block.item_icon = ItemIcon.fill(block)
	block.socket_overlay = SocketOverlay.new()
	block.add_child(block.socket_overlay)
	block.pressed.connect(func(): entry_clicked.emit(self, entry))
	block.mouse_entered.connect(func(): entry_hovered.emit(self, entry))
	_update_block(block)
	return block

func _update_block(block: EntryBlock) -> void:
	var entry := block.entry
	block.position = Vector2(entry.position) * cell_size + Vector2.ONE
	block.size = Vector2(entry.size) * cell_size - Vector2(2, 2)
	block.tooltip_text = describe(entry)
	var border: Color = highlight.call(entry) if highlight.is_valid() else Color.TRANSPARENT
	_style(block, _color_for(entry), border)
	block.item_icon.content = entry.content
	block.item_icon.count = entry.count
	block.socket_overlay.item = entry.content if not entry.is_currency() and entry.content is Item else null

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

func _color_for(entry: GridInventory.Entry) -> Color:
	if entry.is_currency():
		return CURRENCY_COLOR
	if entry.content is Slate:
		return Constants.SLATE_RARITY_COLOR.get(entry.content.rarity, Color.GRAY)
	return Constants.ITEM_RARITY_COLOR.get(entry.content.rarity, Color.GRAY)

func _style(button: Button, color: Color, border: Color = Color.TRANSPARENT) -> void:
	# Dark glass with the rarity as the border; a highlight (active Brand,
	# picked-up currency) takes over the border and thickens it.
	AetherStyle.style_slot_button(button, color)
	if border.a > 0.0:
		for state in ["normal", "hover", "pressed"]:
			var box := AetherStyle.slot_box(border, state != "normal")
			box.set_border_width_all(3)
			button.add_theme_stylebox_override(state, box)

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
	var item_icon: ItemIcon
	var socket_overlay: SocketOverlay

	func _get_drag_data(at_position: Vector2) -> Variant:
		var preview := ItemIcon.new()
		preview.content = entry.content
		preview.count = entry.count
		preview.modulate.a = 0.8
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
