class_name Screenshot extends Node

# Renders the real scene and writes user://screenshot.png, so a person can inspect
# the pixel grid:
#   godot tests/screenshot.tscn
# Needs a real window. Headless renders nothing. Silent with exit 0 once the file is
# written; a failed write is printed with printerr and exits 1.

const OUTPUT_PATH: String = "user://screenshot.png"
const WARMUP_FRAMES: int = 45

var _frame: int = 0
var _done: bool = false


func _process(_delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _frame == 1:
		Input.action_press(&"move_right")
	if _frame < WARMUP_FRAMES:
		return

	_done = true
	Input.action_release(&"move_right")
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var save_error: int = image.save_png(OUTPUT_PATH)
	if save_error != OK:
		printerr("FAIL  could not write %s: error %d" % [OUTPUT_PATH, save_error])
		get_tree().quit(1)
		return
	get_tree().quit(0)
