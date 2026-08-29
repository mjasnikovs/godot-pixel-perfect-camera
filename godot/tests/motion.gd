extends Node

## Logs how the player actually lands on the pixel grid while walking.

const SAMPLE_FRAMES: int = 90

var _frame: int = 0
var _last_screen: Vector2 = Vector2.ZERO
var _steps: Dictionary[int, int] = {}
var _residuals: Array[float] = []


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 1:
		Input.action_press("move_right")
		return
	if _frame < 20:
		return

	var player: Player = Global.player
	var camera: PixelCamera = Global.camera
	if player == null or camera == null:
		return

	# Where the player sits inside the rendered frame, in game pixels.
	var screen: Vector2 = player.global_position - camera.global_position
	_residuals.append(absf(player.global_position.x - roundf(player.global_position.x)))

	if _frame > 21:
		var step: int = int(roundf(screen.x - _last_screen.x))
		_steps[step] = _steps.get(step, 0) + 1
	_last_screen = screen

	if _frame < SAMPLE_FRAMES:
		return

	Input.action_release("move_right")
	var keys: Array[int] = _steps.keys()
	keys.sort()
	print("\nplayer speed: %.1f px/s at 60fps = %.3f game px per frame"
		% [Player.SPEED, Player.SPEED / 60.0])
	print("\non-screen step sizes (player relative to camera, in game pixels):")
	for key: int in keys:
		print("  %+d px : %d frames" % [key, _steps[key]])

	var sum: float = 0.0
	for value: float in _residuals:
		sum += value
	print("\nplayer world position is fractional on average by %.3f px"
		% (sum / float(_residuals.size())))

	var physics_hz: int = Engine.physics_ticks_per_second
	print("\nphysics ticks/sec : %d" % physics_hz)
	print("screen refresh Hz : %.1f" % DisplayServer.screen_get_refresh_rate())
	print("px per physics tick: %.4f  (whole numbers do not wobble)"
		% (Player.SPEED / float(physics_hz)))
	get_tree().quit(0)
