class_name Verify extends Node

# Headless self-test. Drives the real scene and asserts the pixel-perfect invariants
# hold every single frame. A self-test scene, so godot-code-style's test rule holds:
# it prints nothing on a pass, and on a failure it prints each one with printerr and
# quits with exit code 1.

const EPSILON: float = 0.0001
const EXPECTED_VIEWPORT_SIZE: Vector2 = Vector2(322.0, 182.0)
const EXPECTED_GAME_SIZE: Vector2 = Vector2(320.0, 180.0)
# A headless launch only parses what the main scene reaches, so every script is
# loaded here by path.
const SCRIPT_DIRECTORIES: Array[String] = ["res://scripts/", "res://tests/"]

@export_category("Nodes")
@export var container: SubViewportContainer
@export var sub_viewport: SubViewport

var _failures: Array[String] = []
var _frame: int = 0
var _camera_start: Vector2 = Vector2.ZERO
var _max_subpixel: float = 0.0
var _saw_fractional_offset: bool = false
var _phase: String = "startup"


func _ready() -> void:
	assert(container, "verify.gd - @export container is not set in the editor on: " + self.name)
	assert(sub_viewport, "verify.gd - @export sub_viewport is not set in the editor on: " + self.name)


func _process(_delta: float) -> void:
	_check_invariants_this_frame()
	_frame += 1

	if _frame == 1:
		_check_every_script_compiles()
		_check_static_setup()
		if Global.camera:
			_camera_start = Global.camera.global_position
		Input.action_press(&"move_right")
		_phase = "walking right"
	elif _frame == 90:
		Input.action_release(&"move_right")
		_check_follow()
	elif _frame == 100:
		# Teleport the player into the left camera trigger.
		_place_player(Vector2(-180.0, 60.0))
		_phase = "inside trigger"
	elif _frame == 140:
		_check_trigger_claimed()
	elif _frame == 150:
		_place_player(Vector2(200.0, 60.0))
		_phase = "outside trigger"
	elif _frame == 200:
		_check_trigger_released()
	elif _frame == 210:
		if Global.camera:
			Global.camera.apply_shake(6.0)
		_phase = "shaking"
	elif _frame == 215:
		_check_shake_active()
	elif _frame == 260:
		_check(
			"shake decays back to zero",
			Global.camera != null and Global.camera.shake_strength < 0.05,
			str(Global.camera.shake_strength) if Global.camera else "no camera"
		)
	elif _frame == 270:
		_report_and_quit()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	var line: String = label
	if !detail.is_empty():
		line = "%s  (%s)" % [label, detail]
	_failures.append(line)


func _check_every_script_compiles() -> void:
	for directory: String in SCRIPT_DIRECTORIES:
		for file_name: String in DirAccess.get_files_at(directory):
			if !file_name.ends_with(".gd"):
				continue
			var script: GDScript = load(directory + file_name)
			_check("%s compiles" % file_name, script != null and script.can_instantiate())


func _check_static_setup() -> void:
	var viewport_size: Vector2 = Vector2(sub_viewport.size)
	_check(
		"SubViewport is %dx%d" % [EXPECTED_VIEWPORT_SIZE.x, EXPECTED_VIEWPORT_SIZE.y],
		viewport_size == EXPECTED_VIEWPORT_SIZE,
		str(viewport_size)
	)
	_check(
		"SubViewport is exactly 1px bigger per side than the game area",
		viewport_size - EXPECTED_GAME_SIZE == Vector2(2.0, 2.0),
		str(viewport_size - EXPECTED_GAME_SIZE)
	)
	_check(
		"container is offset -1,-1 to hide the extra border",
		is_equal_approx(container.position.x, -1.0) and is_equal_approx(container.position.y, -1.0),
		str(container.position)
	)
	_check("container size matches the SubViewport", container.size == EXPECTED_VIEWPORT_SIZE, str(container.size))
	_check(
		"container scale is 1 (the window stretch does all the scaling)",
		container.scale.is_equal_approx(Vector2.ONE),
		str(container.scale)
	)
	_check(
		"SubViewport texture filter is Nearest",
		sub_viewport.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	)
	var texture_filter: int = ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter", -1
	)
	_check("project texture filter default is Nearest", texture_filter == 0, str(texture_filter))

	var scale_mode: String = ProjectSettings.get_setting("display/window/stretch/scale_mode", "")
	_check("stretch scale mode is integer", scale_mode == "integer", scale_mode)

	var stretch_mode: String = ProjectSettings.get_setting("display/window/stretch/mode", "")
	_check(
		"stretch mode is canvas_items (renders at native res, so the shader\n        offset lands on real screen pixels)",
		stretch_mode == "canvas_items",
		stretch_mode
	)

	var base_width: float = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var base_height: float = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	_check(
		"base viewport equals the game size, so the container needs no scale",
		Vector2(base_width, base_height) == EXPECTED_GAME_SIZE,
		str(Vector2(base_width, base_height))
	)

	var resizable: bool = ProjectSettings.get_setting("display/window/size/resizable", true)
	_check("window is not resizable (a tiling WM would break integer scaling)", !resizable)

	var snap_transforms: bool = ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false)
	_check("snap_2d_transforms_to_pixel is OFF (godot#98764)", !snap_transforms)

	var snap_vertices: bool = ProjectSettings.get_setting("rendering/2d/snap/snap_2d_vertices_to_pixel", false)
	_check("root snap_2d_vertices_to_pixel is OFF (it rounds away the shader offset)", !snap_vertices)
	_check("SubViewport does its own vertex snapping instead", sub_viewport.snap_2d_vertices_to_pixel)

	var interpolation: bool = ProjectSettings.get_setting("physics/common/physics_interpolation", false)
	_check("physics interpolation is OFF (fights this technique)", !interpolation)
	_check("container material is a ShaderMaterial", container.material is ShaderMaterial)
	_check("camera registered itself in Global", Global.camera != null)
	_check("player registered itself in Global", Global.player != null)
	if Global.camera:
		_check("camera anchor mode is Drag Center", Global.camera.anchor_mode == Camera2D.ANCHOR_MODE_DRAG_CENTER)


