extends Node
## Holds current run/session state. Vertical slice scope only -
## no save/load, no persistence layer yet.

var player_stat_sheet: Resource # StatSheet, assigned at runtime by Player.gd
var fate_board: Resource        # FateBoard, assigned at runtime
var player_equipment: Node      # EquipmentComponent, assigned at runtime by Player.gd

var debug_overlay_enabled: bool = true
