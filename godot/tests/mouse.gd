class_name Mouse extends Node

# Measures where a mouse position actually lands in this SubViewport setup:
#   godot tests/mouse.tscn
# Injects a mouse motion event at a known window pixel, converts it to a world
# position with several candidate formulas, draws a marker there, then reads the
# rendered frame back and measures how far the marker is from the pointer. Silent with
# exit 0 means the `+1 -cam_offset` formula lands on the pointer's own pixel at every
# sub-pixel camera offset; a failure is printed with printerr and exits 1.

const GAME_SIZE: Vector2 = Vector2(320.0, 180.0)
const MARKER_SIZE: int = 4
const MARKER_COLOR: Color = Color(1.0, 0.0, 1.0, 1.0)
# A marker drawn inside the SubViewport can only land on whole game pixels, so half
# a game pixel is the best any formula can measure as.
const TOLERANCE: float = 0.5
const SEARCH_RADIUS: float = 160.0
const CAMERA_POSITION: Vector2 = Vector2(40.0, 120.0)
const OFFSETS: Array[float] = [0.0, -0.5, -0.25, 0.25, 0.5]
const PROBES: Array[Vector2] = [
	Vector2(640.0, 360.0),
	Vector2(204.0, 116.0),
	Vector2(1084.0, 596.0),
]

@export var container: SubViewportContainer
@export var sub_viewport: SubViewport

var _marker: Sprite2D = null
var _listener: MouseListener = null
var _camera: Camera2D = null
var _material: ShaderMaterial = null
var _scale: float = 1.0
var _event_position: Vector2 = Vector2.ZERO
var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	assert(container, "mouse.gd - @export container is not set in the editor on: " + self.name)
	assert(sub_viewport, "mouse.gd - @export sub_viewport is not set in the editor on: " + self.name)

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


# The position the game actually receives for the injected event.
func _input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_event_position = motion.position


func _process(_delta: float) -> void:
	if _started:
		return
	_started = true
	await _run()


func _run() -> void:
	_camera = Global.camera
	_camera.set_physics_process(false)
	_camera.global_position = CAMERA_POSITION
	if Global.player != null:
		Global.player.set_physics_process(false)
	_material = container.material as ShaderMaterial

	var probe: Image = await _render()
	_scale = float(probe.get_width()) / GAME_SIZE.x

	await _stage_window_to_root()
	await _stage_root_to_sub_viewport()
	await _stage_formulas()
	await _stage_every_offset()

	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL  %s" % failure)
	get_tree().quit(1)


func _stage_window_to_root() -> void:
	for window_pixel: Vector2 in PROBES:
		var root_position: Vector2 = await _point_at(window_pixel)
		var expected: Vector2 = window_pixel / _scale
		_check(
			"window %v arrives as %v" % [window_pixel, expected],
			root_position.is_equal_approx(expected),
			"got %v" % root_position
		)


func _stage_root_to_sub_viewport() -> void:
	for window_pixel: Vector2 in PROBES:
		var root_position: Vector2 = await _point_at(window_pixel)
		var delta: Vector2 = _listener.last_position - root_position
		_check(
			"window %v arrives inside the SubViewport at %v" % [window_pixel, root_position + Vector2.ONE],
			delta.is_equal_approx(Vector2.ONE),
			"delta %v" % delta
		)


# The `+1` formula's error is exactly cam_offset at every offset: the shader shifts
# the displayed image and the mouse is not shifted with it.
func _stage_formulas() -> void:
	var tracks_offset: bool = true
	var worst: Vector2 = Vector2.ZERO
	for offset: float in OFFSETS:
		var cam_offset: Vector2 = Vector2(offset, offset)
		_material.set_shader_parameter(&"cam_offset", cam_offset)
		var root_position: Vector2 = await _point_at(PROBES[0])
		var error: Vector2 = await _error_for("+1", PROBES[0], root_position, cam_offset)
		if is_nan(error.x) or !error.is_equal_approx(cam_offset):
			tracks_offset = false
			worst = error
	_material.set_shader_parameter(&"cam_offset", Vector2.ZERO)
	_check("the displayed image is shifted by exactly cam_offset", tracks_offset, "error %v" % worst)


func _stage_every_offset() -> void:
	for variant: String in ["raw", "+1 -cam_offset"]:
		var worst: float = 0.0
		for window_pixel: Vector2 in PROBES:
			for offset: float in OFFSETS:
				var cam_offset: Vector2 = Vector2(offset, -offset)
				_material.set_shader_parameter(&"cam_offset", cam_offset)
				var root_position: Vector2 = await _point_at(window_pixel)
				var error: Vector2 = await _error_for(variant, window_pixel, root_position, cam_offset)
				if is_nan(error.x):
					worst = INF
					continue
				worst = maxf(worst, maxf(absf(error.x), absf(error.y)))
		if variant == "raw":
			_check("the naive formula is visibly wrong", worst > TOLERANCE, "worst %.2f game px" % worst)
			continue
		_check("%s lands on the pointer's own pixel" % variant, worst <= TOLERANCE, "worst %.2f game px" % worst)
	_material.set_shader_parameter(&"cam_offset", Vector2.ZERO)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	var line: String = label
	if !detail.is_empty():
		line = "%s  (%s)" % [label, detail]
	_failures.append(line)


# Injects a motion event at a window pixel and returns the root-viewport position
# the game sees for it.
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
	var world: Vector2 = Vector2.ZERO
	if variant == "raw":
		world = base
	elif variant == "+1":
		world = base + Vector2.ONE
	elif variant == "+1 -cam_offset":
		world = base + Vector2.ONE - cam_offset
	return world


func _render() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# Centre of the marker in window pixels, searched in a box around the pointer, or
# (-1, -1) if no marker pixel is in that box.
func _find_marker(image: Image, around: Vector2) -> Vector2:
	var reach: Vector2 = Vector2(SEARCH_RADIUS, SEARCH_RADIUS)
	var image_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(image.get_size()))
	var box: Rect2 = Rect2(around.floor() - reach, reach * 2.0).intersection(image_rect)
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
	return sum / float(count) + box.position


# Error in game pixels between the drawn marker and the pointer.
func _error_for(variant: String, window_pixel: Vector2, root_position: Vector2, cam_offset: Vector2) -> Vector2:
	_marker.visible = true
	_marker.global_position = _world_for(variant, root_position, cam_offset)
	var found: Vector2 = _find_marker(await _render(), window_pixel)
	_marker.visible = false
	if found.x < 0.0:
		return Vector2(NAN, NAN)
	return (found - window_pixel) / _scale
