extends CanvasLayer
## The game's tooltip, replacing Godot's popup tooltip (whose delay is set
## out of reach in project.godot). Every frame it reads the control under
## the mouse and its tooltip text, so a tooltip shows the frame the cursor
## arrives, changes the moment the cursor crosses into another slot or cell,
## follows the cursor exactly, and is rebuilt every REFRESH_SEC so it tracks
## changes underneath it (crafts, equips, stat changes).
##
## Controls supply content the usual Godot way: tooltip_text / _get_tooltip()
## for the text, and an optional _make_custom_tooltip() for a custom Control
## (ItemCard). The tooltip ignores the mouse, so it can never steal hover.

const OFFSET := Vector2(18, 20)
const MARGIN := 4.0
const REFRESH_SEC := 0.25
const TOOLTIP_VARIATION := &"TooltipPanel"

var _mouse := Vector2.ZERO
var _source: Control
var _text: String = ""
var _shown: Control
## Built but not shown until it has been laid out for a frame, so a rebuild
## never flashes at the wrong size.
var _pending: Control
var _refresh_left: float = 0.0

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse = event.position
	if event is InputEventMouseButton:
		_refresh_left = 0.0  # a click usually changes what's hovered
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C and (event.ctrl_pressed or event.meta_pressed) and is_instance_valid(_source):
		_copy_hovered()

func _process(delta: float) -> void:
	var root := get_tree().root
	var source: Control = null
	var text := ""
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		var hovered := root.gui_get_hovered_control()
		var found := tooltip_source(hovered, _mouse)
		source = found[0]
		text = found[1]
	if source == null:
		_hide()
		return
	_refresh_left -= delta
	if source != _source or text != _text or _refresh_left <= 0.0:
		_source = source
		_text = text
		_refresh_left = REFRESH_SEC
		_build()
	if _pending and _pending.is_inside_tree():
		if _pending.has_meta(&"laid_out"):
			if _shown:
				_shown.queue_free()
			_shown = _pending
			_pending = null
			_ignore_mouse(_shown)  # covers lines a card added since (Alt)
			_shown.modulate.a = 1.0
		else:
			_pending.set_meta(&"laid_out", true)
			_pending.reset_size()
	if _shown:
		_shown.reset_size()
		_shown.position = place(_mouse, _shown.size, root.get_visible_rect().size)

## [control, text] for the control that owns the tooltip at mouse: like
## Godot, it walks up from the hovered control through PASS parents until
## one returns tooltip text.
static func tooltip_source(hovered: Control, mouse: Vector2) -> Array:
	var control := hovered
	while control:
		var text := control.get_tooltip(control.get_global_transform_with_canvas().affine_inverse() * mouse)
		if text != "":
			return [control, text]
		if control.mouse_filter != Control.MOUSE_FILTER_PASS or control.top_level:
			break
		control = control.get_parent_control()
	return [null, ""]

func _build() -> void:
	if _pending:
		_pending.queue_free()
		_pending = null
	var content: Control = null
	if _source.get_script() != null and _source.has_method(&"_make_custom_tooltip"):
		content = _source.call(&"_make_custom_tooltip", _text) as Control
	if content == null:
		content = plain(_text)
	_ignore_mouse(content)
	content.modulate.a = 0.0
	add_child(content)
	content.position = place(_mouse, content.get_combined_minimum_size(), get_tree().root.get_visible_rect().size)
	_pending = content

func _hide() -> void:
	_source = null
	_text = ""
	for node in [_shown, _pending]:
		if node:
			node.queue_free()
	_shown = null
	_pending = null

## Text-only tooltip in the theme's tooltip style.
static func plain(text: String) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = TOOLTIP_VARIATION
	var label := Label.new()
	label.theme_type_variation = &"TooltipLabel"
	label.text = text
	panel.add_child(label)
	return panel

static func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

## Ctrl+C over anything with a card copies it as text (ItemText).
func _copy_hovered() -> void:
	var content = null
	var count := 1
	if _source is FateBoardGrid:
		var board: FateBoard = (_source as FateBoardGrid).board
		if board and board.placements.has(_text):
			content = board.placements[_text].slate
	elif "entry" in _source and _source.get("entry") is GridInventory.Entry:
		content = _source.get("entry").content
		count = _source.get("entry").count
	elif "id" in _source and _source.get("id") is StringName:
		content = _source.get("id")
		count = int(_source.get("count"))
	else:
		for key in ["item", "slate", "ability"]:
			if key in _source and _source.get(key) != null:
				content = _source.get(key)
				break
	var text := ItemText.of(content, count) if content != null else ""
	if text == "":
		return
	DisplayServer.clipboard_set(text)
	get_viewport().set_input_as_handled()
	_toast("Copied to clipboard")

func _toast(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.add_theme_color_override("font_color", AetherStyle.GOLD_BRIGHT)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.position = _mouse + Vector2(14, -28)
	add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.5)
	tween.tween_callback(label.queue_free)

## Whatever tooltip is up right now (null when none), for tests.
func current() -> Control:
	return _shown if _shown else _pending

## Top-left corner for a tooltip of tip_size beside the cursor.
static func place(mouse: Vector2, tip_size: Vector2, view: Vector2) -> Vector2:
	var pos := mouse + OFFSET
	if pos.x + tip_size.x > view.x - MARGIN:
		pos.x = mouse.x - OFFSET.x - tip_size.x
	if pos.y + tip_size.y > view.y - MARGIN:
		pos.y = mouse.y - OFFSET.y - tip_size.y
	pos.x = clampf(pos.x, MARGIN, maxf(view.x - tip_size.x - MARGIN, MARGIN))
	pos.y = clampf(pos.y, MARGIN, maxf(view.y - tip_size.y - MARGIN, MARGIN))
	return pos
