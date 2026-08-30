extends CanvasLayer
## Hold-Alt+hover shows this instead of (alongside) the native tooltip -
## matches Path of Exile's real Alt-hold behavior (confirmed by request:
## it's a HOLD modifier, not a toggle - release Alt and it's gone), not
## the click-and-forget "sticky until Escape" behavior this had before,
## which read as unintuitive since nothing else in the game works that
## way. Releasing Alt hides it UNLESS the mouse is currently over the
## card itself, so a player can still move onto it one-handed to click
## through mod-tier ranges / stat glossary links without it vanishing out
## from under the cursor the instant Alt comes up - it then closes as
## soon as the mouse leaves the card too. Escape and clicking elsewhere
## remain explicit fallbacks. Triggered by ItemSlotButton.gd.

const CARD_SCENE := preload("res://ui/item_card/ItemCard.tscn")

var _card: ItemCard
var _mouse_over_card: bool = false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_card = CARD_SCENE.instantiate()
	_card.visible = false
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.closed.connect(hide_advanced)
	_card.mouse_entered.connect(func(): _mouse_over_card = true)
	_card.mouse_exited.connect(_on_card_mouse_exited)
	add_child(_card)

func _on_card_mouse_exited() -> void:
	_mouse_over_card = false
	if not Input.is_key_pressed(KEY_ALT):
		hide_advanced()

## Called by ItemSlotButton.gd on Alt release - the hold ends unless the
## mouse is now over the card itself (still reading/interacting with it).
func on_alt_released() -> void:
	if not _mouse_over_card:
		hide_advanced()

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
