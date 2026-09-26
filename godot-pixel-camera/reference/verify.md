# Verification

Do not trust the skill. Build the harness and run it.

## Strict typing

All 49 GDScript warnings are errors, exactly as godot-code-style sets them. Copy the
`[debug]` block from its `reference/checklist.md`. The project refuses to run if one
fires, and nothing is suppressed.

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
| `unused_variable` | a local used only for a sum | prefix it `_` |

### Patterns that keep it clean

```gdscript
	# Variant -> typed: assign, do not cast. `as` on a Variant fires unsafe_cast.
	var scale_mode: String = ProjectSettings.get_setting("display/window/stretch/scale_mode", "")

	# A return you do not need is still assigned; the underscore keeps unused_variable quiet.
	var _collided: bool = move_and_slide()

	# Typed collections and typed loop variables.
	var widths: Dictionary[int, int] = {}
	for width: int in widths:
		widths[width] += 1
```

The rest of the dialect is godot-code-style's.

---

## What the tools measure

Do not trust this document. Run the tools.

Every harness is a self-test scene, so godot-code-style's test rule (its `SKILL.md`)
holds: it prints nothing on a pass. On a failure it prints each one with `printerr` and
quits with exit code 1. Its CI step fails on any output other than the engine banner,
or on a non-zero exit, because a harness that fails to parse prints the error and
still exits 0.

```sh
status=0
output=$(godot --headless tests/verify.tscn --quit-after 400 2>&1) || status=$?
output=$(echo "$output" | grep -v '^Godot Engine' || true)
if [ -n "$output" ] || [ "$status" != 0 ]; then echo "$output"; exit 1; fi
```

In a window the engine prints its renderer line first (`Vulkan 1.4 - Forward+ -
Using Device ...`); that line is Godot's, not the harness's.

The values quoted below were measured on Godot 4.7.2 while building this project.
The harnesses assert the bounds; they do not print the values.

### `tests/verify.tscn` — the invariants, headless

It drives the real scene for 270 frames and asserts, **every single frame**:

- the camera never sits on a fractional pixel
- `Camera2D.offset` is always zero, so nothing bypassed the rounding
- the shader's `cam_offset` is set and never exceeds half a pixel

Plus, once at startup, that every script in `scripts/` and `tests/` compiles. A
headless launch only parses what the main scene reaches, so a broken harness would
otherwise pass.

And:

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

- the camera moves while following, and a real sub-pixel offset is produced, reaching
  above 0.4 of a pixel
- entering a trigger retargets the camera to its `Marker2D`, and the trigger claims it
- leaving hands the camera back to the player, and releases the claim
- shake becomes active, goes through the rounding, and decays back to zero

The largest sub-pixel offset measured over the 270 frames was `0.4992`. That is the
proof the shader is doing real work: it sits just under 0.5. Near 0.000 the shader is
never being fed, and the harness fails below 0.4.

### `tests/diagnose.tscn` — how smooth is it really

Needs a real window. Freezes the camera on a whole pixel, then renders the same frame
at sixteen different `cam_offset` values and counts visually distinct results. It
asserts one distinct step per screen pixel of the scale factor: 4 of 4 at 1280x720.
It also walks every scanline at eight offsets and asserts that each run of identical
colour is a multiple of the scale factor, apart from the two runs the screen edges
cut off.

Measured as shipped: 4 of 4 steps per game pixel, every run square.

If a settings change halves that number, this is how you find out.

### `tests/motion.tscn` — the followed sprite

Headless. Walks the player right and records its on-screen step size per rendered
frame. It asserts that no step is negative while walking forwards, which would mean
the camera is on the wrong clock, and that the speed is a whole number of pixels per
physics tick with no fractional residual.

Measured at 60 px/s: 1.000 px per tick, a mean residual of 0.000 px, and on-screen
steps of +0 px on 59 frames and +1 px on 10.

### `tests/mouse.tscn` — where the mouse actually lands

Needs a real window. Injects a mouse motion event at a known window pixel, converts
it to a world position, draws a marker there, reads the rendered frame back and
measures how far the marker is from the pointer. It asserts that the root receives
the window pixel divided by the scale, that the SubViewport receives it `+1, +1`,
that the `+1` formula is off by exactly `cam_offset`, that the naive formula misses,
and that `+1 -cam_offset` lands on the pointer's own pixel at every offset.

Measured on Godot 4.7.2, 320x180 in a 1280x720 window, with four candidate formulas:
window `(640, 360)` arrives at the root as `(160, 90)` and inside the SubViewport as
`(161, 91)`. The rendered marker's error in game pixels, per formula:

