class_name AureliaAilments
## Every hit Aurelia, her golems and her arena land on the player goes
## through hit(), where the ailments already on the player decide what else
## happens:
##   Chilled or Frozen + Lightning -> Electrocuted and Shocked.
##   Entangled + Fire              -> Forbidden Fire (ForbiddenFire.gd).
##   Ignited + Cold                -> Pallid.
## The combo lands before the hit, so a Shock raises the bolt that caused it.

## Long enough for her to answer with a Fire Wall from across the arena.
const ENTANGLE_SEC := 2.5
const ENTANGLE_COLOR := Color(0.45, 0.8, 0.3)

static func hit(p: Player, amount: float, type: int, source: Node, kind: Player.HitKind = Player.HitKind.SPELL, is_melee: bool = false) -> void:
	if p == null or not is_instance_valid(p) or not p.health.is_alive():
		return
	var s := p.status_effects
	if s:
		match type:
			Constants.DamageType.LIGHTNING:
				if s.has_effect("chill") or s.has_effect("freeze"):
					s.apply_effect("electrocute", source, amount)
					s.apply_effect("shock", source, amount)
					_electrocute_fx(p)
			Constants.DamageType.FIRE:
				if s.has_effect("entangle"):
					ForbiddenFire.ignite(p, source)
			Constants.DamageType.COLD:
				if s.has_effect("ignite") and not s.has_effect("pallid"):
					s.apply_effect("pallid", source, amount)
					_pallid_fx(p)
	p.take_damage(amount, type, source, kind, is_melee)

## Roots the player where they stand.
static func entangle(p: Player, seconds: float = ENTANGLE_SEC) -> void:
	if p == null or p.status_effects == null:
		return
	var fresh := not p.status_effects.has_effect("entangle")
	p.status_effects.apply_timed_effect("entangle", seconds)
	if fresh:
		AureliaRoots.bind(p, seconds)
		AureliaSfx.play("roots_erupt", p.global_position, 0.0, 1.1)

static func _electrocute_fx(p: Player) -> void:
	var parent := p.get_parent()
	var at := p.global_position
	for i in 3:
		var a := randf() * TAU
		LightningArc.spawn(parent, at + Vector3(cos(a) * 1.4, 2.2, sin(a) * 1.4), at + Vector3(0, 0.4, 0), Color(0.75, 0.85, 1.0), 1.2)
	SpellFx.flash(parent, at + Vector3.UP, Color(0.7, 0.85, 1.0), 3.0, 0.25)
	AureliaSfx.play("combo_electrocute", at, 2.0)

static func _pallid_fx(p: Player) -> void:
	var parent := p.get_parent()
	SpellCastFx.mist_ring(parent, p.global_position, 1.6, Color(0.9, 0.9, 0.85))
	SpellFx.burst(parent, p.global_position + Vector3.UP * 0.8, Color(0.92, 0.9, 0.82), 24, Vector2(1, 3), 0.9, Vector2(0.1, 0.22), 180.0, 1.0)
	AureliaSfx.play("combo_pallid", p.global_position, 0.0)
