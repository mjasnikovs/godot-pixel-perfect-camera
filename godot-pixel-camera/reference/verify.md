# Verification

Do not trust the skill. Build the harness and run it.

## Strict typing

Every warning that matters set to **error**, so the project refuses to run if one
fires. In `project.godot`:

```ini
[debug]

gdscript/warnings/enable=true
gdscript/warnings/exclude_addons=true
gdscript/warnings/untyped_declaration=2
gdscript/warnings/inferred_declaration=2
gdscript/warnings/unsafe_property_access=2
gdscript/warnings/unsafe_method_access=2
gdscript/warnings/unsafe_cast=2
gdscript/warnings/unsafe_call_argument=2
gdscript/warnings/unsafe_void_return=2
gdscript/warnings/return_value_discarded=2
gdscript/warnings/shadowed_variable=2
gdscript/warnings/unused_variable=2
gdscript/warnings/unused_parameter=2
gdscript/warnings/unused_signal=2
gdscript/warnings/standalone_expression=2
gdscript/warnings/narrowing_conversion=2
gdscript/warnings/int_as_enum_without_cast=2
gdscript/warnings/integer_division=2
gdscript/warnings/static_called_on_instance=2
gdscript/warnings/redundant_await=2
gdscript/warnings/assert_always_true=2
gdscript/warnings/assert_always_false=2
gdscript/warnings/confusable_identifier=2
gdscript/warnings/confusable_local_declaration=2
gdscript/warnings/confusable_local_usage=2
gdscript/warnings/native_method_override=2
gdscript/warnings/get_node_default_without_onready=2
gdscript/warnings/onready_with_export=2
```

Value `0` = ignore, `1` = warn, `2` = error.

Level `1` only warns, and a warning you can scroll past is a warning you will ignore.
Use `2`.

### What this actually caught

Not theoretical. These all fired while building and verifying this camera.

| Warning | Offending code | Fix |
|---|---|---|
| `return_value_discarded` | `area.body_entered.connect(...)` | capture the return |
| `return_value_discarded` | `PackedStringArray.append(...)` | use `Array[String]`, whose `append` returns void |
| `return_value_discarded` | `DirAccess.make_dir_recursive_absolute(...)` | capture into `var _mkdir: int` |
| `return_value_discarded` | `tween.tween_property(...)` | capture into `var _t: PropertyTweener` |
| `int_as_enum_without_cast` | `var e: Error = connect(...)` | `connect` returns `int`, not `Error` |
| `unsafe_call_argument` | `int(ProjectSettings.get_setting(...))` | assign the Variant to a typed var first |
| `integer_division` | `image.get_width() / GAME_WIDTH` | cast both to `float` |
| `unused_variable` | a local used only for a sum | prefix with `_` |

### Patterns that keep it clean

```gdscript
# Variant -> typed: assign, do not cast. `as` triggers unsafe_cast.
var scale_mode: String = ProjectSettings.get_setting("display/window/stretch/scale_mode", "")

# Discarded return you genuinely do not need: underscore prefix suppresses
# unused_variable, but you still have to assign it.
var _collided: bool = move_and_slide()

# Typed collections, not the untyped built-ins.
var failures: Array[String] = []
var widths: Dictionary[int, int] = {}

# Typed loop variables.
for width: int in keys:
	...
```

---

## What the tools measure

Do not trust this document. Run the tools.

### `tests/verify.tscn` — 29 assertions, headless

```sh
godot --headless tests/verify.tscn    # exit 0 = pass
```

It drives the real scene for 270 frames and asserts, **every single frame**:

- the camera never sits on a fractional pixel
- `Camera2D.offset` is always zero, so nothing bypassed the rounding
- the shader's `cam_offset` is set and never exceeds half a pixel

Plus, once at startup:

