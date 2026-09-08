extends Node

## Measures where a mouse position actually lands in this SubViewport setup.
##
##     godot tests/mouse.tscn
##
## Injects a mouse motion event at a known window pixel, converts it to a world
## position with several candidate formulas, draws a marker there, then reads
## the rendered frame back and reports how far the marker is from the pointer.
## Exit code 0 = one formula is exact at every sub-pixel camera offset.

const GAME_SIZE: Vector2 = Vector2(320.0, 180.0)
const MARKER_SIZE: int = 4
const MARKER_COLOR: Color = Color(1.0, 0.0, 1.0, 1.0)
## A marker drawn inside the SubViewport can only land on whole game pixels,
## so half a game pixel is the best any formula can measure as.
const TOLERANCE: float = 0.5
const SEARCH_RADIUS: int = 160
const CAMERA_POSITION: Vector2 = Vector2(40.0, 120.0)
const OFFSETS: Array[float] = [0.0, -0.5, -0.25, 0.25, 0.5]
const PROBES: Array[Vector2] = [
	Vector2(640.0, 360.0),
	Vector2(204.0, 116.0),
	Vector2(1084.0, 596.0),
]
const VARIANTS: Array[String] = [
	"raw",
	"+1",
	"+1 +cam_offset",
	"+1 -cam_offset",
]

@export var container: SubViewportContainer = null
@export var sub_viewport: SubViewport = null

