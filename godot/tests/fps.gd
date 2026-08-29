extends Node

## Measures the real frame rate of the running game.
##
##     godot tests/fps.tscn -- screen=1 vsync=off
##
## A mixed-refresh multi-monitor Wayland desktop can pace a window badly, which
## reads as stutter no matter how correct the camera is.

const WARMUP_FRAMES: int = 150
const SAMPLE_SECONDS: float = 2.0

var _frames: int = 0
var _warmup: int = 0
var _elapsed: float = 0.0
var _screen: int = 0
var _vsync: bool = true


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("screen="):
			_screen = argument.trim_prefix("screen=").to_int()
		elif argument.begins_with("vsync="):
			_vsync = argument.trim_prefix("vsync=") == "on"

	var window: Window = get_window()
	if _screen < DisplayServer.get_screen_count():
		window.current_screen = _screen
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if _vsync else DisplayServer.VSYNC_DISABLED
	)


func _process(delta: float) -> void:
	if _warmup < WARMUP_FRAMES:
		_warmup += 1
		return

	_frames += 1
	_elapsed += delta
	if _elapsed < SAMPLE_SECONDS:
		return

	print("  screen %d (%5.1f Hz)  vsync %-3s -> %6.1f fps" % [
		_screen,
		DisplayServer.screen_get_refresh_rate(_screen),
		"on" if _vsync else "off",
		float(_frames) / _elapsed
	])
	get_tree().quit(0)
