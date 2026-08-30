extends Node3D
class_name PlayerArmRig
## Procedural low-poly first-person arm rig (2026-08-30) - first piece of
## the Dark Messiah-style animation engine pass (deferred in full per the
## user's own sequencing choice; this is the rig itself, not the whole
## stance/moveset system). No new assets: mesh is built at runtime with
## SurfaceTool, matching the "no skeleton/body exists yet" constraint the
## procedural weapon-tween system was originally chosen under.
##
## Arm MESHES are currently OFF (SHOW_ARM_MESH = false, user request,
## 2026-08-30 later still): "letting go of the arms... just letting the
## meshes [i.e. the weapon] do the talking." The visible arm geometry had
## been the single biggest source of bugs/iteration this session
## (invisible mesh, wrong grip anchor, blending into the background, the
## stance pose swinging off-screen, the off-hand losing the sword) versus
## what it actually added - the weighty-swing feel comes from the
## weapon's own arc/timing/hitstop, not from rendering the arm. The
## SKELETON still exists and still drives the swing (see below) - only
## the mesh-building call is skipped. Flip SHOW_ARM_MESH back to true to
## re-enable; the generation code (_build_mesh() etc.) is untouched.
##
## Three-bone chain per arm (UpperArm -> Forearm -> Hand). Weapon meshes
## attach to the primary arm's Hand bone via a BoneAttachment3D, so
## PlayerMeleeAttack's swing rotates a real bone chain instead of
## tweening one rigid WeaponSocket node - this part is unaffected by
## SHOW_ARM_MESH, the weapon still swings the same way either way.
##
## Second arm (2026-08-30 follow-up, user request: "two handed weapons
## should clearly need two hands"): set_two_handed(true) builds a second,
## unarmed arm chain that tracks a grip point near the primary hand with a
## real 2-bone IK (see _solve_offhand_ik()) - even with SHOW_ARM_MESH off
## this still runs (harmlessly, on invisible bones) so re-enabling the
## mesh doesn't also require re-deriving this.
##
## All primary-arm coordinates are in ArmRig-local space, which sits at
## WeaponSocket's origin (Player.tscn) - i.e. roughly where the old flat
## WeaponMesh used to sit relative to the camera.

const SHOW_ARM_MESH := false

## Local coordinates put the Hand bone at the REAL VISIBLE GRIP of the
## equipped weapon model, not WeaponMesh's own (near-empty) pivot node.
## Player._update_weapon_model() nests the actual weapon scene under
## WeaponMesh with its own extra local offset (Vector3(0.4, -0.4, 0.35))
## for a "held" look - measured at runtime via a temporary debug print
## (arm_rig.to_local(_weapon_model.global_transform.origin)) rather than
## computed by hand, since two earlier attempts at hand-placing this rig
## (once too close to camera and invisible, once anchored to WeaponMesh's
## own pivot instead of the real rendered blade) both looked plausible on
## paper and were both wrong - see PATCH_NOTES.md for the full history.
## This also makes the swing's rotation pivot land at the actual grip
## instead of empty space, which the earlier placements didn't.
const HAND_POS := Vector3(0.513, -0.189, -0.5)
const FOREARM_POS := HAND_POS + Vector3(-0.05, -0.20, 0.45)
const UPPER_ARM_POS := FOREARM_POS + Vector3(-0.05, -0.15, 0.45)

## Off-hand shoulder - a modest "shoulder width" step left of the primary
## shoulder (same height/depth), NOT a full mirror across camera-center.
## First attempt used a full mirror (~1.5 units away from the primary
## hand's own area) and the off-hand's 2-bone IK (see _solve_offhand_ik())
## couldn't reach the primary hand through most of a swing - verified
## numerically (a scratch test measuring hand-to-hand drift came back
## ~0.58 units off, i.e. maxed out at full extension, nowhere near the
## target) before this was corrected, not just eyeballed.
const OFFHAND_SHOULDER_POS := UPPER_ARM_POS + Vector3(-0.5, 0.0, 0.0)
const OFFHAND_HAND_POS := HAND_POS + Vector3(-0.12, 0.10, 0.25)
const OFFHAND_FOREARM_POS := (OFFHAND_SHOULDER_POS + OFFHAND_HAND_POS) * 0.5 + Vector3(0.0, -0.05, 0.05)
## How much the off-hand's IK target actually follows the primary hand's
## full motion vs. staying near its own rest spot - 1.0 = exact 1:1 follow
## (verified unreachable through most of a real swing, see
## OFFHAND_SHOULDER_POS's own comment), 0.0 = never moves at all (the
## original bug, just via a different mechanism). Tuned empirically via a
## scratch test measuring hand-to-hand drift, not eyeballed.
const OFFHAND_TRACKING_DAMPING := 0.5

