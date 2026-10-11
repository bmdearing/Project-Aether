extends Control
class_name CharacterHeader
## Top of the character sheet: a portrait medallion with the level on a
## badge, the character's name, level, and an XP bar. The portrait is a
## drawn hooded figure until characters have portrait art.

const PORTRAIT_R := 46.0
const HEIGHT := 118.0
const FALLBACK_NAME := "Nameless Wanderer"

var character_name := FALLBACK_NAME
var level := 1
var xp := 0.0
var xp_next := 1.0

func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func refresh(player: Player) -> void:
	character_name = GameState.player_name if GameState.player_name != "" else FALLBACK_NAME
	if player and player.experience:
		level = player.experience.level
		xp = player.experience.xp
		xp_next = maxf(player.experience.xp_to_next_level(), 1.0)
	queue_redraw()

func _draw() -> void:
	var c := Vector2(PORTRAIT_R + 6.0, PORTRAIT_R + 6.0)
	_draw_portrait(c)
	# Level badge on the medallion's lower rim.
	var badge := c + Vector2(0, PORTRAIT_R + 2.0)
	AetherStyle.diamond(self, badge, 15.0, AetherStyle.GLASS_SOLID, AetherStyle.GOLD)
	AetherStyle.text(self, AetherStyle.numbers(), badge + Vector2(-15, 6), str(level), 16, AetherStyle.GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER, 30.0)

	var x := c.x + PORTRAIT_R + 22.0
	var width := size.x - x - 6.0
	AetherStyle.text(self, AetherStyle.title(), Vector2(x, 34), character_name, 22, AetherStyle.GOLD, HORIZONTAL_ALIGNMENT_LEFT, width)
	AetherStyle.text(self, AetherStyle.serif_italic(), Vector2(x, 58), "Level %d" % level, 16, AetherStyle.TEXT_DIM)
	var bar := Rect2(x + 4.0, 74.0, width - 8.0, 9.0)
	AetherStyle.bar(self, bar, clampf(xp / xp_next, 0.0, 1.0), AetherStyle.AETHER.darkened(0.25))
	AetherStyle.text(self, AetherStyle.numbers(), Vector2(x + 4.0, 102), "%s / %s XP" % [_short(xp), _short(xp_next)], 14, AetherStyle.TEXT_DIM)
	AetherStyle.text(self, AetherStyle.numbers(), Vector2(x, 102), "%d%%" % int(clampf(xp / xp_next, 0.0, 1.0) * 100.0), 14, AetherStyle.AETHER, HORIZONTAL_ALIGNMENT_RIGHT, width - 4.0)

## A dark medallion with a cloaked, hooded figure lit from one side.
func _draw_portrait(c: Vector2) -> void:
	var r := PORTRAIT_R
	# Background: deep violet fading to near black at the rim.
	for i in 12:
		var t := float(i) / 11.0
		draw_circle(c, r * (1.0 - t * 0.92), Color(0.06, 0.05, 0.12).lerp(Color(0.2, 0.16, 0.36), t))
	# Shoulders and cloak.
	var cloak := PackedVector2Array([
		c + Vector2(-r * 0.86, r * 0.95), c + Vector2(-r * 0.62, r * 0.38), c + Vector2(-r * 0.3, r * 0.16),
		c + Vector2(0, r * 0.3), c + Vector2(r * 0.3, r * 0.16), c + Vector2(r * 0.62, r * 0.38), c + Vector2(r * 0.86, r * 0.95),
	])
	draw_colored_polygon(_clip_circle(cloak, c, r - 1.0), Color(0.07, 0.08, 0.13))
	# Hood: a pointed arch around the face.
	var hood := PackedVector2Array([
		c + Vector2(-r * 0.36, r * 0.28), c + Vector2(-r * 0.42, -r * 0.08), c + Vector2(-r * 0.3, -r * 0.42),
		c + Vector2(0, -r * 0.62), c + Vector2(r * 0.3, -r * 0.42), c + Vector2(r * 0.42, -r * 0.08), c + Vector2(r * 0.36, r * 0.28),
	])
	draw_colored_polygon(hood, Color(0.1, 0.11, 0.18))
	# The face in shadow, with two faint Aether-lit eyes.
	var face := PackedVector2Array([
		c + Vector2(-r * 0.2, r * 0.18), c + Vector2(-r * 0.24, -r * 0.12), c + Vector2(0, -r * 0.34),
		c + Vector2(r * 0.24, -r * 0.12), c + Vector2(r * 0.2, r * 0.18), c + Vector2(0, r * 0.26),
	])
	draw_colored_polygon(face, Color(0.02, 0.02, 0.04))
	for side in [-1.0, 1.0]:
		draw_circle(c + Vector2(side * r * 0.1, -r * 0.06), 1.8, AetherStyle.AETHER)
	# Rim light down the hood's left edge.
	draw_polyline(PackedVector2Array([hood[1], hood[2], hood[3]]), Color(AetherStyle.AETHER, 0.55), 1.5, true)
	# Gold frame with tick marks.
	draw_arc(c, r, 0.0, TAU, 64, AetherStyle.GOLD, 2.0, true)
	draw_arc(c, r - 4.0, 0.0, TAU, 64, AetherStyle.GOLD_FAINT, 1.0, true)
	AetherStyle.ticks(self, c, r + 2.0, 24, 6, AetherStyle.GOLD_DIM)

## Keeps the cloak inside the medallion: points past the rim are pulled in.
static func _clip_circle(points: PackedVector2Array, c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(c + (p - c).limit_length(r))
	return out

static func _short(value: float) -> String:
	if value >= 1.0e6:
		return "%.1fM" % (value / 1.0e6)
	if value >= 1.0e4:
		return "%.0fk" % (value / 1.0e3)
	return "%.0f" % value
