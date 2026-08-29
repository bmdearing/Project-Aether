extends Button
class_name ItemSlotButton
## Attaches a rich ItemCard.tscn hover tooltip to a Button in place of
## Godot's plain-text one. _make_custom_tooltip() is Godot's own hook for
## this - return a Control and the engine handles positioning/hover-delay/
## auto-hide itself, so there's no custom mouse-follow logic here. Godot
## only invokes this at all when tooltip_text is non-empty, so callers
## still need to set that (any non-empty placeholder works - the text
## itself is ignored once item/slate is set).
##
## Used by both InventoryScreen (grid + paper-doll slots) and
## FateBoardEditor (Slate palette) - set exactly one of `item`/`slate` per
## button; the other stays null. Neither set means "empty slot," which
## falls through to Godot's default plain-text tooltip (or none, if
## tooltip_text is also empty).

const ITEM_CARD_SCENE := preload("res://ui/item_card/ItemCard.tscn")

var item: Item
var slate: Slate

func _make_custom_tooltip(_for_text: String) -> Object:
	if item == null and slate == null:
		return null
	var card: ItemCard = ITEM_CARD_SCENE.instantiate()
	if item:
		card.display_item(item)
	else:
		card.display_slate(slate)
	return card