- SubViewport is 322x182, exactly 2 bigger than the game area in each dimension
- container is at -1,-1, sized to match, scale (1, 1)
- SubViewport texture filter is Nearest; the project default is Nearest
- stretch mode is `canvas_items`, scale mode is `integer`
- base viewport equals the game size
- window is not resizable
- root `snap_2d_vertices_to_pixel` is off; the SubViewport's is on
- `snap_2d_transforms_to_pixel` is off (godot#98764)
- physics interpolation is off
- container material is a `ShaderMaterial`
- camera and player registered themselves
- camera anchor mode is Drag Center

Plus behaviour:

- the camera moves while following, and a real sub-pixel offset is produced
- entering a trigger retargets the camera to its `Marker2D`, and the trigger claims it
- leaving hands the camera back to the player, and releases the claim
- shake becomes active, goes through the rounding, and decays back to zero

Typical output ends:

```
[frame invariants]
  frames stepped: 270
  max sub-pixel offset seen: 0.498558

------------------------------------------------------------
PASS  29 checks, 270 frames, 0 failures
```

That `0.4986` is the proof the shader is doing real work. It should sit just under
0.5. If it is 0.000 the shader is never being fed.

### `tests/diagnose.tscn` — how smooth is it really

Needs a real window. Freezes the camera on a whole pixel, then renders the same frame
at sixteen different `cam_offset` values and counts visually distinct results. Also
walks every scanline and checks that runs of identical colour are all multiples of the
scale factor.

```
A. as shipped (viewport stretch)   render 1280x720   4x  steps/pixel 4/4   square
```

If a settings change halves that number, this is how you find out.

### `tests/motion.tscn` — the followed sprite

Headless. Walks the player right and histograms its on-screen step size per rendered
frame. Any negative step while walking forwards means the camera is on the wrong
clock.

### `tests/mouse.tscn` — where the mouse actually lands

Needs a real window. Injects a mouse motion event at a known window pixel, converts
it to a world position with four candidate formulas, draws a marker there, reads the
rendered frame back and measures how far the marker is from the pointer.

Measured on Godot 4.7.2, 320x180 in a 1280x720 window:

```
[stage 1] window pixel -> what the game receives (event.position)
  ok    window (640, 360) arrives as (160, 90)

[stage 2] root viewport -> SubViewport (who adds the container's +1?)
  ok    window (640, 360) arrives inside the SubViewport at (161, 91)

[stage 3] rendered marker error in game pixels, per formula
  formula            cam_offset [0.0, -0.5, -0.25, 0.25, 0.5]
  raw                 -1.00,-1.00  -1.50,-1.50  -1.25,-1.25  -0.75,-0.75  -0.50,-0.50
  +1                  +0.00,+0.00  -0.50,-0.50  -0.25,-0.25  +0.25,+0.25  +0.50,+0.50
  +1 +cam_offset      +0.00,+0.00  -0.50,-0.50  -0.25,-0.25  +0.25,+0.25  +1.50,+1.50
  +1 -cam_offset      +0.00,+0.00  +0.50,+0.50  -0.25,-0.25  +0.25,+0.25  +0.50,+0.50
```

Three things fall out of that.

`event.position` on the root is already in game pixels. Godot applied the window
stretch. Dividing by 4 again, or by 2, is the single most common mouse bug in this
setup.

An event that reaches a node **inside** the SubViewport already has the container's
`+1, +1` added by the engine. So does `get_global_mouse_position()`. Code reading
`event.position` on the root or a `CanvasLayer` has to add it by hand: the `raw` row
is off by exactly `-1, -1` at `cam_offset` zero.

The `+1` row's error is **exactly** `cam_offset`, at every offset. The displayed
image is shifted by the shader and the mouse is not, so the conversion has to
subtract it. Half a game pixel is invisible when the camera is still, but it drifts
with the camera while it moves, which is what makes a cursor feel loose.

Half a pixel of residual is the floor here. A marker drawn inside the SubViewport can
only land on whole game pixels, so a perfect formula still reads as ±0.5 whenever
`cam_offset` is ±0.5. The test asserts that, and asserts the naive formula is worse.

### `tests/fps.tscn` — real frame rate

```sh
godot tests/fps.tscn --position 2100,300 -- screen=1 vsync=on
```

Launch with `--position`, never move the window at runtime.

### `tests/screenshot.tscn` — look at it

Writes `user://screenshot.png` at full window resolution. Open it and zoom in. Bricks
should be perfectly uniform blocks.

---

## The test harness, in full

Copy these into a `tests/` folder. Each `.gd` needs the matching `.tscn` beside it.
They are written under the same strict warning settings as everything else, so they
compile clean at warning level `2`.

### `tests/verify.tscn`

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/main.tscn" id="1_verify"]
[ext_resource type="Script" path="res://tests/verify.gd" id="2_verify"]

[node name="VerifyRoot" type="Node"]

[node name="SubViewportContainer" parent="." instance=ExtResource("1_verify")]

[node name="Verifier" type="Node" parent="." node_paths=PackedStringArray("container", "sub_viewport")]
script = ExtResource("2_verify")
container = NodePath("../SubViewportContainer")
sub_viewport = NodePath("../SubViewportContainer/SubViewport")
```

### `tests/diagnose.tscn`

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/main.tscn" id="1_diag"]
[ext_resource type="Script" path="res://tests/diagnose.gd" id="2_diag"]

[node name="DiagnoseRoot" type="Node"]

[node name="SubViewportContainer" parent="." instance=ExtResource("1_diag")]

[node name="Diagnoser" type="Node" parent="." node_paths=PackedStringArray("container")]
script = ExtResource("2_diag")
container = NodePath("../SubViewportContainer")
```

### `tests/motion.tscn`

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/main.tscn" id="1_motion"]
[ext_resource type="Script" path="res://tests/motion.gd" id="2_motion"]

[node name="MotionRoot" type="Node"]

[node name="SubViewportContainer" parent="." instance=ExtResource("1_motion")]

[node name="Motion" type="Node" parent="."]
script = ExtResource("2_motion")
```

### `tests/fps.tscn`

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/main.tscn" id="1_fps"]
[ext_resource type="Script" path="res://tests/fps.gd" id="2_fps"]

[node name="FpsRoot" type="Node"]

[node name="SubViewportContainer" parent="." instance=ExtResource("1_fps")]

[node name="Fps" type="Node" parent="."]
script = ExtResource("2_fps")
```

### `tests/screenshot.tscn`

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/main.tscn" id="1_shot"]
[ext_resource type="Script" path="res://tests/screenshot.gd" id="2_shot"]

[node name="ScreenshotRoot" type="Node"]

[node name="SubViewportContainer" parent="." instance=ExtResource("1_shot")]

[node name="Shooter" type="Node" parent="."]
script = ExtResource("2_shot")
```

### `tests/verify.gd`

Drives the real scene for 270 frames and asserts the invariants every frame.

```gdscript
extends Node

## Headless self-test. Drives the real scene and asserts the pixel-perfect
## invariants hold every single frame.
##
##     godot --headless tests/verify.tscn
##
## Exit code 0 = all checks passed. 1 = at least one failed.

const EPSILON: float = 0.0001
const EXPECTED_VIEWPORT_SIZE: Vector2i = Vector2i(322, 182)
const EXPECTED_GAME_SIZE: Vector2i = Vector2i(320, 180)

@export var container: SubViewportContainer = null
@export var sub_viewport: SubViewport = null

var _failures: Array[String] = []
var _checks: int = 0
var _frame: int = 0
var _camera_start: Vector2 = Vector2.ZERO
var _max_subpixel: float = 0.0
var _saw_fractional_offset: bool = false
var _phase: String = "startup"


func _ready() -> void:
	assert(container != null, "verify.gd: 'container' is not assigned.")
	assert(sub_viewport != null, "verify.gd: 'sub_viewport' is not assigned.")


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
		return
	var line: String = label
	if not detail.is_empty():
		line = "%s  (%s)" % [label, detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


func _check_static_setup() -> void:
	print("\n[setup]")
	_check(
		"SubViewport is %dx%d" % [EXPECTED_VIEWPORT_SIZE.x, EXPECTED_VIEWPORT_SIZE.y],
		sub_viewport.size == EXPECTED_VIEWPORT_SIZE,
		str(sub_viewport.size)
	)
	_check(
		"SubViewport is exactly 1px bigger per side than the game area",
		sub_viewport.size - EXPECTED_GAME_SIZE == Vector2i(2, 2),
		str(sub_viewport.size - EXPECTED_GAME_SIZE)
	)
	_check(
		"container is offset -1,-1 to hide the extra border",
		is_equal_approx(container.position.x, -1.0) and is_equal_approx(container.position.y, -1.0),
		str(container.position)
	)
	_check(
		"container size matches the SubViewport",
		container.size == Vector2(EXPECTED_VIEWPORT_SIZE),
		str(container.size)
	)
	_check(
		"container scale is 1 (the window stretch does all the scaling)",
		container.scale.is_equal_approx(Vector2.ONE),
		str(container.scale)
	)
	_check(
		"SubViewport texture filter is Nearest",
		sub_viewport.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	)
	var texture_filter: int = ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter", -1
	)
	_check("project texture filter default is Nearest", texture_filter == 0, str(texture_filter))

	var scale_mode: String = ProjectSettings.get_setting("display/window/stretch/scale_mode", "")
	_check("stretch scale mode is integer", scale_mode == "integer", scale_mode)

	var stretch_mode: String = ProjectSettings.get_setting("display/window/stretch/mode", "")
	_check(
		"stretch mode is canvas_items (renders at native res, so the shader\n        offset lands on real screen pixels)",
		stretch_mode == "canvas_items",
		stretch_mode
	)

	var base_width: int = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var base_height: int = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	_check(
		"base viewport equals the game size, so the container needs no scale",
		Vector2i(base_width, base_height) == EXPECTED_GAME_SIZE,
		str(Vector2i(base_width, base_height))
	)

	var resizable: bool = ProjectSettings.get_setting("display/window/size/resizable", true)
	_check("window is not resizable (a tiling WM would break integer scaling)", not resizable)

	var snap_transforms: bool = ProjectSettings.get_setting(
		"rendering/2d/snap/snap_2d_transforms_to_pixel", false
	)
	_check("snap_2d_transforms_to_pixel is OFF (godot#98764)", not snap_transforms)

	var snap_vertices: bool = ProjectSettings.get_setting(
		"rendering/2d/snap/snap_2d_vertices_to_pixel", false
	)
	_check(
		"root snap_2d_vertices_to_pixel is OFF (it rounds away the shader offset)",
		not snap_vertices
	)
	_check(
		"SubViewport does its own vertex snapping instead",
		sub_viewport.snap_2d_vertices_to_pixel
	)

	var interpolation: bool = ProjectSettings.get_setting(
		"physics/common/physics_interpolation", false
	)
	_check("physics interpolation is OFF (fights this technique)", not interpolation)
	_check("container material is a ShaderMaterial", container.material is ShaderMaterial)
	_check("camera registered itself in Global", Global.camera != null)
	_check("player registered itself in Global", Global.player != null)
	if Global.camera != null:
		_check(
			"camera anchor mode is Drag Center",
			Global.camera.anchor_mode == Camera2D.ANCHOR_MODE_DRAG_CENTER
		)


func _check_invariants_this_frame() -> void:
	var camera: PixelCamera = Global.camera
	if camera == null:
		return

	var pos: Vector2 = camera.global_position
	if absf(pos.x - roundf(pos.x)) > EPSILON or absf(pos.y - roundf(pos.y)) > EPSILON:
		_failures.append("frame %d: camera position not whole pixels: %v" % [_frame, pos])

	if camera.offset != Vector2.ZERO:
		_failures.append("frame %d: Camera2D.offset bypassed the rounding: %v" % [_frame, camera.offset])

	var material: ShaderMaterial = container.material as ShaderMaterial
	var raw_offset: Variant = material.get_shader_parameter("cam_offset")
	if raw_offset == null:
		_failures.append("frame %d: cam_offset shader parameter is unset" % _frame)
		return

	var offset: Vector2 = raw_offset
	_max_subpixel = maxf(_max_subpixel, maxf(absf(offset.x), absf(offset.y)))
	if absf(offset.x) > 0.5 + EPSILON or absf(offset.y) > 0.5 + EPSILON:
		_failures.append("frame %d: cam_offset exceeds half a pixel: %v" % [_frame, offset])
	if absf(offset.x) > EPSILON or absf(offset.y) > EPSILON:
		_saw_fractional_offset = true


func _process(_delta: float) -> void:
	_check_invariants_this_frame()
	_frame += 1

	match _frame:
		1:
			_check_static_setup()
			if Global.camera != null:
				_camera_start = Global.camera.global_position
			Input.action_press("move_right")
			_phase = "walking right"
		90:
			Input.action_release("move_right")
			print("\n[follow]")
			_check(
				"camera moved while following the player",
				Global.camera != null and Global.camera.global_position != _camera_start,
				"start %v" % _camera_start
			)
			_check(
				"a sub-pixel offset was actually produced",
				_saw_fractional_offset,
				"max seen %f" % _max_subpixel
			)
			_check(
				"camera target is the player",
				Global.camera != null and Global.camera.target == Global.player
			)
		100:
			# Teleport the player into the left camera trigger.
			if Global.player != null:
				Global.player.global_position = Vector2(-180.0, 60.0)
				Global.player.velocity = Vector2.ZERO
			_phase = "inside trigger"
		140:
			print("\n[camera trigger]")
			_check(
				"entering a trigger retargets the camera to its Marker2D",
				Global.camera != null and Global.camera.target is Marker2D,
				str(Global.camera.target) if Global.camera != null else "no camera"
			)
			_check("trigger claimed the camera", Global.active_camera_trigger != null)
		150:
			if Global.player != null:
				Global.player.global_position = Vector2(200.0, 60.0)
				Global.player.velocity = Vector2.ZERO
			_phase = "outside trigger"
		200:
			_check(
				"leaving the trigger hands the camera back to the player",
				Global.camera != null and Global.camera.target == Global.player,
				str(Global.camera.target) if Global.camera != null else "no camera"
			)
			_check("trigger released the camera", Global.active_camera_trigger == null)
		210:
			print("\n[shake]")
			if Global.camera != null:
				Global.camera.apply_shake(6.0)
			_phase = "shaking"
		215:
			_check(
				"shake is active",
				Global.camera != null and Global.camera.shake_strength > 0.0,
				str(Global.camera.shake_strength) if Global.camera != null else "no camera"
			)
			_check(
				"shake goes through the rounding, not Camera2D.offset",
				Global.camera != null and Global.camera.offset == Vector2.ZERO,
				str(Global.camera.offset) if Global.camera != null else "no camera"
			)
		260:
			_check(
				"shake decays back to zero",
				Global.camera != null and Global.camera.shake_strength < 0.05,
				str(Global.camera.shake_strength) if Global.camera != null else "no camera"
			)
		270:
			_report_and_quit()


func _report_and_quit() -> void:
	print("\n[frame invariants]")
	print("  frames stepped: %d" % _frame)
	print("  max sub-pixel offset seen: %f" % _max_subpixel)

	var hard_failures: Array[String] = _failures
	print("\n------------------------------------------------------------")
	if hard_failures.is_empty():
		print("PASS  %d checks, %d frames, 0 failures" % [_checks, _frame])
		get_tree().quit(0)
		return

	print("FAIL  %d failures out of %d checks (phase: %s)" % [hard_failures.size(), _checks, _phase])
	for failure: String in hard_failures:
		print("  - %s" % failure)
	get_tree().quit(1)
```

### `tests/diagnose.gd`

Needs a real window. Renders the same frame at sixteen sub-pixel offsets and counts
distinct results, then checks that runs of identical colour are all multiples of the
scale factor.

```gdscript
extends Node

## Measures two things on real rendered frames, across several configurations:
##
##   1. steps/pixel - how many sub-pixel positions per game pixel actually
##      reach the screen. Higher is smoother. 1 means the shader does nothing.
##   2. square      - is every game pixel the same size on screen at every
##      sub-pixel offset? Anything else is smearing.
##
##     godot tests/diagnose.tscn

const GAME_WIDTH: int = 320
const STEPS: int = 16
const PROBE_OFFSETS: Array[float] = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]

