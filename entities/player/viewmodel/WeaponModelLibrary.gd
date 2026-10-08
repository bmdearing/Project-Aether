class_name WeaponModelLibrary
## Builds the first-person model for a weapon type or off-hand item.
##
## Every model is returned in GRIP space: the origin is where the hand closes
## around it. Melee weapons point their blade/head along +Y; guns, crossbows
## and foci aim along -Z; bows stand upright with the string toward +Z.
## Metadata on the returned node:
##   "offhand_grip" (Vector3) - where a second hand goes, absent = one-handed
##   "hide_hand"    (bool)    - the model already includes the hand (gauntlets)
##   "muzzle"       (Vector3) - barrel tip, for muzzle flashes

const PACK := "res://assets/models/pack1/Low Poly Weapon Pack - by Kickin It Studios.fbx_%s.fbx"

## Animation family per weapon type - PlayerArmRig picks rest poses and
## attack clips by family, not by individual type.
const FAMILY := {
	"Shortsword": &"blade", "Saber": &"blade", "Cutlass": &"blade",
	"Dagger": &"thrust", "Rapier": &"thrust", "Athame": &"thrust",
	"Greatsword": &"heavy", "Claymore": &"heavy", "Greataxe": &"heavy",
	"Mace": &"blunt", "War Pick": &"blunt",
	"Spear": &"spear", "Shock Lance": &"spear",
	"Halberd": &"halberd",
	"Staff": &"staff",
	"Whip": &"whip",
	"Gauntlet": &"fist", "Pressure Fist": &"fist", "Spell Gauntlet": &"fist",
	"Wand": &"wand",
	"Service Pistol": &"pistol", "Revolver": &"pistol", "Machine Pistol": &"pistol",
	"Submachine Gun": &"rifle", "Battle Rifle": &"rifle", "Bolt Action Rifle": &"rifle",
	"Lever Action Rifle": &"rifle", "Machine Gun": &"rifle",
	"Pump Action Shotgun": &"rifle", "Loaded Shotgun": &"rifle",
	"Bow": &"bow", "Longbow": &"bow", "Shortbow": &"bow",
	"Crossbow": &"rifle",
}

## Pack models run blade/head-first along model -Z. Spec: [file stem, scale,
## main hand position along model Z, off hand position along model Z or null
## for one-handed]. Hand positions were measured from each mesh's width
## profile (guard = widest slice near the middle, handle = the narrow run
## past it) - the model origins sit at the guard or head, not the handle.
const PACK_MELEE := {
	"Greatsword": ["Great_Sword", 0.42, 0.27, 0.5],
	"Claymore": ["Kriegmesser", 0.46, 0.14, 0.32],
	"Greataxe": ["Double_Axe", 0.8, 0.3, 0.6],
	"Shortsword": ["Arming_Sword", 0.48, 0.18, null],
	"Saber": ["Scimitar", 0.42, 0.3, null],
	"Cutlass": ["Cutlass", 0.55, 0.27, null],
	"Dagger": ["Dagger", 0.6, 0.11, null],
	"Athame": ["Bone_Shiv", 0.6, 0.14, null],
	"Rapier": ["Offset_Sword", 0.5, 0.33, null],
	"Mace": ["Spiked_Club", 0.5, 0.6, null],
	"War Pick": ["War_Hammer", 0.48, 0.7, null],
	"Spear": ["Spear", 0.6, 0.55, -0.15],
	"Shock Lance": ["Flared_Spear", 0.55, 0.65, 0.0],
	"Halberd": ["Halberd", 0.5, 0.8, 0.1],
	"Staff": ["Wizard_Staff", 0.42, -0.05, 0.6],
}
## Glow orbs on magic polearms: [model Z, radius].
const PACK_ORB := {"Staff": [-1.3, 0.05], "Shock Lance": [-1.38, 0.035]}

## Bow limb half-length and brace height (string distance from the grip).
const BOW_SIZE := {"Bow": [0.36, 0.11], "Longbow": [0.44, 0.12], "Shortbow": [0.29, 0.1]}

static var _materials: Dictionary = {}

static func get_family(weapon_type: String) -> StringName:
	return FAMILY.get(weapon_type, &"blade")

