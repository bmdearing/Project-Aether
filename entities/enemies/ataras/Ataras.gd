extends PinnacleBoss
class_name Ataras
## Third Pinnacle boss: Ataras, a jackal-headed lord of the sands (model:
## Anubithas / Anubis by Mr Ogre man and vindorei, Hive Workshop). Kinetic.
## Fought in the SandArena.
##   Slash: his ordinary melee attack.
##   Sandstorm Cuts: two fast slashes around him, then a thrust ahead.
##   Sand Globes: floating globes that can be killed; each fires at you every
##   2 seconds for a little damage.
##   Phase 2 (50%): Shifting Sands - two of the arena's three wedges turn to
##   quicksand for a while (SandArena). Once the sand settles he starts
##   casting Ticking Time: for 4 seconds the ground you cross is marked, and
##   every mark becomes a permanent sand trap.

const DISPLAY_NAME := "Ataras"
const PHASES: Array[float] = [0.5]

const SLASH_RADIUS := 3.8
const SLASH_HALF_ANGLE := 75.0
const SLASH_TELEGRAPH := 0.35
const SLASH_GAP := 0.15
const THRUST_LENGTH := 8.0
const THRUST_WIDTH := 1.8
const THRUST_TELEGRAPH := 0.55
const THRUST_DAMAGE := 1.6

const GLOBE_COUNT := 3
const GLOBE_CAP := 5
const GLOBE_RING := Vector2(8.0, 16.0)
const GLOBE_SCENE := preload("res://entities/enemies/ataras/SandGlobe.tscn")

const TICKING_DURATION := 4.0
const TICKING_INTERVAL := 0.4
const TICKING_RADIUS := 1.6
const TICKING_MARK_COLOR := Color(1.0, 0.75, 0.35, 0.5)

var _arena: SandArena
var _globes: Array[Node] = []
## Ticking Time waits until Shifting Sands has run its course.
var _sands_settled := false

func _ready() -> void:
	super._ready()
	display_name = DISPLAY_NAME

func phase_thresholds() -> Array[float]:
	return PHASES

func abilities() -> Array:
	return [
		{"id": "sandstorm_cuts", "display_name": "Sandstorm Cuts", "kind": BossAbility.Kind.CUSTOM, "cooldown": 7.0, "max_range": 6.0, "damage_mult": 1.1, "weight": 2.0},
		{"id": "sand_globes", "display_name": "Sand Globes", "kind": BossAbility.Kind.CUSTOM, "cooldown": 22.0, "telegraph": 1.0, "max_range": 40.0},
		{"id": "shifting_sands", "display_name": "Shifting Sands", "kind": BossAbility.Kind.CUSTOM, "cooldown": 9999.0, "min_phase": 2, "weight": 0.0, "max_range": 99.0},
		{"id": "ticking_time", "display_name": "Ticking Time", "kind": BossAbility.Kind.CUSTOM, "cooldown": 16.0, "min_phase": 2, "max_range": 40.0},
	]

func phase_openers() -> Dictionary:
	return {2: "shifting_sands"}

func arena() -> SandArena:
	if not is_instance_valid(_arena) and is_inside_tree():
		_arena = get_tree().get_first_node_in_group("sand_arena") as SandArena
	return _arena

func can_use_ability(ability: BossAbility) -> bool:
	if ability.id == "ticking_time":
		return _sands_settled or arena() == null
	if ability.id == "sand_globes":
		_globes = _globes.filter(func(g): return is_instance_valid(g) and g.health.is_alive())
		return _globes.size() + GLOBE_COUNT <= GLOBE_CAP
	return true

func cast_custom(ability: BossAbility) -> void:
	match ability.id:
		"sandstorm_cuts":
			await _sandstorm_cuts(ability)
		"sand_globes":
			await _sand_globes(ability)
		"shifting_sands":
			await _shifting_sands()
		"ticking_time":
			await _ticking_time()
		_:
			await get_tree().process_frame

func _target_player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _forward() -> Vector3:
	var p := _target_player()
	var to := (p.global_position - global_position) if p else -global_transform.basis.z
	to.y = 0.0
	return to.normalized() if to.length() > 0.05 else Vector3.FORWARD

