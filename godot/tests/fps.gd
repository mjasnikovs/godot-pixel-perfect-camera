class_name Fps extends Node

# Measures the real frame rate of the running game:
#   godot tests/fps.tscn -- screen=1 vsync=on
# Silent with exit 0 means the game presents at least one frame per physics tick, so
# the 60Hz tick maps 1:1 onto drawn frames. A failure prints the measured rate with
# printerr and exits 1. A mixed-refresh multi-monitor Wayland desktop can throttle an
# unfocused window, which reads as stutter no matter how correct the camera is.

const WARMUP_FRAMES: int = 150
const SAMPLE_SECONDS: float = 2.0
# A frame rate within this fraction of the physics rate counts as keeping up.
const TOLERANCE: float = 0.95

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
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _vsync else DisplayServer.VSYNC_DISABLED)


func _process(delta: float) -> void:
	if _warmup < WARMUP_FRAMES:
		_warmup += 1
		return

	_frames += 1
	_elapsed += delta
	if _elapsed < SAMPLE_SECONDS:
		return

	var fps: float = float(_frames) / _elapsed
	var physics_hz: float = float(Engine.physics_ticks_per_second)
	if fps >= physics_hz * TOLERANCE:
		get_tree().quit(0)
		return
	var refresh: float = DisplayServer.screen_get_refresh_rate(_screen)
	printerr(
		(
			"FAIL  %.1f fps is under the %.0f Hz physics rate (screen %d at %.1f Hz, vsync %s)"
			% [fps, physics_hz, _screen, refresh, "on" if _vsync else "off"]
		)
	)
	get_tree().quit(1)
