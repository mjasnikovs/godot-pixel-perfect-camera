extends Node

# Sizes the window to a whole multiple of the game, x2, x3, x4 and up to whatever fits
# the screen, in windowed mode.
#   godot -- scale=2     start at 2x
#   - and =              step down and up while playing
#
# The window is not resizable, so a tiling window manager cannot pick a size that
# collapses the integer factor. This is the one place that changes it. Nothing else
# has to know: canvas_items stretch with integer scaling picks the new size up on its
# own, the root viewport stays 320x180, and event.position stays in game pixels at
# every factor.

# How long to wait for the window manager's first title bar, in frames.
const SETTLE_FRAMES: int = 60

# The factor the window was last sized to.
var factor: int = 1
# The size the window opened at, before anything here resized it: the project's, or
# --resolution's.
var opened_size: Vector2i = Vector2i.ZERO
var _game_size: Vector2i = Vector2i.ZERO
# Title bar and borders, and where the client area sits inside them, last measured
# while windowed. Fullscreen has none, and a window reads none in the frame it leaves
# fullscreen.
var _decorations: Vector2i = Vector2i.ZERO
var _client_offset: Vector2i = Vector2i.ZERO
# Frames left to wait for a first measurement of the title bar. A window sized before
# its title bar was measured, at startup or straight out of fullscreen, is fitted
# again once it is.
var _settle_frames: int = 0
# Where set_factor last put the window, to tell a window nobody has moved since.
var _placed_position: Vector2i = Vector2i.ZERO
var _placed: bool = false
# The size set_factor last asked for. Until Window.size reads it back, the window is
# mid-resize and its decorated size belongs to a different frame.
var _requested_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	opened_size = get_window().size
	var width: int = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var height: int = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	_game_size = Vector2i(width, height)
	# Release builds drop asserts, so a project without a base size switches this off.
	if _game_size.x <= 0 or _game_size.y <= 0:
		push_error("window_scale.gd - the project has no base viewport size")
	# Headless has no window to size.
	if _game_size.x <= 0 or _game_size.y <= 0 or DisplayServer.get_name() == "headless":
		_settle(0)
		set_process_unhandled_input(false)
		return
	# Keeps settling and the keys working while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A window that starts fullscreen, or maximized, stays so unless scale= asks for a window,
	# and its factor is the one the project's window would have, not the screen's.
	var windowed: bool = get_window().mode == Window.MODE_WINDOWED
	var fit: int = max_factor()
	factor = current_factor() if windowed else mini(_project_factor(), fit)
	var asked: String = _scale_argument()
	if asked.is_valid_int():
		var _applied: int = set_factor(asked.to_int())
	elif windowed and (factor > fit or get_window().size != _game_size * factor):
		# The 1280x720 the project opens at can be bigger than a small screen, and a
		# window manager or --resolution can open it at a size that is no multiple.
		var _fitted: int = set_factor(mini(factor, fit))
	# Nothing measured yet means the fit above left the title bar out.
	_settle(SETTLE_FRAMES if _decorations == Vector2i.ZERO else 0)


# Runs only while settling. Once the title bar is measured, fits and centres the window
# again if its frame does not lie on the screen or nobody has moved it since; a window
# the player or the window manager has moved, and that fits, stays where it is.
func _process(_delta: float) -> void:
	_settle(_settle_frames - 1)
	var window: Window = get_window()
	if window.mode != Window.MODE_WINDOWED or _measure_decorations() == Vector2i.ZERO:
		return
	_settle(0)
	var frame: Rect2i = Rect2i(window.position - _client_offset, window.size + _decorations)
	var on_screen: bool = DisplayServer.screen_get_usable_rect(window.current_screen).encloses(frame)
	if !on_screen or (_placed and window.position == _placed_position):
		var _refitted: int = set_factor(factor)


func _unhandled_input(event: InputEvent) -> void:
	# Exact, so Ctrl+= and the like stay free for the game.
	if event.is_action_pressed(&"window_scale_up", false, true):
		_step(1)
	elif event.is_action_pressed(&"window_scale_down", false, true):
		_step(-1)
	else:
		return
	get_viewport().set_input_as_handled()


