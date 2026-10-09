extends VBoxContainer
class_name Wiki
## The Wiki (main menu and pause menu): tabs for Uniques, Modifiers and
## Corruption. Pages are built the first time they're opened.

signal back_pressed

const PAGES := ["Uniques", "Modifiers", "Corruption"]
const PAGE_HEIGHT := 650.0

var uniques: UniqueWiki
var modifiers: ModifierWiki
var corruption: CorruptionWiki
var current_page: String = "Uniques"

var _tabs: HBoxContainer
var _holder: Control

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Wiki"
	AetherStyle.title_label(title, 26)
	add_child(title)
	_tabs = HBoxContainer.new()
	add_child(_tabs)
	for page in PAGES:
		var b := Button.new()
		b.text = page
		b.toggle_mode = true
		b.pressed.connect(show_page.bind(page))
		_tabs.add_child(b)
	_holder = VBoxContainer.new()
	_holder.custom_minimum_size = Vector2(UniqueWiki.WIDTH, PAGE_HEIGHT)
	add_child(_holder)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)
	show_page("Uniques")

func show_page(page: String) -> void:
	current_page = page
	for b in _tabs.get_children():
		b.button_pressed = b.text == page
	if page == "Uniques" and uniques == null:
		uniques = UniqueWiki.new()
		_holder.add_child(uniques)
	elif page == "Modifiers" and modifiers == null:
		modifiers = ModifierWiki.new()
		_holder.add_child(modifiers)
	elif page == "Corruption" and corruption == null:
		corruption = CorruptionWiki.new()
		_holder.add_child(corruption)
	for p in [uniques, modifiers, corruption]:
		if p:
			p.visible = (p == uniques and page == "Uniques") or (p == modifiers and page == "Modifiers") or (p == corruption and page == "Corruption")

## Re-reads the character for the Uniques page's Magic Find.
func refresh_character() -> void:
	if uniques:
		uniques.refresh_character()