static func build(weapon: Weapon) -> Node3D:
	var root := Node3D.new()
	root.name = "WeaponModel"
	# Builders below author guns/gauntlets/crossbows barrel-forward (-Z, top +Y);
	# `inner` turns those to the shared tip=+Y, face=+Z convention.
	var inner := Node3D.new()
	root.add_child(inner)
	var forward_authored := true
	var accent: Color = Constants.DAMAGE_TYPE_COLOR.get(weapon.native_damage_type, Color(0.5, 0.8, 1.0))
	var t := weapon.weapon_type
	if PACK_MELEE.has(t):
		forward_authored = false
		var spec: Array = PACK_MELEE[t]
		_mount_pack_melee(inner, spec)
		if PACK_ORB.has(t):
			var orb: Array = PACK_ORB[t]
			_glow_orb(inner, Vector3(0, (float(spec[2]) - float(orb[0])) * float(spec[1]), 0), orb[1], accent)
	elif BOW_SIZE.has(t):
		forward_authored = false
		_build_bow(inner, BOW_SIZE[t][0], BOW_SIZE[t][1])
	elif t == "Crossbow":
		_mount_pack(inner, "Crossbow", 0.42, Basis.IDENTITY, Vector3(0, 0.05, 0.02))
		inner.set_meta("offhand_grip", Vector3(0, 0.0, -0.18))
		inner.set_meta("muzzle", Vector3(0, 0.07, -0.2))
	else:
		match t:
			"Service Pistol": _build_pistol(inner)
			"Revolver": _build_revolver(inner)
			"Machine Pistol": _build_machine_pistol(inner)
			"Submachine Gun": _build_smg(inner)
			"Battle Rifle": _build_battle_rifle(inner)
			"Bolt Action Rifle": _build_bolt_rifle(inner)
			"Lever Action Rifle": _build_lever_rifle(inner)
			"Machine Gun": _build_machine_gun(inner)
			"Pump Action Shotgun": _build_pump_shotgun(inner)
			"Loaded Shotgun": _build_double_shotgun(inner)
			"Gauntlet", "Pressure Fist", "Spell Gauntlet": _build_gauntlet(inner, t, accent, false)
			"Whip":
				forward_authored = false
				_build_whip(inner)
			"Wand":
				forward_authored = false
				_build_wand(inner, accent)
			_:
				forward_authored = false
				_build_fallback_blade(inner, accent)
	if forward_authored:
		inner.basis = FORWARD_TO_TIP
	_lift_meta(inner, root)
	return root

## Barrel-forward (-Z) authoring -> tip along +Y, top along +Z.
const FORWARD_TO_TIP := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

static func _lift_meta(inner: Node3D, root: Node3D) -> void:
	for key in inner.get_meta_list():
		var value: Variant = inner.get_meta(key)
		root.set_meta(key, inner.basis * value if value is Vector3 else value)

## Second gauntlet for fist weapons, worn on the left hand.
static func build_left_gauntlet(weapon: Weapon) -> Node3D:
	var root := Node3D.new()
	root.name = "LeftGauntlet"
	var inner := Node3D.new()
	inner.basis = FORWARD_TO_TIP
	root.add_child(inner)
	var accent: Color = Constants.DAMAGE_TYPE_COLOR.get(weapon.native_damage_type, Color(0.5, 0.8, 1.0))
	_build_gauntlet(inner, weapon.weapon_type, accent, true)
	_lift_meta(inner, root)
	return root

## Off-hand item held in the left hand: shields and casting foci.
static func build_offhand(item: Item) -> Node3D:
	var root := Node3D.new()
	root.name = "OffhandModel"
	var accent := Color(0.55, 0.75, 1.0)
	if item is Weapon:
		var w := item as Weapon
		accent = Constants.DAMAGE_TYPE_COLOR.get(w.native_damage_type, accent)
		match w.weapon_type:
			"Rod": _build_rod(root, accent)
			"Tome": _build_book(root, Color(0.42, 0.2, 0.12), accent, 0.05)
			"Grimoire": _build_book(root, Color(0.12, 0.1, 0.14), accent, 0.075)
			"Fetish": _build_fetish(root, accent)
			"Talisman": _build_talisman(root, accent)
			_: _build_rod(root, accent)
		return root
	var line := item.base_line_id
	_build_shield(root, line.get_slice("_", 0), Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE))
	return root

# --- pack models ---

