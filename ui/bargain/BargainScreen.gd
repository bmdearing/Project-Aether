extends CanvasLayer
class_name BargainScreen
## The Watcher's offer: three deals (a boon and its price, for the rest of
## the Figment), a challenge, or walking away. Built in code; pauses the game
## while open and frees itself on close.

var _watcher: Watcher
var _is_open := false

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("blocking_menu")

func is_open() -> bool:
	return _is_open

func open(watcher: Watcher) -> void:
	_watcher = watcher
	_is_open = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = AetherStyle.build_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.name = "DimBackground"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(620, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = Watcher.NAME
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var line := Label.new()
	line.text = "Every boon has its price, carried until this Figment ends. Choose one, or prove yourself."
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	box.add_child(line)
	box.add_child(HSeparator.new())

	for row in _watcher.offer_rows():
		box.add_child(_deal_row(row))
	box.add_child(HSeparator.new())

	var challenge := Button.new()
	challenge.text = "Challenge: face its champion (an Ascendant pack) for a hoard"
	challenge.pressed.connect(func():
		_watcher.challenge()
		close())
	box.add_child(challenge)
	var leave := Button.new()
	leave.text = "Walk away (the offer stands)"
	leave.pressed.connect(close)
	box.add_child(leave)
	AetherStyle.style_screen(self)
	AetherStyle.wrap_in_plate(box, 24)

func _deal_row(row: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var boon := Label.new()
	boon.text = row["boon"]
	boon.add_theme_color_override("font_color", AetherStyle.GOLD)
	boon.add_theme_font_size_override("font_size", 18)
	text.add_child(boon)
	var price := Label.new()
	price.text = "Price: " + String(row["price"])
	price.add_theme_color_override("font_color", Color(0.9, 0.45, 0.4))
	text.add_child(price)
	h.add_child(text)
	var accept := Button.new()
	accept.text = "Accept"
	accept.custom_minimum_size = Vector2(110, 0)
	accept.pressed.connect(func():
		_watcher.accept(row["id"])
		close())
	h.add_child(accept)
	return h
