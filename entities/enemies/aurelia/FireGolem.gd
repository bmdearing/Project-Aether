extends Enemy
class_name FireGolem
## Aurelia's Fire Golem (model: Fire Golem by Vulfar, Hive Workshop). It
## chases the player down and has one attack: a slam that sends a line of
## erupting fire along the ground. A player caught in it is knocked into the
## air (Player.knock_up()), and in her last phase Aurelia answers that with a
## Living Bomb.

signal player_knocked_up(golem: FireGolem, player: Player)

const SLAM_RANGE := 7.5
const SLAM_LENGTH := 10.0
const SLAM_WIDTH := 2.4
const SLAM_TELEGRAPH := 1.0
const SLAM_COOLDOWN := 3.2
const SLAM_DAMAGE := 1.5
const KNOCK_UP_HEIGHT := 2.6
const FIRE := Color(1.0, 0.45, 0.12)

var _cooldown := 1.5
var _slamming := false

func _ready() -> void:
	super._ready()
	display_name = "Fire Golem"
	# The slam is its only attack.
	var melee := get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	if melee:
		melee.attack_range = 0.0
	var light := OmniLight3D.new()
	light.light_color = FIRE
	light.light_energy = 1.2
	light.omni_range = 4.0
	light.position.y = 1.8
	add_child(light)
	health.died.connect(func(): AureliaSfx.play("golem_death", global_position, 2.0))

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not health.is_alive() or _slamming:
		return
	_cooldown -= delta
	if _cooldown > 0.0 or status_effects.is_stunned() or not is_instance_valid(_player):
		return
	var to := _player.global_position - global_position
	to.y = 0.0
	if to.length() <= SLAM_RANGE:
		_slam(to.normalized() if to.length() > 0.1 else -global_transform.basis.z)

func _apply_definition() -> void:
	super._apply_definition()
	Aurelia.apply_boss_level(self)

## Always the same golem: no Magic or Rare rolls.
func _roll_rank() -> Constants.EnemyRank:
	return Constants.EnemyRank.NORMAL

func is_attack_locked() -> bool:
	return _slamming or super.is_attack_locked()

func is_mid_attack() -> bool:
	return _slamming or super.is_mid_attack()

func _slam(dir: Vector3) -> void:
	_slamming = true
	var origin := global_position
	look_at(origin + dir, Vector3.UP)
	begin_attack_telegraph(SLAM_TELEGRAPH)
	BossTelegraph.line(get_parent(), origin, dir, SLAM_LENGTH, SLAM_WIDTH, SLAM_TELEGRAPH, FIRE)
	BossFx.charge(self, origin + Vector3.UP * 2.2, Constants.DamageType.FIRE, SLAM_TELEGRAPH, false)
	AureliaSfx.play("golem_slam", origin, 0.0)
	await get_tree().create_timer(SLAM_TELEGRAPH, false).timeout
	if not is_inside_tree() or not health.is_alive():
		return
	_eruption(origin, dir)
	var p := _player
	if is_instance_valid(p) and p.health.is_alive() and p.global_position.y - origin.y < 2.0:
		var rel := p.global_position - origin
		rel.y = 0.0
		var along := rel.dot(dir)
		if along >= -0.5 and along <= SLAM_LENGTH and (rel - dir * along).length() <= SLAM_WIDTH * 0.5 + 0.4:
			AureliaAilments.hit(p, get_ability_base_damage() * SLAM_DAMAGE, Constants.DamageType.FIRE, self, Player.HitKind.ATTACK)
			p.knock_up(KNOCK_UP_HEIGHT)
			player_knocked_up.emit(self, p)
	await get_tree().create_timer(0.5, false).timeout
	_slamming = false
	_cooldown = SLAM_COOLDOWN

## Fire bursting out of the ground along the strip, rippling away from it.
func _eruption(origin: Vector3, dir: Vector3) -> void:
	var parent := get_parent()
	AureliaSfx.play("quake", origin, 2.0, 1.1)
	SpellFx.shockwave(parent, origin + Vector3.UP * 0.05, 3.0, FIRE, 0.3)
	SmokePuff.spawn(parent, origin + dir * 1.5, 1.2, Color(0.3, 0.25, 0.22))
	var steps := 6
	for i in steps:
		var spot := origin + dir * (SLAM_LENGTH * (i + 0.7) / steps)
		get_tree().create_timer(0.04 * i, false).timeout.connect(func():
			if not is_instance_valid(parent):
				return
			SpellFx.burst(parent, spot + Vector3.UP * 0.3, FIRE, 18, Vector2(4, 9), 0.6, Vector2(0.1, 0.24), 25.0, 3.0)
			SpellFx.shards(parent, spot + Vector3.UP * 0.2, Color(0.3, 0.2, 0.16), 5, Vector2(4, 7), Vector2(0.1, 0.24), 0.8, 30.0, false)
			SpellFx.flash(parent, spot + Vector3.UP * 0.8, FIRE, 2.2, 0.2)
			if i % 2 == 0:
				SpellFx.ground_mark(parent, spot, 1.6, SpellFx.Mark.SCORCH, Color(0.08, 0.05, 0.04, 0.8), FIRE, 3.5, 1.0)
				AureliaSfx.play("fire_wall_roll", spot, -6.0, 1.2))
	SpellFx.light_pop(parent, origin + dir * SLAM_LENGTH * 0.5 + Vector3.UP * 1.5, FIRE, 3.0, 7.0, 0.4)
