class_name CameraTrigger extends Node2D

# Walk in, the camera parks on the marker. Walk out, it follows the player again.

@export var target: Marker2D
@export var trigger_area: Area2D


func _ready() -> void:
	assert(target, "camera_trigger.gd - @export target is not set in the editor on: " + self.name)
	assert(trigger_area, "camera_trigger.gd - @export trigger_area is not set in the editor on: " + self.name)
	var _error: int = trigger_area.body_entered.connect(
		func(body: Node2D) -> void:
			if !(body is Player) or Global.camera == null:
				return
			# Claim the camera, so overlapping triggers cannot release each other's.
			Global.active_camera_trigger = self
			Global.camera.set_target(target)
	)
	_error = trigger_area.body_exited.connect(
		func(body: Node2D) -> void:
			if !(body is Player) or Global.camera == null:
				return
			if Global.active_camera_trigger != self:
				return
			Global.active_camera_trigger = null
			Global.camera.set_target(Global.player)
	)
