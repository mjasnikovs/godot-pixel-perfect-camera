class_name MouseListener extends Node

# Records where mouse events land inside the SubViewport, for tests/mouse.gd.

var last_position: Vector2 = Vector2.ZERO


func _input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		last_position = motion.position