enum PoseSet { CLEAVE, SWEEP_RIGHT, SWEEP_LEFT, BIG_SWEEP, DASH_THRUST, GUARD }

## One arm's runtime rig state (skeleton + bone indices). Two of these
## can exist at once (primary, off-hand) - see set_two_handed().
class _Arm:
	var skeleton: Skeleton3D
	var upper_arm_bone: int = -1
	var forearm_bone: int = -1
	var hand_bone: int = -1

var _primary: _Arm
var _offhand: _Arm = null
var hand_attachment: BoneAttachment3D
## Kept for existing external readers (PlayerMeleeAttack's scratch tests
## read this directly) - always the primary arm's skeleton.
var skeleton: Skeleton3D:
	get: return _primary.skeleton if _primary else null

var _rest_pose: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY, Quaternion.IDENTITY]
var _poses: Dictionary = {}  # PoseSet -> {windup: Array[Quaternion], strike: Array[Quaternion]}
var _swing_tween: Tween
var _current_pose: Array[Quaternion]  # what's actually applied right now, so a new swing can blend from mid-motion instead of snapping from rest
var _offhand_upper_len: float = 0.0
var _offhand_forearm_len: float = 0.0

func _ready() -> void:
	_current_pose = _rest_pose.duplicate()
	_offhand_upper_len = (OFFHAND_FOREARM_POS - OFFHAND_SHOULDER_POS).length()
	_offhand_forearm_len = (OFFHAND_HAND_POS - OFFHAND_FOREARM_POS).length()
	_primary = _build_arm("Skeleton3D", UPPER_ARM_POS, FOREARM_POS, HAND_POS, true)
	_reparent_weapon_mesh()
	_build_swing_poses()

## Invented swing choreography (no doc source, same status as Dash/Slide
## elsewhere in this project). Five pose sets:
## - CLEAVE: original diagonal wind-up-and-cut.
## - SWEEP_RIGHT/SWEEP_LEFT: horizontal slashes (user request: "feel free
##   to sweep from side to side as well") - mostly shoulder yaw, arm
##   stays more extended than the vertical cleave.
## - BIG_SWEEP: an exaggerated SWEEP for the Greatsword's stance special
##   ("a great sword might have a big sweep"). User feedback (2026-08-30
##   follow-up): the original 70 degree shoulder yaw here, further scaled
##   by SPECIAL_INTENSITY_MULTIPLIER on top of the weapon's own swing
##   intensity, swung the sword ~114 degrees and off past the edge of the
##   screen - halved to a still-big-but-framed magnitude.
## - DASH_THRUST: arm draws back then extends straight out, paired in
##   PlayerMeleeAttack with a real forward Player dash so it reads as a
##   lunging stab ("a rapier might dash and thrust in one direction" - no
##   Rapier item exists yet, mapped onto Dagger as the closest existing
##   light one-handed weapon; see PATCH_NOTES.md).
## - GUARD: NOT an attack pose - this is what WeaponStance holds while
##   right-click is down. User feedback (2026-08-30 follow-up): stance
##   was previously reusing BIG_SWEEP/DASH_THRUST's own windup pose at
##   an even further boosted intensity, which is what caused the
##   "sword and arms disappear to the sides" bug above - a small, mostly
##   rest-adjacent raise instead, so the weapon stays clearly on-screen
##   the way a real held-ready pose (poised, blade up and visible) would.
func _build_swing_poses() -> void:
	_poses[PoseSet.CLEAVE] = {
		"windup": [_euler_deg(-25.0, 15.0, 30.0), _euler_deg(-55.0, 0.0, 0.0), _euler_deg(-15.0, 0.0, 0.0)],
		"strike": [_euler_deg(50.0, -25.0, -40.0), _euler_deg(25.0, 0.0, 0.0), _euler_deg(30.0, 0.0, 20.0)],
	}
	_poses[PoseSet.SWEEP_RIGHT] = {
		"windup": [_euler_deg(-5.0, 45.0, 10.0), _euler_deg(-15.0, 0.0, 0.0), _euler_deg(-10.0, 0.0, 0.0)],
		"strike": [_euler_deg(10.0, -50.0, -15.0), _euler_deg(10.0, 0.0, 0.0), _euler_deg(15.0, 0.0, 20.0)],
	}
	_poses[PoseSet.SWEEP_LEFT] = {
		"windup": [_euler_deg(-5.0, -45.0, -10.0), _euler_deg(-15.0, 0.0, 0.0), _euler_deg(-10.0, 0.0, 0.0)],
		"strike": [_euler_deg(10.0, 50.0, 15.0), _euler_deg(10.0, 0.0, 0.0), _euler_deg(15.0, 0.0, -20.0)],
	}
	_poses[PoseSet.BIG_SWEEP] = {
		"windup": [_euler_deg(-8.0, 35.0, 10.0), _euler_deg(-18.0, 0.0, 0.0), _euler_deg(-10.0, 0.0, 0.0)],
		"strike": [_euler_deg(15.0, -40.0, -18.0), _euler_deg(15.0, 0.0, 0.0), _euler_deg(18.0, 0.0, 22.0)],
	}
	_poses[PoseSet.DASH_THRUST] = {
		"windup": [_euler_deg(-10.0, 5.0, 10.0), _euler_deg(-20.0, 0.0, 0.0), _euler_deg(-5.0, 0.0, 0.0)],
		"strike": [_euler_deg(20.0, 0.0, -5.0), _euler_deg(45.0, 0.0, 0.0), _euler_deg(10.0, 0.0, 5.0)],
	}
	# Modest raise from rest - blade tilts up and slightly across the body,
	# staying in frame the whole time (see the enum-comment block above).
	_poses[PoseSet.GUARD] = {
		"windup": [_euler_deg(-8.0, 8.0, 6.0), _euler_deg(-12.0, 0.0, 0.0), _euler_deg(-6.0, 0.0, 0.0)],
		"strike": [_euler_deg(-8.0, 8.0, 6.0), _euler_deg(-12.0, 0.0, 0.0), _euler_deg(-6.0, 0.0, 0.0)],
	}