static func _mount_pack_melee(root: Node3D, spec: Array) -> void:
	var scale: float = spec[1]
	var hand_z: float = spec[2]
	# Rotate blade-first -Z onto +Y; model point z lands at y = (hand_z - z) * scale.
	_mount_pack(root, spec[0], scale, Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, hand_z * scale, 0))
	if spec[3] != null:
		root.set_meta("offhand_grip", Vector3(0, (hand_z - float(spec[3])) * scale, 0))

static func _mount_pack(root: Node3D, stem: String, scale: float, basis: Basis, offset: Vector3) -> Node3D:
	var scene := load(PACK % stem) as PackedScene
	var model: Node3D = scene.instantiate()
	model.transform = Transform3D(basis.scaled(Vector3.ONE * scale), offset)
	root.add_child(model)
	return model

## Limbs curve back toward the archer so the tips sit on the string plane
## (z = brace). PlayerArmRig draws the string and the nocked arrow itself.
static func _build_bow(root: Node3D, half_length: float, brace: float) -> void:
	_cyl(root, 0.02, 0.02, 0.1, Vector3.ZERO, &"leather")
	for side in [1.0, -1.0]:
		var prev := Vector3(0, 0.04 * side, 0.0)
		var segments := 7
		for i in range(1, segments + 1):
			var f := float(i) / segments
			var next := Vector3(0, (0.04 + (half_length - 0.04) * f) * side, brace * f * f)
			var seg := _cyl(root, lerpf(0.013, 0.006, f), lerpf(0.016, 0.008, f), prev.distance_to(next) + 0.004, (prev + next) * 0.5, &"wood")
			seg.basis = _basis_along(next - prev)
			prev = next
		_sphere(root, 0.009, prev, &"darksteel")
	root.set_meta("bow_tip_top", Vector3(0, half_length, brace))
	root.set_meta("bow_tip_bottom", Vector3(0, -half_length, brace))
	root.set_meta("offhand_grip", Vector3(0.13, -0.03, 0.24))

# --- guns (barrel along -Z, hand on the pistol grip at the origin) ---

static func _build_pistol(root: Node3D) -> void:
	_box(root, Vector3(0.034, 0.042, 0.2), Vector3(0, 0.078, -0.07), &"gunmetal")
	_box(root, Vector3(0.03, 0.03, 0.17), Vector3(0, 0.042, -0.06), &"polymer")
	_box(root, Vector3(0.03, 0.115, 0.048), Vector3(0, -0.015, 0.0), &"polymer", Vector3(-12, 0, 0))
	_box(root, Vector3(0.008, 0.012, 0.012), Vector3(0, 0.104, 0.02), &"steel")
	_box(root, Vector3(0.006, 0.01, 0.01), Vector3(0, 0.104, -0.16), &"steel")
	_trigger_guard(root, Vector3(0, 0.02, -0.04))
	root.set_meta("muzzle", Vector3(0, 0.078, -0.18))

static func _build_revolver(root: Node3D) -> void:
	_cyl(root, 0.012, 0.012, 0.17, Vector3(0, 0.08, -0.15), &"steel", Vector3(90, 0, 0))
	_box(root, Vector3(0.012, 0.016, 0.17), Vector3(0, 0.097, -0.15), &"steel")
	_cyl(root, 0.026, 0.026, 0.055, Vector3(0, 0.067, -0.04), &"gunmetal", Vector3(90, 0, 0))
	_box(root, Vector3(0.026, 0.05, 0.09), Vector3(0, 0.06, -0.02), &"gunmetal")
	_box(root, Vector3(0.03, 0.11, 0.045), Vector3(0, -0.015, 0.02), &"wood", Vector3(-18, 0, 0))
	_box(root, Vector3(0.01, 0.025, 0.02), Vector3(0, 0.095, 0.02), &"steel", Vector3(-30, 0, 0))
	_trigger_guard(root, Vector3(0, 0.02, -0.035))
	root.set_meta("muzzle", Vector3(0, 0.08, -0.24))

static func _build_machine_pistol(root: Node3D) -> void:
	_build_pistol(root)
	_box(root, Vector3(0.024, 0.09, 0.034), Vector3(0, -0.11, 0.01), &"gunmetal", Vector3(-12, 0, 0))
	_box(root, Vector3(0.03, 0.03, 0.05), Vector3(0, 0.078, -0.19), &"steel")
	_box(root, Vector3(0.02, 0.05, 0.03), Vector3(0, 0.03, -0.15), &"polymer")
	root.set_meta("muzzle", Vector3(0, 0.078, -0.22))

