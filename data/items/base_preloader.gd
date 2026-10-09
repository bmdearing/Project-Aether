extends Node
class_name BasePreloader
## Loads every base item .tres (ItemRoller.BASE_ITEM_DIRS) on background
## threads at boot and keeps them loaded, so the first loot roll, Shard of
## Tharsis or Wiki Modifiers page doesn't stall for a second loading ~1000
## files on the main thread. GameState adds one to the tree at startup.

static var _held: Array[Resource] = []
var _pending: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for dir_path in ItemRoller.BASE_ITEM_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next().trim_suffix(".remap")
		while file_name != "":
			if file_name.ends_with(".tres"):
				var path: String = dir_path + file_name
				if ResourceLoader.load_threaded_request(path) == OK:
					_pending.append(path)
			file_name = dir.get_next().trim_suffix(".remap")
		dir.list_dir_end()

## Collects finished loads a batch at a time; frees itself when done.
func _process(_delta: float) -> void:
	var i := 0
	while i < _pending.size():
		var status := ResourceLoader.load_threaded_get_status(_pending[i])
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			i += 1
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_held.append(ResourceLoader.load_threaded_get(_pending[i]))
		_pending.remove_at(i)
	if _pending.is_empty():
		queue_free()

static func loaded_count() -> int:
	return _held.size()