static func _euler_deg(x: float, y: float, z: float) -> Quaternion:
	return Basis.from_euler(Vector3(deg_to_rad(x), deg_to_rad(y), deg_to_rad(z))).get_rotation_quaternion()

## Builds one 3-bone arm (its own Skeleton3D, no rendered mesh - see
## SHOW_ARM_MESH). `build_hand_attachment` is only true for the primary
## arm - the off-hand doesn't hold anything of its own, it just tracks a
## grip point near the primary hand (see _solve_offhand_ik()).
func _build_arm(skeleton_name: String, shoulder: Vector3, elbow: Vector3, hand: Vector3, build_hand_attachment: bool) -> _Arm:
	var arm := _Arm.new()
	arm.skeleton = Skeleton3D.new()
	arm.skeleton.name = skeleton_name
	add_child(arm.skeleton)

	arm.upper_arm_bone = arm.skeleton.add_bone("UpperArm")
	arm.skeleton.set_bone_rest(arm.upper_arm_bone, Transform3D(Basis.IDENTITY, shoulder))

	arm.forearm_bone = arm.skeleton.add_bone("Forearm")
	arm.skeleton.set_bone_parent(arm.forearm_bone, arm.upper_arm_bone)
	arm.skeleton.set_bone_rest(arm.forearm_bone, Transform3D(Basis.IDENTITY, elbow - shoulder))

	arm.hand_bone = arm.skeleton.add_bone("Hand")
	arm.skeleton.set_bone_parent(arm.hand_bone, arm.forearm_bone)
	arm.skeleton.set_bone_rest(arm.hand_bone, Transform3D(Basis.IDENTITY, hand - elbow))

	arm.skeleton.reset_bone_poses()

	if build_hand_attachment:
		hand_attachment = BoneAttachment3D.new()
		hand_attachment.name = "HandAttachment"
		arm.skeleton.add_child(hand_attachment)
		hand_attachment.bone_name = "Hand"
		hand_attachment.set_bone_idx(arm.hand_bone)

	if SHOW_ARM_MESH:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "ArmMesh"
		mesh_instance.mesh = _build_mesh(arm.upper_arm_bone, arm.forearm_bone, arm.hand_bone, shoulder, elbow, hand)
		arm.skeleton.add_child(mesh_instance)
		# No custom Skin resource - leaving `skin` null makes MeshInstance3D
		# auto-generate one from the skeleton's current rest pose (each ARRAY_BONES
		# index binding directly to that same skeleton bone index, bind pose =
		# that bone's rest transform). A hand-built Skin here previously left the
		# whole arm invisible - Skin.add_bind()'s pose parameter convention
		# (bind vs. inverse-bind) wasn't actually verified against this Godot
		# version, so trust the engine's own rest-pose-derived default instead
		# of a manually-inverted transform that may have been inverted twice.
		mesh_instance.skeleton = mesh_instance.get_path_to(arm.skeleton)
		mesh_instance.material_override = _build_material()
	return arm

