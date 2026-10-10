extends Node
## Conduit stances (CasterStance), using the real conduit items: hold RMB,
## cast with keys 1-4 or attack with LMB.
## Run: Godot --headless --path . res://tests/combat/test_caster_stances.tscn --quit-after 60000

var _checks := 0
var _failures := 0
var _arena: Node3D
var _player: Player
var _cast_failures: Array[String] = []
const START := Vector3(0, 0.05, 0)
const WEAPONS_DIR := "res://data/weapons/instances/"

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _seconds(s: float) -> void:
	await _frames(int(s * Engine.physics_ticks_per_second))

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	await _setup()
	EventBus.ability_cast_failed.connect(func(_c, _a, reason): _cast_failures.append(reason))
	await _test_spell_library()
	await _test_page_tag()
	await _test_unleash()
	await _test_stance_buffs()
	await _test_ward_buff()
	await _test_page_modifiers()
	await _test_mana_stars()
	await _test_battlemage()
	await _test_wand_bolts()
	await _test_rod_is_passive()
	print("caster stance tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _setup() -> void:
	_arena = Node3D.new()
	add_child(_arena)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	_arena.add_child(body)
	_player = load("res://entities/player/Player.tscn").instantiate()
	_arena.add_child(_player)
	await _frames(3)
	_clear()
	await _frames(2)

func _clear() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.remove_from_group("enemy")
		e.queue_free()
	for node in get_tree().current_scene.get_children():
		if node is Projectile or node is PiercingBolt:
			node.queue_free()

## First instance of a conduit line from the item data.
func _conduit(line_id: String) -> Weapon:
	var dir := DirAccess.open(WEAPONS_DIR)
	for file in dir.get_files():
		if file.ends_with(".tres") and file.begins_with("gen_"):
			var w := load(WEAPONS_DIR + file) as Weapon
			if w and w.base_line_id == line_id:
				return w.duplicate() as Weapon
	return null

func _spell(id: String) -> Ability:
	var a := load("res://data/abilities/instances/%s.tres" % id) as Ability
	a.level = 1
	a.base_crit_chance = 0.0
	a.base_damage_min = a.base_damage_max  # fixed rolls, so damage comparisons are exact
	a.status_chance = 1.0
	a.cooldown_seconds = 1.0  # a started cooldown is how these checks see a cast
	a.cast_type = Ability.CastType.INSTANT  # these check stances, not cast times
	a.base_cast_time = 0.0
	return a

func _reset(main: Weapon, off: Weapon = null, page: WeaponStance.StancePage = WeaponStance.StancePage.A) -> void:
	Input.action_release("stance")
	Input.action_release("attack")
	for i in 4:
		Input.action_release("ability_%d" % (i + 1))
	await _frames(2)
	while not _player.melee_attack.is_idle():
		await _frames(1)
	_clear()
	_player.equipment.primary_weapon = main
	_player.equipment.offhand = off
	for i in 8:
		_player.ability_loadout.slots[i] = null
	_player.ability_cast._cooldowns.clear()
	_player.weapon_stance.set_stance_page(page)
	_player.global_position = START
	_player.velocity = Vector3.ZERO
	_player.mana.current_mana = _player.mana.max_mana
	_player.mana.regen_per_second = 0.0  # exact mana checks
	_player.stat_sheet.finesse_crit_bonus = -1.0
	_cast_failures.clear()
	await _frames(5)

func _forward() -> Vector3:
	return -_player.global_transform.basis.z

func _dummy(pos: Vector3) -> Enemy:
	var e := EnemyRoster.create_unit("unchartered_brigand")
	e.position = pos
	_arena.add_child(e)
	e.move_speed = 0.0
	e.evasion_value = 0.0
	e.armor_value = 0.0
	e.health.max_health = 1.0e6
	e.health.current_health = 1.0e6
	for path in ["MeleeAttack", "RangedAttack"]:
		var attack := e.get_node_or_null(path)
		if attack:
			attack.set_physics_process(false)
	return e

func _lost(e: Enemy) -> float:
	return 1.0e6 - e.health.current_health

func _cast_key(key: int, settle: float = 0.8) -> void:
	var action := "ability_%d" % key
	_player.ability_cast._cast_lockout = 0.0  # each check casts on its own, not back-to-back
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _seconds(settle)

func _bolts() -> int:
	return get_tree().current_scene.get_children().filter(func(n): return n is PiercingBolt).size()

func _test_spell_library() -> void:
	await _reset(_conduit("wand_line1"))
	var bar_spell := _spell("ice_pulse")
	var page_spell := _spell("thunder_javelin")
	_player.ability_loadout.equip(bar_spell, 0)
	_player.ability_loadout.equip(page_spell, 4)
	Input.action_press("stance")
	await _frames(3)
	_check(_player.ability_cast.get_bar_ability(0) == page_spell, "holding RMB shows the stance page on the bar")
	var mana_before := _player.mana.current_mana
	await _cast_key(1, 0.3)
	_check(_player.mana.current_mana < mana_before, "key 1 casts the stance page spell in stance")
	_check(_player.ability_cast.get_cooldown_remaining(bar_spell) == 0.0, "the bar spell stays unused")
	Input.action_release("stance")
	await _frames(3)
	_check(_player.ability_cast.get_bar_ability(0) == bar_spell, "releasing RMB brings the bar back")
	await _cast_key(1, 0.3)
	_check(_player.ability_cast.get_cooldown_remaining(bar_spell) > 0.0, "key 1 casts the bar spell out of stance")

func _test_page_tag() -> void:
	await _reset(_conduit("athame_line1"))
	var fire := _spell("cinder_lance")
	_player.ability_loadout.equip(fire, 4)
	Input.action_press("stance")
	await _frames(3)
	await _cast_key(1, 0.3)
	_check(_player.ability_cast.get_cooldown_remaining(fire) == 0.0 and _cast_failures.any(func(r): return "Esoteric" in r), "an Esoteric page refuses a Fire spell")
	var esoteric := _spell("entropic_decay")
	_player.ability_loadout.equip(esoteric, 4)
	await _cast_key(1, 0.3)
	_check(_player.ability_cast.get_cooldown_remaining(esoteric) > 0.0, "and casts an Esoteric one")

func _test_unleash() -> void:
	await _reset(_conduit("staff_line1"))
	var javelin := _spell("thunder_javelin")
	_player.ability_loadout.equip(javelin, 0)
	Input.action_press("stance")
	await _frames(3)
	var mana := _player.mana.current_mana
	await _cast_key(1, 0.0)
	await _frames(1)
	_check(_bolts() == 3, "staff unleash fires 3 copies (%d)" % _bolts())
	_check(absf(mana - _player.mana.current_mana - javelin.get_mana_cost(_player.stat_sheet) * 3) < 0.01, "mana is paid per copy")
	var pulse := _spell("ice_pulse")
	_player.ability_loadout.equip(pulse, 1)
	mana = _player.mana.current_mana
	await _cast_key(2, 0.3)
	_check(absf(mana - _player.mana.current_mana - pulse.get_mana_cost(_player.stat_sheet)) < 0.01, "non-Unleashable spells cast once (%.1f mana)" % (mana - _player.mana.current_mana))
	await _reset(_conduit("wand_line2"))
	_player.ability_loadout.equip(javelin, 0)
	Input.action_press("stance")
	await _frames(3)
	await _cast_key(1, 0.0)
	await _frames(1)
	_check(_bolts() == 2, "wand unleash fires 2 copies (%d)" % _bolts())

## Ice Pulse on a dummy in range, with or without the stance held.
func _pulse_damage(main: Weapon, off: Weapon, page: WeaponStance.StancePage, spell_id: String, in_stance: bool) -> float:
	await _reset(main, off, page)
	var target := _dummy(START + _forward() * 2.0)
	_player.ability_loadout.equip(_spell(spell_id), 0)
	await _frames(3)
	if in_stance:
		Input.action_press("stance")
		await _frames(3)
	await _cast_key(1, 0.8)
	return _lost(target)

func _test_stance_buffs() -> void:
	var main := _conduit("wand_line1")
	var talisman := _conduit("talisman_line1")
	var plain := await _pulse_damage(main, talisman, WeaponStance.StancePage.B, "ice_pulse", false)
	var buffed := await _pulse_damage(main, talisman, WeaponStance.StancePage.B, "ice_pulse", true)
	_check(plain > 0.0 and absf(buffed / plain - CasterStance.SPELL_DAMAGE_BUFF) < 0.02, "talisman: +25%% spell damage in stance (%.0f vs %.0f)" % [buffed, plain])
	var athame := _conduit("athame_line2")
	var esoteric_plain := await _pulse_damage(athame, null, WeaponStance.StancePage.A, "entropic_decay", false)
	var esoteric_buffed := await _pulse_damage(athame, null, WeaponStance.StancePage.A, "entropic_decay", true)
	var cold_plain := await _pulse_damage(athame, null, WeaponStance.StancePage.A, "ice_pulse", false)
	var cold_buffed := await _pulse_damage(athame, null, WeaponStance.StancePage.A, "ice_pulse", true)
	_check(absf(esoteric_buffed / esoteric_plain - CasterStance.ESOTERIC_DAMAGE_BUFF) < 0.02, "athame: Esoteric spells hit 30%% harder in stance")
	_check(absf(cold_buffed / cold_plain - 1.0) < 0.02, "athame: other spells are unchanged")

func _test_ward_buff() -> void:
	await _reset(_conduit("wand_line1"), _conduit("talisman_line2"), WeaponStance.StancePage.B)
	_player.ward.max_ward = 100.0
	_player.ward.current_ward = 0.0
	_player.ability_loadout.equip(_spell("ice_pulse"), 0)
	Input.action_press("stance")
	await _frames(3)
	await _cast_key(1, 0.1)
	_check(_player.ward.current_ward >= 7.9, "ward talisman restores Ward per cast (%.1f)" % _player.ward.current_ward)

func _page_cast(off_line: String, spell_id: String) -> Enemy:
	await _reset(_conduit("wand_line1"), _conduit(off_line), WeaponStance.StancePage.B)
	var target := _dummy(START + _forward() * 2.0)
	_player.ability_loadout.equip(_spell(spell_id), 4)
	await _frames(3)
	Input.action_press("stance")
	await _frames(3)
	await _cast_key(1, 0.6)
	return target

func _test_page_modifiers() -> void:
	var doubled := await _page_cast("grimoire_line2", "ice_pulse")
	_check(doubled.status_effects._chill_stacks == 2, "dark knowledge applies Chill twice (%d)" % doubled.status_effects._chill_stacks)
	var enhanced := await _page_cast("fetish_line1", "ice_pulse")
	var chill_left: float = enhanced.status_effects._timers.get("chill", 0.0)
	_check(chill_left > StatusEffectComponent.CHILL_DURATION, "status amplifier makes Chill last longer (%.2f s)" % chill_left)
	var pale := await _page_cast("fetish_line2", "entropic_decay")
	_check(pale.status_effects.has_effect("pallid"), "pale focus applies Pallid")
	_check(pale.get_outgoing_damage_multiplier() < 1.0, "Pallid enemies deal less damage")

func _test_mana_stars() -> void:
	await _reset(_conduit("spell_gauntlet_line1"))
	var target := _dummy(START + _forward() * 6.0)
	Input.action_press("stance")
	await _frames(3)
	var mana := _player.mana.current_mana
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _seconds(0.6)
	_check(_lost(target) > 0.0, "mana star hits")
	_check(absf(mana - _player.mana.current_mana - CasterStance.MANA_STAR_MANA_COST) < 0.01, "each mana star costs mana (%.1f)" % (mana - _player.mana.current_mana))
	_check(_player.melee_attack.is_idle(), "mana stars replace the punch")

func _test_battlemage() -> void:
	await _reset(_conduit("spell_gauntlet_line2"))
	var target := _dummy(START + _forward() * 1.6)
	var hits: Array[int] = [0]  # lambdas capture locals by value; an Array is shared
	var count := func(_s, t, _a, _ty, _sp, _c): if t == target: hits[0] += 1
	EventBus.damage_dealt.connect(count)
	Input.action_press("stance")
	await _frames(3)
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _seconds(1.2)
	EventBus.damage_dealt.disconnect(count)
	_check(hits[0] >= 2, "battlemage punch lands and a mana star follows (%d hits)" % hits[0])
	await _reset(_conduit("staff_line2"))
	var far := _dummy(START + _forward() * 3.8)
	await _frames(3)
	Input.action_press("stance")
	await _seconds(1.0)
	_check(_lost(far) > 0.0, "battlemage staff strikes at reach on RMB")

func _test_wand_bolts() -> void:
	await _reset(_conduit("wand_line1"))
	var target := _dummy(START + _forward() * 6.0)
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _seconds(0.6)
	_check(_lost(target) > 0.0, "wands fire energy bolts on LMB")
	_check(_player.melee_attack.is_idle(), "instead of swinging")

func _test_rod_is_passive() -> void:
	var sword := Weapon.new()
	sword.weapon_type = "Greatsword"
	sword.base_damage_min = 40.0
	sword.base_damage_max = 40.0
	await _reset(sword, _conduit("rod_line1"), WeaponStance.StancePage.B)
	Input.action_press("stance")
	await _frames(3)
	_check(not _player.caster_stance.is_active(), "a Rod gives no stance")
	_check(_player.weapon_stance.current_behavior != null, "the weapon's own stance B applies instead")
