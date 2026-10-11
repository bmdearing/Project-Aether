class_name AureliaSfx
## Aurelia's fight sounds: Warcraft III spell and unit sounds pulled from the
## local install (tools/mdx_pipeline/wc3_sounds.js + aurelia_sounds.json)
## into assets/sfx/aurelia/. A name with numbered copies ("spears_hit" ->
## spears_hit_1, spears_hit_2) plays one of them at random.

const DIR := "res://assets/sfx/aurelia/"

static var _cache: Dictionary = {}

static func streams(sound: String) -> Array[AudioStream]:
	if _cache.has(sound):
		return _cache[sound]
	var found: Array[AudioStream] = []
	if ResourceLoader.exists(DIR + sound + ".ogg"):
		found.append(load(DIR + sound + ".ogg"))
	var i := 1
	while ResourceLoader.exists("%s%s_%d.ogg" % [DIR, sound, i]):
		found.append(load("%s%s_%d.ogg" % [DIR, sound, i]))
		i += 1
	_cache[sound] = found
	return found

static func play(sound: String, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var options := streams(sound)
	if not options.is_empty():
		AudioManager.play_at(options.pick_random(), at, volume_db, pitch)

## A looping sound heard everywhere in the arena, faded in; stop with fade_out().
static func loop(parent: Node, sound: String, volume_db: float = 0.0, fade: float = 0.6) -> AudioStreamPlayer:
	var options := streams(sound)
	if options.is_empty() or parent == null:
		return null
	var stream := options[0].duplicate() as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -50.0
	parent.add_child(player)
	player.play()
	player.create_tween().tween_property(player, "volume_db", volume_db, fade)
	return player

static func fade_out(player: AudioStreamPlayer, fade: float = 0.8) -> void:
	if not is_instance_valid(player):
		return
	var tween := player.create_tween()
	tween.tween_property(player, "volume_db", -50.0, fade)
	tween.tween_callback(player.queue_free)