## The pre-existing WeaponMesh (still declared statically in Player.tscn,
## sibling of this node, carrying AttackHitbox + its CollisionShape3D)
## moves onto the primary arm's Hand bone here. keep_global_transform=true
## means its visual resting position/rotation is unchanged from before
## this rig existed - only its parent (and therefore its behavior during
## a swing) changes.
func _reparent_weapon_mesh() -> void:
	var weapon_mesh := get_node_or_null("WeaponMesh")
	if weapon_mesh == null:
		return
	weapon_mesh.reparent(hand_attachment, true)

## User request (2026-08-30): "Two handed weapons should clearly need two
## hands." Called from Player._update_active_weapon_visual() whenever
## equipment changes. Builds/tears down a second, unarmed arm reaching to
## a secondary grip point near the primary hand (see OFFHAND_* constants)
## - it doesn't get its own weapon or hand attachment, and it shares
## whatever pose the primary arm is playing (see _apply_pose()).
func set_two_handed(enabled: bool) -> void:
	if enabled == (_offhand != null):
		return
	if enabled:
		_offhand = _build_arm("OffhandSkeleton3D", OFFHAND_SHOULDER_POS, OFFHAND_FOREARM_POS, OFFHAND_HAND_POS, false)
		_apply_pose(1.0, _current_pose, _current_pose)  # snap the new arm to whatever pose is already playing, not rest
	else:
		_offhand.skeleton.queue_free()
		_offhand = null

func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# Confirmed by screenshot (2026-08-30): the mesh renders correctly, an
	# earlier muted brown just blended into TestArena's own brown floor -
	# a real lighting-independent gauntlet color, not unshaded, so facet
	# edges actually read via shading instead of flattening into one
	# undifferentiated blob. Cull stays disabled since this mesh's winding
	# order was hand-picked, not verified face-by-face.
	mat.albedo_color = Color(0.22, 0.26, 0.34)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _build_mesh(upper_arm_bone: int, forearm_bone: int, hand_bone: int, shoulder: Vector3, elbow: Vector3, hand: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Shoulder cuff - bound to UpperArm, short stub above the pivot.
	var cuff_dir := (shoulder - elbow).normalized() if shoulder != elbow else Vector3.UP
	_add_tapered_box(st, upper_arm_bone, shoulder + cuff_dir * 0.11, shoulder, Vector2(0.085, 0.085), Vector2(0.075, 0.075))
	# Upper arm - bound to UpperArm, shoulder pivot to elbow pivot.
	_add_tapered_box(st, upper_arm_bone, shoulder, elbow, Vector2(0.075, 0.075), Vector2(0.06, 0.06))
	# Forearm - bound to Forearm, elbow pivot to wrist pivot.
	_add_tapered_box(st, forearm_bone, elbow, hand, Vector2(0.06, 0.06), Vector2(0.05, 0.05))
	# Hand/glove - bound to Hand, a small knuckle stub past the grip/pivot.
	var hand_dir := (hand - elbow).normalized() if hand != elbow else Vector3.FORWARD
	_add_tapered_box(st, hand_bone, hand, hand + hand_dir * 0.07, Vector2(0.055, 0.05), Vector2(0.045, 0.045))

	st.generate_normals()
	return st.commit()

## Builds one 6-sided tapered box (4 sides + 2 caps) between `from` and
## `to`, all vertices rigidly bound to `bone_idx`. `from_half`/`to_half`
## are the box's half-width/half-height at each end (x=width, y=height),
## measured against a local frame built from the from->to axis.
static func _add_tapered_box(st: SurfaceTool, bone_idx: int, from: Vector3, to: Vector3, from_half: Vector2, to_half: Vector2) -> void:
	var axis := to - from
	var length := axis.length()
	if length < 0.0001:
		return
	var fwd := axis / length
	var reference := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var right := fwd.cross(reference).normalized()
	var up := right.cross(fwd).normalized()

	var p0 := from + right * from_half.x + up * from_half.y
	var p1 := from - right * from_half.x + up * from_half.y
	var p2 := from - right * from_half.x - up * from_half.y
	var p3 := from + right * from_half.x - up * from_half.y
	var d0 := to + right * to_half.x + up * to_half.y
	var d1 := to - right * to_half.x + up * to_half.y
	var d2 := to - right * to_half.x - up * to_half.y
	var d3 := to + right * to_half.x - up * to_half.y

	st.set_bones(PackedInt32Array([bone_idx, 0, 0, 0]))
	st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))

	_quad(st, p0, p1, d1, d0)
	_quad(st, p1, p2, d2, d1)
	_quad(st, p2, p3, d3, d2)
	_quad(st, p3, p0, d0, d3)
	_quad(st, p0, p3, p2, p1)
	_quad(st, d0, d1, d2, d3)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