var _marker: Sprite2D = null
var _listener: MouseListener = null
var _camera: Camera2D = null
var _material: ShaderMaterial = null
var _scale: float = 1.0
var _event_position: Vector2 = Vector2.ZERO
var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	assert(container != null, "mouse.gd: 'container' is not assigned.")
	assert(sub_viewport != null, "mouse.gd: 'sub_viewport' is not assigned.")

	var image: Image = Image.create_empty(MARKER_SIZE, MARKER_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(MARKER_COLOR)
	_marker = Sprite2D.new()
	_marker.texture = ImageTexture.create_from_image(image)
	_marker.centered = true
	_marker.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	_marker.visible = false
	sub_viewport.add_child(_marker)

	_listener = MouseListener.new()
	sub_viewport.add_child(_listener)


## The position the game actually receives for the injected event.
func _input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_event_position = motion.position


## Injects a motion event at a window pixel and returns the root-viewport
## position the game sees for it.
func _point_at(window_pixel: Vector2) -> Vector2:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = window_pixel
	motion.global_position = window_pixel
	Input.parse_input_event(motion)
	await get_tree().process_frame
	return _event_position


func _center() -> Vector2:
	return Vector2(sub_viewport.size) * 0.5


func _world_for(variant: String, root_position: Vector2, cam_offset: Vector2) -> Vector2:
	var base: Vector2 = _camera.global_position + root_position - _center()
	match variant:
		"raw":
			return base
		"+1":
			return base + Vector2.ONE
		"+1 +cam_offset":
			return base + Vector2.ONE + cam_offset
		"+1 -cam_offset":
			return base + Vector2.ONE - cam_offset
		"get_global_mouse_position()":
			return _camera.get_global_mouse_position()
		"get_global_mouse_position() -cam_offset":
			return _camera.get_global_mouse_position() - cam_offset
	return Vector2.ZERO


func _render() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Centre of the marker in window pixels, searched in a box around the
## pointer, or (-1, -1) if no marker pixel is in that box.
func _find_marker(image: Image, around: Vector2) -> Vector2:
	var box: Rect2i = Rect2i(
		Vector2i(around) - Vector2i(SEARCH_RADIUS, SEARCH_RADIUS),
		Vector2i(SEARCH_RADIUS * 2, SEARCH_RADIUS * 2)
	).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var region: Image = image.get_region(box)
	region.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = region.get_data()
	var width: int = region.get_width()
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0
	for index: int in range(0, bytes.size(), 4):
		if bytes[index] > 230 and bytes[index + 1] < 25 and bytes[index + 2] > 230:
			var pixel: int = index >> 2
			var row: int = int(float(pixel) / float(width))
			sum += Vector2(float(pixel % width) + 0.5, float(row) + 0.5)
			count += 1
	if count == 0:
		return Vector2(-1.0, -1.0)
	return sum / float(count) + Vector2(box.position)


## Error in game pixels between the drawn marker and the pointer.
func _error_for(variant: String, window_pixel: Vector2, root_position: Vector2,
		cam_offset: Vector2) -> Vector2:
	_marker.visible = true
	_marker.global_position = _world_for(variant, root_position, cam_offset)
	var found: Vector2 = _find_marker(await _render(), window_pixel)
	_marker.visible = false
	if found.x < 0.0:
		return Vector2(NAN, NAN)
	return (found - window_pixel) / _scale


func _run() -> void:
	_camera = Global.camera
	_camera.set_physics_process(false)
	_camera.global_position = CAMERA_POSITION
	if Global.player != null:
		Global.player.set_physics_process(false)
	_material = container.material as ShaderMaterial

	var probe: Image = await _render()
	_scale = float(probe.get_width()) / GAME_SIZE.x
	print("\nwindow %v   render %dx%d   scale %dx   SubViewport %v   container %v\n" % [
		get_window().size, probe.get_width(), probe.get_height(), int(_scale),
		sub_viewport.size, container.position
	])

	print("[stage 1] window pixel -> what the game receives (event.position)")
	for window_pixel: Vector2 in PROBES:
		var root_position: Vector2 = await _point_at(window_pixel)
		var expected: Vector2 = window_pixel / _scale
		_check("window %v arrives as %v" % [window_pixel, expected],
			root_position.is_equal_approx(expected), "got %v" % root_position)

	print("\n[stage 2] root viewport -> SubViewport (who adds the container's +1?)")
	for window_pixel: Vector2 in PROBES:
		var root_position: Vector2 = await _point_at(window_pixel)
		var delta: Vector2 = _listener.last_position - root_position
		_check("window %v arrives inside the SubViewport at %v"
			% [window_pixel, root_position + Vector2.ONE],
			delta.is_equal_approx(Vector2.ONE), "delta %v" % delta)

	print("\n[stage 3] rendered marker error in game pixels, per formula")
	print("  %-18s %s" % ["formula", "cam_offset " + str(OFFSETS)])
	var tracks_offset: bool = true
	for variant: String in VARIANTS:
		var cells: Array[String] = []
		for offset: float in OFFSETS:
			var cam_offset: Vector2 = Vector2(offset, offset)
			_material.set_shader_parameter("cam_offset", cam_offset)
			var root_position: Vector2 = await _point_at(PROBES[0])
			var error: Vector2 = await _error_for(variant, PROBES[0], root_position, cam_offset)
			if is_nan(error.x):
				cells.append(" off-screen")
				continue
			cells.append("%+6.2f,%+6.2f" % [error.x, error.y])
			if variant == "+1" and not error.is_equal_approx(cam_offset):
				tracks_offset = false
		print("  %-18s %s" % [variant, " ".join(cells)])
	_material.set_shader_parameter("cam_offset", Vector2.ZERO)
	_check("the displayed image is shifted by exactly cam_offset", tracks_offset)

	print("\n[stage 4] every pointer position, every sub-pixel camera offset")
	for variant: String in ["raw", "+1 -cam_offset"]:
		var worst: float = 0.0
		for window_pixel: Vector2 in PROBES:
			for offset: float in OFFSETS:
				var cam_offset: Vector2 = Vector2(offset, -offset)
				_material.set_shader_parameter("cam_offset", cam_offset)
				var root_position: Vector2 = await _point_at(window_pixel)
				var error: Vector2 = await _error_for(variant, window_pixel, root_position, cam_offset)
				if is_nan(error.x):
					worst = INF
					continue
				worst = maxf(worst, maxf(absf(error.x), absf(error.y)))
		if variant == "raw":
			_check("the naive formula is visibly wrong", worst > TOLERANCE,
				"worst %.2f game px" % worst)
			continue
		_check("%s lands on the pointer's own pixel" % variant, worst <= TOLERANCE,
			"worst %.2f game px" % worst)
	_material.set_shader_parameter("cam_offset", Vector2.ZERO)

	print("")
	if _failures.is_empty():
		print("all checks passed")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("FAILED: %s" % failure)
	get_tree().quit(1)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok    %s" % label)
		return
	var line: String = label
	if not detail.is_empty():
		line = "%s  (%s)" % [label, detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


func _process(_delta: float) -> void:
	if _started:
		return
	_started = true
	await _run()


## Reports mouse events as they arrive inside the SubViewport.
class MouseListener extends Node:
	var last_position: Vector2 = Vector2.ZERO

	func _input(event: InputEvent) -> void:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if motion != null:
			last_position = motion.position
