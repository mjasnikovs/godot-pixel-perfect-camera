class_name Player extends CharacterBody2D

const SPEED: float = 60.0
const JUMP_VELOCITY: float = -180.0
const GRAVITY: float = 500.0

@export var sprite: Sprite2D = null


func _ready() -> void:
	assert(sprite != null, "Player: 'sprite' is not assigned.")
	Global.register_player(self)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed("shake") and Global.camera != null:
		Global.camera.apply_shake(4.0)

	var direction: float = Input.get_axis("move_left", "move_right")
	if is_zero_approx(direction):
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
	else:
		velocity.x = direction * SPEED
		sprite.flip_h = direction < 0.0

	var _collided: bool = move_and_slide()
