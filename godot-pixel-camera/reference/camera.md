# Camera reference

The full camera implementation. Read `../SKILL.md` first for the mechanism and the
project settings; this file is the code.

## The camera script

`scripts/pixel_camera.gd`, whole. The time-effect methods are explained under Time
effects below.

```gdscript
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

@export_category("Nodes")
@export var viewport_container: SubViewportContainer
@export var initial_target: Node2D

@export_category("Settings")
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
	if !target:
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
```

### The loop, line by line

- `_actual_position` is the true float position. It lerps toward the target.
- `weight` is clamped to 1.0. Without the clamp, one long frame at a high
  `camera_speed` overshoots and the camera snaps past the target.
- `shake` is computed but **not** written to `Camera2D.offset`. See Screen shake below.
- `desired_position` is the one and only float position. Everything feeds into it.
- `rounded_position` is the one and only round.
- `offset` is forced to zero every frame. Treat a non-zero value as a bug.
- The shader gets `rounded - desired`, the fraction rounding just threw away.

`camera_speed = 3.0` is the lerp rate. It is `@export_range`, so tune it in the
inspector. Higher is snappier. 2 to 4 is a sensible range.

`_ready` snaps the camera onto the target first, then follows it. No opening swoop.

### `_physics_process`, never `_process`

Almost every example you will find uses `_process`. Do not copy that. It is the most
visible defect in the whole setup, and it looks like a bug in the character, not the
camera.

**The mismatch.** The camera lerps every *rendered* frame. The player moves every
*physics* tick, 60 times a second. A modern monitor is not 60Hz.

Measured on a 143.8Hz screen, walking right at a constant speed, sampling the player's
position relative to the camera every rendered frame:

| Camera updates in | Player's on-screen step per frame |
|---|---|
| `_process` | **-1px on 10 frames**, 0px on 44, +1px on 15 |
| `_physics_process` | 0px on 64 frames, +1px on 5. **Never backwards.** |

Read the first row again. The character steps **backwards** on roughly one frame in
six while walking forwards. The world slides at 144Hz, the player steps at 60Hz, and
the difference goes negative whenever the camera gains on him.

That reads as the character vibrating against a smooth background. It is not a sprite
problem. It is the camera running on the wrong clock.

The fix is one word: `_physics_process`, not `_process`.

Now the camera and everything it follows move on the same tick. The whole image
updates at 60Hz rather than 144Hz, which for pixel art at 320x180 is what you want:
coherent, not fast.

### Whole pixels per physics tick

A smaller win, worth taking.

The followed sprite's own world position is fractional. It gets snapped to the grid
for drawing, so a varying residual adds up to half a pixel of wobble.

Pick a speed that divides evenly into the physics rate and the residual is constant:

```gdscript
# 60 px/s at 60Hz is exactly 1.000 px per tick.
const SPEED: float = 60.0
```

| Speed | Px per tick | Mean fractional residual |
|---|---|---|
| 70.0 | 1.1667 | 0.249 px |
| **60.0** | **1.0000** | **0.000 px** |

Applies to gravity and jump velocity too, if you want it perfect.

---

## Moving the camera elsewhere

### The target swap

```gdscript
func set_target(new_target: Node2D) -> void:
	target = new_target
```

Any `Node2D` works. The camera only reads `target.global_position`. A bare `Marker2D`
is a perfectly good camera target.

### The trigger

`scripts/camera_trigger.gd`:

```gdscript
class_name CameraTrigger extends Node2D

# Walk in, the camera parks on the marker. Walk out, it follows the player again.

@export_category("Nodes")
@export var target: Marker2D
@export var trigger_area: Area2D


func _ready() -> void:
	assert(target, "camera_trigger.gd - @export target is not set in the editor on: " + self.name)
	assert(trigger_area, "camera_trigger.gd - @export trigger_area is not set in the editor on: " + self.name)
	var _error: int = trigger_area.body_entered.connect(
		func(body: Node2D) -> void:
			if !(body is Player) or !Global.camera:
				return
			# Claim the camera, so overlapping triggers cannot release each other's.
			Global.active_camera_trigger = self
			Global.camera.set_target(target)
	)
	_error = trigger_area.body_exited.connect(
		func(body: Node2D) -> void:
			if !(body is Player) or !Global.camera:
				return
			if Global.active_camera_trigger != self:
				return
			Global.active_camera_trigger = null
			Global.camera.set_target(Global.player)
	)
```

The `active_camera_trigger` guard matters. Without it, two overlapping triggers fight:
leaving trigger A resets the camera even though the player is still inside trigger B.
The guard means only the trigger that claimed the camera can release it.

Both reactions are inline lambdas, as godot-code-style wires every signal. `connect()`
returns an `int`, not an `Error`: keep it in a typed `_error: int` throwaway or
`return_value_discarded` fires, and type it `Error` and `int_as_enum_without_cast`
fires instead.

### The trigger scene

`scenes/camera_trigger.tscn`:

```
CameraTrigger (Node2D, script camera_trigger.gd)
├── Marker2D              position (0, -40)   <- where the camera goes
│   └── Gizmo (Sprite2D)                      <- so you can see it in the editor
└── Area2D                collision_layer = 0, collision_mask = 2
    └── CollisionShape2D  RectangleShape2D 120 x 96
```

`collision_layer = 0` — the trigger is invisible to everything else.
`collision_mask = 2` — it only sees the player's layer.

Put the marker offset inside the trigger scene, not on each instance. Then placing a
trigger is one drag, with no editable-instance overrides.

Instances live under a plain `Node2D` named `Cameras`. Set `visible = false` on an
instance to hide the gizmo at runtime.

