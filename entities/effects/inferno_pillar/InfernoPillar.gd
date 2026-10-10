extends Node3D
class_name InfernoPillar
## Inferno's cast VFX: WC3's Flame Strike (converted by tools/mdx_pipeline/
## mdx_fx.js) sized to the cast radius, plus a ring marking the real reach.
## Purely visual, same damage-timing note as CometImpact.

const FX_PATH := "res://assets/models/spells/flamestrike/flamestrike.fx.json"
## Flame Strike's own area (200 WC3 units) at the converter's 0.02 scale.
const FX_RADIUS := 4.0
## Skips Flame Strike's lead-in so the column rises as the damage lands.
const FX_START := 0.5
const FX_SPEED := 1.5
const RING_SCENE := preload("res://entities/effects/ability_range_effect/AbilityRangeEffect.tscn")

func play(radius: float, color: Color) -> void:
	var ring: AbilityRangeEffect = RING_SCENE.instantiate()
	add_child(ring)
	ring.position.y = 0.05
	ring.play(radius, color.lightened(0.2))

	var fx := MdxEffect.new()
	fx.fx_path = FX_PATH
	fx.start_time = FX_START
	fx.speed_scale = FX_SPEED
	fx.free_when_finished = false
	fx.scale = Vector3.ONE * (radius / FX_RADIUS)
	fx.finished.connect(queue_free)
	add_child(fx)