@export var container: SubViewportContainer = null

var _started: bool = false


func _render(offset: Vector2) -> Image:
	var material: ShaderMaterial = container.material as ShaderMaterial
	material.set_shader_parameter("cam_offset", offset)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Counts runs of identical colour along many scanlines. On a clean integer
## upscale every run length is a multiple of the scale factor.
func _bad_run_ratio(image: Image, scale_factor: int) -> float:
	var bad: int = 0
	var total: int = 0
	var height: int = image.get_height()
	var width: int = image.get_width()
	for row: int in range(int(float(height) * 0.55), int(float(height) * 0.95), 3):
		var run: int = 1
		var previous: Color = image.get_pixel(0, row)
		for x: int in range(1, width):
			var current: Color = image.get_pixel(x, row)
			if current == previous:
				run += 1
				continue
			# Ignore the two runs clipped by the screen edges.
			if x < width - 1:
				total += 1
				if run % scale_factor != 0:
					bad += 1
			run = 1
			previous = current
	if total == 0:
		return -1.0
	return float(bad) / float(total)


func _report(label: String) -> void:
	var first: Image = await _render(Vector2.ZERO)
	var scale_factor: int = int(float(first.get_width()) / float(GAME_WIDTH))

	var previous: PackedByteArray = first.get_data()
	var distinct: int = 0
	for step: int in range(1, STEPS + 1):
		var current: PackedByteArray = (await _render(Vector2(float(step) / float(STEPS), 0.0))).get_data()
		if current != previous:
			distinct += 1
		previous = current

	var worst: float = 0.0
	for offset: float in PROBE_OFFSETS:
		var image: Image = await _render(Vector2(offset, 0.0))
		worst = maxf(worst, _bad_run_ratio(image, scale_factor))

	print("  %-34s render %4dx%-4d  %dx  steps/pixel %d/%d   %s" % [
		label,
		first.get_width(), first.get_height(),
		scale_factor,
		distinct, scale_factor,
		"square" if is_zero_approx(worst) else "UNEVEN (%.1f%% of runs)" % (worst * 100.0)
	])


