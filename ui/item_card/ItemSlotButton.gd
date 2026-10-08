extends Button
class_name ItemSlotButton
## Slot button with an ItemCard hover tooltip (_make_custom_tooltip()).
## Holding Alt swaps the card to Alt Info in place. Set exactly one of
## item/slate/ability.
##
## Items with an icon_path show the icon; others fall back to a colored
## square with text.
##
## `draggable` enables drag-and-drop between slots, emitting
## item_drag_dropped(source_index, target_index) by child index.

const ITEM_CARD_SCENE := preload("res://ui/item_card/ItemCard.tscn")

signal item_drag_dropped(source_index: int, target_index: int)

var item: Item:
	set(value):
		item = value
		_refresh_icon()
var slate: Slate
var ability: Ability
var draggable: bool = false
## false for invisible tooltip-only buttons laid over custom-drawn widgets.
var show_icon: bool = true:
	set(value):
		show_icon = value
		_refresh_icon()

var _is_hovered: bool = false
var _icon_rect: TextureRect
var _sockets: SocketOverlay

func _ready() -> void:
	mouse_entered.connect(func(): _is_hovered = true)
	mouse_exited.connect(func(): _is_hovered = false)
	_icon_rect = TextureRect.new()
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.visible = false
	add_child(_icon_rect)
	_sockets = SocketOverlay.new()
	add_child(_sockets)
	_refresh_icon()

func _refresh_icon() -> void:
	if _icon_rect == null:
		return
	_sockets.item = item if show_icon else null
	if show_icon and item and item.icon_path != "":
		_icon_rect.texture = load(item.icon_path)
		_icon_rect.visible = true
	else:
		_icon_rect.visible = false

## Only a slot holding an item can be dragged.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if not draggable or item == null:
		return null
	var preview := Label.new()
	preview.text = item.display_name
	preview.add_theme_color_override("font_color", Constants.get_contrasting_text_color(Color(0.15, 0.15, 0.15)))
	var preview_box := StyleBoxFlat.new()
	preview_box.bg_color = Color(0.15, 0.15, 0.15, 0.85)
	preview_box.set_corner_radius_all(4)
	preview_box.content_margin_left = 6
	preview_box.content_margin_right = 6
	preview_box.content_margin_top = 3
	preview_box.content_margin_bottom = 3
	preview.add_theme_stylebox_override("normal", preview_box)
	set_drag_preview(preview)
	return {"source_index": get_index()}

## Empty slots accept drops too.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return draggable and data is Dictionary and data.has("source_index")

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_drag_dropped.emit(data["source_index"], get_index())

func _make_custom_tooltip(_for_text: String) -> Object:
	if item == null and slate == null and ability == null:
		return null
	var card: ItemCard = ITEM_CARD_SCENE.instantiate()
	if item:
		card.display_item(item)
	elif slate:
		card.display_slate(slate)
	else:
		var player := get_tree().get_first_node_in_group("player") as Player
		card.display_ability(ability, player.stat_sheet if player else null)
	return card