```
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
godot tests/fps.tscn -- screen=0 vsync=on
```

Asserts that the game presents at least 95% of the 60 Hz physics rate, so every
physics tick reaches the screen, and fails with the measured rate when it does not.
`screen=N` picks the monitor; the harness moves its window there in `_ready`, before
the warmup frames. Never move the window while it measures.

It fails under `xvfb-run`: measured 30–38 fps there. It passes only on a real,
visible display, which is what it is for.

### `tests/screenshot.tscn` — look at it

Writes `user://screenshot.png` at full window resolution and exits silently. Open it
and zoom in. Bricks should be perfectly uniform blocks. It only fails when the file
cannot be written.

---

## The test harness, in full

Copy these into a `tests/` folder. Each `.gd` needs the matching `.tscn` beside it.
They follow godot-code-style and compile with all 49 warnings at level `2`. Each is
silent on a pass and prints its failures with `printerr`.

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
class_name Verify extends Node

# Headless self-test. Drives the real scene and asserts the pixel-perfect invariants
# hold every single frame. A self-test scene, so godot-code-style's test rule holds:
# it prints nothing on a pass, and on a failure it prints each one with printerr and
# quits with exit code 1.

const EPSILON: float = 0.0001
const EXPECTED_VIEWPORT_SIZE: Vector2 = Vector2(322.0, 182.0)
const EXPECTED_GAME_SIZE: Vector2 = Vector2(320.0, 180.0)
# A headless launch only parses what the main scene reaches, so every script is
# loaded here by path.
const SCRIPT_DIRECTORIES: Array[String] = ["res://scripts/", "res://tests/"]

@export_category("Nodes")
@export var container: SubViewportContainer
@export var sub_viewport: SubViewport

var _failures: Array[String] = []
var _frame: int = 0
var _camera_start: Vector2 = Vector2.ZERO
var _max_subpixel: float = 0.0
var _saw_fractional_offset: bool = false
var _phase: String = "startup"


func _ready() -> void:
	assert(container, "verify.gd - @export container is not set in the editor on: " + self.name)
	assert(sub_viewport, "verify.gd - @export sub_viewport is not set in the editor on: " + self.name)


func _process(_delta: float) -> void:
	_check_invariants_this_frame()
	_frame += 1

	if _frame == 1:
		_check_every_script_compiles()
		_check_static_setup()
		if Global.camera:
			_camera_start = Global.camera.global_position
		Input.action_press(&"move_right")
		_phase = "walking right"
	elif _frame == 90:
		Input.action_release(&"move_right")
		_check_follow()
	elif _frame == 100:
		# Teleport the player into the left camera trigger.
		_place_player(Vector2(-180.0, 60.0))
		_phase = "inside trigger"
	elif _frame == 140:
		_check_trigger_claimed()
	elif _frame == 150:
		_place_player(Vector2(200.0, 60.0))
		_phase = "outside trigger"
	elif _frame == 200:
		_check_trigger_released()
	elif _frame == 210:
		if Global.camera:
			Global.camera.apply_shake(6.0)
		_phase = "shaking"
	elif _frame == 215:
		_check_shake_active()
	elif _frame == 260:
		_check(
			"shake decays back to zero",
			Global.camera != null and Global.camera.shake_strength < 0.05,
			str(Global.camera.shake_strength) if Global.camera else "no camera"
		)
	elif _frame == 270:
		_report_and_quit()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	var line: String = label
	if !detail.is_empty():
		line = "%s  (%s)" % [label, detail]
	_failures.append(line)


func _check_every_script_compiles() -> void:
	for directory: String in SCRIPT_DIRECTORIES:
		for file_name: String in DirAccess.get_files_at(directory):
			if !file_name.ends_with(".gd"):
				continue
			var script: GDScript = load(directory + file_name)
			_check("%s compiles" % file_name, script != null and script.can_instantiate())


