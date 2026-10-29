extends Node3D
class_name GroundHazard
## A short-lived patch of ground left by a web twist (Scorched Earth, Ember
## Trail, Permafrost): a ground mark, and every `tick` seconds `on_tick(enemy,
## tick)` for each living enemy standing on it.

var radius := 2.0
var duration := 3.0
var tick := 0.25
var on_tick: Callable
var _elapsed := 0.0
var _ticker := 0.0

static func spawn(parent: Node, at: Vector3, patch_radius: float, lasts: float, every: float, mark: SpellFx.Mark, base: Color, accent: Color, callback: Callable) -> GroundHazard:
	var h := GroundHazard.new()
	h.radius = patch_radius
	h.duration = lasts
	h.tick = every
	h.on_tick = callback
	parent.add_child(h)
	h.global_position = at
	SpellFx.ground_mark(parent, at, patch_radius, mark, base, accent, lasts, minf(lasts * 0.8, 1.5))
	return h

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	_ticker -= delta
	if _ticker > 0.0:
		return
	_ticker += tick
	if not on_tick.is_valid():
		return
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy and enemy.health.is_alive() and enemy.distance_to_body(global_position) <= radius:
			on_tick.call(enemy, tick)
