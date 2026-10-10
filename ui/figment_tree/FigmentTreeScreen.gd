extends CanvasLayer
class_name FigmentTreeScreen
## The Figment Tree screen (L / open_figment_tree, a Tab-menu screen).
## Left: endgame progress - points, the completion grid (every style at
## every tier; a first clear is a point) and the story milestones. Right:
## the tree (FigmentTreeView). Click a node to allocate it, right-click to
## refund it; drag to pan, wheel to zoom.

const LEFT_WIDTH := 430.0
const CELL := 13.0

var _is_open := false
var _view: FigmentTreeView
var _points_label: Label
var _summary_label: Label
var _grid: ProgressGrid
var _milestones: VBoxContainer
var _effects_label: Label
var _status_label: Label

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("figment_tree_screen")
	add_to_group("blocking_menu")
	_build()
	AetherStyle.style_screen(self)

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()

func close() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SaveManager.save_game()

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "DimBackground"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 44)  # under the tab strip
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = LEFT_WIDTH
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "Figment Tree"
	left.add_child(title)
	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 18)
	_points_label.add_theme_color_override("font_color", AetherStyle.AETHER)
	left.add_child(_points_label)
	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	left.add_child(_summary_label)

	var grid_title := Label.new()
	grid_title.name = "GridTitle"
	grid_title.text = "Completed Figments"
	left.add_child(grid_title)
	_grid = ProgressGrid.new()
	left.add_child(_grid)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var scroll_box := VBoxContainer.new()
	scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_box)
	var story_title := Label.new()
	story_title.name = "StoryTitle"
	story_title.text = "The Rebuilt Memory"
	scroll_box.add_child(story_title)
	_milestones = VBoxContainer.new()
	_milestones.add_theme_constant_override("separation", 6)
	scroll_box.add_child(_milestones)
	var effects_title := Label.new()
	effects_title.name = "EffectsTitle"
	effects_title.text = "Tree Effects"
	scroll_box.add_child(effects_title)
	_effects_label = Label.new()
	_effects_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effects_label.custom_minimum_size.x = LEFT_WIDTH - 20.0
	_effects_label.add_theme_color_override("font_color", AetherStyle.MOD_BLUE)
	scroll_box.add_child(_effects_label)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", AetherStyle.glass_box(AetherStyle.GOLD_DIM, AetherStyle.GLASS_SOLID, 1, 2.0))
	right.add_child(panel)
	_view = FigmentTreeView.new()
	_view.clip_contents = true
	_view.changed.connect(refresh)
	_view.status.connect(func(text: String): _status_label.text = text)
	panel.add_child(_view)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	right.add_child(bottom)
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	_status_label.text = "Click: allocate   Right-click: refund   Drag: pan   Wheel: zoom"
	bottom.add_child(_status_label)
	var reset := Button.new()
	reset.text = "Refund All"
	reset.pressed.connect(func():
		FigmentTree.reset()
		refresh())
	bottom.add_child(reset)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	bottom.add_child(close_button)

func refresh() -> void:
	if _points_label == null:
		return
	_points_label.text = "%d point%s to spend   (%d earned, %d spent)" % [FigmentProgress.points_available(),
		"" if FigmentProgress.points_available() == 1 else "s", FigmentProgress.points_earned(), FigmentProgress.points_spent()]
	var bands := []
	for b in 3:
		var r := FigmentMods.band_range(b)
		bands.append("%s (T%d-%d): %d" % [FigmentMods.BAND_NAMES[b], r.x, r.y, FigmentProgress.completed_in_band(b)])
	_summary_label.text = "Highest tier completed: %d   Figments drop up to Tier %d\n%s\nEach style earns a point for its first clear in each band." % [
		FigmentProgress.highest_tier_completed(), FigmentProgress.max_drop_tier(), "   ".join(bands)]
	_grid.queue_redraw()
	_view.queue_redraw()
	_refresh_milestones()
	_refresh_effects()

func _refresh_milestones() -> void:
	for child in _milestones.get_children():
		child.queue_free()
	for m in FigmentProgress.MILESTONES:
		var reached := FigmentProgress.milestone_reached(m)
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = LEFT_WIDTH - 20.0
		var need := ("Complete a Tier %d Figment" % int(m["tier"])) if m.has("tier") else ("Earn %d points" % (FigmentProgress.total_possible() if int(m["total"]) < 0 else int(m["total"])))
		label.text = "%s\n%s" % [m["title"], m["text"]] if reached else "???\n%s" % need
		label.add_theme_color_override("font_color", AetherStyle.TEXT if reached else AetherStyle.TEXT_DIM)
		_milestones.add_child(label)

func _refresh_effects() -> void:
	var lines: Array[String] = []
	for id in GameState.figment_tree_unlocked_nodes:
		var node := FigmentTree.get_node_by_id(id)
		if node and node.notable:
			lines.append("%s: %s" % [node.display_name, node.description.replace("\n", "; ")])
	var smalls := {}
	for id in GameState.figment_tree_unlocked_nodes:
		var node := FigmentTree.get_node_by_id(id)
		if node and not node.notable:
			smalls[node.description] = int(smalls.get(node.description, 0)) + 1
	for desc in smalls:
		lines.append("%s%s" % [desc, "  (x%d)" % smalls[desc] if smalls[desc] > 1 else ""])
	_effects_label.text = "\n".join(lines) if not lines.is_empty() else "No nodes allocated yet."

## Rows are styles (grouped by family), one column per band; a filled cell
## is a band cleared (a point) and shows the highest tier cleared in it.
class ProgressGrid extends Control:
	const LABEL_W := 92.0
	const BAND_W := 96.0

	func _ready() -> void:
		custom_minimum_size = Vector2(LABEL_W + 3 * BAND_W + 4.0, (MapTileset.all_ids().size() + 1) * CELL + 4.0)

	func _draw() -> void:
		var font := AetherStyle.numbers()
		for b in 3:
			var r := FigmentMods.band_range(b)
			AetherStyle.text(self, font, Vector2(LABEL_W + b * BAND_W, CELL - 2.0), "%s  T%d-%d" % [FigmentMods.BAND_NAMES[b], r.x, r.y], 10, AetherStyle.TEXT_DIM)
		var ids := _ordered_ids()
		for row in ids.size():
			var y := (row + 1) * CELL + 2.0
			var style := MapTileset.load_style(ids[row])
			AetherStyle.text(self, AetherStyle.serif(), Vector2(0, y + CELL - 3.0), style.display_name if style else ids[row], 11, AetherStyle.TEXT_DIM)
			for b in 3:
				var band_color: Color = FigmentMods.BAND_COLORS[b]
				var rect := Rect2(LABEL_W + b * BAND_W, y, BAND_W - 4.0, CELL - 2.0)
				var best := FigmentProgress.highest_in_band(ids[row], b)
				if best > 0:
					draw_rect(rect, band_color)
					AetherStyle.text(self, font, rect.position + Vector2(0, CELL - 3.0), "T%d" % best, 10, AetherStyle.GLASS_SOLID, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
				else:
					draw_rect(rect, Color(band_color, 0.12))
					draw_rect(rect, Color(band_color, 0.35), false, 1.0)

	static func _ordered_ids() -> Array[String]:
		var out: Array[String] = []
		for family in MapTileset.FAMILIES:
			for id in MapTileset.all_ids():
				if MapTileset.family_of(id) == family:
					out.append(id)
		for id in MapTileset.all_ids():
			if not out.has(id):
				out.append(id)
		return out
