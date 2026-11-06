extends Control
class_name Crosshair
## Hollow-centre cross, hidden only while a UI panel has the mouse. With a gun
## or bow out, its ticks spread to the area shots can land in (an ellipse:
## full spread sideways, half up and down), and a ring round it fills while
## reloading.

const COLOR := Color(1.0, 1.0, 1.0, 0.8)
const RING_RADIUS := 9.0
const ARM_LENGTH := 5.0
const THICKNESS := 1.5
const GAP := 4.0
const SPREAD_COLOR := Color(1.0, 1.0, 1.0, 0.28)
## Spread smaller than this (px) reads as "always on the crosshair": no ellipse.
const MIN_SPREAD_PX := 3.0
const SPREAD_EASE := 18.0
const RELOAD_WIDTH := 3.0
const RELOAD_GAP := 5.0
const RELOAD_COLOR := Color(1.0, 0.82, 0.45, 0.95)
const RELOAD_TRACK_COLOR := Color(0.0, 0.0, 0.0, 0.35)

var _spread := Vector2.ZERO  # half-size of the landing area, px
var _reload := -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS  # panels pause the tree

## v4.7: hidden while any UI panel is open. Every panel (inventory,
## character, Fate Board, crafting, shop, pause, map, death...) frees the
## mouse on open and recaptures it on close, so capture state is the one
## signal they all already share - no per-panel open/close bookkeeping.
func _process(delta: float) -> void:
	visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not visible:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	var target := _target_spread(player)
	_spread = _spread.lerp(target, clampf(delta * SPREAD_EASE, 0.0, 1.0))
	_reload = player.ranged_attack.get_reload_progress() if player and player.ranged_attack else -1.0
	queue_redraw()

## Screen half-size (px) of where the active ranged weapon's shots can land.
func _target_spread(player: Player) -> Vector2:
	if player == null or player.camera == null or player.ranged_attack == null:
		return Vector2.ZERO
	var weapon := player.get_active_weapon()
	if weapon == null or not weapon.is_ranged or weapon.is_throwing() or player.weapon_stance.is_scoped():
		return Vector2.ZERO
	var spread := player.ranged_attack.spread_degrees(weapon, player.weapon_stance.is_active)
	var arrows: int = 1 + weapon.get_local_count("local_additional_arrows") if not weapon.is_hitscan() else 1
	var sideways := spread + PlayerRangedAttack.EXTRA_ARROW_SPREAD_DEG * (arrows - 1) * 0.5
	var px_per_tan := get_viewport_rect().size.y * 0.5 / tan(deg_to_rad(player.camera.fov) * 0.5)
	return Vector2(tan(deg_to_rad(sideways)), tan(deg_to_rad(spread * 0.5))) * px_per_tan

## A thin ring with four short ticks and a centre dot; the ticks move out to
## the spread ellipse when it's wider than the ring.
func _draw() -> void:
	var c := size / 2.0
	var spread_on := _spread.x >= MIN_SPREAD_PX
	if spread_on:
		var points := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			points.append(c + Vector2(cos(a) * _spread.x, sin(a) * maxf(_spread.y, 1.0)))
		draw_polyline(points, SPREAD_COLOR, 1.2, true)
	else:
		draw_arc(c, RING_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.55), 1.2, true)
	var reach := Vector2(maxf(RING_RADIUS, _spread.x), maxf(RING_RADIUS, _spread.y)) if spread_on else Vector2(RING_RADIUS, RING_RADIUS)
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var from := c + d * (reach + Vector2(GAP, GAP))
		draw_line(from, from + d * ARM_LENGTH, COLOR, THICKNESS, true)
	draw_circle(c, 1.6, Color(1, 1, 1, 0.9))
	if _reload >= 0.0:
		var r := RING_RADIUS + GAP + ARM_LENGTH + RELOAD_GAP
		draw_arc(c, r, 0.0, TAU, 48, RELOAD_TRACK_COLOR, RELOAD_WIDTH, true)
		if _reload > 0.0:
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * _reload, 48, RELOAD_COLOR, RELOAD_WIDTH, true)