func _check_static_setup() -> void:
	var viewport_size: Vector2 = Vector2(sub_viewport.size)
	_check(
		"SubViewport is %dx%d" % [EXPECTED_VIEWPORT_SIZE.x, EXPECTED_VIEWPORT_SIZE.y],
		viewport_size == EXPECTED_VIEWPORT_SIZE,
		str(viewport_size)
	)
	_check(
		"SubViewport is exactly 1px bigger per side than the game area",
		viewport_size - EXPECTED_GAME_SIZE == Vector2(2.0, 2.0),
		str(viewport_size - EXPECTED_GAME_SIZE)
	)
	_check(
		"container is offset -1,-1 to hide the extra border",
		is_equal_approx(container.position.x, -1.0) and is_equal_approx(container.position.y, -1.0),
		str(container.position)
	)
	_check("container size matches the SubViewport", container.size == EXPECTED_VIEWPORT_SIZE, str(container.size))
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

	var base_width: float = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var base_height: float = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	_check(
		"base viewport equals the game size, so the container needs no scale",
		Vector2(base_width, base_height) == EXPECTED_GAME_SIZE,
		str(Vector2(base_width, base_height))
	)

	var resizable: bool = ProjectSettings.get_setting("display/window/size/resizable", true)
	_check("window is not resizable (a tiling WM would break integer scaling)", !resizable)

	var snap_transforms: bool = ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false)
	_check("snap_2d_transforms_to_pixel is OFF (godot#98764)", !snap_transforms)

	var snap_vertices: bool = ProjectSettings.get_setting("rendering/2d/snap/snap_2d_vertices_to_pixel", false)
	_check("root snap_2d_vertices_to_pixel is OFF (it rounds away the shader offset)", !snap_vertices)
	_check("SubViewport does its own vertex snapping instead", sub_viewport.snap_2d_vertices_to_pixel)

	var interpolation: bool = ProjectSettings.get_setting("physics/common/physics_interpolation", false)
	_check("physics interpolation is OFF (fights this technique)", !interpolation)
	_check("container material is a ShaderMaterial", container.material is ShaderMaterial)
	_check("camera registered itself in Global", Global.camera != null)
	_check("player registered itself in Global", Global.player != null)
	if Global.camera:
		_check("camera anchor mode is Drag Center", Global.camera.anchor_mode == Camera2D.ANCHOR_MODE_DRAG_CENTER)


func _check_follow() -> void:
	_check(
		"camera moved while following the player",
		Global.camera != null and Global.camera.global_position != _camera_start,
		"start %v" % _camera_start
	)
	_check("a sub-pixel offset was actually produced", _saw_fractional_offset, "max seen %f" % _max_subpixel)
	# Measured 0.4992: a camera that has moved has met nearly every fraction. Far
	# under that, the shader is not being fed each physics tick.
	_check("the sub-pixel offset reached close to half a pixel", _max_subpixel > 0.4, "max seen %f" % _max_subpixel)
	_check("camera target is the player", Global.camera != null and Global.camera.c_target == Global.player)


func _check_trigger_claimed() -> void:
	_check(
		"entering a trigger retargets the camera to its Marker2D",
		Global.camera != null and Global.camera.c_target is Marker2D,
		str(Global.camera.c_target) if Global.camera else "no camera"
	)
	_check("trigger claimed the camera", Global.active_camera_trigger != null)


func _check_trigger_released() -> void:
	_check(
		"leaving the trigger hands the camera back to the player",
		Global.camera != null and Global.camera.c_target == Global.player,
		str(Global.camera.c_target) if Global.camera else "no camera"
	)
	_check("trigger released the camera", Global.active_camera_trigger == null)


func _check_shake_active() -> void:
	_check(
		"shake is active",
		Global.camera != null and Global.camera.shake_strength > 0.0,
		str(Global.camera.shake_strength) if Global.camera else "no camera"
	)
	_check(
		"shake goes through the rounding, not Camera2D.offset",
		Global.camera != null and Global.camera.offset == Vector2.ZERO,
		str(Global.camera.offset) if Global.camera else "no camera"
	)


func _place_player(at: Vector2) -> void:
	if !Global.player:
		return
	Global.player.global_position = at
	Global.player.velocity = Vector2.ZERO


func _check_invariants_this_frame() -> void:
	var camera: PixelCamera = Global.camera
	if !camera:
		return

	var pos: Vector2 = camera.global_position
	if absf(pos.x - roundf(pos.x)) > EPSILON or absf(pos.y - roundf(pos.y)) > EPSILON:
		_failures.append("frame %d: camera position not whole pixels: %v" % [_frame, pos])

	if camera.offset != Vector2.ZERO:
		_failures.append("frame %d: Camera2D.offset bypassed the rounding: %v" % [_frame, camera.offset])

	var material: ShaderMaterial = container.material as ShaderMaterial
	var raw_offset: Variant = material.get_shader_parameter(&"cam_offset")
	if typeof(raw_offset) != TYPE_VECTOR2:
		_failures.append("frame %d: cam_offset shader parameter is not a Vector2" % _frame)
		return

	var offset: Vector2 = raw_offset
	_max_subpixel = maxf(_max_subpixel, maxf(absf(offset.x), absf(offset.y)))
	if absf(offset.x) > 0.5 + EPSILON or absf(offset.y) > 0.5 + EPSILON:
		_failures.append("frame %d: cam_offset exceeds half a pixel: %v" % [_frame, offset])
	if absf(offset.x) > EPSILON or absf(offset.y) > EPSILON:
		_saw_fractional_offset = true