func _check_follow() -> void:
	_check(
		"camera moved while following the player",
		Global.camera != null and Global.camera.global_position != _camera_start,
		"start %v" % _camera_start
	)
	_check("a sub-pixel offset was actually produced", _saw_fractional_offset, "max seen %f" % _max_subpixel)
	# Measured 0.4992: a camera that has moved has met nearly every fraction. Far
	# under that, the shader is not being fed each frame.
	_check("the sub-pixel offset reached close to half a pixel", _max_subpixel > 0.4, "max seen %f" % _max_subpixel)
	_check("camera target is the player", Global.camera != null and Global.camera.target == Global.player)


func _check_trigger_claimed() -> void:
	_check(
		"entering a trigger retargets the camera to its Marker2D",
		Global.camera != null and Global.camera.target is Marker2D,
		str(Global.camera.target) if Global.camera else "no camera"
	)
	_check("trigger claimed the camera", Global.active_camera_trigger != null)


func _check_trigger_released() -> void:
	_check(
		"leaving the trigger hands the camera back to the player",
		Global.camera != null and Global.camera.target == Global.player,
		str(Global.camera.target) if Global.camera else "no camera"
	)
	_check("trigger released the camera", Global.active_camera_trigger == null)


func _check_shake_active() -> void:
	_check(
		"shake is active",
		Global.camera != null and Global.camera.shake_strength > 0.0,
		str(Global.camera.shake_strength) if Global.camera else "no camera"
	)
	_check(
		"shake goes through the rounding, not Camera2D.offset",
		Global.camera != null and Global.camera.offset == Vector2.ZERO,
		str(Global.camera.offset) if Global.camera else "no camera"
	)


func _place_player(at: Vector2) -> void:
	if !Global.player:
		return
	Global.player.global_position = at
	Global.player.velocity = Vector2.ZERO


func _check_invariants_this_frame() -> void:
	var camera: PixelCamera = Global.camera
	if !camera:
		return

	var pos: Vector2 = camera.global_position
	if absf(pos.x - roundf(pos.x)) > EPSILON or absf(pos.y - roundf(pos.y)) > EPSILON:
		_failures.append("frame %d: camera position not whole pixels: %v" % [_frame, pos])

	if camera.offset != Vector2.ZERO:
		_failures.append("frame %d: Camera2D.offset bypassed the rounding: %v" % [_frame, camera.offset])

	var material: ShaderMaterial = container.material as ShaderMaterial
	var raw_offset: Variant = material.get_shader_parameter(&"cam_offset")
	if typeof(raw_offset) != TYPE_VECTOR2:
		_failures.append("frame %d: cam_offset shader parameter is not a Vector2" % _frame)
		return

	var offset: Vector2 = raw_offset
	_max_subpixel = maxf(_max_subpixel, maxf(absf(offset.x), absf(offset.y)))
	if absf(offset.x) > 0.5 + EPSILON or absf(offset.y) > 0.5 + EPSILON:
		_failures.append("frame %d: cam_offset exceeds half a pixel: %v" % [_frame, offset])
	if absf(offset.x) > EPSILON or absf(offset.y) > EPSILON:
		_saw_fractional_offset = true


func _report_and_quit() -> void:
	if _failures.is_empty():
		get_tree().quit(0)
		return
	printerr("FAIL  %d failures, phase: %s" % [_failures.size(), _phase])
	for failure: String in _failures:
		printerr("  - %s" % failure)
	get_tree().quit(1)
