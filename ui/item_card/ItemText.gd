extends RefCounted
class_name ItemText
## Plain-text copy of an item, Slate, spell or currency, exactly as its hover
## card reads (Ctrl+C over anything with a card, see TooltipFollow), with
## "--------" between the card's sections, ready to paste anywhere.

const SEPARATOR := "--------"

## content: Item, Slate, Ability or a currency id (StringName).
static func of(content, count: int = 1) -> String:
	var card: ItemCard = ItemSlotButton.ITEM_CARD_SCENE.instantiate()
	if content is Item:
		card.display_item(content)
	elif content is Slate:
		card.display_slate(content)
	elif content is Ability:
		card.display_ability(content)
	elif content is StringName:
		card.display_currency(content, count)
	else:
		card.free()
		return ""
	var lines: Array[String] = []
	_collect(card, lines)
	card.free()
	while not lines.is_empty() and lines[-1] == SEPARATOR:
		lines.pop_back()
	return "\n".join(lines)

static func _collect(node: Node, lines: Array[String]) -> void:
	for child in node.get_children():
		if child is Label:
			var text := (child as Label).text.strip_edges()
			if text != "":
				lines.append(text)
		elif child is RichTextLabel:
			var rich := (child as RichTextLabel).get_parsed_text().strip_edges()
			if rich != "":
				lines.append(rich)
		elif child is ItemCard.LeaderRow:
			lines.append("%s: %s" % [child.label, child.value])
		elif child is ItemCard.CardDivider or child is HSeparator:
			if not lines.is_empty() and lines[-1] != SEPARATOR:
				lines.append(SEPARATOR)
		else:
			_collect(child, lines)
