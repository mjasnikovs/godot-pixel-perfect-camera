extends Node

## Headless self-test. Drives the real scene and asserts the pixel-perfect
## invariants hold every single frame.
##
##     godot --headless tests/verify.tscn
##
## Exit code 0 = all checks passed. 1 = at least one failed.

const EPSILON: float = 0.0001
const EXPECTED_VIEWPORT_SIZE: Vector2i = Vector2i(322, 182)
const EXPECTED_GAME_SIZE: Vector2i = Vector2i(320, 180)

@export var container: SubViewportContainer = null
@export var sub_viewport: SubViewport = null

var _failures: Array[String] = []
var _checks: int = 0
var _frame: int = 0
var _camera_start: Vector2 = Vector2.ZERO
var _max_subpixel: float = 0.0
var _saw_fractional_offset: bool = false
var _phase: String = "startup"


func _ready() -> void:
	assert(container != null, "verify.gd: 'container' is not assigned.")
	assert(sub_viewport != null, "verify.gd: 'sub_viewport' is not assigned.")


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
		return
	var line: String = label
	if not detail.is_empty():
		line = "%s  (%s)" % [label, detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


func _check_static_setup() -> void:
	print("\n[setup]")
	_check(
		"SubViewport is %dx%d" % [EXPECTED_VIEWPORT_SIZE.x, EXPECTED_VIEWPORT_SIZE.y],
		sub_viewport.size == EXPECTED_VIEWPORT_SIZE,
		str(sub_viewport.size)
	)
	_check(
		"SubViewport is exactly 1px bigger per side than the game area",
		sub_viewport.size - EXPECTED_GAME_SIZE == Vector2i(2, 2),
		str(sub_viewport.size - EXPECTED_GAME_SIZE)
	)
	_check(
		"container is offset -1,-1 to hide the extra border",
		is_equal_approx(container.position.x, -1.0) and is_equal_approx(container.position.y, -1.0),
		str(container.position)
	)
	_check(
		"container size matches the SubViewport",
		container.size == Vector2(EXPECTED_VIEWPORT_SIZE),
		str(container.size)
	)
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

	var base_width: int = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var base_height: int = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	_check(
		"base viewport equals the game size, so the container needs no scale",
		Vector2i(base_width, base_height) == EXPECTED_GAME_SIZE,
		str(Vector2i(base_width, base_height))
	)

	var resizable: bool = ProjectSettings.get_setting("display/window/size/resizable", true)
	_check("window is not resizable (a tiling WM would break integer scaling)", not resizable)

	var snap_transforms: bool = ProjectSettings.get_setting(
		"rendering/2d/snap/snap_2d_transforms_to_pixel", false
	)
	_check("snap_2d_transforms_to_pixel is OFF (godot#98764)", not snap_transforms)

	var snap_vertices: bool = ProjectSettings.get_setting(
		"rendering/2d/snap/snap_2d_vertices_to_pixel", false
	)
	_check(
		"root snap_2d_vertices_to_pixel is OFF (it rounds away the shader offset)",
		not snap_vertices
	)
	_check(
		"SubViewport does its own vertex snapping instead",
		sub_viewport.snap_2d_vertices_to_pixel
	)

	var interpolation: bool = ProjectSettings.get_setting(
		"physics/common/physics_interpolation", false
	)
	_check("physics interpolation is OFF (fights this technique)", not interpolation)
	_check("container material is a ShaderMaterial", container.material is ShaderMaterial)
	_check("camera registered itself in Global", Global.camera != null)
	_check("player registered itself in Global", Global.player != null)
	if Global.camera != null:
		_check(
			"camera anchor mode is Drag Center",
			Global.camera.anchor_mode == Camera2D.ANCHOR_MODE_DRAG_CENTER
		)


func _check_invariants_this_frame() -> void:
	var camera: PixelCamera = Global.camera
	if camera == null:
		return

	var pos: Vector2 = camera.global_position
	if absf(pos.x - roundf(pos.x)) > EPSILON or absf(pos.y - roundf(pos.y)) > EPSILON:
		_failures.append("frame %d: camera position not whole pixels: %v" % [_frame, pos])

	if camera.offset != Vector2.ZERO:
		_failures.append("frame %d: Camera2D.offset bypassed the rounding: %v" % [_frame, camera.offset])

	var material: ShaderMaterial = container.material as ShaderMaterial
	var raw_offset: Variant = material.get_shader_parameter("cam_offset")
	if raw_offset == null:
		_failures.append("frame %d: cam_offset shader parameter is unset" % _frame)
		return

	var offset: Vector2 = raw_offset
	_max_subpixel = maxf(_max_subpixel, maxf(absf(offset.x), absf(offset.y)))
	if absf(offset.x) > 0.5 + EPSILON or absf(offset.y) > 0.5 + EPSILON:
		_failures.append("frame %d: cam_offset exceeds half a pixel: %v" % [_frame, offset])
	if absf(offset.x) > EPSILON or absf(offset.y) > EPSILON:
		_saw_fractional_offset = true


func _process(_delta: float) -> void:
	_check_invariants_this_frame()
	_frame += 1

	match _frame:
		1:
			_check_static_setup()
			if Global.camera != null:
				_camera_start = Global.camera.global_position
			Input.action_press("move_right")
			_phase = "walking right"
		90:
			Input.action_release("move_right")
			print("\n[follow]")
			_check(
				"camera moved while following the player",
				Global.camera != null and Global.camera.global_position != _camera_start,
				"start %v" % _camera_start
			)
			_check(
				"a sub-pixel offset was actually produced",
				_saw_fractional_offset,
				"max seen %f" % _max_subpixel
			)
			_check(
				"camera target is the player",
				Global.camera != null and Global.camera.target == Global.player
			)
		100:
			# Teleport the player into the left camera trigger.
			if Global.player != null:
				Global.player.global_position = Vector2(-180.0, 60.0)
				Global.player.velocity = Vector2.ZERO
			_phase = "inside trigger"
		140:
			print("\n[camera trigger]")
			_check(
				"entering a trigger retargets the camera to its Marker2D",
				Global.camera != null and Global.camera.target is Marker2D,
				str(Global.camera.target) if Global.camera != null else "no camera"
			)
			_check("trigger claimed the camera", Global.active_camera_trigger != null)
		150:
			if Global.player != null:
				Global.player.global_position = Vector2(200.0, 60.0)
				Global.player.velocity = Vector2.ZERO
			_phase = "outside trigger"
		200:
			_check(
				"leaving the trigger hands the camera back to the player",
				Global.camera != null and Global.camera.target == Global.player,
				str(Global.camera.target) if Global.camera != null else "no camera"
			)
			_check("trigger released the camera", Global.active_camera_trigger == null)
		210:
			print("\n[shake]")
			if Global.camera != null:
				Global.camera.apply_shake(6.0)
			_phase = "shaking"
		215:
			_check(
				"shake is active",
				Global.camera != null and Global.camera.shake_strength > 0.0,
				str(Global.camera.shake_strength) if Global.camera != null else "no camera"
			)
			_check(
				"shake goes through the rounding, not Camera2D.offset",
				Global.camera != null and Global.camera.offset == Vector2.ZERO,
				str(Global.camera.offset) if Global.camera != null else "no camera"
			)
		260:
			_check(
				"shake decays back to zero",
				Global.camera != null and Global.camera.shake_strength < 0.05,
				str(Global.camera.shake_strength) if Global.camera != null else "no camera"
			)
		270:
			_report_and_quit()


func _report_and_quit() -> void:
	print("\n[frame invariants]")
	print("  frames stepped: %d" % _frame)
	print("  max sub-pixel offset seen: %f" % _max_subpixel)

	var hard_failures: Array[String] = _failures
	print("\n------------------------------------------------------------")
	if hard_failures.is_empty():
		print("PASS  %d checks, %d frames, 0 failures" % [_checks, _frame])
		get_tree().quit(0)
		return

	print("FAIL  %d failures out of %d checks (phase: %s)" % [hard_failures.size(), _checks, _phase])
	for failure: String in hard_failures:
		print("  - %s" % failure)
	get_tree().quit(1)
