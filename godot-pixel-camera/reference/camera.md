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

var c_target: Node2D = null
# The shader's sub-pixel shift this physics tick, -0.5 to +0.5; mouse-to-world conversions subtract it.
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
	if !c_target:
		return

	# Clamped, so a single long frame cannot overshoot the target.
	var weight: float = minf(camera_speed * delta, 1.0)
	_actual_position = _actual_position.lerp(c_target.global_position, weight)

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
	c_target = new_target


func apply_shake(strength: float = 3.0) -> void:
	shake_strength = maxf(shake_strength, strength)


func apply_freeze_frame(time_scale: float = 0.1, duration: float = 0.075) -> void:
	Engine.time_scale = time_scale
	var restore: Timer = Timer.new()
	restore.autostart = true
	restore.one_shot = true
	restore.wait_time = duration
	# Otherwise the time scale this sets slows the timer too, and at 0 it never fires.
	restore.ignore_time_scale = true
	var _error: int = restore.timeout.connect(
		func() -> void:
			Engine.time_scale = 1.0
			restore.queue_free()
	)
	add_child(restore)


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
- `offset` is forced to zero every physics tick. Treat a non-zero value as a bug.
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
	c_target = new_target
```

Any `Node2D` works. The camera only reads `c_target.global_position`. A bare `Marker2D`
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
	var restore: Timer = Timer.new()
	restore.autostart = true
	restore.one_shot = true
	restore.wait_time = duration
	# Otherwise the time scale this sets slows the timer too, and at 0 it never fires.
	restore.ignore_time_scale = true
	var _error: int = restore.timeout.connect(
		func() -> void:
			Engine.time_scale = 1.0
			restore.queue_free()
	)
	add_child(restore)
```

The restore runs on a local `Timer`, not an `await`. With `missing_await` at 2 an
awaiting method makes every caller await it, and a hit that awaited the freeze would
sit out the whole freeze before its next line. The call returns at once and the timer
restores the time scale on its own, then frees itself.

`ignore_time_scale = true` is what lets it fire. Without it the timer runs on the very
time scale it is waiting to restore, so it is slowed, and at a scale of 0 it never fires.

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

## Window scale

`scripts/window_scale.gd`, the second autoload, registered after `Global`:

```ini
[autoload]

Global="*res://scripts/global.gd"
WindowScale="*res://scripts/window_scale.gd"
```

```gdscript
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
# while windowed. Fullscreen has none, and a window usually reads none in the frame it
# leaves fullscreen.
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
```

Two input actions in `project.godot`, abbreviated here; bind them in the editor's
Input Map:

```ini
[input]

window_scale_down={
"deadzone": 0.2,
"events": [Object(InputEventKey,...,"keycode":45,...)                 ; -
, Object(InputEventKey,...,"physical_keycode":4194435,...)            ; keypad -
]
}
window_scale_up={
"deadzone": 0.2,
"events": [Object(InputEventKey,...,"keycode":61,...)                 ; =
, Object(InputEventKey,...,"shift_pressed":true,...,"keycode":61,...) ; + as Shift+= (US)
, Object(InputEventKey,...,"keycode":43,...)                          ; + on its own key (German)
, Object(InputEventKey,...,"physical_keycode":4194437,...)            ; keypad +
]
}
```

The main-keyboard keys are bound by `keycode`, not by `physical_keycode`: on a German
keyboard the keys printed `-` and `+` sit where a US keyboard has `/` and `]`, and
they work. `keycode` is the label only when the label is a Godot key constant; for any
other label Godot falls back to the US key in that position. So on German `ß`, where a
US keyboard has `-`, also shrinks the window. Measured with `setxkbmap de`. The keypad
keys are the same everywhere.

`godot -- scale=2` starts at 640x360, in one resize: a `scale=` replaces the
shrink-to-fit rather than following it. `-` and `=` step down and up while playing.

### Why from code

`window/size/resizable=false` stays. It stops the user and a tiling window manager
from resizing the window (bug 5); it does not stop `Window.size`. So the factor
changes only here, and only to a whole multiple.

`set_factor` sets `mode` to windowed before the size, so asking for a factor from
fullscreen drops back to a window of exactly that size. `tests/scale.tscn` checks it.

`max_factor` clamps to the screen's usable rect less the title bar and borders, so `=`
stops at the largest factor that fits and the window never runs off the screen. On a
1920x1080 screen that is x6 with no window manager, and x5 under Openbox, whose 21px
title bar does not fit above 1080 rows of game. Leave the decorations out and x6 puts
the title bar at y = -20.

