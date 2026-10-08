class_name StanceInfo
## Player-facing stance names and descriptions, from Patch v3.4's melee and
## ranged stance tables. Keyed by Weapon.weapon_type; melee entries are
## [Stance A, Stance B]; ranged entries are the aim stance (RANGED_B for the
## bows' second page). Shown on the inventory's Behaviors tab and the HUD.

const MELEE := {
	"Rapier": [
		{"name": "Charged Thrust", "desc": "Hold RMB to charge a lunge of up to 4 m. It fires at full charge, or shorter if you let go early."},
		{"name": "Ready Parry", "desc": "Significantly wider parry window while held."},
	],
	"Dagger": [
		{"name": "Slice and Dice", "desc": "LMB becomes a rapid multi-hit flurry. Low damage per hit, high total on full execution."},
		{"name": "Stealth", "desc": "Reduces detection radius while held. Moving slowly maintains stealth. The first attack from stealth deals bonus damage."},
	],
	"Greatsword": [
		{"name": "Execute", "desc": "Fully charged slam into a small area. Very high damage. Must hold the full charge to release."},
		{"name": "Guard", "desc": "Blocks 80% of incoming melee damage while held."},
	],
	"Mace": [
		{"name": "Overhead Slam", "desc": "Charge and release a devastating overhead blow. An aftershock detonates 1.5 s after impact for the same damage again."},
		{"name": "Fortify", "desc": "Plant the weapon, rooting yourself. Significant damage reduction aura while rooted."},
	],
	"Cutlass": [
		{"name": "Water Slices", "desc": "LMB releases projectile slashes. Each deals 40% of its damage again as Cold."},
		{"name": "Parry Ready", "desc": "Widened parry window while held."},
	],
	"War Pick": [
		{"name": "Armor Pierce", "desc": "Stance strikes ignore all Armor and leave a stacking Armor Shred debuff."},
		{"name": "Hooking Strike", "desc": "LMB pulls the target toward you, interrupting their current action."},
	],
	"Halberd": [
		{"name": "Sweep", "desc": "Wide 270 degree arc around you. Hits every enemy in range and knocks them back."},
		{"name": "Brace", "desc": "Plant the halberd. Enemies that charge into you take Piercing damage and are staggered."},
	],
	"Spear": [
		{"name": "Lunge", "desc": "Gap close with longer range than the Rapier. A full charge goes further but recovers slower."},
		{"name": "Phalanx", "desc": "Projects a damage-absorbing barrier in front of you. Frontal attacks only."},
	],
	"Shock Lance": [
		{"name": "Discharge", "desc": "Builds electrical charge while held. Release to send a Lightning shockwave along the ground."},
		{"name": "Repulse", "desc": "LMB releases an electrical burst that pushes nearby enemies away and Electrocutes them."},
	],
	"Whip": [
		{"name": "Crack", "desc": "Charged strike at maximum whip range. Applies Bleed and briefly interrupts the target."},
		{"name": "Entangle", "desc": "Wraps the target, rooting it for 2 s. No damage, pure control."},
	],
	"Greataxe": [
		{"name": "Earthquake", "desc": "A heavy slam that leaves a wide field of rough ground. When you leave the field or use a Warcry it ruptures for 60% of the slam's damage."},
		{"name": "Shatter", "desc": "A crushing overhead blow that breaks Armour (3 Armour Shred). Enemies it kills shatter, hitting those around them for 40% of the blow."},
	],
	"Pressure Fist": [
		{"name": "Pressure Blast", "desc": "Charge internal pressure, then release a point-blank cone of force. Massive Stagger, sends enemies flying."},
		{"name": "Stance B", "desc": "Not designed yet."},
	],
}

