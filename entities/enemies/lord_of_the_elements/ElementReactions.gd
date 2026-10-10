extends Node3D
class_name ElementReactions
## The Lord of the Elements' spells change the crescent, and react with each
## other (LordOfTheElements feeds it every ground strike):
##   - Cold strikes leave chilled ground (FrostPatch) for a while; standing in
##     it chills you.
##   - Cold landing on a Fire pool turns it to steam: a cloud he can't see
##     into, so he holds his aimed spells while you stand inside.
##   - Lightning landing on chilled ground runs through it and every chilled
##     patch touching it, hitting anyone on them.
##   - Fire landing on chilled ground shatters it into flying shards.
## Chains and shards that reach him hurt and stagger him too, so baiting his
## spells into each other is a way in.

const FROST_DURATION := 10.0
const FROST_CHILL_TICK := 1.0
const STEAM_DURATION := 7.0
const STEAM_RADIUS_BONUS := 1.0
## Damage of a chain / shard burst, as a share of the triggering ability hit.
const CHAIN_DAMAGE := 0.8
const SHARD_DAMAGE := 1.0
const SHARD_REACH := 2.5
## How close (to his body) a chain or shard burst must reach to hit him.
const LORD_REACH := 1.5

var lord: LordOfTheElements
## Each {"center", "radius", "left", "node"}.
var frost: Array[Dictionary] = []
## Each {"center", "radius", "left", "node"}.
var steam: Array[Dictionary] = []
var _chill_tick := 0.0

func _process(delta: float) -> void:
	for list in [frost, steam]:
		for p in list.duplicate():
			p["left"] -= delta
			var node: Node3D = p["node"]
			if is_instance_valid(node):
				node.set("fade", clampf(p["left"] / 1.0, 0.0, 1.0))
			if p["left"] <= 0.0:
				_remove(list, p)
	_chill_tick -= delta
	if _chill_tick <= 0.0:
		_chill_tick = FROST_CHILL_TICK
		var player := _player()
		if player and in_frost(player.global_position) and player.status_effects:
			player.status_effects.apply_effect("chill", lord)

func _remove(list: Array[Dictionary], p: Dictionary) -> void:
	if is_instance_valid(p["node"]):
		p["node"].queue_free()
	list.erase(p)

## A spell of `element` landed at `center` with `radius`; `damage` is that
## ability's hit. `fire_pools` are the live Fire hazard pools (BossBrain).
func on_strike(element: int, center: Vector3, radius: float, damage: float) -> void:
	match element:
		Constants.DamageType.COLD:
			_freeze_ground(center, radius)
		Constants.DamageType.LIGHTNING:
			var touched := _overlapping(frost, center, radius)
			if not touched.is_empty():
				_chain(touched, center, damage)
		Constants.DamageType.FIRE:
			for p in _overlapping(frost, center, radius):
				_shatter(p, damage)

## Cold on a Fire pool: the pool is put out and a steam cloud rises instead.
func on_cold_over_fire(center: Vector3, radius: float) -> void:
	var cloud := SteamCloud.new()
	cloud.radius = radius + STEAM_RADIUS_BONUS
	add_child(cloud)
	cloud.global_position = center
	steam.append({"center": center, "radius": cloud.radius, "left": STEAM_DURATION, "node": cloud})

func in_frost(point: Vector3) -> bool:
	return frost.any(func(p): return _flat(p["center"], point) <= p["radius"])

func in_steam(point: Vector3) -> bool:
	return steam.any(func(p): return _flat(p["center"], point) <= p["radius"])

func _freeze_ground(center: Vector3, radius: float) -> void:
	# A new strike over old chilled ground refreshes it rather than stacking.
	for p in frost.duplicate():
		if _flat(p["center"], center) < 0.5:
			_remove(frost, p)
	var patch := FrostPatch.new()
	patch.radius = radius
	add_child(patch)
	patch.global_position = center
	frost.append({"center": center, "radius": radius, "left": FROST_DURATION, "node": patch})

## Lightning spreads through every chilled patch connected to the ones it hit.
func _chain(start: Array[Dictionary], from: Vector3, damage: float) -> void:
	var lit: Array[Dictionary] = []
	var queue: Array[Dictionary] = start.duplicate()
	while not queue.is_empty():
		var p: Dictionary = queue.pop_back()
		if lit.has(p):
			continue
		lit.append(p)
		for other in frost:
			if not lit.has(other) and _flat(p["center"], other["center"]) <= p["radius"] + other["radius"]:
				queue.append(other)
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(Constants.DamageType.LIGHTNING, Color.WHITE)
	var player := _player()
	var player_hit := false
	var lord_hit := false
	var prev := from
	for p in lit:
		LightningArc.spawn(_scene(), prev + Vector3.UP * 0.3, p["center"] + Vector3.UP * 0.3, color)
		prev = p["center"]
		if is_instance_valid(p["node"]):
			p["node"].call("flash", color)
		if player and not player_hit and _flat(p["center"], player.global_position) <= p["radius"]:
			player_hit = true
			player.take_damage(damage * CHAIN_DAMAGE, Constants.DamageType.LIGHTNING, lord, Player.HitKind.SPELL)
		if not lord_hit and _reaches_lord(p["center"], p["radius"]):
			lord_hit = true
			LightningArc.spawn(_scene(), p["center"] + Vector3.UP * 0.3, lord.global_position + Vector3.UP * 2.0, color)
			lord.take_reaction_backlash(Constants.DamageType.LIGHTNING)

