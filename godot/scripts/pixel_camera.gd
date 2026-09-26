class_name PixelCamera extends Camera2D

# Follows a target smoothly while staying snapped to whole pixels. The camera's own
# position is always rounded; the fraction rounding threw away goes to the container's
# shader, which slides the finished image by less than one pixel.
#
# It runs in _physics_process, on the same tick as everything it follows. In _process
# it would update at the display rate while sprites move at the physics rate, and on a
# 144Hz screen the followed target steps backwards on roughly 1 frame in 6. Measured.
#
# Physics interpolation stays off: it would put the camera back on fractional
# positions, which is exactly what the shader already handles.

const SHAKE_DECAY: float = 15.0
const NOISE_SPEED: float = 10.0

@export var viewport_container: SubViewportContainer
@export var initial_target: Node2D
@export_range(0.5, 20.0, 0.1) var camera_speed: float = 3.0

var target: Node2D = null
# The shader's sub-pixel shift this frame, -0.5 to +0.5. Mouse-to-world conversions
# subtract it.
var cam_offset: Vector2 = Vector2.ZERO
var shake_strength: float = 0.0
var _actual_position: Vector2 = Vector2.ZERO
var _noise_time: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()
var _shader_material: ShaderMaterial = null
var _time_tween: Tween = null


func _ready() -> void:
	assert(viewport_container, "pixel_camera.gd - @export viewport_container is not set in the editor on: " + self.name)
	assert(initial_target, "pixel_camera.gd - @export initial_target is not set in the editor on: " + self.name)
	var container_material: Material = viewport_container.material
	assert(
		container_material is ShaderMaterial,
		"pixel_camera.gd - the container material is not a ShaderMaterial on: " + self.name
	)
	_shader_material = container_material as ShaderMaterial

	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	set_target(initial_target)
	_actual_position = initial_target.global_position
	global_position = _actual_position.round()
	Global.register_camera(self)


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

	# Shake included, everything lands in one float position rounded once.
	# Camera2D.offset is applied after this rounding, so it stays at zero.
	var desired_position: Vector2 = _actual_position + shake
	var rounded_position: Vector2 = desired_position.round()

	offset = Vector2.ZERO
	global_position = rounded_position
	cam_offset = rounded_position - desired_position
	_shader_material.set_shader_parameter(&"cam_offset", cam_offset)


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
		tween.tween_property(Engine, "time_scale", to_scale, duration).set_trans(Tween.TRANS_LINEAR).from_current()
	)
	_time_tween = tween
	return tween


func _get_noise_offset(delta: float, strength: float) -> Vector2:
	_noise_time += delta * NOISE_SPEED
	# Sample two distant columns so the axes are uncorrelated.
	return Vector2(_noise.get_noise_2d(1.0, _noise_time) * strength, _noise.get_noise_2d(100.0, _noise_time) * strength)
