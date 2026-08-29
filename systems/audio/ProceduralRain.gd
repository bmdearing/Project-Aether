extends AudioStreamPlayer
class_name ProceduralRain
## Continuous rain hiss, synthesized at runtime via AudioStreamGenerator -
## no audio asset exists (or is needed) for it. A one-pole low-pass on
## white noise (each sample pulled partway toward the last) turns harsh
## static into a softer "shhh" wash. Plays on the default Master bus, so
## it already respects GameState.master_volume like everything else.

@export var mix_rate: float = 22050.0
@export var buffer_length: float = 0.5
@export var target_volume_db: float = -20.0
@export var smoothing: float = 0.12

var _playback: AudioStreamGeneratorPlayback
var _phase: float = 0.0

func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = mix_rate
	generator.buffer_length = buffer_length
	stream = generator
	volume_db = target_volume_db
	autoplay = false
	play()
	_playback = get_stream_playback()

func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	for i in range(frames):
		var white := randf_range(-1.0, 1.0)
		_phase = lerp(_phase, white, smoothing)
		var sample: float = _phase * 0.6
		_playback.push_frame(Vector2(sample, sample))
