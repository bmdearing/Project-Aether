extends Control
class_name ItemIcon
## Draws IconArt for an Item, Slate or currency id, fitted to this
## control's rect, plus a stack count in the corner. With no content and a
## ghost_key it draws that item type as a faint silhouette (empty slot).

const COUNT_COLOR := Color(1.0, 0.95, 0.82)
const GHOST_COLOR := Color(0.75, 0.65, 0.45, 0.16)

## Item, Slate, StringName currency id, or null.
var content = null:
	set(value):
		content = value
		queue_redraw()
## Shown in the bottom-right corner when above 1.
var count: int = 0:
	set(value):
		count = value
		queue_redraw()
var ghost_key: StringName = &"":
	set(value):
		ghost_key = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

## Fills `host` edge to edge, under anything added after it.
static func fill(host: Control) -> ItemIcon:
	var icon := ItemIcon.new()
	host.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return icon

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if content == null:
		if ghost_key != &"":
			IconArt.draw_ghost(self, ghost_key, rect, GHOST_COLOR)
		return
	IconArt.draw(self, content, rect)
	if count > 1:
		var font := AetherStyle.numbers()
		var px := clampi(int(minf(size.x, size.y) * 0.3), 10, 18)
		var s := str(count)
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var pos := Vector2(size.x - w - 3.0, size.y - 4.0)
		draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, IconArt.OUTLINE)
		draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, COUNT_COLOR)
