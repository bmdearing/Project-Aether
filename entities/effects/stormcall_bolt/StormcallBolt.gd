extends Node3D
class_name StormcallBolt
## Stormcall's cast VFX: a thick branching bolt cracks down from high above
## onto the cast point (LightningArc), with a white flash, a light that
## lights the room for an instant, sparks, a scorched crack and the ground
## shockwave. Real lightning doesn't loiter, so it's over in a blink.
## Purely visual, same damage-timing note as CometImpact/InfernoPillar.

const BOLT_HEIGHT := 10.0
const BOLT_WIDTH := 2.4
const SPARK := Color(1.0, 0.95, 0.6)

func play(radius: float, color: Color) -> void:
	var parent := get_parent()
	var at := global_position
	var sky := at + Vector3(randf_range(-1.5, 1.5), BOLT_HEIGHT, randf_range(-1.5, 1.5))
	LightningArc.spawn(parent, sky, at, color, BOLT_WIDTH, false)
	LightningArc.spawn(parent, sky + Vector3(0.4, -1.0, 0.2), at + Vector3(0.3, 0, -0.2), color, BOLT_WIDTH * 0.4, false)
	SpellFx.shockwave(parent, at, radius, color, 0.3)
	SpellFx.flash(parent, at + Vector3.UP * 0.8, Color(SPARK, 1.0), 4.0, 0.18)
	SpellFx.light_pop(parent, at + Vector3.UP * 2.0, SPARK, 7.0, radius * 1.6, 0.3)
	SpellFx.burst(parent, at + Vector3.UP * 0.2, SPARK, 34, Vector2(4.0, 9.0), 0.4, Vector2(0.04, 0.09), 80.0, -10.0)
	SpellFx.ground_mark(parent, at, minf(radius, 3.0) * 0.7, SpellFx.Mark.CRACKS, Color(0.03, 0.03, 0.04, 0.7), SPARK, 2.5, 0.35)
	get_tree().create_timer(0.5, false).timeout.connect(queue_free)