## Two fast slashes around him, then a thrust down a line.
func _sandstorm_cuts(ability: BossAbility) -> void:
	var damage := get_ability_base_damage() * ability.damage_mult
	for i in 2:
		begin_attack_telegraph(SLASH_TELEGRAPH)
		BossTelegraph.circle(get_parent(), global_position, SLASH_RADIUS, SLASH_TELEGRAPH, Color(1.0, 0.7, 0.3))
		await get_tree().create_timer(SLASH_TELEGRAPH, false).timeout
		if not health.is_alive():
			return
		var p := _target_player()
		if p and _in_slash(p.global_position):
			p.take_damage(damage, Constants.DamageType.KINETIC, self, Player.HitKind.ATTACK)
		await get_tree().create_timer(SLASH_GAP, false).timeout
	var dir := _forward()
	begin_attack_telegraph(THRUST_TELEGRAPH)
	BossTelegraph.line(get_parent(), global_position, dir, THRUST_LENGTH, THRUST_WIDTH, THRUST_TELEGRAPH, Color(1.0, 0.55, 0.2))
	await get_tree().create_timer(THRUST_TELEGRAPH, false).timeout
	if not health.is_alive():
		return
	var p := _target_player()
	if p:
		var rel := p.global_position - global_position
		rel.y = 0.0
		var along := rel.dot(dir)
		if along >= 0.0 and along <= THRUST_LENGTH and (rel - dir * along).length() <= THRUST_WIDTH * 0.5 + 0.4:
			p.take_damage(damage * THRUST_DAMAGE, Constants.DamageType.PIERCING, self, Player.HitKind.ATTACK)

func _in_slash(point: Vector3) -> bool:
	var rel := point - global_position
	rel.y = 0.0
	return rel.length() <= SLASH_RADIUS + 0.4 and (rel.length() < 0.6 or rad_to_deg(_forward().angle_to(rel.normalized())) <= SLASH_HALF_ANGLE)

## Globes rise around the arena and start firing.
func _sand_globes(ability: BossAbility) -> void:
	begin_attack_telegraph(ability.telegraph)
	var spots: Array[Vector3] = []
	var centre := arena().global_position if arena() else global_position
	for i in GLOBE_COUNT:
		var angle := randf() * TAU
		spots.append(centre + Vector3(sin(angle), 0, cos(angle)) * randf_range(GLOBE_RING.x, GLOBE_RING.y))
		BossTelegraph.circle(get_parent(), spots[i], 1.2, ability.telegraph, Color(0.95, 0.8, 0.45))
	await get_tree().create_timer(ability.telegraph, false).timeout
	if not health.is_alive():
		return
	for spot in spots:
		var globe: Enemy = GLOBE_SCENE.instantiate()
		get_parent().add_child(globe)
		globe.global_position = spot + Vector3.UP * SandGlobe.HOVER
		_globes.append(globe)

func _shifting_sands() -> void:
	var a := arena()
	if a == null:
		_sands_settled = true
		await get_tree().process_frame
		return
	if not a.wedges_ended.is_connected(_on_sands_settled):
		a.wedges_ended.connect(_on_sands_settled)
	a.start_wedges()
	begin_attack_telegraph(1.2)
	await get_tree().create_timer(1.2, false).timeout

func _on_sands_settled() -> void:
	_sands_settled = true

## Ticking Time: for a few seconds the ground the player crosses is marked;
## when it ends, every mark becomes a permanent sand trap.
func _ticking_time() -> void:
	begin_attack_telegraph(TICKING_DURATION)
	var marks: Array[Vector3] = []
	var elapsed := 0.0
	while elapsed < TICKING_DURATION:
		var p := _target_player()
		if p and (marks.is_empty() or marks[-1].distance_to(p.global_position) > TICKING_RADIUS * 0.9):
			var spot := Vector3(p.global_position.x, (arena().global_position.y if arena() else 0.0), p.global_position.z)
			marks.append(spot)
			BossTelegraph.circle(get_parent(), spot, TICKING_RADIUS, TICKING_DURATION - elapsed, TICKING_MARK_COLOR)
		await get_tree().create_timer(TICKING_INTERVAL, false).timeout
		elapsed += TICKING_INTERVAL
		if not health.is_alive():
			return
	var a := arena()
	if a:
		for spot in marks:
			a.add_trap(spot, TICKING_RADIUS)

func _on_died() -> void:
	for g in _globes:
		if is_instance_valid(g) and g.health.is_alive():
			g.health.apply_damage(g.health.current_health + 1.0)
	super._on_died()
