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
## Used by InventoryScreen (grid + paper-doll slots), FateBoardEditor
## (Slate palette), and AbilitiesScreen (owned list + bar slots) - set
## exactly one of `item`/`slate`/`ability` per button; the rest stay null.
## None set means "empty slot," which falls through to Godot's default
## plain-text tooltip (or none, if tooltip_text is also empty).

const ITEM_CARD_SCENE := preload("res://ui/item_card/ItemCard.tscn")

var item: Item
var slate: Slate
var ability: Ability

func _make_custom_tooltip(_for_text: String) -> Object:
	if item == null and slate == null and ability == null:
		return null
	var card: ItemCard = ITEM_CARD_SCENE.instantiate()
	if item:
		card.display_item(item)
	elif slate:
		card.display_slate(slate)
	else:
		# Looked up fresh per hover (not cached) so "Predicted Damage"
		# reflects the player's CURRENT stats, not whatever they were
		# when this button was built.
		var player := get_tree().get_first_node_in_group("player") as Player
		card.display_ability(ability, player.stat_sheet if player else null)
	return card
