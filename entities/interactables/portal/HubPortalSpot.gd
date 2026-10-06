extends Node3D
## Where the return portal appears in the Hub while a map run is open.

func _ready() -> void:
	if GameState.portal_map_state.is_empty():
		return
	var portal := Portal.new()
	portal.destination = Portal.Destination.MAP
	add_child(portal)
