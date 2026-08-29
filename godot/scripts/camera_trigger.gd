class_name CameraTrigger extends Node2D

## Walk in, the camera parks on the marker. Walk out, it follows the player again.

@export var target: Marker2D = null
@export var trigger_area: Area2D = null


func _ready() -> void:
	assert(target != null, "CameraTrigger: 'target' is not assigned.")
	assert(trigger_area != null, "CameraTrigger: 'trigger_area' is not assigned.")

	var entered_error: int = trigger_area.body_entered.connect(_on_body_entered)
	var exited_error: int = trigger_area.body_exited.connect(_on_body_exited)
	assert(entered_error == OK, "CameraTrigger: could not connect body_entered.")
	assert(exited_error == OK, "CameraTrigger: could not connect body_exited.")


func _on_body_entered(body: Node2D) -> void:
	if body is not Player or Global.camera == null:
		return
	# Claim the camera, so overlapping triggers cannot release each other's.
	Global.active_camera_trigger = self
	Global.camera.set_target(target)


func _on_body_exited(body: Node2D) -> void:
	if body is not Player or Global.camera == null:
		return
	if Global.active_camera_trigger != self:
		return
	Global.active_camera_trigger = null
	Global.camera.set_target(Global.player)