static func _build_smg(root: Node3D) -> void:
	_box(root, Vector3(0.048, 0.075, 0.3), Vector3(0, 0.07, -0.1), &"gunmetal")
	_cyl(root, 0.013, 0.013, 0.12, Vector3(0, 0.08, -0.31), &"steel", Vector3(90, 0, 0))
	_box(root, Vector3(0.032, 0.17, 0.045), Vector3(0, -0.05, -0.13), &"polymer", Vector3(8, 0, 0))
	_box(root, Vector3(0.034, 0.1, 0.048), Vector3(0, -0.005, 0.0), &"polymer", Vector3(-12, 0, 0))
	_box(root, Vector3(0.02, 0.02, 0.22), Vector3(0, 0.07, 0.14), &"steel")
	_box(root, Vector3(0.03, 0.07, 0.02), Vector3(0, 0.05, 0.25), &"polymer")
	_box(root, Vector3(0.012, 0.02, 0.04), Vector3(0, 0.12, 0.0), &"steel")
	_trigger_guard(root, Vector3(0, 0.025, -0.04))
	root.set_meta("offhand_grip", Vector3(0, -0.04, -0.13))
	root.set_meta("muzzle", Vector3(0, 0.08, -0.37))

static func _build_battle_rifle(root: Node3D) -> void:
	_box(root, Vector3(0.05, 0.085, 0.42), Vector3(0, 0.07, -0.14), &"gunmetal")
	_box(root, Vector3(0.056, 0.06, 0.24), Vector3(0, 0.07, -0.4), &"polymer")
	_cyl(root, 0.012, 0.012, 0.2, Vector3(0, 0.085, -0.6), &"steel", Vector3(90, 0, 0))
	_cyl(root, 0.02, 0.02, 0.05, Vector3(0, 0.085, -0.7), &"gunmetal", Vector3(90, 0, 0))
	_box(root, Vector3(0.034, 0.14, 0.06), Vector3(0, -0.035, -0.18), &"gunmetal", Vector3(14, 0, 0))
	_box(root, Vector3(0.034, 0.1, 0.048), Vector3(0, -0.005, 0.0), &"polymer", Vector3(-14, 0, 0))
	_box(root, Vector3(0.045, 0.1, 0.24), Vector3(0, 0.05, 0.17), &"polymer")
	_cyl(root, 0.02, 0.02, 0.15, Vector3(0, 0.145, -0.12), &"gunmetal", Vector3(90, 0, 0))
	_box(root, Vector3(0.02, 0.025, 0.06), Vector3(0, 0.12, -0.12), &"steel")
	_trigger_guard(root, Vector3(0, 0.025, -0.045))
	root.set_meta("offhand_grip", Vector3(0, 0.02, -0.4))
	root.set_meta("muzzle", Vector3(0, 0.085, -0.73))

static func _build_bolt_rifle(root: Node3D) -> void:
	_box(root, Vector3(0.05, 0.065, 0.62), Vector3(0, 0.045, -0.2), &"wood")
	_box(root, Vector3(0.048, 0.11, 0.24), Vector3(0, 0.03, 0.2), &"wood", Vector3(-6, 0, 0))
	_box(root, Vector3(0.036, 0.04, 0.2), Vector3(0, 0.09, -0.07), &"gunmetal")
	_cyl(root, 0.011, 0.011, 0.5, Vector3(0, 0.09, -0.45), &"gunmetal", Vector3(90, 0, 0))
	_cyl(root, 0.022, 0.022, 0.24, Vector3(0, 0.15, -0.08), &"gunmetal", Vector3(90, 0, 0))
	_cyl(root, 0.027, 0.022, 0.04, Vector3(0, 0.15, -0.21), &"gunmetal", Vector3(90, 0, 0))
	_box(root, Vector3(0.012, 0.03, 0.03), Vector3(0, 0.125, -0.08), &"steel")
	_cyl(root, 0.007, 0.007, 0.07, Vector3(0.04, 0.09, 0.0), &"steel", Vector3(0, 0, 90))
	_sphere(root, 0.013, Vector3(0.075, 0.09, 0.0), &"steel")
	_trigger_guard(root, Vector3(0, 0.0, -0.03))
	root.set_meta("offhand_grip", Vector3(0, 0.0, -0.36))
	root.set_meta("muzzle", Vector3(0, 0.09, -0.7))