func _report_and_quit() -> void:
	if _failures.is_empty():
		get_tree().quit(0)
		return
	printerr("FAIL  %d failures, phase: %s" % [_failures.size(), _phase])
	for failure: String in _failures:
		printerr("  - %s" % failure)
	get_tree().quit(1)
```

### `tests/diagnose.gd`

Needs a real window. Renders the same frame at sixteen sub-pixel offsets and counts
distinct results, then checks that runs of identical colour are all multiples of the
scale factor.

```gdscript
class_name Diagnose extends Node

# Checks two things on real rendered frames, with the camera parked on a whole pixel:
#   steps/pixel - every sub-pixel position per game pixel reaches the screen, one per
#                 screen pixel of the scale factor.
#   square      - every game pixel is the same size on screen at every sub-pixel
#                 offset. Anything else is smearing.
# Needs a real window. Silent with exit 0 is a pass; a failure prints the measured
# value with printerr and exits 1.

const GAME_WIDTH: float = 320.0
const STEPS: int = 16
const PROBE_OFFSETS: Array[float] = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]

@export_category("Nodes")
@export var container: SubViewportContainer

var _started: bool = false


func _ready() -> void:
	assert(container, "diagnose.gd - @export container is not set in the editor on: " + self.name)


func _process(_delta: float) -> void:
	if _started:
		return
	_started = true
	await _run()


