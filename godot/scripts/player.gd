class_name Player extends CharacterBody2D

# 60 px/s at 60 physics ticks is exactly 1 px per tick, so the sprite's rounding
# residual stays constant instead of wobbling.
const SPEED: float = 60.0
const JUMP_VELOCITY: float = -180.0
const GRAVITY: float = 500.0

@export_category("Nodes")
@export var sprite: Sprite2D


func _ready() -> void:
	assert(sprite, "player.gd - @export sprite is not set in the editor on: " + self.name)
	Global.register_player(self)


func _physics_process(delta: float) -> void:
	if !is_on_floor():
		velocity.y += GRAVITY * delta

	if Input.is_action_just_pressed(&"jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed(&"shake") and Global.camera:
		Global.camera.apply_shake(4.0)

	var direction: float = Input.get_axis(&"move_left", &"move_right")
	if is_zero_approx(direction):
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
	else:
		velocity.x = direction * SPEED
		sprite.flip_h = direction < 0.0

	var _collided: bool = move_and_slide()
