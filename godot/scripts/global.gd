extends Node

# Nodes register themselves here, so no script holds a node path and renaming a
# node cannot break anything.

var camera: PixelCamera = null
var player: Player = null
var active_camera_trigger: CameraTrigger = null


func register_camera(new_camera: PixelCamera) -> void:
	camera = new_camera


func register_player(new_player: Player) -> void:
	player = new_player