## Fire on chilled ground: the ice bursts outward and is gone.
func _shatter(p: Dictionary, damage: float) -> void:
	var center: Vector3 = p["center"]
	var reach: float = p["radius"] + SHARD_REACH
	ShardBurst.spawn(_scene(), center, reach)
	_remove(frost, p)
	var player := _player()
	if player and _flat(center, player.global_position) <= reach:
		player.take_damage(damage * SHARD_DAMAGE, Constants.DamageType.COLD, lord, Player.HitKind.SPELL)
	if _reaches_lord(center, reach):
		lord.take_reaction_backlash(Constants.DamageType.COLD)

func _reaches_lord(center: Vector3, radius: float) -> bool:
	return is_instance_valid(lord) and lord.health.is_alive() and lord.distance_to_body(center) <= radius + LORD_REACH

func _overlapping(list: Array[Dictionary], center: Vector3, radius: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for p in list:
		if _flat(p["center"], center) <= p["radius"] + radius * 0.5:
			found.append(p)
	return found

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _scene() -> Node:
	return get_parent()

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Chilled ground: a pale icy disc with a frosted rim.
class FrostPatch extends Node3D:
	var radius := 4.0
	var fade := 1.0
	var _mat: StandardMaterial3D
	var _rim_mat: StandardMaterial3D
	var _flash := 0.0
	var _flash_color := Color.WHITE

	func _ready() -> void:
		var color: Color = Constants.DAMAGE_TYPE_COLOR.get(Constants.DamageType.COLD, Color(0.6, 0.85, 1.0))
		_mat = _material(Color(color.lightened(0.3), 0.32))
		_rim_mat = _material(Color(color.lightened(0.5), 0.7))
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = 0.02
		cyl.radial_segments = 40
		disc.mesh = cyl
		disc.position.y = 0.05
		disc.material_override = _mat
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(disc)
		var rim := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius - 0.2
		torus.outer_radius = radius
		torus.rings = 40
		rim.mesh = torus
		rim.scale = Vector3(1, 0.08, 1)
		rim.position.y = 0.06
		rim.material_override = _rim_mat
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rim)

	func flash(color: Color) -> void:
		_flash = 1.0
		_flash_color = color

	func _process(delta: float) -> void:
		_flash = maxf(_flash - delta * 2.5, 0.0)
		var base: Color = Constants.DAMAGE_TYPE_COLOR.get(Constants.DamageType.COLD, Color(0.6, 0.85, 1.0)).lightened(0.3)
		var c := base.lerp(_flash_color, _flash)
		_mat.albedo_color = Color(c, (0.32 + 0.4 * _flash) * fade)
		_rim_mat.albedo_color = Color(c.lightened(0.2), 0.7 * fade)

	func _material(color: Color) -> StandardMaterial3D:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = color
		return mat


## A billowing cloud of steam; seen from inside it whites out the view.
class SteamCloud extends Node3D:
	var radius := 4.0
	var fade := 1.0
	var _puffs: Array[MeshInstance3D] = []
	var _mat: StandardMaterial3D
	var _age := 0.0

	func _ready() -> void:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.albedo_color = Color(0.92, 0.94, 0.96, 0.0)
		for i in 9:
			var puff := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			var r := radius * randf_range(0.45, 0.7)
			sphere.radius = r
			sphere.height = r * 1.6
			puff.mesh = sphere
			var a := TAU * i / 9.0
			var d := 0.0 if i == 0 else radius * randf_range(0.35, 0.6)
			puff.position = Vector3(cos(a) * d, r * 0.6 + randf() * 0.8, sin(a) * d)
			puff.material_override = _mat
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(puff)
			_puffs.append(puff)

	func _process(delta: float) -> void:
		_age += delta
		var grow := clampf(_age / 0.6, 0.0, 1.0)
		_mat.albedo_color.a = 0.42 * grow * fade
		for i in _puffs.size():
			_puffs[i].position.y += sin(_age * 0.8 + i) * delta * 0.15
			_puffs[i].rotation.y += delta * 0.1


## Ice shards bursting out of a shattered patch.
class ShardBurst extends Node3D:
	const COUNT := 14
	const TIME := 0.5

	static func spawn(parent: Node, at: Vector3, reach: float) -> void:
		var burst := ShardBurst.new()
		parent.add_child(burst)
		burst.global_position = at
		var color: Color = Constants.DAMAGE_TYPE_COLOR.get(Constants.DamageType.COLD, Color(0.6, 0.85, 1.0))
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color.lightened(0.5), 0.95)
		for i in COUNT:
			var shard := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(0.18, 0.7, 0.18)
			shard.mesh = prism
			shard.material_override = mat
			shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var a := TAU * i / COUNT + randf() * 0.3
			var dir := Vector3(cos(a), 0.0, sin(a))
			shard.position = dir * reach * 0.3 + Vector3.UP * 0.4
			shard.rotation = Vector3(PI * 0.5, -a + PI * 0.5, 0)
			burst.add_child(shard)
			var tween := shard.create_tween()
			tween.tween_property(shard, "position", dir * reach + Vector3.UP * randf_range(0.3, 1.2), TIME).set_ease(Tween.EASE_OUT)
		var fade := burst.create_tween()
		fade.tween_property(mat, "albedo_color:a", 0.0, TIME)
		fade.tween_callback(burst.queue_free)
