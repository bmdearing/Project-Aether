extends VBoxContainer
class_name NewGamePanel
## New Game, in three steps: the character's name, a starter weapon, then the
## game mode. Campaign is shown but locked until there is one.

signal confirmed(player_name: String, weapon_path: String, mode: GameState.GameMode)
signal back_pressed

const NAME_MAX := 20
const NAME_MIN := 2
## [label, weapon resource, one-line pitch].
const STARTER_WEAPONS := [
	["Sword", "res://data/weapons/instances/gen_shortsword_crude_blade.tres", "Quick one-handed blade. Leaves a hand free for a shield or focus."],
	["Great Sword", "res://data/weapons/instances/crude_greatsword.tres", "Slow, heavy two-handed swings that cleave through packs."],
	["Short Bow", "res://data/weapons/instances/gen_shortbow_crude_shortbow.tres", "Fire arrows from range and keep moving."],
	["Staff", "res://data/weapons/instances/worn_staff.tres", "A caster's weapon that strengthens your spells."],
]

var _step := 0
var _name_edit: LineEdit
var _name_hint: Label
var _title: Label
var _pages: Array[Control] = []
var _next: Button
var _weapon_index := -1
var _weapon_buttons: Array[Button] = []
var _mode := GameState.GameMode.FRAGMENTED_REALITY

## Letters and single spaces only: no digits, symbols or punctuation.
static func sanitize_name(text: String) -> String:
	var out := ""
	for ch in text:
		var is_letter := ch.to_upper() != ch.to_lower()
		if is_letter:
			out += ch
		elif ch == " " and out != "" and not out.ends_with(" "):
			out += ch
	return out.substr(0, NAME_MAX)

static func is_valid_name(text: String) -> bool:
	return text.strip_edges().length() >= NAME_MIN

func _ready() -> void:
	custom_minimum_size = Vector2(560, 0)
	add_theme_constant_override("separation", 14)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", MainMenu.GOLD)
	add_child(_title)
	_pages = [_build_name_page(), _build_weapon_page(), _build_mode_page()]
	for page in _pages:
		add_child(page)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	add_child(nav)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back)
	nav.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	_next = Button.new()
	_next.pressed.connect(_on_next)
	nav.add_child(_next)
	reset()

func reset() -> void:
	_step = 0
	_weapon_index = -1
	_mode = GameState.GameMode.FRAGMENTED_REALITY
	_name_edit.text = ""
	for b in _weapon_buttons:
		b.button_pressed = false
	_show_step()

func _show_step() -> void:
	for i in _pages.size():
		_pages[i].visible = i == _step
	_title.text = ["Name Your Character", "Choose a Starter Weapon", "Choose a Mode"][_step]
	_next.text = "Begin" if _step == _pages.size() - 1 else "Next"
	_refresh_next()
	if _step == 0:
		_name_edit.grab_focus.call_deferred()

func _refresh_next() -> void:
	match _step:
		0: _next.disabled = not is_valid_name(_name_edit.text)
		1: _next.disabled = _weapon_index < 0
		_: _next.disabled = _mode != GameState.GameMode.FRAGMENTED_REALITY

func _on_next() -> void:
	if _next.disabled:
		return
	if _step < _pages.size() - 1:
		_step += 1
		_show_step()
		return
	confirmed.emit(_name_edit.text.strip_edges(), STARTER_WEAPONS[_weapon_index][1], _mode)

func _on_back() -> void:
	if _step == 0:
		back_pressed.emit()
		return
	_step -= 1
	_show_step()

func _build_name_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name"
	_name_edit.max_length = NAME_MAX
	_name_edit.custom_minimum_size = Vector2(0, 40)
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(func(_t): _on_next())
	page.add_child(_name_edit)
	_name_hint = _small("Letters and spaces only, %d to %d characters." % [NAME_MIN, NAME_MAX])
	page.add_child(_name_hint)
	return page

func _on_name_changed(text: String) -> void:
	var clean := sanitize_name(text)
	if clean != text:
		var caret := _name_edit.caret_column - (text.length() - clean.length())
		_name_edit.text = clean
		_name_edit.caret_column = clampi(caret, 0, clean.length())
	_refresh_next()

func _build_weapon_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for i in STARTER_WEAPONS.size():
		var entry: Array = STARTER_WEAPONS[i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 54)
		b.text = "%s\n%s" % [entry[0], entry[2]]
		b.pressed.connect(func():
			_weapon_index = i
			_refresh_next())
		_weapon_buttons.append(b)
		page.add_child(b)
	return page

func _build_mode_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	var campaign := Button.new()
	campaign.toggle_mode = true
	campaign.button_group = group
	campaign.disabled = true
	campaign.alignment = HORIZONTAL_ALIGNMENT_LEFT
	campaign.custom_minimum_size = Vector2(0, 54)
	campaign.text = "Campaign\nComing soon."
	page.add_child(campaign)
	var fragmented := Button.new()
	fragmented.toggle_mode = true
	fragmented.button_group = group
	fragmented.button_pressed = true
	fragmented.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fragmented.custom_minimum_size = Vector2(0, 54)
	fragmented.text = "Fragmented Reality\nRun Figments from the Hub, the endless mapping game."
	fragmented.pressed.connect(func():
		_mode = GameState.GameMode.FRAGMENTED_REALITY
		_refresh_next())
	page.add_child(fragmented)
	return page

func _small(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MainMenu.TEXT_DISABLED)
	return label