func _process(_delta: float) -> void:
	if _started:
		return
	_started = true
	await _run()


func _run() -> void:
	var camera: PixelCamera = Global.camera
	camera.set_physics_process(false)
	camera.global_position = Vector2(40, 120)
	if Global.player != null:
		Global.player.set_physics_process(false)

	var window: Window = get_window()
	var root_rid: RID = get_viewport().get_viewport_rid()
	var sub_viewport: SubViewport = container.get_node("SubViewport") as SubViewport

	print("\nwindow %v\n" % window.size)
	print("  steps/pixel is measured out of the scale factor. Equal = perfectly")
	print("  smooth. Half = the camera judders in half-pixel hops.\n")

	await _report("A. as shipped (viewport stretch)")

	RenderingServer.viewport_set_snap_2d_vertices_to_pixel(root_rid, false)
	await _report("B. A, root vertex snap off")

	RenderingServer.viewport_set_snap_2d_transforms_to_pixel(root_rid, true)
	RenderingServer.viewport_set_snap_2d_vertices_to_pixel(root_rid, true)
	await _report("C. A, root transform + vertex snap")

	RenderingServer.viewport_set_snap_2d_transforms_to_pixel(root_rid, false)
	RenderingServer.viewport_set_snap_2d_vertices_to_pixel(root_rid, false)
	sub_viewport.snap_2d_vertices_to_pixel = true
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i(320, 180)
	container.scale = Vector2.ONE
	container.position = Vector2(-1.0, -1.0)
	await _report("D. canvas_items, base 320x180")

	get_tree().quit(0)
