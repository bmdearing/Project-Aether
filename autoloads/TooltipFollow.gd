extends Node
## Keeps Godot's tooltip next to the mouse while it's showing, instead of
## frozen where it first appeared. Works for every tooltip (item cards,
## currency, plain text): each frame it finds the viewport's tooltip window
## and moves it. The tooltip sits below-right of the cursor and flips to the
## other side near a screen edge; it never covers the cursor, or the
## hovered control would lose the mouse and close it.

const OFFSET := Vector2(18, 20)
const MARGIN := 4.0
const TOOLTIP_VARIATION := &"TooltipPanel"

var _mouse := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000  # after the GUI has shown/resized it this frame

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse = event.position

func _process(_delta: float) -> void:
	var root := get_tree().root
	var tooltip := find_tooltip(root)
	if tooltip:
		tooltip.position = Vector2i(place(_mouse, Vector2(tooltip.size), root.get_visible_rect().size))

## Top-left corner for a tooltip of tip_size beside the cursor.
static func place(mouse: Vector2, tip_size: Vector2, view: Vector2) -> Vector2:
	var pos := mouse + OFFSET
	if pos.x + tip_size.x > view.x - MARGIN:
		pos.x = mouse.x - OFFSET.x - tip_size.x
	if pos.y + tip_size.y > view.y - MARGIN:
		pos.y = mouse.y - OFFSET.y - tip_size.y
	pos.x = clampf(pos.x, MARGIN, maxf(view.x - tip_size.x - MARGIN, MARGIN))
	pos.y = clampf(pos.y, MARGIN, maxf(view.y - tip_size.y - MARGIN, MARGIN))
	return pos

## The viewport's own tooltip window: class TooltipPanel (not exposed to
## scripts) with the TooltipPanel theme variation.
static func find_tooltip(root: Window) -> Window:
	for child in root.get_children(true):
		if child is Window and child.visible and (child.get_class() == "TooltipPanel" or child.theme_type_variation == TOOLTIP_VARIATION):
			return child
	return null
