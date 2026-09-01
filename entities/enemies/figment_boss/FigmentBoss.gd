extends Enemy
class_name FigmentBoss
## User request: "figure out how to add bosses to each Figment to
## 'complete' a figment." No boss design exists anywhere in this project
## (Section 24 lists "Boss design philosophy" as explicitly not designed
## in the doc either) - this is a from-scratch, invented first pass: a
## much larger/tankier/harder-hitting HeavyHitter, spawned in the Vault's
## platform slot (see GeneratedMap.gd - the Vault is already the one
## guaranteed "real risk/reward set-piece" room per Map, so it's the
## natural, zero-extra-plumbing home for the one guaranteed Boss too),
## whose death fires EventBus.figment_completed - the signal
## GameState._on_figment_completed() listens to for Figment Tree points
## (see systems/figment_tree/ - scaffolding only, not a full system yet).
##
## Not a 4th Trinity Rule archetype (Fast/Lethal/Tanky combination) -
## bosses are explicitly exempt from that rule in most ARPGs this project
## draws from, and Section 21 doesn't weigh in on bosses at all.

const HEALTH_MULTIPLIER := 8.0    # relative to a HeavyHitter's 220
const DAMAGE_MULTIPLIER := 2.2    # relative to a HeavyHitter's MeleeAttack damage_amount
const REWARD_MULTIPLIER := 10.0   # relative to a HeavyHitter's xp/gold_reward

## User request (2026-08-30): "make this Arator model the first Figment
## boss" - built via tools/mdx_pipeline/ (a from-scratch MDX->glTF
## converter, since Godot has no native Warcraft III model support).
## Materials are assigned here rather than baked into the exported glTF
## (see that folder's README) - Godot already imports .dds natively and
## has ORMMaterial3D, a direct match for this asset's Diffuse/Normal/
## Emissive/ORM texture packing, so there was nothing to gain from
## fighting glTF's PNG/JPEG-oriented texture model instead.
##
## The index->group mapping below is hardcoded to Arator_Midnights.glb's
## own known 9-geoset order, not derived generically - this model is a
## composite rig merging geometry from OTHER base Reforged models
## (Anasterian Sunstrider, High Elf Archmage) that this project has no
## textures for. Those three geosets (index 3, 4, 8) get a flat gray
## placeholder instead - same "missing asset, flagged" treatment this
## project already gives other incomplete art. Indices 6/7 only have a
## real Diffuse map (their Normal/ORM references point at base-game
## texture paths not present here) - a legitimate diffuse-only
## ORMMaterial3D, not an error.
const MODEL_DIR := "res://assets/models/Arator the Redeemer/"
const _GEOSET_TEXTURE_GROUPS := [
	"Main", "Armor", "Armor", "", "", "Weapon", "Hair:diffuse_only", "Main:diffuse_only", "",
]

var _arator_meshes: Array[MeshInstance3D] = []
var _arator_real_materials: Array[Material] = []

## Section 2 (2026-08-30, user: "let's work on animations for the first
## boss now") - `tools/mdx_pipeline/mdx_to_gltf.js` now bakes the model's
## 13 named sequences into the `.glb` as real glTF animations, each
## sampled at a fixed 30Hz rate from the MDX source (see that script's own
## header for the exact math - this isn't guesswork, it mirrors war3-
## model's own per-frame delta-transform formula). Only 4 of the 13 are
## actually driven here (idle/walk/attack/death) - the rest (Stand 2/3,
## Stand Ready 1, Stand Victory 1, Spell 1, Stand Channel 1, Dissipate)
## have no real trigger in this project's current combat model (no spell-
## cast phase, no victory/idle-fidget-cycling system) and are left unused
## rather than wired to something that wouldn't be meaningful.
const IDLE_ANIM := "Base"
const WALK_ANIM := "Walk 1"
const ATTACK_ANIM := "Attack 1"  # "Attack 2" bakes identically - same source Interval as Attack 1 in this file
const DEATH_ANIM := "Death 1"
const MOVING_VELOCITY_THRESHOLD := 0.15

var _animation_player: AnimationPlayer
var _animation_locked: bool = false

func _ready() -> void:
	super._ready()
	display_name = "Arator the Redeemer"
	archetype = Constants.EnemyArchetype.HEAVY_HITTER  # closest fit - Lethal + Tanky, taken to an extreme
	move_speed = 1.4
	stop_distance = 2.6
	health.max_health = 220.0 * HEALTH_MULTIPLIER
	xp_reward = 25.0 * REWARD_MULTIPLIER
	gold_reward = int(12 * REWARD_MULTIPLIER)
	_setup_arator_visual()  # must run before _set_placeholder_color() below, which immediately triggers _apply_mesh_color() and expects _arator_meshes to already be populated
	_set_placeholder_color(Color(0.25, 0.04, 0.35))  # only used as _base_color bookkeeping now (see _apply_mesh_color() override) - never actually painted onto the real model
	_setup_animation_player()

	var melee: EnemyMeleeAttack = get_node_or_null("MeleeAttack")
	if melee:
		melee.damage_amount *= DAMAGE_MULTIPLIER

