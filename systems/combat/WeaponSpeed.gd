extends RefCounted
class_name WeaponSpeed
## Attacks per second for a weapon, before the player's own attack speed:
## swings for melee and conduits, bolts for wands, shots for ranged (the
## slower of the fire cooldown and the cycle or draw). Kept out of Weapon:
## it reads the combat scripts' timings, and Weapon referencing them made a
## preload cycle that broke the Projectile scene.

static func attacks_per_second(w: Weapon, include_local: bool = true) -> float:
	var local := w.get_local_multiplier("local_increased_attack_speed") if include_local else 1.0
	if w.weapon_type == "Wand":
		return local / CasterStance.WAND_BOLT_COOLDOWN
	if not w.is_ranged:
		return local / PlayerMeleeAttack.swing_seconds(w.weapon_type)
	if w.fire_mode == Constants.FireMode.FULL_AUTO and w.fire_rate > 0.0:
		return w.fire_rate * local
	var cycle := w.get_draw_time() if w.get_draw_time() > 0.0 else w.cycle_time
	return local / maxf(PlayerRangedAttack.BASE_FIRE_COOLDOWN, cycle)
