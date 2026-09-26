class_name Diagnose extends Node

# Checks two things on real rendered frames, with the camera parked on a whole pixel:
#   steps/pixel - every sub-pixel position per game pixel reaches the screen, one per
#                 screen pixel of the scale factor.
#   square      - every game pixel is the same size on screen at every sub-pixel
#                 offset. Anything else is smearing.
# Needs a real window. Silent with exit 0 is a pass; a failure prints the measured
# value with printerr and exits 1.

const GAME_WIDTH: float = 320.0
const STEPS: int = 16
const PROBE_OFFSETS: Array[float] = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]

@export_category("Nodes")
@export var container: SubViewportContainer

var _started: bool = false


func _ready() -> void:
	assert(container, "diagnose.gd - @export container is not set in the editor on: " + self.name)


func _process(_delta: float) -> void:
	if _started:
		return
	_started = true
	await _run()


func _run() -> void:
	var camera: PixelCamera = Global.camera
	camera.set_physics_process(false)
	camera.global_position = Vector2(40.0, 120.0)
	if Global.player:
		Global.player.set_physics_process(false)

	var failures: Array[String] = []
	var first: Image = await _render(Vector2.ZERO)
	var scale_factor: int = int(float(first.get_width()) / GAME_WIDTH)

	var previous: PackedByteArray = first.get_data()
	var distinct: int = 0
	for step: int in range(1, STEPS + 1):
		var current: PackedByteArray = (await _render(Vector2(float(step) / float(STEPS), 0.0))).get_data()
		if current != previous:
			distinct += 1
		previous = current
	if distinct != scale_factor:
		failures.append("steps/pixel %d of %d: the camera judders in coarser hops" % [distinct, scale_factor])

	for offset: float in PROBE_OFFSETS:
		var image: Image = await _render(Vector2(offset, 0.0))
		var ratio: float = _bad_run_ratio(image, scale_factor)
		if !is_zero_approx(ratio):
			failures.append("at cam_offset %.3f, %.1f%% of colour runs are uneven" % [offset, ratio * 100.0])

	for failure: String in failures:
		printerr("FAIL  %s" % failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _render(offset: Vector2) -> Image:
	var material: ShaderMaterial = container.material as ShaderMaterial
	material.set_shader_parameter(&"cam_offset", offset)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# Counts runs of identical colour along many scanlines. On a clean integer upscale
# every run length is a multiple of the scale factor, except the two runs the screen
# edges cut off: the image slides by up to a game pixel, so the edge run is partial.
func _bad_run_ratio(image: Image, scale_factor: int) -> float:
	var bad: int = 0
	var total: int = 0
	var height: int = image.get_height()
	var width: int = image.get_width()
	for row: int in range(int(float(height) * 0.55), int(float(height) * 0.95), 3):
		var run: int = 1
		var run_start: int = 0
		var previous: Color = image.get_pixel(0, row)
		for x: int in range(1, width):
			var current: Color = image.get_pixel(x, row)
			if current == previous:
				run += 1
				continue
			if run_start > 0 and x < width - 1:
				total += 1
				if run % scale_factor != 0:
					bad += 1
			run = 1
			run_start = x
			previous = current
	if total == 0:
		return -1.0
	return float(bad) / float(total)
