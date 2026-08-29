extends AudioStreamPlayer
class_name ProceduralThunder
## Periodic thunder rumble, synthesized like ProceduralRain but with a
## heavier low-pass (lower cutoff = deeper rumble) gated by a fading
## envelope, firing at random intervals. thunder_started lets the scene
## sync a lightning flash to the same moment the rumble begins.

signal thunder_started

@export var min_interval_sec: float = 14.0
@export var max_interval_sec: float = 32.0
@export var rumble_duration_min: float = 1.5
@export var rumble_duration_max: float = 3.5
@export var mix_rate: float = 22050.0
@export var buffer_length: float = 0.5
@export var target_volume_db: float = -8.0
@export var rumble_smoothing: float = 0.03  # lower = deeper/heavier rumble

var _playback: AudioStreamGeneratorPlayback
var _seconds_until_next: float = 0.0
var _rumble_seconds_left: float = 0.0
var _rumble_duration: float = 1.0
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
	_seconds_until_next = randf_range(min_interval_sec, max_interval_sec)

func _process(delta: float) -> void:
	_seconds_until_next -= delta
	if _seconds_until_next <= 0.0 and _rumble_seconds_left <= 0.0:
		_start_rumble()
	if _playback:
		_fill_buffer()

func _start_rumble() -> void:
	_rumble_duration = randf_range(rumble_duration_min, rumble_duration_max)
	_rumble_seconds_left = _rumble_duration
	_seconds_until_next = randf_range(min_interval_sec, max_interval_sec)
	thunder_started.emit()

## Ticks the envelope in sample-count, not `delta` - audio-thread-accurate
## timing (each pushed frame is exactly 1/mix_rate seconds), unlike
## `_process`'s visual-frame-rate delta.
func _fill_buffer() -> void:
	var frames := _playback.get_frames_available()
	var seconds_per_frame := 1.0 / mix_rate
	for i in range(frames):
		var sample := 0.0
		if _rumble_seconds_left > 0.0:
			var envelope: float = clamp(_rumble_seconds_left / _rumble_duration, 0.0, 1.0)
			var white := randf_range(-1.0, 1.0)
			_phase = lerp(_phase, white, rumble_smoothing)
			sample = _phase * envelope
			_rumble_seconds_left -= seconds_per_frame
		_playback.push_frame(Vector2(sample, sample))
