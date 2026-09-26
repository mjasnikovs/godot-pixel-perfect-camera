class_name Motion extends Node

# Walks the player right and checks how it lands on the pixel grid. Silent with exit
# 0 means the camera is on the physics clock and the speed is a whole number of pixels
# per tick; a failure is printed with printerr and exits 1.

const SAMPLE_FRAMES: int = 90
const EPSILON: float = 0.001

var _frame: int = 0
var _last_screen: Vector2 = Vector2.ZERO
var _steps: Dictionary[int, int] = {}
var _residuals: Array[float] = []


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 1:
		Input.action_press(&"move_right")
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

	Input.action_release(&"move_right")
	get_tree().quit(_report_failures())


# Returns the exit code: 0 when every bound holds.
func _report_failures() -> int:
	var failures: Array[String] = []
	var backwards: int = 0
	for step: int in _steps:
		if step < 0:
			backwards += _steps[step]
	if backwards > 0:
		failures.append("the player stepped backwards on %d frames while walking forwards" % backwards)

	var per_tick: float = Player.SPEED / float(Engine.physics_ticks_per_second)
	if absf(per_tick - roundf(per_tick)) > EPSILON:
		failures.append("the player moves %.4f px per physics tick, not a whole number" % per_tick)

	var sum: float = 0.0
	for value: float in _residuals:
		sum += value
	var mean_residual: float = sum / float(_residuals.size())
	if mean_residual > EPSILON:
		failures.append("the player's world position is fractional on average by %.3f px" % mean_residual)

	for failure: String in failures:
		printerr("FAIL  %s" % failure)
	return 0 if failures.is_empty() else 1
