class_name Scale extends Node

# Sizes the window to every integer factor up to 4 that fits the screen, x1 x2 x3 x4,
# in windowed mode, and checks each on real rendered frames:
#   godot tests/scale.tscn
# Needs a real window and a window manager, which is what makes a window fullscreen
# and gives it a title bar. Xvfb with Openbox is enough:
#   xvfb-run -a sh -c 'openbox & until xprop -root _NET_SUPPORTING_WM_CHECK |
#     grep -q "window id"; do sleep 0.2; done; exec godot tests/scale.tscn'
# Silent with exit 0 is a pass; each failure is printed with printerr and the run
# exits 1.
#
# The sub-pixel probes sit between screen pixel boundaries, never on one. An offset
# that puts an edge exactly on a pixel centre is a rasteriser tie, and a software
# rasteriser breaks ties differently from a GPU.

const FACTORS: Array[int] = [1, 2, 3, 4]
const PROBES_PER_SCREEN_PIXEL: int = 4
# How long a window manager may take to apply a new size, in frames.
const RESIZE_FRAMES: int = 60
const CAMERA_POSITION: Vector2 = Vector2(40.0, 120.0)

@export_category("Nodes")
@export var container: SubViewportContainer

var _failures: Array[String] = []
var _material: ShaderMaterial = null
var _event_position: Vector2 = Vector2.ZERO
var _started: bool = false


func _ready() -> void:
	assert(container, "scale.gd - @export container is not set in the editor on: " + self.name)


# The position the game actually receives for an injected event.
func _input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion:
		_event_position = motion.position


func _process(_delta: float) -> void:
	if _started:
		return
	_started = true
	await _run()