static func _build_lever_rifle(root: Node3D) -> void:
	_box(root, Vector3(0.046, 0.05, 0.3), Vector3(0, 0.05, -0.35), &"wood")
	_box(root, Vector3(0.046, 0.11, 0.25), Vector3(0, 0.03, 0.2), &"wood", Vector3(-8, 0, 0))
	_box(root, Vector3(0.04, 0.07, 0.15), Vector3(0, 0.07, -0.04), &"brass")
	_cyl(root, 0.012, 0.012, 0.5, Vector3(0, 0.095, -0.4), &"gunmetal", Vector3(90, 0, 0))
	_cyl(root, 0.01, 0.01, 0.42, Vector3(0, 0.068, -0.4), &"gunmetal", Vector3(90, 0, 0))
	var lever := _torus(root, 0.025, 0.04, Vector3(0, -0.0, 0.0), &"steel", Vector3(0, 0, 90))
	lever.scale = Vector3(1, 1, 1.4)
	root.set_meta("offhand_grip", Vector3(0, 0.02, -0.33))
	root.set_meta("muzzle", Vector3(0, 0.095, -0.65))

static func _build_machine_gun(root: Node3D) -> void:
	_box(root, Vector3(0.08, 0.11, 0.42), Vector3(0, 0.08, -0.12), &"gunmetal")
	_cyl(root, 0.035, 0.035, 0.32, Vector3(0, 0.09, -0.48), &"polymer", Vector3(90, 0, 0))
	_cyl(root, 0.017, 0.017, 0.22, Vector3(0, 0.09, -0.72), &"steel", Vector3(90, 0, 0))
	_box(root, Vector3(0.1, 0.12, 0.12), Vector3(-0.08, 0.05, -0.12), &"olive")
	_box(root, Vector3(0.04, 0.1, 0.05), Vector3(0, -0.0, 0.0), &"polymer", Vector3(-12, 0, 0))
	_box(root, Vector3(0.06, 0.12, 0.22), Vector3(0, 0.06, 0.2), &"polymer")
	var handle := _torus(root, 0.03, 0.045, Vector3(0, 0.16, -0.18), &"gunmetal", Vector3(0, 0, 90))
	handle.scale = Vector3(1, 1, 1.5)
	_cyl(root, 0.007, 0.007, 0.25, Vector3(0.02, 0.05, -0.55), &"steel", Vector3(90, 0, 0))
	_cyl(root, 0.007, 0.007, 0.25, Vector3(-0.02, 0.05, -0.55), &"steel", Vector3(90, 0, 0))
	_trigger_guard(root, Vector3(0, 0.025, -0.045))
	root.set_meta("offhand_grip", Vector3(0, 0.04, -0.36))
	root.set_meta("muzzle", Vector3(0, 0.09, -0.83))

static func _build_pump_shotgun(root: Node3D) -> void:
	_box(root, Vector3(0.05, 0.075, 0.22), Vector3(0, 0.065, -0.06), &"gunmetal")
	_cyl(root, 0.017, 0.017, 0.48, Vector3(0, 0.095, -0.4), &"gunmetal", Vector3(90, 0, 0))
	_cyl(root, 0.014, 0.014, 0.4, Vector3(0, 0.06, -0.36), &"gunmetal", Vector3(90, 0, 0))
	_cyl(root, 0.026, 0.026, 0.16, Vector3(0, 0.06, -0.36), &"wood", Vector3(90, 0, 0))
	_box(root, Vector3(0.034, 0.1, 0.048), Vector3(0, -0.005, 0.01), &"wood", Vector3(-14, 0, 0))
	_box(root, Vector3(0.045, 0.1, 0.25), Vector3(0, 0.045, 0.19), &"wood", Vector3(-6, 0, 0))
	_trigger_guard(root, Vector3(0, 0.02, -0.04))
	root.set_meta("offhand_grip", Vector3(0, 0.03, -0.36))
	root.set_meta("muzzle", Vector3(0, 0.095, -0.64))

