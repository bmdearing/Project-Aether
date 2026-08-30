extends Node3D
class_name CaltropsField
## Caltrops ("26 - Ability Staging Ground", Physical): "Scatter caltrops
## across a designated ground area. Enemies that walk through take
## Piercing damage and are slowed." User revision (2026-08-30) added a
## real "slow" status effect (StatusEffectComponent.gd) independent of
## Cold's Chill - reusing Chill for a Physical/Piercing effect would have
## been a thematic mismatch. This deals repeated Piercing damage to
## anything standing in the field for DURATION seconds AND refreshes
## "slow" on every tick (its own duration is intentionally shorter than
## TICK_INTERVAL's cadence would need for a single application to
## linger, but longer than the gap between ticks - continuous standing
## keeps it topped up, stepping out lets it expire on its own within a
## tick's worth of time); each damage tick rolls its own fraction of the
## ability's damage independently (ability.roll_damage()) rather than
## reusing one hit's damage repeatedly, so Crit still varies tick to tick.

const DURATION := 5.0
const TICK_INTERVAL := 0.5
const TICK_DAMAGE_PERCENT := 0.3  # each tick = 30% of a fresh damage roll

var _radius: float = 4.0
var _ability: Ability
var _stat_sheet: StatSheet
var _source: Node
var _elapsed: float = 0.0
var _ticker: float = 0.0

@onready var patch: MeshInstance3D = $Patch

func play(radius: float, color: Color, ability: Ability, stat_sheet: StatSheet, source: Node) -> void:
	_radius = radius
	_ability = ability
	_stat_sheet = stat_sheet
	_source = source
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c := color
	c.a = 0.4
	mat.albedo_color = c
	patch.material_override = mat
	patch.scale = Vector3(radius, 1.0, radius)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	_ticker -= delta
	if _ticker > 0.0:
		return
	_ticker += TICK_INTERVAL
	if _ability == null or _stat_sheet == null:
		return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if global_position.distance_to(enemy.global_position) > _radius:
			continue
		var hit := _ability.roll_damage(_stat_sheet)
		var damage: float = hit["final_damage"] * TICK_DAMAGE_PERCENT
		enemy.take_damage(damage, Constants.DamageType.PIERCING)
		EventBus.damage_dealt.emit(_source, enemy, damage, Constants.DamageType.PIERCING, false, hit["is_critical"])
		enemy.status_effects.apply_effect("slow", _source)