const RANGED := {
	"Service Pistol": {"name": "Steady Aim", "desc": "Tightens accuracy and increases crit chance while held."},
	"Revolver": {"name": "Fan the Hammer", "desc": "Unloads every remaining chamber in rapid succession. Low accuracy, high burst, forced reload after."},
	"Machine Pistol": {"name": "Suppression", "desc": "Each hit applies a stacking movement slow."},
	"Submachine Gun": {"name": "Full Auto Burst", "desc": "Dumps the magazine in a continuous stream. Staggers enemies hit repeatedly."},
	"Loaded Shotgun": {"name": "Point Blank", "desc": "Bonus damage the closer the target. Maximum at melee range."},
	"Pump Action Shotgun": {"name": "Brace", "desc": "Plant your feet, negating self-knockback. The next shot has double spread and hits everything in a wide cone."},
	"Shortbow": {"name": "Rapid Fire", "desc": "LMB fires one arrow per tap at high speed. Low damage per arrow."},
	"Longbow": {"name": "Snipe", "desc": "High damage arrow that pierces every enemy in a line."},
	"Lever Action Rifle": {"name": "Marksman", "desc": "Longer aim before firing means a bigger hit."},
	"Bolt Action Rifle": {"name": "Breath Control", "desc": "No movement. Removes damage falloff and pierces one target."},
	"Machine Gun": {"name": "Dig In", "desc": "Roots you completely. Massively increased fire rate, reduced recoil."},
	"Battle Rifle": {"name": "Tracer Round", "desc": "The first shot marks the target. Further shots deal increased damage to it for 4 s."},
}

## The bows' second aim stance (Hold X switches, as for melee).
const RANGED_B := {
	"Shortbow": {"name": "Kiting Shot", "desc": "No movement penalty while moving away from where you aim."},
	"Longbow": {"name": "Rain of Arrows", "desc": "Fires in a high arc; volleys rain down on the spot you aim at."},
}

## Conduits, by conduit_stance_type (Patch v3.4 caster stances, v3.6 lines);
## a line's spell_page_modifier / stance_buff picks a more specific entry.
const CONDUIT := {
	"spell_library": {"name": "Spell Library", "desc": "While RMB is held, keys 1-4 cast your Stance Page - four more spells (set on the Abilities screen)."},
	"unleash": {"name": "Unleash", "desc": "Unleashable spells cast while RMB is held fire several copies at once. Mana is paid per copy."},
	"mana_stars": {"name": "Mana Stars", "desc": "Hold RMB; each LMB fires a Mana Star using the gauntlet's damage and infusion, scaled by Spell Power."},
	"battlemage_staff": {"name": "Battlemage", "desc": "RMB strikes out with the staff's reach."},
	"battlemage_gauntlet": {"name": "Battlemage", "desc": "Hold RMB to punch with LMB; a punch that lands sends a Mana Star after it."},
	"spell_damage": {"name": "Stance Buff", "desc": "Spells cast while RMB is held deal 25% more damage."},
	"esoteric_damage": {"name": "Pale Focus", "desc": "Esoteric spells cast while RMB is held deal 30% more damage."},
	"ward_restore": {"name": "Ward Buff", "desc": "Each spell cast while RMB is held restores 8% of your Ward."},
	"double_status": {"name": "Dark Knowledge", "desc": "Stance Page spells apply their status effects twice."},
	"enhanced_status": {"name": "Status Amplifier", "desc": "Stance Page spells' status effects last 50% longer."},
	"pallid": {"name": "Pallid Page", "desc": "Stance Page spells always apply Pallid (enemies deal less damage)."},
	"passive": {"name": "Passive", "desc": "No stance; boosts the main hand's casting."},
}

## {name, desc} for a conduit's stance, with its page restriction appended.
static func for_conduit(conduit: Weapon) -> Dictionary:
	if conduit == null or not conduit.is_conduit:
		return {}
	var key := conduit.conduit_stance_type
	if key == "battlemage":
		key = "battlemage_gauntlet" if conduit.weapon_type == "Spell Gauntlet" else "battlemage_staff"
	if conduit.spell_page_modifier != "":
		key = conduit.spell_page_modifier
	elif conduit.stance_buff != "":
		key = conduit.stance_buff
	var info: Dictionary = CONDUIT.get(key, {}).duplicate()
	if info.is_empty():
		return info
	if conduit.conduit_stance_type == "spell_library" and conduit.spell_page_tag in ["esoteric", "elemental"]:
		info["desc"] += " Only %s spells." % conduit.spell_page_tag.capitalize()
	if conduit.conduit_stance_type == "unleash":
		info["desc"] += " %d copies." % maxi(conduit.unleash_copy_count, CasterStance.MIN_UNLEASH_COPIES)
	return info

