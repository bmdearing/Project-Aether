extends Button
class_name ItemSlotButton
## Slot button with an ItemCard hover tooltip (_make_custom_tooltip()).
## Holding Alt swaps the card to Alt Info in place. Set exactly one of
## item/slate/ability.
##
## The item, slate or ability draws as an ItemIcon: filling the button when it has no
## text, or in a square at its left edge beside the text. ghost_key draws a
## faint silhouette while the slot is empty.
##
## `draggable` enables drag-and-drop between slots, emitting
## item_drag_dropped(source_index, target_index) by child index.

const ITEM_CARD_SCENE := preload("res://ui/item_card/ItemCard.tscn")

signal item_drag_dropped(source_index: int, target_index: int)

var item: Item:
	set(value):
		item = value
		_refresh_icon()
var slate: Slate:
	set(value):
		slate = value
		_refresh_icon()
var ability: Ability:
	set(value):
		ability = value
		_refresh_icon()
var draggable: bool = false
## false for invisible tooltip-only buttons laid over custom-drawn widgets.
var show_icon: bool = true:
	set(value):
		show_icon = value
		_refresh_icon()
## Item type drawn as a faint silhouette while the slot is empty.
var ghost_key: StringName = &"":
	set(value):
		ghost_key = value
		_refresh_icon()

var _is_hovered: bool = false
var _icon: ItemIcon
var _sockets: SocketOverlay
static var _spacers: Dictionary = {}

func _ready() -> void:
	mouse_entered.connect(func(): _is_hovered = true)
	mouse_exited.connect(func(): _is_hovered = false)
	_icon = ItemIcon.fill(self)
	_sockets = SocketOverlay.new()
	add_child(_sockets)
	resized.connect(_refresh_icon)
	_refresh_icon()

func _refresh_icon() -> void:
	if _icon == null:
		return
	_sockets.item = item if show_icon else null
	var content = null
	if show_icon:
		content = item if item else (slate if slate else ability)
	_icon.content = content
	_icon.ghost_key = ghost_key if show_icon else &""
	var beside_text := content != null and text != ""
	icon = _placeholder() if beside_text else null
	if beside_text:
		var side := float(icon.get_width())
		_icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_icon.position = Vector2(4, (size.y - side) * 0.5)
		_icon.size = Vector2(side, side)
	else:
		_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## A transparent square that reserves room at the left so Button lays its
## text out after the drawn icon. Sized from the minimum height, never the
## current one, so it can't grow the button it sits in.
func _placeholder() -> Texture2D:
	var side := clampi(int(custom_minimum_size.y) - 8, 24, 48) if custom_minimum_size.y > 0.0 else 28
	if not _spacers.has(side):
		_spacers[side] = ImageTexture.create_from_image(Image.create_empty(side, side, false, Image.FORMAT_RGBA8))
	return _spacers[side]

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
