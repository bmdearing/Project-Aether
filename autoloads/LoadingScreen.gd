extends CanvasLayer
## Load screen for every scene change: a full-screen plate with where you're
## going, a gameplay tip and a progress bar. The next scene loads on a
## background thread (ResourceLoader threaded load); the plate stays up while
## the new scene builds itself (generated maps do their work in _ready()) and
## fades out a moment after.
##
## LoadingScreen.change_scene(path) replaces get_tree().change_scene_to_file(path).

const FADE_SEC := 0.35
## Frames to keep the plate up after the scene changes, so its first heavy
## frames (map building, shader compiles) happen behind it.
const SETTLE_FRAMES := 6
const MIN_SHOW_SEC := 0.6

const TIPS := [
	"Tap Left Mouse for a quick light attack; hold it for a heavy one.",
	"Hold Right Mouse to enter your weapon's stance. Charged stances fire on release.",
	"Press F as an enemy's attack lands to parry, then strike back for a riposte.",
	"Hold Alt over an item to see its modifier tiers and ranges.",
	"Slates that touch and share a tag form a chain. Longer chains amplify their attributes more.",
	"Press T to open a portal home. Your Figment waits for you to come back.",
	"Spells level up with gold and Crystallized Aether on the Spells screen (K).",
	"Jewels socket permanently: right-click one, then click the item to set it in.",
	"Magic Find raises both the number of drops and their rarity.",
	"Killing a Figment's boss opens a portal home on the altar of its chamber.",
	"Ward absorbs damage before Life and recovers on its own once you stop taking hits.",
	"Tap Shift to dash; tap Ctrl while sprinting to slide.",
	"Hold X to switch your stance page, tap it to swap weapon sets.",
	"Controls can be remapped under Settings > Controls.",
]

var _root: Control
var _title: Label
var _subtitle: Label
var _tip: Label
var _bar: ProgressBar
var _path: String = ""
var _shown_at: int = 0
var _busy := false

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false

func is_busy() -> bool:
	return _busy

## Shows the plate and changes to path once it has loaded.
func change_scene(path: String) -> void:
	if _busy:
		return
	_busy = true
	_path = path
	_describe(path)
	_bar.value = 0.0
	_root.modulate.a = 1.0
	visible = true
	_shown_at = Time.get_ticks_msec()
	get_tree().paused = false
	if ResourceLoader.load_threaded_request(path) != OK:
		_finish(load(path) as PackedScene)
		return
	set_process(true)

func _process(_delta: float) -> void:
	if not _busy or _path == "":
		set_process(false)
		return
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(_path, progress)
	if not progress.is_empty():
		_bar.value = maxf(_bar.value, float(progress[0]) * 90.0)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			set_process(false)
			_finish(ResourceLoader.load_threaded_get(_path) as PackedScene)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			set_process(false)
			_finish(load(_path) as PackedScene)

func _finish(scene: PackedScene) -> void:
	_path = ""
	await get_tree().process_frame  # the plate has drawn at least once before the hitch
	if scene:
		get_tree().change_scene_to_packed(scene)
	else:
		push_error("LoadingScreen: could not load the scene")
	_bar.value = 95.0
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	var wait := MIN_SHOW_SEC - (Time.get_ticks_msec() - _shown_at) / 1000.0
	if wait > 0.0:
		await get_tree().create_timer(wait, true, false, true).timeout
	_bar.value = 100.0
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_SEC)
	await tween.finished
	visible = false
	_busy = false

func _describe(path: String) -> void:
	var title := "Loading"
	var subtitle := ""
	if path == GameState.MAP_SCENE:
		var map := GameState.active_map
		var style := MapTileset.load_style(map.tileset_id) if map else null
		title = map.display_name if map else "Figment"
		if style:
			subtitle = "%s  ·  %s" % [style.display_name, style.family.capitalize()]
		if map:
			subtitle += ("  ·  " if subtitle != "" else "") + "Tier %d" % map.tier
	elif path == GameState.HUB_SCENE:
		title = "The Memory Nexus"
		subtitle = "A hub adrift in the void"
	elif path == GameState.MAIN_MENU_SCENE:
		title = "Project Aether"
	else:
		title = "Pinnacle"
		subtitle = "Beyond the Reality Engine"
	_title.text = title
	_subtitle.text = subtitle
	_tip.text = TIPS.pick_random()

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing underneath takes clicks meanwhile
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.045)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var frame := LoadingFrame.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(frame)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(900, 0)
	box.position = Vector2(-450, -110)
	box.add_theme_constant_override("separation", 14)
	_root.add_child(box)
	_title = _label(AetherStyle.title(), 46, AetherStyle.GOLD_BRIGHT)
	box.add_child(_title)
	_subtitle = _label(AetherStyle.serif_italic(), 20, AetherStyle.TEXT_DIM)
	box.add_child(_subtitle)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	box.add_child(spacer)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(900, 8)
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = AetherStyle.AETHER
	var back := StyleBoxFlat.new()
	back.bg_color = Color(AetherStyle.AETHER, 0.12)
	back.border_color = AetherStyle.GOLD_DIM
	back.set_border_width_all(1)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	box.add_child(_bar)
	_tip = _label(AetherStyle.serif(), 18, AetherStyle.TEXT)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_tip)

func _label(font: Font, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label

## Gold border lines and a slow-turning ring of ticks behind the text.
class LoadingFrame extends Control:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		AetherStyle.ticks(self, c, 260.0, 72, 6, Color(AetherStyle.GOLD_FAINT, 0.35))
		draw_arc(c, 250.0, _t * 0.4, _t * 0.4 + TAU * 0.3, 48, Color(AetherStyle.AETHER, 0.35), 2.0, true)
		draw_arc(c, 250.0, _t * 0.4 + PI, _t * 0.4 + PI + TAU * 0.3, 48, Color(AetherStyle.AETHER, 0.35), 2.0, true)
		var inset := 40.0
		draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), AetherStyle.GOLD_FAINT, false, 1.0)
		for p in [Vector2(inset, inset), Vector2(size.x - inset, inset), size - Vector2(inset, inset), Vector2(inset, size.y - inset)]:
			AetherStyle.diamond(self, p, 6.0, AetherStyle.GLASS_SOLID, AetherStyle.GOLD)
