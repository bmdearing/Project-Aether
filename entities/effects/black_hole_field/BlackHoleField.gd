extends Node3D
class_name BlackHoleField
## Black Hole ("26 - Ability Staging Ground", Esoteric/Entropic): "Summons
## a point of collapsing incoherence that drags surrounding enemies toward
## its center for a short duration." User revision (2026-08-30): "Black
## Hole shouldn't be a DoT, but deals Entropic damage every .25 seconds" -
## i.e. not a single instant hit at cast time (the previous design,
## routed through PlayerAbilityCast._cast()'s generic damage loop) and
## not a StatusEffectComponent-style DoT tick (Ignite's own model) either -
## a real repeated direct hit, rolled fresh each tick same as any other
## ability damage instance (crit varies tick to tick, same reasoning
## CaltropsField's own ticks already follow). PlayerAbilityCast.gd now
## skips its generic loop entirely for "black_hole" (see _cast()) - ALL of
## this ability's damage comes from here.

const DURATION := 2.5
const PULL_SPEED := 3.0
const RISE_DURATION := 0.3
const TICK_INTERVAL := 0.25

var _radius: float = 5.0
var _elapsed: float = 0.0
var _ticker: float = 0.0
var _ability: Ability
var _stat_sheet: StatSheet
var _source: Node

@onready var core: MeshInstance3D = $Core

var _duration: float = DURATION

func play(radius: float, color: Color, ability: Ability, stat_sheet: StatSheet, source: Node) -> void:
	_duration = DURATION * ability.get_duration_multiplier(stat_sheet)
	_radius = radius
	_ability = ability
	_stat_sheet = stat_sheet
	_source = source
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.darkened(0.5)
	core.material_override = mat
	core.scale = Vector3.ONE * 0.2
	var tween := create_tween()
	tween.tween_property(core, "scale", Vector3.ONE * 0.6, RISE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		queue_free()
		return
	_ticker -= delta
	var should_tick := _ticker <= 0.0
	if should_tick:
		_ticker += TICK_INTERVAL
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		var to_center: Vector3 = global_position - enemy.global_position
		to_center.y = 0.0
		var dist := to_center.length()
		if dist > _radius:
			continue
		# The dist<0.05 guard only matters for the pull math below (avoids
		# normalizing a near-zero vector) - an enemy pulled all the way to
		# the center should still keep taking damage, not go immune once
		# it arrives (caught by scratch_spells_test.gd: a same-position
		# enemy took zero damage across a full second of ticks).
		if dist >= 0.05:
			var pull: Vector3 = to_center.normalized() * PULL_SPEED * delta
			if pull.length() > dist:
				pull = to_center  # don't overshoot past the center
			enemy.global_position += pull
		if should_tick and _ability and _stat_sheet:
			var hit := _ability.roll_damage(_stat_sheet)
			var damage: float = hit["final_damage"]
			enemy.take_damage(damage, _ability.damage_type)
			EventBus.damage_dealt.emit(_source, enemy, damage, _ability.damage_type, false, hit["is_critical"])
