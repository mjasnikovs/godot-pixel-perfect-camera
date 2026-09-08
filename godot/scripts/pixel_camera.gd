class_name PixelCamera extends Camera2D

## Follows a target smoothly while staying snapped to whole pixels.
##
## The camera's own position is always rounded. The leftover fraction is pushed
## into the SubViewportContainer's shader, which slides the finished image by
## less than one pixel. Motion looks smooth, sprites stay crisp.
##
## Runs in _physics_process, on the same tick as everything it follows.
##
## Do NOT move this to _process. The camera would then update at the display
## refresh rate while sprites still move at the physics rate. On a 144Hz screen
## the world would slide smoothly while the player stepped at 60Hz, and the
## player would visibly jitter against it. Measured: that mismatch makes the
## followed target step backwards on roughly 1 frame in 6.
##
## Do NOT enable Project Settings > Physics > Physics Interpolation either. It
## would put the camera back on fractional positions, which is the exact thing
## the shader already handles.

const SHAKE_DECAY: float = 15.0
const NOISE_SPEED: float = 10.0

## SubViewportContainer that owns the sub-pixel shader. Assigned in the scene.
@export var viewport_container: SubViewportContainer = null

## Node the camera follows on startup. Usually the player.
@export var initial_target: Node2D = null

## Lerp rate toward the target. Higher is snappier.
@export_range(0.5, 20.0, 0.1) var camera_speed: float = 3.0

var target: Node2D = null

## Sub-pixel shift the shader is applying this frame, -0.5 to +0.5.
## Mouse-to-world conversions must subtract it. See "Mouse input" in the skill.
var cam_offset: Vector2 = Vector2.ZERO

var _actual_position: Vector2 = Vector2.ZERO
## Current shake amount in game pixels. Decays to zero on its own.
var shake_strength: float = 0.0
var _noise_time: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()
var _shader_material: ShaderMaterial = null
var _time_tween: Tween = null


func _ready() -> void:
	assert(viewport_container != null, "PixelCamera: 'viewport_container' is not assigned.")
	assert(initial_target != null, "PixelCamera: 'initial_target' is not assigned.")

	var material: Material = viewport_container.material
	assert(material is ShaderMaterial, "PixelCamera: container material must be a ShaderMaterial.")
	_shader_material = material as ShaderMaterial

	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	set_target(initial_target)
	_actual_position = initial_target.global_position
	global_position = _actual_position.round()

	Global.register_camera(self)


func set_target(new_target: Node2D) -> void:
	target = new_target


func apply_shake(strength: float = 3.0) -> void:
	shake_strength = maxf(shake_strength, strength)


func apply_freeze_frame(time_scale: float = 0.1, duration: float = 0.075) -> void:
	Engine.time_scale = time_scale
	# ignore_time_scale = true, or the timer would be slowed down too.
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func slow_down_time(to_scale: float = 0.2, duration: float = 0.3) -> Tween:
	return _tween_time_scale(to_scale, duration)


func speed_up_time(duration: float = 0.3) -> Tween:
	return _tween_time_scale(1.0, duration)


func _tween_time_scale(to_scale: float, duration: float) -> Tween:
	if is_instance_valid(_time_tween):
		_time_tween.kill()
	var tween: Tween = create_tween()
	var _property_tweener: PropertyTweener = (
		tween
		.tween_property(Engine, "time_scale", to_scale, duration)
		.set_trans(Tween.TRANS_LINEAR)
		.from_current()
	)
	_time_tween = tween
	return tween


func _get_noise_offset(delta: float, strength: float) -> Vector2:
	_noise_time += delta * NOISE_SPEED
	# Sample two distant columns so the axes are uncorrelated.
	return Vector2(
		_noise.get_noise_2d(1.0, _noise_time) * strength,
		_noise.get_noise_2d(100.0, _noise_time) * strength
	)


func _physics_process(delta: float) -> void:
	if target == null:
		return

	# Clamped, so a single long frame cannot overshoot the target.
	var weight: float = minf(camera_speed * delta, 1.0)
	_actual_position = _actual_position.lerp(target.global_position, weight)

	var shake: Vector2 = Vector2.ZERO
	if shake_strength > 0.0:
		shake_strength = lerpf(shake_strength, 0.0, SHAKE_DECAY * delta)
		shake = _get_noise_offset(delta, shake_strength)

	# Everything the camera does, shake included, lands in ONE float position
	# that gets rounded ONCE. Camera2D.offset is deliberately left at zero:
	# it bypasses this rounding, so shake written there would move the camera
	# by a fraction the shader does not know about, and every sprite would snap
	# to the grid on its own. That is what makes shake look mushy.
	var desired_position: Vector2 = _actual_position + shake
	var rounded_position: Vector2 = desired_position.round()

	offset = Vector2.ZERO
	global_position = rounded_position
	cam_offset = rounded_position - desired_position
	_shader_material.set_shader_parameter("cam_offset", cam_offset)