func _run() -> void:
	var camera: PixelCamera = Global.camera
	if !camera:
		printerr("FAIL  the camera never registered with Global")
		get_tree().quit(1)
		return
	camera.set_physics_process(false)
	camera.global_position = CAMERA_POSITION
	if Global.player:
		Global.player.set_physics_process(false)
	_material = container.material as ShaderMaterial

	# A window sized before the window manager framed it is fitted again once it has.
	await WindowScale.wait_until_settled()
	if get_window().mode == Window.MODE_WINDOWED:
		await _wait_until_shown(WindowScale.game_size() * WindowScale.factor)
	_check_startup()
	var start_factor: int = WindowScale.factor
	# From a fullscreen start the title bar is not measured until the window is back.
	if get_window().mode != Window.MODE_WINDOWED:
		var _windowed: int = WindowScale.set_factor(start_factor)
		await WindowScale.wait_until_settled()
	var max_factor: int = _expected_max()
	_check("the screen fits at least x2", max_factor >= 2, "max x%d" % max_factor)
	_check(
		"the largest factor is x%d, the largest whose frame fits" % max_factor,
		WindowScale.max_factor() == max_factor,
		"WindowScale says x%d" % WindowScale.max_factor()
	)

	for factor: int in FACTORS:
		if factor > max_factor:
			continue
		await _check_factor(factor)

	_check(
		"after every resize the largest factor is still x%d" % max_factor,
		WindowScale.max_factor() == max_factor,
		"WindowScale says x%d" % WindowScale.max_factor()
	)
	_check_clamped(0, 1)
	_check_clamped(max_factor + 1, max_factor)
	_check_frame_readings()
	await _check_largest_fits(max_factor)
	if max_factor >= 2:
		await _check_keys(max_factor)
	await _check_leaves_fullscreen(max_factor)
	var _restored: int = WindowScale.set_factor(start_factor)
	_material.set_shader_parameter(&"cam_offset", Vector2.ZERO)

	for failure: String in _failures:
		printerr("FAIL  %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_startup() -> void:
	var window: Window = get_window()
	var windowed: bool = window.mode == Window.MODE_WINDOWED
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	var game: Vector2 = Vector2(WindowScale.game_size())
	# Worked out here from the engine and the command line, not asked of WindowScale.
	var expected: int = 0
	# The first whole-number scale= counts; a malformed one only names the run.
	var asked: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if !argument.begins_with("scale="):
			continue
		var value: String = argument.trim_prefix("scale=")
		if value.is_valid_int():
			asked = value
			break
		if asked.is_empty():
			asked = value
	if asked.is_valid_int():
		expected = clampi(asked.to_int(), 1, _expected_max())
	elif windowed:
		# The window opens at --resolution, or the project's size, shrunk to fit and
		# snapped to a whole multiple. A malformed scale= changes nothing.
		var opened: Vector2 = Vector2(WindowScale.opened_size)
		var whole: Vector2 = (opened / game).floor()
		expected = clampi(int(minf(whole.x, whole.y)), 1, _expected_max())
	else:
		# Fullscreen, the factor is the project window's, if it fits the screen; the
		# title bar is not known yet.
		var width: int = ProjectSettings.get_setting("display/window/size/window_width_override", 0)
		var height: int = ProjectSettings.get_setting("display/window/size/window_height_override", 0)
		var project_fit: Vector2 = (Vector2(width, height) / game).floor()
		var screen_fit: Vector2 = (Vector2(usable.size) / game).floor()
		expected = mini(maxi(1, int(minf(project_fit.x, project_fit.y))), int(minf(screen_fit.x, screen_fit.y)))
	var label: String = "scale=%s" % asked if !asked.is_empty() else "the start"
	_check("%s gives x%d" % [label, expected], WindowScale.factor == expected, "factor x%d" % WindowScale.factor)
	if !windowed:
		return
	_check(
		"%s opens a window of exactly x%d" % [label, expected],
		_shown_size() == WindowScale.game_size() * expected,
		"window %s" % _shown()
	)
	_check(
		"the starting window, title bar included, lies on its screen",
		usable.encloses(_frame_rect()),
		"frame %s, screen %s" % [_frame_rect(), usable]
	)


# The largest factor whose window and the frame the window manager draws around it fit
# the screen, from the engine's own frame. Needs a window, not fullscreen.
func _expected_max() -> int:
	var window: Window = get_window()
	var decorations: Vector2i = window.get_size_with_decorations() - window.size
	var usable: Vector2i = DisplayServer.screen_get_usable_rect(window.current_screen).size
	var fit: Vector2 = (Vector2(usable - decorations) / Vector2(WindowScale.game_size())).floor()
	return maxi(1, int(minf(fit.x, fit.y)))


func _check_factor(factor: int) -> void:
	var label: String = "x%d" % factor
	var applied: int = WindowScale.set_factor(factor)
	_check("%s is applied, not clamped" % label, applied == factor, "applied x%d" % applied)
	var window: Window = get_window()
	var expected: Vector2i = WindowScale.game_size() * factor
	await _wait_until_shown(expected)

	_check("%s window is windowed, not fullscreen" % label, window.mode == Window.MODE_WINDOWED, str(window.mode))
	_check("%s window is %s" % [label, expected], _shown_size() == expected, "got %s" % _shown())
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	_check(
		"%s window, title bar included, lies on its screen" % label,
		usable.encloses(_frame_rect()),
		"frame %s, screen %s" % [_frame_rect(), usable]
	)
	# Rounding puts the centre at most a pixel off.
	var off_centre: Vector2i = (_frame_rect().get_center() - usable.get_center()).abs()
	_check(
		"%s window, title bar included, is centred on its screen" % label,
		off_centre.x <= 1 and off_centre.y <= 1,
		"frame %s, screen %s" % [_frame_rect(), usable]
	)
	_check("%s factor reads back from the window" % label, WindowScale.current_factor() == factor)
	var visible: Vector2 = get_viewport().get_visible_rect().size
	_check(
		"%s root viewport stays the game size" % label, visible == Vector2(WindowScale.game_size()), "got %v" % visible
	)

	var image: Image = await _render(Vector2.ZERO)
	_check("%s renders at %s" % [label, expected], image.get_size() == expected, "got %s" % image.get_size())

	await _check_steps(label, factor)
	await _check_mouse(label, factor, expected)


# One distinct picture per screen pixel the shader can slide across: the sub-pixel
# offset still reaches the screen at every factor, and x1 has nothing to slide into.
# Every picture is also an exact integer upscale.
func _check_steps(label: String, factor: int) -> void:
	var probes: int = PROBES_PER_SCREEN_PIXEL * factor
	var previous: PackedByteArray = PackedByteArray()
	var distinct: int = 0
	var uneven: Array[String] = []
	for probe: int in probes:
		var offset: float = (float(probe) + 0.5) / float(probes)
		var image: Image = await _render(Vector2(offset, 0.0))
		var data: PackedByteArray = image.get_data()
		if probe > 0 and data != previous:
			distinct += 1
		previous = data
		# At x1 every run is a multiple of 1, so there is nothing to check.
		if factor > 1 and probe % PROBES_PER_SCREEN_PIXEL == 0 and !_runs_are_square(image, factor):
			uneven.append("%.3f" % offset)
	_check("%s steps/pixel is %d" % [label, factor], distinct == factor, "got %d" % distinct)
	_check("%s every game pixel is %dx%d screen pixels" % [label, factor, factor], uneven.is_empty(), ", ".join(uneven))


func _check_mouse(label: String, factor: int, window_size: Vector2i) -> void:
	var corner: Vector2 = Vector2(window_size) - Vector2.ONE
	for window_pixel: Vector2 in [Vector2.ZERO, Vector2(window_size) * 0.5, corner]:
		var root_position: Vector2 = await _point_at(window_pixel)
		var expected: Vector2 = window_pixel / float(factor)
		_check(
			"%s window %v arrives in game pixels as %v" % [label, window_pixel, expected],
			root_position.is_equal_approx(expected),
			"got %v" % root_position
		)


# - and = step the factor down and up, from the size the window really has.
func _check_keys(max_factor: int) -> void:
	var game: Vector2i = WindowScale.game_size()
	var _start: int = WindowScale.set_factor(1)
	await _wait_until_shown(game)
	await _press(KEY_EQUAL)
	await _wait_until_shown(game * 2)
	_check("= steps x1 up to x2", _shown_size() == game * 2, "window %s" % _shown())
	await _press(KEY_MINUS)
	await _wait_until_shown(game)
	_check("- steps x2 down to x1", _shown_size() == game, "window %s" % _shown())
	await _press(KEY_EQUAL, true)
	await _wait_for(func() -> bool: return false)
	_check("Ctrl+= is left for the game", _shown_size() == game, "window %s" % _shown())
	await _press(KEY_EQUAL, false, true)
	await _wait_until_shown(game * 2)
	_check("+, Shift+=, steps x1 up to x2", _shown_size() == game * 2, "window %s" % _shown())
	await _press(KEY_MINUS)
	await _wait_until_shown(game)
	# A layout with its own + key, German for one: there + is no Shift+=.
	await _press(KEY_PLUS)
	await _wait_until_shown(game * 2)
	_check("+ on its own key steps x1 up to x2", _shown_size() == game * 2, "window %s" % _shown())
	get_tree().paused = true
	await _press(KEY_MINUS)
	await _wait_until_shown(game)
	get_tree().paused = false
	_check("- works while the game is paused", _shown_size() == game, "window %s" % _shown())

	# Something else leaves the window at no whole multiple: a key snaps it back, even
	# - at x1, where there is nothing smaller to step to.
	var window: Window = get_window()
	var decorations: Vector2i = window.get_size_with_decorations() - window.size
	window.size = game + Vector2i(80, 20)
	await _wait_until_framed(game + Vector2i(80, 20), decorations)
	_check(
		"the window manager applies a window of no whole multiple",
		WindowScale.current_factor() == 1 and window.size == game + Vector2i(80, 20),
		"window %s" % _shown()
	)
	await _press(KEY_MINUS)
	await _wait_until_shown(game)
	_check("- at x1 snaps a window of no whole multiple to x1", _shown_size() == game, "window %s" % _shown())

	# Something else makes the window bigger than fits: = leaves it, - brings it back.
	var oversized: Vector2i = game * (max_factor + 1)
	window.size = oversized
	await _wait_until_framed(oversized, decorations)
	_check(
		"the window manager allows an oversized window",
		_shown_size() == oversized and WindowScale.current_factor() == max_factor + 1,
		"window %s" % _shown()
	)
	await _press(KEY_EQUAL)
	await _wait_for(func() -> bool: return false)
	_check("= does not shrink a window bigger than fits", _shown_size() == oversized, "window %s" % _shown())
	await _press(KEY_MINUS)
	await _wait_until_shown(game * max_factor)
	_check(
		"- brings a window bigger than fits back to x%d" % max_factor,
		_shown_size() == game * max_factor,
		"window %s" % _shown()
	)


# Asking for a factor from fullscreen drops back to a window of exactly that size, and
# asking for too much from fullscreen still keeps the title bar on the screen.
func _check_leaves_fullscreen(max_factor: int) -> void:
	var window: Window = get_window()
	var decorations: Vector2i = window.get_size_with_decorations() - window.size
	for asked: int in [2, max_factor + 1]:
		await _go_fullscreen()
		var applied: int = WindowScale.set_factor(asked)
		var expected: Vector2i = WindowScale.game_size() * mini(asked, max_factor)
		await _wait_until_shown(expected)
		# Waits for the title bar too, in case a window manager frames it after the size.
		await _wait_for(func() -> bool: return window.get_size_with_decorations() - window.size == decorations)
		var label: String = "x%d from fullscreen" % asked
		_check("%s is windowed" % label, window.mode == Window.MODE_WINDOWED, str(window.mode))
		_check("%s is %s" % [label, expected], _shown_size() == expected, "got %s, applied x%d" % [_shown(), applied])
		var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
		_check(
			"%s lies on its screen with its title bar" % label,
			usable.encloses(_frame_rect()),
			"frame %s, screen %s" % [_frame_rect(), usable]
		)


# Waits until the window really covers the screen, not just until mode reads back,
# which it does at once.
func _go_fullscreen() -> void:
	var window: Window = get_window()
	window.mode = Window.MODE_FULLSCREEN
	var screen: Vector2i = DisplayServer.screen_get_size(window.current_screen)
	await _wait_for(func() -> bool: return window.size == screen)
	_check(
		"the window went fullscreen first (no window manager running?)",
		window.size == screen,
		"got %s, screen %s" % [_shown(), screen]
	)


# The largest factor still keeps the title bar and borders on the screen.
func _check_largest_fits(max_factor: int) -> void:
	var window: Window = get_window()
	await _wait_until_shown(WindowScale.game_size() * max_factor)
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	_check(
		"x%d, the largest, lies on its screen with its title bar" % max_factor,
		usable.encloses(_frame_rect()),
		"frame %s, screen %s" % [_frame_rect(), usable]
	)


# The title bar is measured only from a window that has finished resizing. The race
# that breaks this does not come up on demand, so the rule is checked on the readings
# measured when it did: with no window manager, Window.size still 320x180 and the
# decorated size already 640x360.
func _check_frame_readings() -> void:
	var mid_resize: bool = WindowScale.is_frame_reading(Vector2i(320, 180), Vector2i(640, 360), Vector2i(640, 360))
	_check("a reading taken mid-resize is not a title bar", !mid_resize)
	var framed: bool = WindowScale.is_frame_reading(Vector2i(640, 360), Vector2i(642, 381), Vector2i(640, 360))
	_check("Openbox's 2x21 frame, once resized, is a title bar", framed)
	var bare: bool = WindowScale.is_frame_reading(Vector2i(640, 360), Vector2i(640, 360), Vector2i(640, 360))
	_check("no window manager reads as no title bar", !bare)
	# Under Openbox, after a resize WindowScale did not ask for.
	var stale: bool = WindowScale.is_frame_reading(Vector2i(320, 180), Vector2i(1922, 1101), Vector2i(320, 180))
	_check("a frame left from a resize nobody asked for is not a title bar", !stale)
	# Small enough for a title bar, but Window.size is not yet the size asked for.
	var early: bool = WindowScale.is_frame_reading(Vector2i(320, 180), Vector2i(342, 201), Vector2i(640, 360))
	_check("a reading before the window has the size asked for is not a title bar", !early)


func _check_clamped(asked: int, expected: int) -> void:
	var applied: int = WindowScale.set_factor(asked)
	_check("x%d is clamped to x%d" % [asked, expected], applied == expected, "applied x%d" % applied)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	var line: String = label
	if !detail.is_empty():
		line = "%s  (%s)" % [label, detail]
	_failures.append(line)


# Presses the key whose label is keycode, so the layout does not matter.
func _press(keycode: Key, ctrl: bool = false, shift: bool = false) -> void:
	for pressed: bool in [true, false]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = keycode
		key.ctrl_pressed = ctrl
		key.shift_pressed = shift
		key.pressed = pressed
		Input.parse_input_event(key)
		await get_tree().process_frame


# The window's size and the size its content is drawn at, as "WxH drawn WxH". The
# integer stretch draws at the largest whole multiple and letterboxes the rest, so the
# two agree only on a window that is a whole multiple of the game.
func _shown() -> String:
	return "%s drawn %s" % [get_window().size, get_viewport().get_texture().get_image().get_size()]


# The window's size when its content is drawn at exactly that size, which only a whole
# multiple of the game is; (-1, -1) otherwise.
func _shown_size() -> Vector2i:
	var window: Vector2i = get_window().size
	return window if get_viewport().get_texture().get_image().get_size() == window else Vector2i(-1, -1)


# Waits until condition is true, or RESIZE_FRAMES frames.
func _wait_for(condition: Callable) -> void:
	for _frame: int in RESIZE_FRAMES:
		var met: bool = condition.call()
		if met:
			return
		await get_tree().process_frame


# Waits until the window manager has applied a size Godot did not choose through
# WindowScale: the window and its frame both read it, three frames running.
func _wait_until_framed(expected: Vector2i, decorations: Vector2i) -> void:
	var window: Window = get_window()
	var steady: int = 0
	for _frame: int in RESIZE_FRAMES:
		var framed: bool = window.size == expected and window.get_size_with_decorations() == expected + decorations
		steady = steady + 1 if framed else 0
		if steady == 3:
			return
		await get_tree().process_frame


func _wait_until_shown(expected: Vector2i) -> void:
	await _wait_for(func() -> bool: return _shown_size() == expected)


# The window manager's frame as the engine reports it, title bar included.
func _frame_rect() -> Rect2i:
	var window: Window = get_window()
	var corner: Vector2i = DisplayServer.window_get_position_with_decorations(window.get_window_id())
	return Rect2i(corner, window.get_size_with_decorations())


func _render(offset: Vector2) -> Image:
	_material.set_shader_parameter(&"cam_offset", offset)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# Injects a motion event at a window pixel and returns the root-viewport position
# the game sees for it.
func _point_at(window_pixel: Vector2) -> Vector2:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = window_pixel
	motion.global_position = window_pixel
	# A sentinel no probe can arrive as, so an event that never arrives cannot pass.
	_event_position = Vector2(-1.0, -1.0)
	Input.parse_input_event(motion)
	await get_tree().process_frame
	return _event_position


# Every run of identical colour along a row or a column is a multiple of the factor,
# except the two runs each line's ends cut off. Columns start below the debug label,
# which is UI at native resolution, not game pixels.
func _runs_are_square(image: Image, factor: int) -> bool:
	var size: Vector2i = image.get_size()
	for row: int in range(int(float(size.y) * 0.55), int(float(size.y) * 0.95), 3 * factor):
		if !_line_is_square(image, factor, Vector2i(0, row), Vector2i.RIGHT, size.x):
			return false
	var top: int = int(float(size.y) * 0.25)
	for column: int in range(0, size.x, 7 * factor):
		if !_line_is_square(image, factor, Vector2i(column, top), Vector2i.DOWN, size.y - top):
			return false
	return true


func _line_is_square(image: Image, factor: int, start: Vector2i, step: Vector2i, length: int) -> bool:
	var run: int = 1
	var run_start: int = 0
	var previous: Color = image.get_pixelv(start)
	for along: int in range(1, length):
		var current: Color = image.get_pixelv(start + step * along)
		if current == previous:
			run += 1
			continue
		if run_start > 0 and run % factor != 0:
			return false
		run = 1
		run_start = along
		previous = current
	return true