The frame is the engine's, not a guess: its size from `get_size_with_decorations()`,
and where the client area sits in it from
`DisplayServer.window_get_position_with_decorations()`. Under Openbox that is 2 by 21
pixels, with the client 1 in and 20 down.

The decorations are cached from the last windowed measurement. Fullscreen has none,
and right after `mode` goes back to windowed `get_size_with_decorations()` usually
still equals `Window.size`: measured under Openbox, 52 of 64 times; the other 12
already had the 2x21 frame. A zero reading is never taken as a title bar, so
`set_factor` gets the cached one there either way; it reads the cache before it
touches `mode` so the rule does not rest on that.

A window sized before anything was measured, at startup or straight out of a fullscreen
start, is fitted without a title bar. So for up to `SETTLE_FRAMES` the autoload watches
for the first measurement and, once it has one, fits and centres the window again if its
frame does not lie on the screen, or if nothing has moved it since `set_factor` placed
it. A window that fits and that the window manager or the player has moved stays where
it is. The watch is the only time `_process` runs, and harnesses
`await WindowScale.wait_until_settled()` before they measure anything. Headless, there
is no window, and the autoload does nothing. Measured: `godot -f -- scale=9` under Openbox
comes up fullscreen, asks for x6 with no title bar known, and settles at x5 with the
title bar on the screen. Without the refit it stays at x6 with the title bar at y = -20.
With no window manager the decorations are zero and the watch simply runs out.

A measurement counts only once `Window.size` reads back the size last asked for, and
only if it is smaller than the game at x1 (`is_frame_reading`). The second rule is for
resizes something else makes: under Openbox, a key pressed just after one read
`Window.size` 320x180 against a frame of 1922x1101, and caching that difference as
the title bar capped `=` at x1. No title bar is as big as the game.
Mid-resize, `Window.size` can still hold the old size while
`get_size_with_decorations()` already has the new one, and the difference is no title
bar at all: measured with no window manager, it cached 320x180 as decorations and
capped the window at x5 instead of x6.

If even x1 and its title bar are bigger than the screen, the window goes to the
top-left corner, so the title bar can still be reached.

`-` and `=` step from the size the window really has, not the cached factor, so a
window something else resized steps from where it is. They do nothing at either end
of a window, so pressing past the end does not re-centre a window the player has
moved. From fullscreen they always come back to a window. Both match exactly, so
Ctrl+= and Ctrl+- stay free for the game, and both mark the key handled. `=` never
shrinks a window that is already bigger than the screen allows; `-` brings it back.
The autoload runs with `PROCESS_MODE_ALWAYS`, so the keys and the settle watch keep
working while the game is paused.

At startup, a window bigger than the screen allows shrinks to the largest factor that
fits, and a window that is no whole multiple, because a window manager clamped it or
`--resolution 1000x600` asked for it, snaps down to one: x3, 960x540. A window that
starts fullscreen stays fullscreen unless `scale=` asks for a window, with the factor of
the project's window, clamped to the screen, so `-` from a 1280x720 project's fullscreen
gives x3. A `scale=` that is not a whole number is ignored rather than read as 0;
`scale=0` is a whole number, and clamps to x1.

### What does not change

Nothing in the scene. The stretch is `canvas_items` with `integer`, so Godot re-derives
the scale from the new window size every time:

| Factor | Window | Root viewport | SubViewport | Sub-pixel steps |
|---|---|---|---|---|
| x1 | 320 x 180 | 320 x 180 | 322 x 182 | 1 of 1 |
| x2 | 640 x 360 | 320 x 180 | 322 x 182 | 2 of 2 |
| x3 | 960 x 540 | 320 x 180 | 322 x 182 | 3 of 3 |
| x4 | 1280 x 720 | 320 x 180 | 322 x 182 | 4 of 4 |

Measured by `tests/scale.tscn`. `event.position` arrives on the root divided by the
factor at every size, so the mouse code in `../SKILL.md` needs no change.

At x1 the shader has no screen pixel to slide into. The camera is still correct, but
it hops whole pixels; x2 is the smallest factor where the smoothing is visible.

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

That 8 renders at 32 physical pixels at x4, 16 at x2. Crisp, not chunky.

### World-anchored UI

Anything on the CanvasLayer that must track a world position has to convert by hand.
Floating damage numbers, for example, end up doing this:

```gdscript
	number.global_position = (
		Vector2(Global.viewport.size)
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