func _run() -> void:
	var camera: PixelCamera = Global.camera
	camera.set_physics_process(false)
	camera.global_position = Vector2(40.0, 120.0)
	if Global.player:
		Global.player.set_physics_process(false)

	var failures: Array[String] = []
	var first: Image = await _render(Vector2.ZERO)
	var scale_factor: int = int(float(first.get_width()) / GAME_WIDTH)

	var previous: PackedByteArray = first.get_data()
	var distinct: int = 0
	for step: int in range(1, STEPS + 1):
		var current: PackedByteArray = (await _render(Vector2(float(step) / float(STEPS), 0.0))).get_data()
		if current != previous:
			distinct += 1
		previous = current
	if distinct != scale_factor:
		failures.append("steps/pixel %d of %d: the camera judders in coarser hops" % [distinct, scale_factor])

	for offset: float in PROBE_OFFSETS:
		var image: Image = await _render(Vector2(offset, 0.0))
		var ratio: float = _bad_run_ratio(image, scale_factor)
		if !is_zero_approx(ratio):
			failures.append("at cam_offset %.3f, %.1f%% of colour runs are uneven" % [offset, ratio * 100.0])

	for failure: String in failures:
		printerr("FAIL  %s" % failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _render(offset: Vector2) -> Image:
	var material: ShaderMaterial = container.material as ShaderMaterial
	material.set_shader_parameter(&"cam_offset", offset)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# Counts runs of identical colour along many scanlines. On a clean integer upscale
# every run length is a multiple of the scale factor, except the two runs the screen
# edges cut off: the image slides by up to a game pixel, so the edge run is partial.
func _bad_run_ratio(image: Image, scale_factor: int) -> float:
	var bad: int = 0
	var total: int = 0
	var height: int = image.get_height()
	var width: int = image.get_width()
	for row: int in range(int(float(height) * 0.55), int(float(height) * 0.95), 3):
		var run: int = 1
		var run_start: int = 0
		var previous: Color = image.get_pixel(0, row)
		for x: int in range(1, width):
			var current: Color = image.get_pixel(x, row)
			if current == previous:
				run += 1
				continue
			if run_start > 0 and x < width - 1:
				total += 1
				if run % scale_factor != 0:
					bad += 1
			run = 1
			run_start = x
			previous = current
	if total == 0:
		return -1.0
	return float(bad) / float(total)
```

### `tests/motion.gd`

Headless. Histograms the followed sprite's on-screen step size per rendered frame.
Any negative step while walking forwards means the camera is on the wrong clock.

```gdscript
class_name Motion extends Node

# Walks the player right and checks how it lands on the pixel grid. Silent with exit
# 0 means the camera is on the physics clock and the speed is a whole number of pixels
# per tick; a failure is printed with printerr and exits 1.

# verify.yml's --quit-after is twice this; a cap below it ends the run before the report, silently.
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
	if !player or !camera:
		printerr("FAIL  the player or the camera never registered with Global")
		get_tree().quit(1)
		return

	# Where the player sits inside the rendered frame, in game pixels.
	var screen: Vector2 = player.global_position - camera.global_position
	_residuals.append(absf(player.global_position.x - roundf(player.global_position.x)))

	if _frame > 21:
		var step: int = int(roundf(screen.x - _last_screen.x))
		var count: int = _steps.get(step, 0)
		_steps[step] = count + 1
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
```

### `tests/fps.gd`

Measures the real frame rate. Pick the monitor with `screen=N`; never move the window
while it measures or the numbers are meaningless.

```gdscript
class_name Fps extends Node

# Measures the real frame rate of the running game:
#   godot tests/fps.tscn -- screen=0 vsync=on
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
```

### `tests/screenshot.gd`

Writes `user://screenshot.png` at full window resolution. Open it and zoom in.

```gdscript
class_name Screenshot extends Node

# Renders the real scene and writes user://screenshot.png, so a person can inspect
# the pixel grid:
#   godot tests/screenshot.tscn
# Needs a real window. Headless renders nothing. Silent with exit 0 once the file is
# written; a failed write is printed with printerr and exits 1.

const OUTPUT_PATH: String = "user://screenshot.png"
const WARMUP_FRAMES: int = 45

var _frame: int = 0
var _done: bool = false


func _process(_delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _frame == 1:
		Input.action_press(&"move_right")
	if _frame < WARMUP_FRAMES:
		return

	_done = true
	Input.action_release(&"move_right")
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var save_error: int = image.save_png(OUTPUT_PATH)
	if save_error != OK:
		printerr("FAIL  could not write %s: error %d" % [OUTPUT_PATH, save_error])
		get_tree().quit(1)
		return
	get_tree().quit(0)
```

---

## `tests/mouse.gd`

```gdscript
class_name Mouse extends Node

# Measures where a mouse position actually lands in this SubViewport setup:
#   godot tests/mouse.tscn
# Injects a mouse motion event at a known window pixel, converts it to a world
# position with several candidate formulas, draws a marker there, then reads the
# rendered frame back and measures how far the marker is from the pointer. Silent with
# exit 0 means the `+1 -cam_offset` formula lands on the pointer's own pixel at every
# sub-pixel camera offset; a failure is printed with printerr and exits 1.

const GAME_SIZE: Vector2 = Vector2(320.0, 180.0)
const MARKER_SIZE: int = 4
const MARKER_COLOR: Color = Color(1.0, 0.0, 1.0, 1.0)
# A marker drawn inside the SubViewport can only land on whole game pixels, so half
# a game pixel is the best any formula can measure as.
const TOLERANCE: float = 0.5
const SEARCH_RADIUS: float = 160.0
const CAMERA_POSITION: Vector2 = Vector2(40.0, 120.0)
const OFFSETS: Array[float] = [0.0, -0.5, -0.25, 0.25, 0.5]
const PROBES: Array[Vector2] = [
	Vector2(640.0, 360.0),
	Vector2(204.0, 116.0),
	Vector2(1084.0, 596.0),
]

@export_category("Nodes")
@export var container: SubViewportContainer
@export var sub_viewport: SubViewport

var _marker: Sprite2D = null
var _listener: MouseListener = null
var _camera: Camera2D = null
var _material: ShaderMaterial = null
var _scale: float = 1.0
var _event_position: Vector2 = Vector2.ZERO
var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	assert(container, "mouse.gd - @export container is not set in the editor on: " + self.name)
	assert(sub_viewport, "mouse.gd - @export sub_viewport is not set in the editor on: " + self.name)

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


# The position the game actually receives for the injected event.
func _input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion:
		_event_position = motion.position


func _process(_delta: float) -> void:
	if _started:
		return
	_started = true
	await _run()


func _run() -> void:
	_camera = Global.camera
	_camera.set_physics_process(false)
	_camera.global_position = CAMERA_POSITION
	if Global.player:
		Global.player.set_physics_process(false)
	_material = container.material as ShaderMaterial

	var probe: Image = await _render()
	_scale = float(probe.get_width()) / GAME_SIZE.x

	await _stage_window_to_root()
	await _stage_root_to_sub_viewport()
	await _stage_formulas()
	await _stage_every_offset()

	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL  %s" % failure)
	get_tree().quit(1)


func _stage_window_to_root() -> void:
	for window_pixel: Vector2 in PROBES:
		var root_position: Vector2 = await _point_at(window_pixel)
		var expected: Vector2 = window_pixel / _scale
		_check(
			"window %v arrives as %v" % [window_pixel, expected],
			root_position.is_equal_approx(expected),
			"got %v" % root_position
		)


func _stage_root_to_sub_viewport() -> void:
	for window_pixel: Vector2 in PROBES:
		var root_position: Vector2 = await _point_at(window_pixel)
		var delta: Vector2 = _listener.last_position - root_position
		_check(
			"window %v arrives inside the SubViewport at %v" % [window_pixel, root_position + Vector2.ONE],
			delta.is_equal_approx(Vector2.ONE),
			"delta %v" % delta
		)


# The `+1` formula's error is exactly cam_offset at every offset: the shader shifts
# the displayed image and the mouse is not shifted with it.
func _stage_formulas() -> void:
	var tracks_offset: bool = true
	var worst: Vector2 = Vector2.ZERO
	for offset: float in OFFSETS:
		var cam_offset: Vector2 = Vector2(offset, offset)
		_material.set_shader_parameter(&"cam_offset", cam_offset)
		var root_position: Vector2 = await _point_at(PROBES[0])
		var error: Vector2 = await _error_for("+1", PROBES[0], root_position, cam_offset)
		if is_nan(error.x) or !error.is_equal_approx(cam_offset):
			tracks_offset = false
			worst = error
	_material.set_shader_parameter(&"cam_offset", Vector2.ZERO)
	_check("the displayed image is shifted by exactly cam_offset", tracks_offset, "error %v" % worst)


func _stage_every_offset() -> void:
	for variant: String in ["raw", "+1 -cam_offset"]:
		var worst: float = 0.0
		for window_pixel: Vector2 in PROBES:
			for offset: float in OFFSETS:
				var cam_offset: Vector2 = Vector2(offset, -offset)
				_material.set_shader_parameter(&"cam_offset", cam_offset)
				var root_position: Vector2 = await _point_at(window_pixel)
				var error: Vector2 = await _error_for(variant, window_pixel, root_position, cam_offset)
				if is_nan(error.x):
					worst = INF
					continue
				worst = maxf(worst, maxf(absf(error.x), absf(error.y)))
		if variant == "raw":
			_check("the naive formula is visibly wrong", worst > TOLERANCE, "worst %.2f game px" % worst)
			continue
		_check("%s lands on the pointer's own pixel" % variant, worst <= TOLERANCE, "worst %.2f game px" % worst)
	_material.set_shader_parameter(&"cam_offset", Vector2.ZERO)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	var line: String = label
	if !detail.is_empty():
		line = "%s  (%s)" % [label, detail]
	_failures.append(line)


# Injects a motion event at a window pixel and returns the root-viewport position
# the game sees for it.
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
	var world: Vector2 = Vector2.ZERO
	if variant == "raw":
		world = base
	elif variant == "+1":
		world = base + Vector2.ONE
	elif variant == "+1 -cam_offset":
		world = base + Vector2.ONE - cam_offset
	return world


func _render() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# Centre of the marker in window pixels, searched in a box around the pointer, or
# (-1, -1) if no marker pixel is in that box.
func _find_marker(image: Image, around: Vector2) -> Vector2:
	var reach: Vector2 = Vector2(SEARCH_RADIUS, SEARCH_RADIUS)
	var image_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(image.get_size()))
	var box: Rect2 = Rect2(around.floor() - reach, reach * 2.0).intersection(image_rect)
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
	return sum / float(count) + box.position


# Error in game pixels between the drawn marker and the pointer.
func _error_for(variant: String, window_pixel: Vector2, root_position: Vector2, cam_offset: Vector2) -> Vector2:
	_marker.visible = true
	_marker.global_position = _world_for(variant, root_position, cam_offset)
	var found: Vector2 = _find_marker(await _render(), window_pixel)
	_marker.visible = false
	if found.x < 0.0:
		return Vector2(NAN, NAN)
	return (found - window_pixel) / _scale
```

`tests/mouse_listener.gd`, the listener it adds inside the SubViewport:

```gdscript
class_name MouseListener extends Node

# Records where mouse events land inside the SubViewport, for tests/mouse.gd.

var last_position: Vector2 = Vector2.ZERO


func _input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion:
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