## Godot's glTF importer leaves every imported Animation's loop_mode at
## its default (LOOP_NONE) - looping is a gameplay decision, not an
## export one, so it's set here rather than baked into the pipeline.
## Attack/Death intentionally stay non-looping (play once, revert via
## _on_animation_finished()/the death-delay in _on_died() below).
func _setup_animation_player() -> void:
	var model := get_node_or_null("ArorModel")
	if model == null:
		return
	var players := model.find_children("*", "AnimationPlayer")
	if players.is_empty():
		return
	_animation_player = players[0]
	for loop_anim in [IDLE_ANIM, WALK_ANIM]:
		var anim := _animation_player.get_animation(loop_anim)
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR
	_animation_player.animation_finished.connect(_on_animation_finished)
	_animation_player.play(IDLE_ANIM)

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == ATTACK_ANIM:
		_animation_locked = false

## Enemy._physics_process() drives chase/gravity/move_and_slide() - this
## just layers idle/walk selection on top, off the same `velocity` that
## already resulted from it.
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_animation_state()

## Split out from _physics_process() so it can be exercised directly
## against a manually-set `velocity` without needing a real Player in the
## scene for Enemy._update_chase() to steer against. Skipped entirely
## while an attack or death animation (see begin_attack_telegraph()/
## _on_died() below) owns playback.
func _update_animation_state() -> void:
	if _animation_player == null or _animation_locked or not health.is_alive():
		return
	var moving := Vector2(velocity.x, velocity.z).length() > MOVING_VELOCITY_THRESHOLD
	var desired := WALK_ANIM if moving else IDLE_ANIM
	if _animation_player.current_animation != desired:
		_animation_player.play(desired)

## Overrides Enemy.begin_attack_telegraph()/end_attack_telegraph() to
## additionally drive ATTACK_ANIM alongside the inherited color-flash
## (super call keeps that working unchanged) - played once at telegraph
## start rather than split across telegraph/strike/recovery, since a
## single "Attack 1" clip (~1.2s) already reads as one continuous swing
## and this project's telegraph+strike+recovery timing (2.7s combined for
## this boss) runs longer than the clip itself anyway.
func begin_attack_telegraph() -> void:
	super.begin_attack_telegraph()
	if _animation_player and _animation_player.has_animation(ATTACK_ANIM):
		_animation_locked = true
		_animation_player.play(ATTACK_ANIM)

func _setup_arator_visual() -> void:
	var model := get_node_or_null("ArorModel")
	if model == null:
		return
	_arator_meshes = _find_mesh_instances(model)
	for i in range(_arator_meshes.size()):
		var group: String = _GEOSET_TEXTURE_GROUPS[i] if i < _GEOSET_TEXTURE_GROUPS.size() else ""
		var mat := _build_material(group)
		_arator_meshes[i].set_surface_override_material(0, mat)
		_arator_real_materials.append(mat)

func _build_material(group: String) -> Material:
	if group == "":
		var placeholder := StandardMaterial3D.new()
		placeholder.albedo_color = Color(0.4, 0.4, 0.42)
		return placeholder
	var diffuse_only := group.ends_with(":diffuse_only")
	var base_name := group.replace(":diffuse_only", "")
	var mat := ORMMaterial3D.new()
	mat.albedo_texture = load(MODEL_DIR + "Arator_%s_Diffuse.dds" % base_name)
	if not diffuse_only:
		mat.normal_enabled = true
		mat.normal_texture = load(MODEL_DIR + "Arator_%s_Normal.dds" % base_name)
		mat.orm_texture = load(MODEL_DIR + "Arator_%s_Orm.dds" % base_name)
		mat.emission_enabled = true
		mat.emission_texture = load(MODEL_DIR + "Arator_%s_Emissive.dds" % base_name)
	return mat

func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		result.append_array(_find_mesh_instances(child))
	return result

## Overrides Enemy._apply_mesh_color() - the base version only tints a
## single `$MeshInstance3D` (the placeholder capsule every other enemy
## still uses), which is hidden for this boss. This applies the same
## telegraph-flash/revert behavior (Section 07's attack-readability
## signal) across every real mesh on the Arator model instead - flat
## color while flashing, the real ORM-textured material restored once
## the color passed back in matches _base_color (the same "at rest"
## convention Enemy.gd's own telegraph methods already use).
func _apply_mesh_color(c: Color) -> void:
	if _arator_meshes.is_empty():
		super._apply_mesh_color(c)
		return
	var restore := c.is_equal_approx(_base_color)
	for i in range(_arator_meshes.size()):
		if restore:
			_arator_meshes[i].set_surface_override_material(0, _arator_real_materials[i])
		else:
			var flash := StandardMaterial3D.new()
			flash.albedo_color = c
			_arator_meshes[i].set_surface_override_material(0, flash)

## Figment "completion" fires immediately (unchanged) - GameState.
## active_map still needs to be whatever it was during this fight, and
## there's no reason to gate Figment Tree points on a death-animation
## delay. The base class's own cleanup (xp/gold/loot drop, queue_free())
## is what gets delayed - plays DEATH_ANIM to completion first rather
## than the base class's instant queue_free(), the one moment in this
## fight where lingering on the real model instead of vanishing
## immediately actually matters. Every other enemy in this project still
## dies instantly - no death animation exists for the placeholder capsule
## to play regardless.
func _on_died() -> void:
	EventBus.figment_completed.emit(GameState.active_map)
	if _animation_player and _animation_player.has_animation(DEATH_ANIM):
		_animation_locked = true  # blocks _physics_process()'s idle/walk selection from fighting this
		_animation_player.play(DEATH_ANIM)
		await _animation_player.animation_finished
	super._on_died()
