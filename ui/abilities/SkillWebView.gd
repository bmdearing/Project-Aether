extends Control
class_name SkillWebView
## Space for a spell's skill web on the Spells screen. The web itself isn't
## designed yet: this draws a faint placeholder (rings and spokes around the
## spell's icon) and a note, sized to the area the web will fill.

var ability: Ability:
	set(value):
		ability = value
		queue_redraw()

const RINGS := 3
const SPOKES := 8

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	AetherStyle.plate(self, Rect2(Vector2.ZERO, size), 4.0, AetherStyle.GLASS)
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	var line := Color(AetherStyle.GOLD_FAINT, 0.35)
	for i in RINGS:
		draw_arc(c, r * float(i + 1) / RINGS, 0.0, TAU, 64, line, 1.5)
	for i in SPOKES:
		var dir := Vector2.from_angle(TAU * i / SPOKES)
		draw_line(c + dir * r / RINGS, c + dir * r, line, 1.5)
		for ring in range(1, RINGS + 1):
			draw_circle(c + dir * r * float(ring) / RINGS, 5.0, Color(AetherStyle.GOLD_FAINT, 0.5))
	if ability:
		var side := r / RINGS * 1.3
		SpellArt.draw(self, ability, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)))
	var font := AetherStyle.serif()
	AetherStyle.text(self, font, Vector2(0, size.y - 18.0), "Skill Web - coming soon", 16, AetherStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x)
