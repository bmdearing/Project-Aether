extends Control
class_name SocketOverlay
## Drawn over an item's art: its sockets while the parent is hovered (or
## always, with the Always Show Item Sockets setting), a filled socket
## showing its jewel's rarity.

const SOCKET_BG := Color(0.02, 0.02, 0.04, 0.85)
const MAX_STEP := 30.0

var item: Item:
	set(value):
		item = value
		_update()
var _hovered: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var host := get_parent() as Control
	if host:
		host.mouse_entered.connect(func():
			_hovered = true
			_update())
		host.mouse_exited.connect(func():
			_hovered = false
			_update())
	EventBus.settings_changed.connect(_update)
	_update()

func _update() -> void:
	visible = item != null and item.sockets > 0 and (_hovered or GameState.always_show_sockets)
	queue_redraw()

func _draw() -> void:
	if item == null:
		return
	var count := item.sockets
	var cols := 2 if count > 1 and GridInventory.footprint_of(item).x >= 2 else 1
	var rows := ceili(float(count) / cols)
	var step := minf(minf(size.x / cols, size.y / rows), MAX_STEP)
	var radius := clampf(step * 0.36, 4.0, 10.0)
	var origin := size / 2.0 - Vector2(cols - 1, rows - 1) * step / 2.0
	var jewels := item.get_socketed_jewels()
	for i in count:
		var row := floori(float(i) / cols)
		var col := i % cols
		if row % 2 == 1:
			col = cols - 1 - col  # snake order, like linked sockets
		var centre := origin + Vector2(col, row) * step
		draw_circle(centre, radius + 1.5, SOCKET_BG)
		draw_arc(centre, radius, 0.0, TAU, 24, AetherStyle.GOLD, 1.5, true)
		if i < jewels.size():
			var colour: Color = Constants.ITEM_RARITY_COLOR.get(jewels[i].rarity, Color.WHITE)
			AetherStyle.diamond(self, centre, radius * 0.75, colour.darkened(0.25), colour.lightened(0.3))