```

### `tests/motion.gd`

Headless. Histograms the followed sprite's on-screen step size per rendered frame.
Any negative step while walking forwards means the camera is on the wrong clock.

```gdscript
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
```

### `tests/fps.gd`

Measures the real frame rate. Launch with `--position X,Y` to place the window;
never move it at runtime or the numbers are meaningless.

```gdscript
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
```

### `tests/screenshot.gd`

Writes `user://screenshot.png` at full window resolution. Open it and zoom in.

```gdscript
extends Node

## Renders the real scene and writes a PNG, so the pixel grid can be inspected.
##
##     godot tests/screenshot.tscn
##
## Needs a real window. Headless renders nothing.

const OUTPUT_PATH: String = "user://screenshot.png"
const WARMUP_FRAMES: int = 45

var _frame: int = 0
var _done: bool = false


func _process(_delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _frame == 1:
		Input.action_press("move_right")
	if _frame < WARMUP_FRAMES:
		return

	_done = true
	Input.action_release("move_right")
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var save_error: int = image.save_png(OUTPUT_PATH)
	if save_error != OK:
		printerr("screenshot failed: %d" % save_error)
		get_tree().quit(1)
		return

	print("wrote %s (%dx%d)" % [ProjectSettings.globalize_path(OUTPUT_PATH), image.get_width(), image.get_height()])
	get_tree().quit(0)
```