static func _build_double_shotgun(root: Node3D) -> void:
	_cyl(root, 0.016, 0.016, 0.5, Vector3(0.016, 0.085, -0.36), &"gunmetal", Vector3(90, 0, 0))
	_cyl(root, 0.016, 0.016, 0.5, Vector3(-0.016, 0.085, -0.36), &"gunmetal", Vector3(90, 0, 0))
	_box(root, Vector3(0.05, 0.035, 0.24), Vector3(0, 0.06, -0.27), &"wood")
	_box(root, Vector3(0.05, 0.07, 0.1), Vector3(0, 0.07, -0.05), &"steel")
	_box(root, Vector3(0.034, 0.1, 0.05), Vector3(0, -0.005, 0.01), &"wood", Vector3(-16, 0, 0))
	_box(root, Vector3(0.045, 0.1, 0.24), Vector3(0, 0.04, 0.18), &"wood", Vector3(-8, 0, 0))
	_trigger_guard(root, Vector3(0, 0.02, -0.04))
	root.set_meta("offhand_grip", Vector3(0, 0.03, -0.28))
	root.set_meta("muzzle", Vector3(0, 0.085, -0.61))

static func _trigger_guard(root: Node3D, pos: Vector3) -> void:
	var guard := _torus(root, 0.016, 0.022, pos, &"polymer", Vector3(0, 0, 90))
	guard.scale = Vector3(1, 1, 1.3)

# --- melee placeholders (blade/handle along +Y) ---

static func _build_whip(root: Node3D) -> void:
	_cyl(root, 0.018, 0.016, 0.22, Vector3(0, 0.02, 0), &"leather")
	_sphere(root, 0.024, Vector3(0, -0.1, 0), &"steel")
	_cyl(root, 0.021, 0.021, 0.025, Vector3(0, 0.13, 0), &"steel")
	# The lash hangs from the tip in a loose curl.
	var p := Vector3(0, 0.14, 0)
	var dir := Vector3(0, 0.6, -0.8).normalized()
	var radius := 0.012
	for i in 14:
		var seg_len := 0.07
		var next := p + dir * seg_len
		var seg := _cyl(root, radius, radius * 0.9, seg_len, (p + next) * 0.5, &"leather")
		seg.basis = _basis_along(dir)
		p = next
		dir = (dir + Vector3(0.05, -0.22, 0.04)).normalized()
		radius = maxf(radius * 0.9, 0.004)

static func _build_gauntlet(root: Node3D, weapon_type: String, accent: Color, mirrored: bool) -> void:
	root.set_meta("hide_hand", true)
	var side := -1.0 if mirrored else 1.0
	var metal := &"steel" if weapon_type != "Spell Gauntlet" else &"darksteel"
	_box(root, Vector3(0.1, 0.095, 0.11), Vector3(0, 0, -0.01), metal)
	_box(root, Vector3(0.105, 0.03, 0.035), Vector3(0, 0.045, -0.06), &"darksteel")
	for k in 4:
		_box(root, Vector3(0.022, 0.025, 0.03), Vector3((k - 1.5) * 0.024, 0.052, -0.075), metal)
	_box(root, Vector3(0.035, 0.04, 0.06), Vector3(-0.055 * side, -0.01, -0.03), metal)
	_cyl(root, 0.05, 0.045, 0.1, Vector3(0, -0.005, 0.09), metal, Vector3(90, 0, 0))
	match weapon_type:
		"Pressure Fist":
			_cyl(root, 0.012, 0.012, 0.18, Vector3(0.03, 0.06, 0.05), &"brass", Vector3(90, 0, 0))
			_cyl(root, 0.012, 0.012, 0.18, Vector3(-0.03, 0.06, 0.05), &"brass", Vector3(90, 0, 0))
			_cyl(root, 0.03, 0.03, 0.09, Vector3(0, 0.06, 0.17), &"brass", Vector3(90, 0, 0))
			_glow_box(root, Vector3(0.06, 0.012, 0.02), Vector3(0, 0.077, 0.12), accent)
		"Spell Gauntlet":
			_glow_box(root, Vector3(0.012, 0.012, 0.13), Vector3(0, 0.05, 0.1), accent)
			_glow_orb(root, Vector3(0, 0.05, 0.0), 0.022, accent)
		_:
			_box(root, Vector3(0.06, 0.012, 0.12), Vector3(0, 0.052, 0.11), &"darksteel")

static func _build_wand(root: Node3D, accent: Color) -> void:
	_cyl(root, 0.014, 0.009, 0.34, Vector3(0, 0.1, 0), &"wood")
	_cyl(root, 0.017, 0.017, 0.05, Vector3(0, -0.06, 0), &"leather")
	_cyl(root, 0.016, 0.012, 0.02, Vector3(0, 0.25, 0), &"brass")
	_glow_orb(root, Vector3(0, 0.285, 0), 0.022, accent)

