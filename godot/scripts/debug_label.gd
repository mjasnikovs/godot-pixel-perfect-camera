class_name DebugLabel extends Label

## Prints what the camera is doing. UI lives outside the SubViewport, so this
## renders at full window resolution, not at 320x180.


func _process(_delta: float) -> void:
	var camera: PixelCamera = Global.camera
	if camera == null:
		text = "no camera"
		return

	var target_name: String = "none"
	if camera.target != null:
		target_name = camera.target.name

	text = "target: %s\ncam: %v" % [target_name, camera.global_position]
