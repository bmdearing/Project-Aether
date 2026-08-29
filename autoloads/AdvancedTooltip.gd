extends CanvasLayer
## Alt+hover shows this instead of (alongside) the native tooltip - a
## real interactive popup that doesn't auto-hide when the mouse leaves
## the hovered slot, so the player can move onto the card itself and
## click through mod-tier ranges / stat glossary links. Closes via its
## own Close button, Escape, or clicking elsewhere. Triggered by
## ItemSlotButton.gd.

const CARD_SCENE := preload("res://ui/item_card/ItemCard.tscn")

var _card: ItemCard

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_card = CARD_SCENE.instantiate()
	_card.visible = false
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.closed.connect(hide_advanced)
	add_child(_card)

func show_for_item(item: Item, at_position: Vector2) -> void:
	_card.display_item(item, true)
	_open(at_position)

func show_for_slate(slate: Slate, at_position: Vector2) -> void:
	_card.display_slate(slate, true)
	_open(at_position)

func show_for_ability(ability: Ability, stat_sheet: StatSheet, at_position: Vector2) -> void:
	_card.display_ability(ability, stat_sheet, true)
	_open(at_position)

func hide_advanced() -> void:
	_card.visible = false

func is_showing() -> bool:
	return _card.visible

func _open(at_position: Vector2) -> void:
	_card.visible = true
	_card.position = at_position
	await _card.get_tree().process_frame
	var viewport_size := _card.get_viewport_rect().size
	_card.position.x = min(_card.position.x, viewport_size.x - _card.size.x - 8.0)
	_card.position.y = min(_card.position.y, viewport_size.y - _card.size.y - 8.0)

func _unhandled_input(event: InputEvent) -> void:
	if not _card.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		hide_advanced()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if not _card.get_global_rect().has_point(event.global_position):
			hide_advanced()
