extends Button
class_name ItemSlotButton
## Rich ItemCard hover tooltip via Godot's _make_custom_tooltip() hook
## (positioning/delay/auto-hide all native). Holding Alt while hovered
## instead opens AdvancedTooltip - a real popup with tier ranges and
## clickable stat glossary links that doesn't auto-hide.
##
## Used by InventoryScreen, FateBoardEditor, AbilitiesScreen, ShopScreen -
## set exactly one of item/slate/ability per button.
##
## Setting `item` to one with a real `icon_path` shows that icon as a
## child TextureRect (drawn on top of the button's own background/text,
## same as any real ARPG's icon-only inventory slot - the name is still
## available via the hover tooltip). Items with no icon yet (icon_path
## empty) fall back to exactly the old colored-square-plus-text look.

const ITEM_CARD_SCENE := preload("res://ui/item_card/ItemCard.tscn")

var item: Item:
	set(value):
		item = value
		_refresh_icon()
var slate: Slate
var ability: Ability

var _is_hovered: bool = false
var _icon_rect: TextureRect

func _ready() -> void:
	mouse_entered.connect(func(): _is_hovered = true)
	mouse_exited.connect(func(): _is_hovered = false)
	_icon_rect = TextureRect.new()
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.visible = false
	add_child(_icon_rect)
	_refresh_icon()

func _refresh_icon() -> void:
	if _icon_rect == null:
		return
	if item and item.icon_path != "":
		_icon_rect.texture = load(item.icon_path)
		_icon_rect.visible = true
	else:
		_icon_rect.visible = false

func _input(event: InputEvent) -> void:
	if not _is_hovered or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_ALT and key_event.pressed and not key_event.echo:
		_show_advanced()

func _show_advanced() -> void:
	var pos := get_global_mouse_position() + Vector2(16, 16)
	if item:
		AdvancedTooltip.show_for_item(item, pos)
	elif slate:
		AdvancedTooltip.show_for_slate(slate, pos)
	elif ability:
		var player := get_tree().get_first_node_in_group("player") as Player
		AdvancedTooltip.show_for_ability(ability, player.stat_sheet if player else null, pos)

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
