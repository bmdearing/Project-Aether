extends Button
class_name ItemSlotButton
## Rich ItemCard hover tooltip via Godot's _make_custom_tooltip() hook
## (positioning/delay/auto-hide all native). Holding Alt while the card
## is showing swaps its OWN content to Alt Info in place (ItemCard.gd's
## own _input() listens for Alt directly) - no second popup, matching
## Patch v3.8 Section 5 ("must not spawn a second floating ItemCard").
##
## Used by InventoryScreen, FateBoardEditor, AbilitiesScreen, ShopScreen -
## set exactly one of item/slate/ability per button.
##
## Setting `item` to one with a real `icon_path` shows that icon as a
## child TextureRect (drawn on top of the button's own background/text,
## same as any real ARPG's icon-only inventory slot - the name is still
## available via the hover tooltip). Items with no icon yet (icon_path
## empty) fall back to exactly the old colored-square-plus-text look.
##
## `draggable` (opt-in, off by default - only InventoryScreen sets it)
## turns on Godot's native Control drag-and-drop: dragging one slot onto
## another emits `item_drag_dropped(source_index, target_index)` using
## each button's own index within its parent container, and the screen
## that owns the grid decides what reordering that actually means.

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

## Drag SOURCE: only a slot with a real item can be picked up (an empty
## padding slot has nothing to move). A small floating label following
## the cursor is enough feedback - matches this project's placeholder-art
## style everywhere else (a colored square is already the "icon").
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

## Drag TARGET: an empty padding slot still accepts a drop (moving an
## item past the end of the current list) - only the flag and the data
## shape matter here, not whether this particular slot has an item.
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
