extends CanvasLayer
class_name TimeStop
## Sands of Time's stance: every enemy and every enemy shot freezes in place
## for DURATION seconds (half while a Pinnacle boss is in the fight), while
## the player moves and hits freely. A sand-coloured tint covers the screen.

const DURATION := 4.0
const PINNACLE_FACTOR := 0.5
const COOLDOWN := 60.0
const TINT := Color(0.95, 0.78, 0.45, 0.16)

static var _active: TimeStop

var _frozen: Array[Node] = []
var _rect: ColorRect

static func is_running() -> bool:
	return is_instance_valid(_active)

## Seconds a Time Stop lasts right now.
static func duration_for(tree: SceneTree) -> float:
	for node in tree.get_nodes_in_group("enemy"):
		if node is PinnacleBoss and (node as Enemy).health.is_alive():
			return DURATION * PINNACLE_FACTOR
	return DURATION

static func start(tree: SceneTree) -> TimeStop:
	var stop := TimeStop.new()
	tree.current_scene.add_child(stop)
	stop._freeze(tree, duration_for(tree))
	return stop

func _freeze(tree: SceneTree, seconds: float) -> void:
	_active = self
	layer = 50
	_rect = ColorRect.new()
	_rect.color = TINT
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	for node in tree.get_nodes_in_group("enemy"):
		_hold(node)
	for node in tree.current_scene.get_children():
		if node is Projectile and not (node as Projectile).source is Player:
			_hold(node)
	tree.create_timer(seconds, false).timeout.connect(_release)

func _hold(node: Node) -> void:
	if node.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	node.set_meta("time_stop_mode", node.process_mode)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_frozen.append(node)

func _release() -> void:
	for node in _frozen:
		if is_instance_valid(node):
			node.process_mode = node.get_meta("time_stop_mode", Node.PROCESS_MODE_INHERIT)
			node.remove_meta("time_stop_mode")
	_frozen.clear()
	if _active == self:
		_active = null
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
