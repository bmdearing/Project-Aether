extends CanvasLayer
class_name DebugOverlay
## Numeric overlay for validating the damage formula and Fate Board chain
## math before any art exists. Toggle via GameState.debug_overlay_enabled.

@onready var label: Label = $Label

func _ready() -> void:
	EventBus.aether_budget_changed.connect(_on_aether_changed)
	EventBus.chain_recalculated.connect(_on_chain_recalculated)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	visible = GameState.debug_overlay_enabled
	label.text = "Project Aether — Debug Overlay\nAether: 0/0"

func _on_aether_changed(used: int, capacity: int) -> void:
	_append_line("Aether: %d/%d" % [used, capacity])

func _on_chain_recalculated(chain_id: int, tile_count: int, bonus_percent: float) -> void:
	_append_line("Chain %d: %d tiles, +%.2f%% bonus" % [chain_id, tile_count, bonus_percent * 100.0])

func _on_damage_dealt(source: Node, target: Node, amount: float, damage_type: int, more_applied: bool) -> void:
	_append_line("Dmg: %.1f (type %d)%s" % [amount, damage_type, " [More applied]" if more_applied else ""])

func _append_line(text: String) -> void:
	label.text += "\n" + text
