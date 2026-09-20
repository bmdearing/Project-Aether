extends Node
## Autoload. Plays one-shot SFX through a small round-robin pool so rapid
## fire (full-auto, shotgun pellets) reuses players instead of piling up new
## ones. A null stream is a silent no-op, which is what every call is until
## sound_library.tres is populated. (No class_name: autoload singleton.)

const SFX_POOL_SIZE := 8
const PITCH_VARIATION := 0.05

var _sfx_pool: Array[AudioStreamPlayer3D] = []
var _pool_index: int = 0

func _ready() -> void:
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer3D.new()
		add_child(player)
		_sfx_pool.append(player)

func play_at(stream: AudioStream, position: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null:
		return
	var player := _sfx_pool[_pool_index]
	_pool_index = (_pool_index + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale + randf_range(-PITCH_VARIATION, PITCH_VARIATION)
	player.play()

func play_2d(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-PITCH_VARIATION, PITCH_VARIATION)
	player.play()
	player.finished.connect(player.queue_free)
