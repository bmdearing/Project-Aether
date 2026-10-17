extends Node
## Autoload. Plays one-shot SFX through a small round-robin pool so rapid
## fire (full-auto, shotgun pellets) reuses players instead of piling up new
## ones. A null stream is a silent no-op, so empty SoundLibrary slots stay
## quiet. (No class_name: autoload singleton.)
##
## Also plays the sounds that hang off EventBus (blocks, loot, crafting),
## a click for every button, and one looping ambience bed (play_ambience()).

const SFX_POOL_SIZE := 16
const PITCH_VARIATION := 0.05
## The same stream won't start again within this window (a spell hitting a
## whole pack plays its hit once, not ten times stacked).
const REPEAT_GUARD_MSEC := 40
const UI_CLICK_DB := -10.0
const AMBIENCE_FADE_SEC := 1.5

var _sfx_pool: Array[AudioStreamPlayer3D] = []
var _pool_index: int = 0
var _last_played: Dictionary = {}  # stream instance id -> msec
var _ambience: Array[AudioStreamPlayer] = []
var _ambience_id: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 8.0
		add_child(player)
		_sfx_pool.append(player)
	get_tree().node_added.connect(_on_node_added)
	EventBus.parry_successful.connect(func(player: Node, _attacker: Node): if player is Node3D: play_at(SoundLib.pick_random(SoundLib.library.parry), (player as Node3D).global_position, -2.0))
	EventBus.hit_blocked.connect(func(player: Node): if player is Node3D: play_at(SoundLib.pick_random(SoundLib.library.shield_block), (player as Node3D).global_position, -4.0))
	EventBus.loot_dropped.connect(func(_item, at: Vector3): play_at(SoundLib.pick_random(SoundLib.library.item_drop), at, -8.0))
	EventBus.loot_picked_up.connect(func(_item): play_2d(SoundLib.library.item_pickup, -8.0))
	EventBus.craft_completed.connect(func(_item, _result): play_2d(SoundLib.library.craft_apply, -6.0))
	EventBus.craft_failed.connect(func(_item, _error, _message): play_2d(SoundLib.library.dry_click, -6.0))
	EventBus.ability_cast_failed.connect(_on_ability_cast_failed)

## Warcraft III's Human "Not enough mana", at most once per NO_MANA_VOICE_GAP_MSEC.
const NOT_ENOUGH_MANA := preload("res://assets/sfx/ui/not_enough_mana.ogg")
const NO_MANA_VOICE_GAP_MSEC := 1500
var _no_mana_voice_at: int = -NO_MANA_VOICE_GAP_MSEC

func _on_ability_cast_failed(caster: Node, _ability: Ability, reason: String) -> void:
	if not caster is Player or reason != "Not enough Mana":
		return
	var now := Time.get_ticks_msec()
	if now - _no_mana_voice_at < NO_MANA_VOICE_GAP_MSEC:
		return
	_no_mana_voice_at = now
	var player := AudioStreamPlayer.new()  # not play_2d(): no pitch jitter on a voice
	add_child(player)
	player.stream = NOT_ENOUGH_MANA
	player.volume_db = -2.0
	player.play()
	player.finished.connect(player.queue_free)

func _guarded(stream: AudioStream) -> bool:
	var now := Time.get_ticks_msec()
	var id := stream.get_instance_id()
	if now - int(_last_played.get(id, -REPEAT_GUARD_MSEC)) < REPEAT_GUARD_MSEC:
		return true
	_last_played[id] = now
	return false

func play_at(stream: AudioStream, position: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null or _guarded(stream):
		return
	var player := _sfx_pool[_pool_index]
	_pool_index = (_pool_index + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale + randf_range(-PITCH_VARIATION, PITCH_VARIATION)
	player.play()

func play_2d(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null or _guarded(stream):
		return
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-PITCH_VARIATION, PITCH_VARIATION)
	player.play()
	player.finished.connect(player.queue_free)

## Every button clicks; inventory and other item slots handle their own.
func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node is ItemSlotButton:
		(node as BaseButton).pressed.connect(func(): play_2d(SoundLib.library.ui_click, UI_CLICK_DB))

## Crossfades to a looping ambience: one Ambience.LOOPS id, or several
## layered with optional dB offsets ("river:-9,forest"). "" fades it out.
func play_ambience(spec: String, volume_db: float = 0.0) -> void:
	if spec == ambience_id():
		return
	_ambience_id = spec
	for old in _ambience:
		var out := create_tween()
		out.tween_property(old, "volume_db", -60.0, AMBIENCE_FADE_SEC * 0.5)
		out.tween_callback(old.queue_free)
	_ambience.clear()
	for layer in spec.split(",", false):
		var parts := layer.strip_edges().split(":")
		var id := parts[0]
		var stream := Ambience.load_loop(id)
		if stream == null:
			push_error("AudioManager: ambience loop '%s' is missing or not imported" % id)
			continue
		var offset := float(parts[1]) if parts.size() > 1 else 0.0
		var player := AudioStreamPlayer.new()
		add_child(player)
		player.stream = stream
		player.volume_db = -60.0
		player.play()
		_ambience.append(player)
		create_tween().tween_property(player, "volume_db", volume_db + Ambience.volume_db(id) + offset, AMBIENCE_FADE_SEC)

func ambience_id() -> String:
	return _ambience_id if _ambience.any(func(p: AudioStreamPlayer): return is_instance_valid(p) and p.playing) else ""