## --- Animation API, called by PlayerMeleeAttack / WeaponStance ---

## `intensity` scales how far each bone actually rotates toward the
## chosen pose set's windup/strike targets (1.0 = as authored, >1 = a
## bigger arc for a heavier weapon/a stance special, <1 = tighter/faster)
## via partial slerp from identity - PlayerMeleeAttack passes a per-
## weapon-type value so a greatsword reads as a genuinely bigger
## commitment than a dagger, not just a slower copy of the same motion.
## User feedback (2026-08-30): the first version of this swing "was far
## too fast along with the animation" for a greatsword - windup now ends
## with a brief held beat at full wind-up (anticipation, a real pause
## before commitment) rather than flowing straight into the strike, and
## the strike itself eases IN (slow start, fast finish) instead of OUT -
## a heavy weapon overcoming its own inertia, not a flick. Blends from
## whatever pose is currently applied (not always rest), so back-to-back
## swings (combo cycling) don't visually snap.
func play_attack_swing(pose_set: PoseSet, windup_duration: float, strike_duration: float, recovery_duration: float, intensity: float = 1.0) -> void:
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	var poses: Dictionary = _poses[pose_set]
	var windup_pose := _scale_pose(poses["windup"], intensity)
	var strike_pose := _scale_pose(poses["strike"], intensity)
	var start_pose := _current_pose.duplicate()
	var hold_duration := windup_duration * 0.2
	var settle_duration := windup_duration - hold_duration

	_swing_tween = create_tween()
	_swing_tween.tween_method(_apply_pose.bind(start_pose, windup_pose), 0.0, 1.0, settle_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_interval(hold_duration)
	_swing_tween.tween_method(_apply_pose.bind(windup_pose, strike_pose), 0.0, 1.0, strike_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_swing_tween.tween_method(_apply_pose.bind(strike_pose, _rest_pose), 0.0, 1.0, recovery_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## Holds the chosen pose set's windup pose indefinitely (no auto-return) -
## the "prep" look for WeaponStance's right-click hold. exit_ready_pose()
## (or a swing starting mid-hold) returns to rest.
func enter_ready_pose(pose_set: PoseSet, duration: float, intensity: float = 1.0) -> void:
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	var target := _scale_pose(_poses[pose_set]["windup"], intensity)
	var start_pose := _current_pose.duplicate()
	_swing_tween = create_tween()
	_swing_tween.tween_method(_apply_pose.bind(start_pose, target), 0.0, 1.0, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func exit_ready_pose(duration: float) -> void:
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	var start_pose := _current_pose.duplicate()
	_swing_tween = create_tween()
	_swing_tween.tween_method(_apply_pose.bind(start_pose, _rest_pose), 0.0, 1.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

static func _scale_pose(pose: Array, intensity: float) -> Array[Quaternion]:
	var scaled: Array[Quaternion] = []
	for q in pose:
		scaled.append(Quaternion.IDENTITY.slerp(q, intensity))
	return scaled

## Applies the primary arm's pose directly, then (if two-handed) solves a
## 2-bone IK for the off-hand so it tracks the PRIMARY HAND'S ACTUAL
## CURRENT POSITION every frame, instead of independently applying the
## same rotation values from a differently-shaped rest pose. User report
## (2026-08-30, third follow-up): sharing raw rotation values "looks
## awkward" - "the other hand lets go of the sword" - because the two
## arms have different shoulder/bone-length geometry, so identical
## rotations from different rest poses swing the two hands along
## completely different arcs. Records the result in _current_pose so the
## next tween (a new swing, a stance entry/exit) can blend from here
## instead of snapping from rest.
func _apply_pose(t: float, from_pose: Array[Quaternion], to_pose: Array[Quaternion]) -> void:
	var upper := from_pose[0].slerp(to_pose[0], t)
	var elbow := from_pose[1].slerp(to_pose[1], t)
	var wrist := from_pose[2].slerp(to_pose[2], t)
	_current_pose = [upper, elbow, wrist]
	_primary.skeleton.set_bone_pose_rotation(_primary.upper_arm_bone, upper)
	_primary.skeleton.set_bone_pose_rotation(_primary.forearm_bone, elbow)
	_primary.skeleton.set_bone_pose_rotation(_primary.hand_bone, wrist)
	if _offhand:
		var primary_hand := _primary.skeleton.get_bone_global_pose(_primary.hand_bone).origin
		# Static offset (not rotated with the weapon) so the off-hand sits
		# a bit further down the grip toward the pommel, same as its rest
		# placement - an approximation, not a true grip-relative offset,
		# but keeps the two hands visually close together throughout.
		var full_target := primary_hand + (OFFHAND_HAND_POS - HAND_POS)
		# Damped, not a 1:1 follow - verified numerically that the primary
		# hand travels far enough during a real swing (peak ~1.34 units
		# from the off-hand's shoulder) to exceed the off-hand's own reach
		# (~0.93 units) if tracked exactly, which would just re-introduce
		# the original "lets go" bug via IK clamping instead of raw
		# rotation-sharing. Damping keeps the target always within reach
		# while still visibly following the swing's direction.
		var damped_target := OFFHAND_HAND_POS.lerp(full_target, OFFHAND_TRACKING_DAMPING)
		_solve_offhand_ik(damped_target)

## Standard 2-bone (upper arm + forearm) analytic IK via the law of
## cosines: given a fixed shoulder and two fixed link lengths, finds the
## elbow bend that reaches `target` (clamped to the arm's actual reach),
## bending toward OFFHAND_FOREARM_POS's rest side so the elbow always
## bends the same visual direction this rig was authored with. The hand
## bone itself is left at rest - only the two upper joints solve for
## position, which is enough for "the off-hand visibly tracks the grip"
## without needing a full 3-bone solve.
func _solve_offhand_ik(target: Vector3) -> void:
	var s := OFFHAND_SHOULDER_POS
	var l1 := _offhand_upper_len
	var l2 := _offhand_forearm_len
	var to_target := target - s
	var raw_dist := to_target.length()
	if raw_dist < 0.001:
		return
	var dist: float = clamp(raw_dist, absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var dir := to_target / raw_dist

	var shoulder_angle := acos(clamp((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))

	var pole := OFFHAND_FOREARM_POS - s
	var perp_pole := pole - dir * pole.dot(dir)
	var bend_axis: Vector3
	if perp_pole.length() > 0.001:
		bend_axis = dir.cross(perp_pole).normalized()
	else:
		bend_axis = dir.cross(Vector3.UP).normalized()
		if bend_axis.length() < 0.001:
			bend_axis = dir.cross(Vector3.RIGHT).normalized()

	var upper_arm_dir := dir.rotated(bend_axis, shoulder_angle).normalized()
	var elbow_pos := s + upper_arm_dir * l1
	var forearm_dir := (target - elbow_pos).normalized()

	var rest_upper_dir := (OFFHAND_FOREARM_POS - OFFHAND_SHOULDER_POS).normalized()
	var q_upper := Quaternion(rest_upper_dir, upper_arm_dir)

	# set_bone_pose_rotation() on a child bone is relative to its PARENT's
	# current (posed) orientation, not world space - so the target forearm
	# direction has to be un-rotated by the upper arm's own pose first.
	var rest_forearm_dir := (OFFHAND_HAND_POS - OFFHAND_FOREARM_POS).normalized()
	var forearm_dir_local := (q_upper.inverse() * forearm_dir).normalized()
	var q_forearm := Quaternion(rest_forearm_dir, forearm_dir_local)

	_offhand.skeleton.set_bone_pose_rotation(_offhand.upper_arm_bone, q_upper)
	_offhand.skeleton.set_bone_pose_rotation(_offhand.forearm_bone, q_forearm)