The transition needs no code. The existing lerp glides the camera over.

---

## Screen shake

```gdscript
func apply_shake(strength: float = 3.0) -> void:
	shake_strength = maxf(shake_strength, strength)


func _get_noise_offset(delta: float, strength: float) -> Vector2:
	_noise_time += delta * NOISE_SPEED
	# Sample two distant columns so the axes are uncorrelated.
	return Vector2(_noise.get_noise_2d(1.0, _noise_time) * strength, _noise.get_noise_2d(100.0, _noise_time) * strength)
```

`FastNoiseLite`, not `randf_range`. X samples the noise field at `x = 1`, Y at
`x = 100`. Far apart, so the two axes are uncorrelated. Noise gives a rolling rumble.
Pure random gives a buzz.

`maxf` in `apply_shake` means a small shake cannot cancel a big one already running.

Decay is `lerpf(shake_strength, 0.0, SHAKE_DECAY * delta)` with `SHAKE_DECAY = 15.0`.

### Shake must go through the rounding

The usual advice is to write shake to `Camera2D.offset` and leave `global_position`
alone, on the grounds that this "keeps it clear of the pixel snapping".

**That is backwards, and it is a bug.**

`Camera2D.offset` is added to the camera transform *after* your script has rounded
`global_position`. It bypasses the entire technique.

So during a shake the canvas is translated by a fractional amount the shader knows
nothing about — the shader is still applying the offset for the *unshaken* position.
Meanwhile every sprite snaps to the pixel grid independently, because
`snap_2d_vertices_to_pixel` rounds each one on its own.

The result is a shake where sprites shift against each other by a pixel instead of the
picture moving as one. It reads as mushy or torn, exactly when you most want impact.

Fold the shake into the position **before** the single round:

```gdscript
	var shake: Vector2 = Vector2.ZERO
	if shake_strength > 0.0:
		shake_strength = lerpf(shake_strength, 0.0, SHAKE_DECAY * delta)
		shake = _get_noise_offset(delta, shake_strength)

	var desired_position: Vector2 = _actual_position + shake
	var rounded_position: Vector2 = desired_position.round()

	offset = Vector2.ZERO
	global_position = rounded_position
	cam_offset = rounded_position - desired_position
	_shader_material.set_shader_parameter(&"cam_offset", cam_offset)
```

Now the shake is sub-pixel smooth *and* pixel perfect, like everything else.
`Camera2D.offset` stays at zero forever. The harness in `verify.md` asserts that on
every single frame.

---

## Time effects

The camera is a convenient owner for hit-stop and slow motion.

```gdscript
func apply_freeze_frame(time_scale: float = 0.1, duration: float = 0.075) -> void:
	Engine.time_scale = time_scale
	# ignore_time_scale = true, or the timer would be slowed down too.
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
```

The timer's fourth argument is `ignore_time_scale = true`. Without it the timer itself
is slowed and never fires on schedule.

```gdscript
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
```

The old tween is killed before a new one starts. Call slow then fast in quick
succession and you never get two tweens fighting over `Engine.time_scale`.

`tween_property` returns a `PropertyTweener`. Capture it into an underscore-prefixed
variable or `return_value_discarded` fires.

Callers `await` the returned tween:

```gdscript
	await Global.camera.slow_down_time().finished
	await Global.camera.speed_up_time().finished
```

**Note:** `Engine.time_scale` scales `delta`, so a lower time scale means the camera
lerps more slowly too. That is usually what you want.

---

## The autoload

`scripts/global.gd`:

```gdscript
extends Node

# Nodes register themselves here, so no script holds a node path and renaming a
# node cannot break anything.

var camera: PixelCamera = null
var player: Player = null
var active_camera_trigger: CameraTrigger = null


func register_camera(new_camera: PixelCamera) -> void:
	camera = new_camera


func register_player(new_player: Player) -> void:
	player = new_player
```

Nodes register themselves in `_ready`:

```gdscript
	Global.register_camera(self)  # in PixelCamera._ready
	Global.register_player(self)  # in Player._ready
```

### Why not the other way

The alternative is an autoload that looks each node up by its path in the tree.
godot-code-style bans that: rename any node on the path and the game breaks at
startup. Registration also removes the requirement that the root node be named
`SubViewportContainer`.

---

## UI lives outside the viewport

`CanvasLayer` is a child of `SubViewportContainer`, **not** of `SubViewport`.

So health bars and dialogue render at native window resolution, not at 320x180. Crisp
text over a chunky pixel world.

The shader does not touch the UI. It only moves the game image.

With `canvas_items` stretch the layer's coordinates are in the 320x180 logical space,
so use small numbers:

```
offset_left = 4.0
offset_top = 3.0
theme_override_font_sizes/font_size = 8
```

That 8 renders at 32 physical pixels. Crisp, not chunky.

### World-anchored UI

Anything on the CanvasLayer that must track a world position has to convert by hand.
Floating damage numbers, for example, end up doing this:

```gdscript
	number.global_position = (
		Global.viewport.size
		+ (Global.camera.global_position - target.global_position + target.collision_shape_size) * -2
		+ Vector2(randf_range(-10, 10), randf_range(-10, 10))
	)
```

The `* -2` is that project's container `scale = (2, 2)`, inverted. With container scale
1 the factor is different. This is fiddly; consider putting world-anchored UI inside
the SubViewport instead and accepting chunky text.

### Font settings for pixel fonts

If you use a pixel font anywhere, in `project.godot`:

```ini
[gui]
theme/custom_font="uid://..."
theme/default_font_antialiasing=0
```

`default_font_antialiasing=0` turns off glyph smoothing.
