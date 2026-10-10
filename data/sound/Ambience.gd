extends RefCounted
class_name Ambience
## Looping ambience beds in assets/sfx/ambience/ (cut by
## tools/sfx_pipeline/process_sfx.js, loudness matched to -24 LUFS). Maps
## pick one by id (MapTileset.ambience_id); AudioManager.play_ambience()
## plays it.

const DIR := "res://assets/sfx/ambience/"
## id -> extra volume in dB.
const LOOPS := {
	"rain": 0.0,
	"factory_hall": -4.0,
	"boiler_room": -3.0,
	"eerie_tunnel": -3.0,
	"wind_gusts": -2.0,
	"wind_calm": 0.0,
	"forest": 0.0,
	"river": -2.0,
}
const THUNDER := ["thunder_01", "thunder_02", "thunder_03", "thunder_04", "thunder_05"]

static func load_loop(id: String) -> AudioStream:
	if not LOOPS.has(id) or not ResourceLoader.exists(DIR + id + ".ogg"):
		return null
	var stream := load(DIR + id + ".ogg") as AudioStreamOggVorbis
	if stream:
		stream.loop = true
	return stream

static func volume_db(id: String) -> float:
	return LOOPS.get(id, 0.0)

static func random_thunder() -> AudioStream:
	var path: String = DIR + THUNDER.pick_random() + ".ogg"
	return load(path) as AudioStream if ResourceLoader.exists(path) else null