# Leaves fullscreen, sizes the window to the game size times new_factor and centres it
# on its screen. Returns the factor applied, clamped to 1..max_factor().
func set_factor(new_factor: int) -> int:
	var window: Window = get_window()
	# Read before leaving fullscreen, while the cache still holds the windowed frame.
	var decorations: Vector2i = _measure_decorations()
	if decorations == Vector2i.ZERO:
		_settle(SETTLE_FRAMES)
	window.mode = Window.MODE_WINDOWED
	factor = clampi(new_factor, 1, _fit(decorations))
	var size: Vector2i = game_size() * factor
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	window.size = size
	_requested_size = size
	# window.position is the client area's. Centre the whole frame, title bar included,
	# and if even x1 is too big for the screen, keep the title bar reachable.
	var frame_corner: Vector2i = Vector2i((Vector2(usable.size - size - decorations) * 0.5).floor())
	window.position = (usable.position + frame_corner).max(usable.position) + _client_offset
	_placed_position = window.position
	_placed = true
	return factor


# The largest factor whose window, title bar and borders included, fits the usable
# area of the window's screen.
func max_factor() -> int:
	return _fit(_measure_decorations())


# The factor the window's current size gives the integer stretch.
func current_factor() -> int:
	return maxi(1, _whole_factor(Vector2(get_window().size)))


func game_size() -> Vector2i:
	return _game_size


# True once the window has been fitted with its title bar measured, or the window
# manager had SETTLE_FRAMES to show one and did not.
func is_settled() -> bool:
	return _settle_frames <= 0


# Returns once is_settled(), at most SETTLE_FRAMES frames later.
func wait_until_settled() -> void:
	while !is_settled():
		await get_tree().process_frame


# Steps from the window's real size, not the cached factor, so a window something
# else resized steps from where it is. Does nothing at either end of a window, rather
# than re-centring one the player has moved. From fullscreen it always comes back to a
# window.
func _step(direction: int) -> void:
	var windowed: bool = get_window().mode == Window.MODE_WINDOWED
	var from: int = current_factor() if windowed else factor
	var target: int = clampi(from + direction, 1, max_factor())
	# Up never shrinks a window already bigger than fits; down brings it back on screen.
	if direction > 0 and target < from:
		return
	# A window something else left at no whole multiple snaps to one, even at an end.
	var exact: bool = get_window().size == _game_size * from
	if target != from or !windowed or !exact:
		var _applied: int = set_factor(target)


# Whether decorated - size is the window manager's frame and not a resize in flight.
# Mid-resize the two sizes can come from different frames. Measured with no window
# manager: Window.size still 320x180 against a decorated 640x360. Measured under
# Openbox, after a resize something else made: 320x180 against 1922x1101. A title bar
# and borders are never as big as the game at x1, so a reading that big is a stale one.
func is_frame_reading(size: Vector2i, decorated: Vector2i, requested: Vector2i) -> bool:
	var measured: Vector2i = decorated - size
	var resized: bool = requested == Vector2i.ZERO or size == requested
	var small: bool = measured.x < _game_size.x and measured.y < _game_size.y
	return resized and small and measured.x >= 0 and measured.y >= 0 and measured != Vector2i.ZERO


# Title bar and borders, which the window manager adds outside Window.size, as the
# engine reports them. Zero without a window manager.
func _measure_decorations() -> Vector2i:
	var window: Window = get_window()
	var decorated: Vector2i = window.get_size_with_decorations()
	if window.mode == Window.MODE_WINDOWED and is_frame_reading(window.size, decorated, _requested_size):
		_decorations = decorated - window.size
		_client_offset = window.position - DisplayServer.window_get_position_with_decorations(window.get_window_id())
	return _decorations


# The factor of the window size in project.godot; 1 without an override.
func _project_factor() -> int:
	var width: int = ProjectSettings.get_setting("display/window/size/window_width_override", 0)
	var height: int = ProjectSettings.get_setting("display/window/size/window_height_override", 0)
	return maxi(1, _whole_factor(Vector2(width, height)))


# The N of a scale=N user argument, or "" without one. A typo such as scale=x2 is not
# a whole number, so it counts as no argument rather than as 0.
func _scale_argument() -> String:
	for argument: String in OS.get_cmdline_user_args():
		var value: String = argument.trim_prefix("scale=")
		if argument.begins_with("scale=") and value.is_valid_int():
			return value
	return ""


func _settle(frames: int) -> void:
	_settle_frames = maxi(frames, 0)
	set_process(_settle_frames > 0)


func _fit(decorations: Vector2i) -> int:
	var usable: Vector2i = DisplayServer.screen_get_usable_rect(get_window().current_screen).size
	return maxi(1, _whole_factor(Vector2(usable - decorations)))


func _whole_factor(area: Vector2) -> int:
	var ratio: Vector2 = (area / Vector2(game_size())).floor()
	return int(minf(ratio.x, ratio.y))