static func _build_fallback_blade(root: Node3D, accent: Color) -> void:
	_box(root, Vector3(0.05, 0.42, 0.012), Vector3(0, 0.27, 0), &"steel")
	_box(root, Vector3(0.14, 0.022, 0.03), Vector3(0, 0.05, 0), &"darksteel")
	_cyl(root, 0.017, 0.017, 0.12, Vector3(0, -0.02, 0), &"leather")
	_glow_box(root, Vector3(0.012, 0.3, 0.014), Vector3(0, 0.27, 0), accent)

# --- off-hand items (held in the left hand; foci aim along -Z/up) ---

static func _build_rod(root: Node3D, accent: Color) -> void:
	_cyl(root, 0.016, 0.014, 0.38, Vector3(0, 0.1, 0), &"darksteel")
	_cyl(root, 0.022, 0.022, 0.03, Vector3(0, 0.29, 0), &"brass")
	for k in 3:
		var a := TAU * k / 3.0
		_box(root, Vector3(0.012, 0.07, 0.012), Vector3(cos(a) * 0.03, 0.33, sin(a) * 0.03), &"brass", Vector3(0, -rad_to_deg(a), 20))
	_glow_orb(root, Vector3(0, 0.34, 0), 0.03, accent)

static func _build_book(root: Node3D, cover: Color, accent: Color, thickness: float) -> void:
	# Held upright by the spine, cover facing away from the camera.
	var mat := _flat(cover, 0.8, 0.0)
	_box_mat(root, Vector3(0.17, 0.23, thickness), Vector3(0.07, 0.08, 0), mat)
	_box(root, Vector3(0.16, 0.22, thickness * 0.8), Vector3(0.075, 0.08, 0.002), &"paper")
	_box(root, Vector3(0.02, 0.235, thickness + 0.008), Vector3(-0.012, 0.08, 0), &"brass")
	_glow_box(root, Vector3(0.06, 0.06, 0.004), Vector3(0.07, 0.09, -thickness * 0.5 - 0.002), accent)

static func _build_fetish(root: Node3D, accent: Color) -> void:
	_cyl(root, 0.013, 0.011, 0.3, Vector3(0, 0.07, 0), &"wood")
	_sphere(root, 0.045, Vector3(0, 0.25, 0), &"bone")
	_box(root, Vector3(0.05, 0.02, 0.03), Vector3(0, 0.22, -0.03), &"bone")
	_glow_orb(root, Vector3(0.016, 0.26, -0.038), 0.009, accent)
	_glow_orb(root, Vector3(-0.016, 0.26, -0.038), 0.009, accent)
	for k in 3:
		_box(root, Vector3(0.012, 0.09, 0.004), Vector3((k - 1) * 0.02, 0.16, 0.03), &"feather", Vector3(0, 0, (k - 1) * 18.0))

static func _build_talisman(root: Node3D, accent: Color) -> void:
	# Hangs from the fist on a short chain.
	for k in 4:
		_torus(root, 0.004, 0.009, Vector3(0, -0.01 - k * 0.016, 0), &"brass", Vector3(0, 90 * (k % 2), 0))
	_torus(root, 0.035, 0.05, Vector3(0, -0.12, 0), &"brass", Vector3(90, 0, 0))
	_glow_orb(root, Vector3(0, -0.12, 0), 0.03, accent)