## {name, desc} for the weapon's stance on `page` (0 = A, 1 = B), or {} if none is designed.
static func for_weapon(weapon: Weapon, page: int) -> Dictionary:
	if weapon == null:
		return {}
	if weapon.is_ranged:
		if page == 1 and RANGED_B.has(weapon.weapon_type):
			return RANGED_B[weapon.weapon_type]
		return RANGED.get(weapon.weapon_type, {})
	var pages: Array = MELEE.get(weapon.weapon_type, [])
	return pages[page] if page < pages.size() else {}

const BEHAVIOR_DIR := "res://data/stance/instances/"
## Melee stances whose LMB is an instant attack (the rest charge, or are held).
const INSTANT_ATTACKS := [
	MeleeStanceBehavior.MeleeStanceType.WATER_SLICES, MeleeStanceBehavior.MeleeStanceType.SWEEP,
	MeleeStanceBehavior.MeleeStanceType.ARMOR_PIERCE, MeleeStanceBehavior.MeleeStanceType.HOOKING_STRIKE,
	MeleeStanceBehavior.MeleeStanceType.REPULSE,
]
static var _behaviors: Dictionary = {}

## The StanceBehavior data for a weapon's page - same lookup WeaponStance uses.
static func behavior_for(weapon: Weapon, page: int) -> StanceBehavior:
	if weapon == null:
		return null
	if _behaviors.is_empty():
		for file in DirAccess.get_files_at(BEHAVIOR_DIR):
			var path := BEHAVIOR_DIR + file.trim_suffix(".remap")
			if path.ends_with(".tres"):
				var b := load(path) as StanceBehavior
				if b:
					_behaviors[b.weapon_type] = b
	if page == 1 and _behaviors.has(weapon.weapon_type + "_b"):
		return _behaviors[weapon.weapon_type + "_b"]
	if weapon.base_line_id != "" and _behaviors.has(weapon.base_line_id):
		return _behaviors[weapon.base_line_id]
	return _behaviors.get(weapon.weapon_type)

## One short line of what the stance does, from its data where it's an
## attack ("Charge 1s, 300% weapon damage in a 2.5m area"), else its
## description.
static func effect_line(weapon: Weapon, page: int) -> String:
	var info := for_conduit(weapon) if weapon and weapon.is_conduit else for_weapon(weapon, page)
	var b := behavior_for(weapon, page) as MeleeStanceBehavior
	if b == null or b.motion_value_max <= 0.0 or not (b.charge_time > 0.0 or INSTANT_ATTACKS.has(b.stance_type)):
		return info.get("desc", "")
	var damage := "%d%%" % roundi(b.motion_value_max * 100.0)
	if not is_equal_approx(b.motion_value_min, b.motion_value_max):
		damage = "%d-%d%%" % [roundi(b.motion_value_min * 100.0), roundi(b.motion_value_max * 100.0)]
	var hit := "%s weapon damage" % damage
	if b.radius > 0.0:
		hit += " in a %sm area" % _num(b.radius)
	elif b.reach_max > 0.0:
		hit += " up to %sm away" % _num(b.reach_max)
	if b.charge_time > 0.0:
		return "Charge %ss, %s" % [_num(b.charge_time), hit]
	return hit.capitalize().left(1) + hit.substr(1)

static func cooldown_text(weapon: Weapon, page: int) -> String:
	var b := behavior_for(weapon, page)
	return "%ss cooldown" % _num(b.cooldown_seconds) if b and b.cooldown_seconds > 0.0 else ""

static func _num(v: float) -> String:
	return str(int(round(v))) if is_equal_approx(v, round(v)) else "%.1f" % v
