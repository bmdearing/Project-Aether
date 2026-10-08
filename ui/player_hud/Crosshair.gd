extends Control
class_name Crosshair
## Implementation Brief v3.4 Section 1 (2026-08-31): simple static
## crosshair, visible regardless of weapon type (hidden only while a UI
## panel has the mouse, see _process()) - explicitly no
## spread animation, no melee hiding, no movement/firing-driven dynamics.
## Four short segments (a hollow-center cross) rather than two solid
## overlapping bars - reads as one consistent visual language with
## HitMarker's own shape right next to it, just static/dim instead of a
## brief bright flash.

const COLOR := Color(1.0, 1.0, 1.0, 0.8)
const RING_RADIUS := 9.0
const ARM_LENGTH := 5.0
const THICKNESS := 1.5
const GAP := 4.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS  # panels pause the tree

## v4.7: hidden while any UI panel is open. Every panel (inventory,
## character, Fate Board, crafting, shop, pause, map, death...) frees the
## mouse on open and recaptures it on close, so capture state is the one
## signal they all already share - no per-panel open/close bookkeeping.
func _process(_delta: float) -> void:
	visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

## A thin ring with four short ticks and a centre dot.
func _draw() -> void:
	var c := size / 2.0
	draw_arc(c, RING_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.55), 1.2, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * (RING_RADIUS + GAP), c + d * (RING_RADIUS + GAP + ARM_LENGTH), COLOR, THICKNESS, true)
	draw_circle(c, 1.6, Color(1, 1, 1, 0.9))