---

## `tests/mouse.gd`

```gdscript
extends Node

## Measures where a mouse position actually lands in this SubViewport setup.
##
##     godot tests/mouse.tscn
##
## Injects a mouse motion event at a known window pixel, converts it to a world
## position with several candidate formulas, draws a marker there, then reads
## the rendered frame back and reports how far the marker is from the pointer.
## Exit code 0 = one formula is exact at every sub-pixel camera offset.

const GAME_SIZE: Vector2 = Vector2(320.0, 180.0)
const MARKER_SIZE: int = 4
const MARKER_COLOR: Color = Color(1.0, 0.0, 1.0, 1.0)
## A marker drawn inside the SubViewport can only land on whole game pixels,
## so half a game pixel is the best any formula can measure as.
const TOLERANCE: float = 0.5
const SEARCH_RADIUS: int = 160
const CAMERA_POSITION: Vector2 = Vector2(40.0, 120.0)
const OFFSETS: Array[float] = [0.0, -0.5, -0.25, 0.25, 0.5]
const PROBES: Array[Vector2] = [
	Vector2(640.0, 360.0),
	Vector2(204.0, 116.0),
	Vector2(1084.0, 596.0),
]
const VARIANTS: Array[String] = [
	"raw",
	"+1",
	"+1 +cam_offset",
	"+1 -cam_offset",
]

@export var container: SubViewportContainer = null
@export var sub_viewport: SubViewport = null

var _marker: Sprite2D = null
var _listener: MouseListener = null
var _camera: Camera2D = null
var _material: ShaderMaterial = null
var _scale: float = 1.0
var _event_position: Vector2 = Vector2.ZERO
var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	assert(container != null, "mouse.gd: 'container' is not assigned.")
	assert(sub_viewport != null, "mouse.gd: 'sub_viewport' is not assigned.")

	var image: Image = Image.create_empty(MARKER_SIZE, MARKER_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(MARKER_COLOR)
	_marker = Sprite2D.new()
	_marker.texture = ImageTexture.create_from_image(image)
	_marker.centered = true
	_marker.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	_marker.visible = false
	sub_viewport.add_child(_marker)

	_listener = MouseListener.new()
	sub_viewport.add_child(_listener)


## The position the game actually receives for the injected event.
func _input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_event_position = motion.position


## Injects a motion event at a window pixel and returns the root-viewport
## position the game sees for it.
func _point_at(window_pixel: Vector2) -> Vector2:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = window_pixel
	motion.global_position = window_pixel
	Input.parse_input_event(motion)
	await get_tree().process_frame
	return _event_position


func _center() -> Vector2:
	return Vector2(sub_viewport.size) * 0.5


func _world_for(variant: String, root_position: Vector2, cam_offset: Vector2) -> Vector2:
	var base: Vector2 = _camera.global_position + root_position - _center()
	match variant:
		"raw":
			return base
		"+1":
			return base + Vector2.ONE
		"+1 +cam_offset":
			return base + Vector2.ONE + cam_offset
		"+1 -cam_offset":
			return base + Vector2.ONE - cam_offset
		"get_global_mouse_position()":
			return _camera.get_global_mouse_position()
		"get_global_mouse_position() -cam_offset":
			return _camera.get_global_mouse_position() - cam_offset
	return Vector2.ZERO


func _render() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Centre of the marker in window pixels, searched in a box around the
## pointer, or (-1, -1) if no marker pixel is in that box.
func _find_marker(image: Image, around: Vector2) -> Vector2:
	var box: Rect2i = Rect2i(
		Vector2i(around) - Vector2i(SEARCH_RADIUS, SEARCH_RADIUS),
		Vector2i(SEARCH_RADIUS * 2, SEARCH_RADIUS * 2)
	).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var region: Image = image.get_region(box)
	region.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = region.get_data()
	var width: int = region.get_width()
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0
	for index: int in range(0, bytes.size(), 4):
		if bytes[index] > 230 and bytes[index + 1] < 25 and bytes[index + 2] > 230:
			var pixel: int = index >> 2
			var row: int = int(float(pixel) / float(width))
			sum += Vector2(float(pixel % width) + 0.5, float(row) + 0.5)
			count += 1
	if count == 0:
		return Vector2(-1.0, -1.0)
	return sum / float(count) + Vector2(box.position)


## Error in game pixels between the drawn marker and the pointer.
func _error_for(variant: String, window_pixel: Vector2, root_position: Vector2,
		cam_offset: Vector2) -> Vector2:
	_marker.visible = true
	_marker.global_position = _world_for(variant, root_position, cam_offset)
	var found: Vector2 = _find_marker(await _render(), window_pixel)
	_marker.visible = false
	if found.x < 0.0:
		return Vector2(NAN, NAN)
	return (found - window_pixel) / _scale


func _run() -> void:
	_camera = Global.camera
	_camera.set_physics_process(false)
	_camera.global_position = CAMERA_POSITION
	if Global.player != null:
		Global.player.set_physics_process(false)
	_material = container.material as ShaderMaterial

	var probe: Image = await _render()
	_scale = float(probe.get_width()) / GAME_SIZE.x
	print("\nwindow %v   render %dx%d   scale %dx   SubViewport %v   container %v\n" % [
		get_window().size, probe.get_width(), probe.get_height(), int(_scale),
		sub_viewport.size, container.position
	])

	print("[stage 1] window pixel -> what the game receives (event.position)")
	for window_pixel: Vector2 in PROBES:
		var root_position: Vector2 = await _point_at(window_pixel)
		var expected: Vector2 = window_pixel / _scale
		_check("window %v arrives as %v" % [window_pixel, expected],
			root_position.is_equal_approx(expected), "got %v" % root_position)

	print("\n[stage 2] root viewport -> SubViewport (who adds the container's +1?)")
	for window_pixel: Vector2 in PROBES:
		var root_position: Vector2 = await _point_at(window_pixel)
		var delta: Vector2 = _listener.last_position - root_position
		_check("window %v arrives inside the SubViewport at %v"
			% [window_pixel, root_position + Vector2.ONE],
			delta.is_equal_approx(Vector2.ONE), "delta %v" % delta)

	print("\n[stage 3] rendered marker error in game pixels, per formula")
	print("  %-18s %s" % ["formula", "cam_offset " + str(OFFSETS)])
	var tracks_offset: bool = true
	for variant: String in VARIANTS:
		var cells: Array[String] = []
		for offset: float in OFFSETS:
			var cam_offset: Vector2 = Vector2(offset, offset)
			_material.set_shader_parameter("cam_offset", cam_offset)
			var root_position: Vector2 = await _point_at(PROBES[0])
			var error: Vector2 = await _error_for(variant, PROBES[0], root_position, cam_offset)
			if is_nan(error.x):
				cells.append(" off-screen")
				continue
			cells.append("%+6.2f,%+6.2f" % [error.x, error.y])
			if variant == "+1" and not error.is_equal_approx(cam_offset):
				tracks_offset = false
		print("  %-18s %s" % [variant, " ".join(cells)])
	_material.set_shader_parameter("cam_offset", Vector2.ZERO)
	_check("the displayed image is shifted by exactly cam_offset", tracks_offset)

	print("\n[stage 4] every pointer position, every sub-pixel camera offset")
	for variant: String in ["raw", "+1 -cam_offset"]:
		var worst: float = 0.0
		for window_pixel: Vector2 in PROBES:
			for offset: float in OFFSETS:
				var cam_offset: Vector2 = Vector2(offset, -offset)
				_material.set_shader_parameter("cam_offset", cam_offset)
				var root_position: Vector2 = await _point_at(window_pixel)
				var error: Vector2 = await _error_for(variant, window_pixel, root_position, cam_offset)
				if is_nan(error.x):
					worst = INF
					continue
				worst = maxf(worst, maxf(absf(error.x), absf(error.y)))
		if variant == "raw":
			_check("the naive formula is visibly wrong", worst > TOLERANCE,
				"worst %.2f game px" % worst)
			continue
		_check("%s lands on the pointer's own pixel" % variant, worst <= TOLERANCE,
			"worst %.2f game px" % worst)
	_material.set_shader_parameter("cam_offset", Vector2.ZERO)

	print("")
	if _failures.is_empty():
		print("all checks passed")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("FAILED: %s" % failure)
	get_tree().quit(1)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok    %s" % label)
		return
	var line: String = label
	if not detail.is_empty():
		line = "%s  (%s)" % [label, detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


func _process(_delta: float) -> void:
	if _started:
		return
	_started = true
	await _run()


## Reports mouse events as they arrive inside the SubViewport.
class MouseListener extends Node:
	var last_position: Vector2 = Vector2.ZERO

	func _input(event: InputEvent) -> void:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if motion != null:
			last_position = motion.position
```

`tests/mouse.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/main.tscn" id="1_mouse"]
[ext_resource type="Script" path="res://tests/mouse.gd" id="2_mouse"]

[node name="MouseRoot" type="Node"]

[node name="SubViewportContainer" parent="." instance=ExtResource("1_mouse")]

[node name="Mouse" type="Node" parent="." node_paths=PackedStringArray("container", "sub_viewport")]
script = ExtResource("2_mouse")
container = NodePath("../SubViewportContainer")
sub_viewport = NodePath("../SubViewportContainer/SubViewport")
```
