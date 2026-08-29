extends Node

## Autoload. Holds typed references that other nodes register themselves into.
## Nothing here uses hardcoded node paths, so renaming a node cannot break it.

var camera: PixelCamera = null
var player: Player = null
var active_camera_trigger: CameraTrigger = null


func register_camera(new_camera: PixelCamera) -> void:
	camera = new_camera


func register_player(new_player: Player) -> void:
	player = new_player
