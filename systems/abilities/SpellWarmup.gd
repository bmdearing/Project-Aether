extends RefCounted
class_name SpellWarmup
## The first time a spell's effects draw, their shaders compile, which used to
## hitch the first cast of every spell. Once per session, while the loading
## screen still covers the view (LoadingScreen._finish), every spell's effect
## and the shared spell visuals are played far below the level in front of
## a temporary camera for a few frames. They finish on their own down there,
## away from every enemy; only the motionless sample bolts are removed.

const FRAMES := 4
## Far below any level, where nothing can reach or see them.
const WARM_SPOT := Vector3(0, -600, 0)
const ABILITY_DIR := "res://data/abilities/instances/"
## Spells that play through their own launcher rather than a range effect.
const SKIP_RANGE_EFFECT := ["winters_eye"]

static var done := false

static func run(tree: SceneTree) -> void:
	if done:
		return
	var player := tree.get_first_node_in_group("player") as Player
	if player == null or player.camera == null or player.ability_cast == null:
		return
	done = true
	var scene := tree.current_scene
	var spot := WARM_SPOT
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.global_position = spot + Vector3(0, 4, 9)
	cam.look_at(spot + Vector3.UP, Vector3.UP)
	cam.current = true
	var cast := player.ability_cast
	var bolts: Array[Node] = []
	for f in DirAccess.get_files_at(ABILITY_DIR):
		f = f.trim_suffix(".remap")
		if not f.ends_with(".tres"):
			continue
		var ability := load(ABILITY_DIR + f) as Ability
		if ability == null:
			continue
		if not SKIP_RANGE_EFFECT.has(ability.ability_id):
			cast._play_range_effect(ability, spot)
		if ability.has_tag(Ability.TAG_PROJECTILE):
			bolts.append(_bolt(scene, player, ability, spot))
	for type in Constants.DAMAGE_TYPE_COLOR:
		var color: Color = Constants.DAMAGE_TYPE_COLOR[type]
		SpellFx.burst(scene, spot, color)
		SpellFx.shards(scene, spot, color)
		SpellFx.flash(scene, spot, color)
		SpellFx.light_pop(scene, spot, color)
		SpellFx.shockwave(scene, spot, 2.0, color)
		SpellFx.sweep(scene, spot, Vector3.FORWARD, 3.0, 50.0, color)
		LightningArc.spawn(scene, spot + Vector3.UP * 0.5, spot + Vector3(1, 2, 0), color)
	for i in FRAMES:
		await tree.process_frame
	for bolt in bolts:
		if is_instance_valid(bolt):
			bolt.queue_free()
	if is_instance_valid(cam):
		cam.queue_free()
	if is_instance_valid(player) and player.camera:
		player.camera.current = true

## A harmless, motionless copy of the spell's bolt, so its look compiles too.
static func _bolt(scene: Node, player: Player, ability: Ability, spot: Vector3) -> Node:
	var bolt: PiercingBolt = PlayerAbilityCast.PIERCING_BOLT_SCENE.instantiate()
	bolt.damage_amount = 0.0
	bolt.damage_type = ability.damage_type
	bolt.speed = 0.0
	bolt.source = player
	bolt.ability = ability
	scene.add_child(bolt)
	bolt.global_position = spot + Vector3.UP
	return bolt
