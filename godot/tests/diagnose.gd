extends Node

## Measures two things on real rendered frames, across several configurations:
##
##   1. steps/pixel - how many sub-pixel positions per game pixel actually
##      reach the screen. Higher is smoother. 1 means the shader does nothing.
##   2. square      - is every game pixel the same size on screen at every
##      sub-pixel offset? Anything else is smearing.
##
##     godot tests/diagnose.tscn

const GAME_WIDTH: int = 320
const STEPS: int = 16
const PROBE_OFFSETS: Array[float] = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]

@export var container: SubViewportContainer = null

var _started: bool = false


func _render(offset: Vector2) -> Image:
	var material: ShaderMaterial = container.material as ShaderMaterial
	material.set_shader_parameter("cam_offset", offset)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Counts runs of identical colour along many scanlines. On a clean integer
## upscale every run length is a multiple of the scale factor.
func _bad_run_ratio(image: Image, scale_factor: int) -> float:
	var bad: int = 0
	var total: int = 0
	var height: int = image.get_height()
	var width: int = image.get_width()
	for row: int in range(int(float(height) * 0.55), int(float(height) * 0.95), 3):
		var run: int = 1
		var previous: Color = image.get_pixel(0, row)
		for x: int in range(1, width):
			var current: Color = image.get_pixel(x, row)
			if current == previous:
				run += 1
				continue
			# Ignore the two runs clipped by the screen edges.
			if x < width - 1:
				total += 1
				if run % scale_factor != 0:
					bad += 1
			run = 1
			previous = current
	if total == 0:
		return -1.0
	return float(bad) / float(total)


func _report(label: String) -> void:
	var first: Image = await _render(Vector2.ZERO)
	var scale_factor: int = int(float(first.get_width()) / float(GAME_WIDTH))

	var previous: PackedByteArray = first.get_data()
	var distinct: int = 0
	for step: int in range(1, STEPS + 1):
		var current: PackedByteArray = (await _render(Vector2(float(step) / float(STEPS), 0.0))).get_data()
		if current != previous:
			distinct += 1
		previous = current

	var worst: float = 0.0
	for offset: float in PROBE_OFFSETS:
		var image: Image = await _render(Vector2(offset, 0.0))
		worst = maxf(worst, _bad_run_ratio(image, scale_factor))

	print("  %-34s render %4dx%-4d  %dx  steps/pixel %d/%d   %s" % [
		label,
		first.get_width(), first.get_height(),
		scale_factor,
		distinct, scale_factor,
		"square" if is_zero_approx(worst) else "UNEVEN (%.1f%% of runs)" % (worst * 100.0)
	])


func _process(_delta: float) -> void:
	if _started:
		return
	_started = true
	await _run()


func _run() -> void:
	var camera: PixelCamera = Global.camera
	camera.set_physics_process(false)
	camera.global_position = Vector2(40, 120)
	if Global.player != null:
		Global.player.set_physics_process(false)

	var window: Window = get_window()
	var root_rid: RID = get_viewport().get_viewport_rid()
	var sub_viewport: SubViewport = container.get_node("SubViewport") as SubViewport

	print("\nwindow %v\n" % window.size)
	print("  steps/pixel is measured out of the scale factor. Equal = perfectly")
	print("  smooth. Half = the camera judders in half-pixel hops.\n")

	await _report("A. as shipped (viewport stretch)")

	RenderingServer.viewport_set_snap_2d_vertices_to_pixel(root_rid, false)
	await _report("B. A, root vertex snap off")

	RenderingServer.viewport_set_snap_2d_transforms_to_pixel(root_rid, true)
	RenderingServer.viewport_set_snap_2d_vertices_to_pixel(root_rid, true)
	await _report("C. A, root transform + vertex snap")

	RenderingServer.viewport_set_snap_2d_transforms_to_pixel(root_rid, false)
	RenderingServer.viewport_set_snap_2d_vertices_to_pixel(root_rid, false)
	sub_viewport.snap_2d_vertices_to_pixel = true
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i(320, 180)
	container.scale = Vector2.ONE
	container.position = Vector2(-1.0, -1.0)
	await _report("D. canvas_items, base 320x180")

	get_tree().quit(0)