static func _build_shield(root: Node3D, base: String, trim: Color) -> void:
	# Face toward -Z, strap side toward the camera; the hand sits on the strap.
	var face := Node3D.new()
	face.position = Vector3(0, 0.05, -0.06)
	root.add_child(face)
	match base:
		"buckler":
			_cyl(face, 0.17, 0.17, 0.025, Vector3.ZERO, &"wood", Vector3(90, 0, 0))
			_torus(face, 0.16, 0.18, Vector3.ZERO, &"steel", Vector3(90, 0, 0))
			_sphere(face, 0.05, Vector3(0, 0, -0.015), &"steel")
		"tower", "pavise":
			_box(face, Vector3(0.4, 0.72, 0.035), Vector3(0, 0.05, 0), &"wood")
			_box(face, Vector3(0.42, 0.04, 0.045), Vector3(0, 0.4, 0), &"steel")
			_box(face, Vector3(0.42, 0.04, 0.045), Vector3(0, -0.3, 0), &"steel")
			if base == "pavise":
				_box(face, Vector3(0.06, 0.72, 0.06), Vector3(0, 0.05, -0.02), &"steel")
		"kite", "rune":
			_box(face, Vector3(0.34, 0.32, 0.03), Vector3(0, 0.12, 0), &"steel")
			_box(face, Vector3(0.24, 0.24, 0.03), Vector3(0, -0.07, 0), &"steel", Vector3(0, 0, 45))
			_box(face, Vector3(0.05, 0.4, 0.035), Vector3(0, 0.07, -0.005), &"darksteel")
			if base == "rune":
				_glow_box(face, Vector3(0.12, 0.12, 0.01), Vector3(0, 0.12, -0.02), Color(0.4, 0.8, 1.0))
		_:
			# great / spiked / warded: big round shield
			_cyl(face, 0.27, 0.27, 0.03, Vector3.ZERO, &"wood", Vector3(90, 0, 0))
			_torus(face, 0.26, 0.29, Vector3.ZERO, &"steel", Vector3(90, 0, 0))
			_sphere(face, 0.06, Vector3(0, 0, -0.02), &"steel")
			if base == "spiked":
				for k in 6:
					var a := TAU * k / 6.0
					_cyl(face, 0.0, 0.02, 0.07, Vector3(cos(a) * 0.17, sin(a) * 0.17, -0.04), &"steel", Vector3(-90, 0, 0))
			elif base == "warded":
				_torus(face, 0.17, 0.19, Vector3(0, 0, -0.02), &"glow", Vector3(90, 0, 0)).material_override = _glow(Color(0.5, 0.75, 1.0))
	var rim := _box(face, Vector3(0.06, 0.06, 0.01), Vector3(0, 0, 0.03), &"leather")
	rim.material_override = _flat(trim.darkened(0.3), 0.6, 0.2)

# --- primitives ---

static func _mat(kind: StringName) -> Material:
	if _materials.has(kind):
		return _materials[kind]
	var m: StandardMaterial3D
	match kind:
		&"steel": m = _flat(Color(0.72, 0.74, 0.78), 0.32, 0.75)
		&"darksteel": m = _flat(Color(0.26, 0.27, 0.3), 0.4, 0.7)
		&"gunmetal": m = _flat(Color(0.3, 0.31, 0.34), 0.4, 0.6)
		&"polymer": m = _flat(Color(0.22, 0.22, 0.24), 0.7, 0.0)
		&"olive": m = _flat(Color(0.3, 0.33, 0.2), 0.8, 0.0)
		&"wood": m = _flat(Color(0.45, 0.27, 0.14), 0.75, 0.0)
		&"leather": m = _flat(Color(0.3, 0.18, 0.1), 0.85, 0.0)
		&"brass": m = _flat(Color(0.78, 0.6, 0.28), 0.35, 0.8)
		&"bone": m = _flat(Color(0.86, 0.82, 0.7), 0.7, 0.0)
		&"paper": m = _flat(Color(0.9, 0.86, 0.74), 0.9, 0.0)
		&"feather": m = _flat(Color(0.55, 0.15, 0.12), 0.9, 0.0)
		_: m = _flat(Color(0.6, 0.6, 0.6), 0.6, 0.0)
	_materials[kind] = m
	return m

static func _flat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

static func _glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _box(parent: Node3D, size: Vector3, pos: Vector3, kind: StringName, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	return _box_mat(parent, size, pos, _mat(kind), rot_deg)

static func _box_mat(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, mesh, pos, mat, rot_deg)

## Cylinder along local +Y (rotate X 90 to run it along Z).
static func _cyl(parent: Node3D, top_r: float, bottom_r: float, height: float, pos: Vector3, kind: StringName, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	return _add(parent, mesh, pos, _mat(kind), rot_deg)

static func _sphere(parent: Node3D, r: float, pos: Vector3, kind: StringName) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _add(parent, mesh, pos, _mat(kind), Vector3.ZERO)

## Torus ring lies in local XZ; rotate X 90 to face it toward -Z.
static func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, kind: StringName, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 16
	mesh.ring_segments = 6
	return _add(parent, mesh, pos, _mat(kind), rot_deg)

static func _glow_orb(parent: Node3D, pos: Vector3, r: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	return _add(parent, mesh, pos, _glow(color), Vector3.ZERO)

static func _glow_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	return _box_mat(parent, size, pos, _glow(color))

static func _basis_along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
