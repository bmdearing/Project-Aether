extends Node
class_name ComposureComponent
## Handles the vulnerable "Broken" state that opens after Stance depletes
## to zero. A melee attack landed while is_broken == true is a Riposte
## (see ParryRiposteHandler.execute_riposte(), called from
## PlayerMeleeAttack._deal_damage()) - not gated by how the break
## happened (a Parry or plain attrition both work).
##
## Part Composure (independent limb-breaking for Behemoth-tier enemies) is
## flagged as a future extension - not implemented in this scaffold.

signal broken_state_started
signal broken_state_ended

@export var break_duration: float = 4.0
@export var damage_taken_multiplier_while_broken: float = 1.5

var is_broken: bool = false
var _break_timer: float = 0.0

func _ready() -> void:
	var stance: StanceComponent = get_parent().get_node_or_null("StanceComponent")
	if stance:
		EventBus.composure_broken.connect(_on_composure_broken)

func _on_composure_broken(target: Node) -> void:
	if target != get_parent():
		return
	enter_broken_state()

func enter_broken_state() -> void:
	is_broken = true
	_break_timer = break_duration
	EventBus.riposte_window_opened.emit(get_parent())
	broken_state_started.emit()

func _process(delta: float) -> void:
	if not is_broken:
		return
	_break_timer -= delta
	if _break_timer <= 0.0:
		end_broken_state()

## Public so a successful Riposte can end the window early (it consumes
## the break) instead of waiting out break_duration.
func end_broken_state() -> void:
	if not is_broken:
		return
	is_broken = false
	var stance: StanceComponent = get_parent().get_node_or_null("StanceComponent")
	if stance:
		stance.reset()
	broken_state_ended.emit()

## The broken-state bonus excludes spells, so spell damage passes is_spell.
func get_damage_multiplier(is_spell: bool = false) -> float:
	if is_spell:
		return 1.0
	return damage_taken_multiplier_while_broken if is_broken else 1.0
