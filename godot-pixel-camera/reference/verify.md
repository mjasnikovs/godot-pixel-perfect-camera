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

Needs a real window of 1280x720: its probes are pixels of that window. It waits for
`WindowScale` to settle, then sets that size itself, since `WindowScale` shrinks the
window on a screen too small to show it with its title bar, and fails only if the
window manager refuses it.
Injects a mouse motion event at a known window pixel, converts
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

### `tests/scale.tscn` — x1, x2, x3, x4 in a window

```sh
godot tests/scale.tscn                 # starts at the project's 1280x720
godot tests/scale.tscn -- scale=2      # also checks the scale=N argument
xvfb-run -a sh -c 'openbox & until xprop -root _NET_SUPPORTING_WM_CHECK |
  grep -q "window id"; do sleep 0.2; done; exec godot tests/scale.tscn'  # no display
```

Needs a window and a window manager, not a GPU. Without a window manager X11 never
goes fullscreen and a window has no title bar, and the harness fails on "the window
went fullscreen first". Sizes the window to every factor up to 4 that fits the
screen, in windowed mode, and at each one asserts:

- the window is windowed, exactly the game size times the factor, and on its screen and
  centred on it with its title bar. Size means both `Window.size` and the size the
  content is drawn at: the integer stretch letterboxes a window that is no whole
  multiple, so a 1000x600 window draws 960x540, and only the two together prove the
  multiple
- the root viewport is still 320x180, and the frame renders at the window size
- the shader offset reaches the screen in exactly `factor` distinct steps per game
  pixel, and every game pixel is `factor` x `factor` screen pixels, along rows and
  along columns
- a mouse event at a window pixel arrives on the root divided by the factor

Then that a factor of 0 clamps to x1, one past the screen clamps to the largest that
fits and keeps its title bar on the screen, `=`, `+` and `-` step up and down, also
while the game is paused, while Ctrl+= does nothing; a key snaps a window of no whole
multiple back to one and `=` leaves a window bigger than fits alone; and from a
window that really is fullscreen both x2 and one past the largest come back windowed,
at the right size, title bar on the screen. At startup it waits for `WindowScale` to
settle, then checks the window is on its screen, a whole multiple of the game, with
the right factor, and with
`scale=N` that it started at N, clamped to what fits. It also runs from a fullscreen
start, `godot -f`.

Measured under `xvfb-run` on Mesa llvmpipe with Openbox: x1 to x4 all pass on a
1920x1080 screen, steps/pixel 1, 2, 3, 4; on 1024x768 the 1280x720 start shrinks to
x3 and x1 to x3 pass. CI runs both screens, plus `scale=2`, `scale=9`, a malformed
`scale=`, `scale=0`, `--resolution 1000x600`, and a fullscreen start with and without
`scale=9`, and `mouse.tscn` on both screens, under
`timeout` rather than `--quit-after`: `--quit-after` exits 0, so a harness that stalls
before its report would pass. It starts Godot only once Openbox has claimed the
screen, and where the harness resizes the window itself, not through `WindowScale`,
it waits until Openbox has framed the new size before pressing a key. Measured: 42
runs, six at a time on one machine, all pass; before that wait and the stale-reading
bound below, 5 in about 40 failed.

The title-bar checks read the frame from the engine,
`DisplayServer.window_get_position_with_decorations()` and
`get_size_with_decorations()`, not from `WindowScale`, so they cannot agree with a
wrong guess in the script they check.

The sub-pixel probes sit at `(i + 0.5) / (4 * factor)` of a game pixel, so no probe
puts an edge exactly on a screen pixel centre. `diagnose.tscn` sweeps in sixteenths,
which does land on those ties at x4, and a software rasteriser breaks ties differently
from a GPU: under `xvfb-run` it reads 7 of 4. This harness reads the same quantity
without the ties, which is why it can run in CI.

Every check was seen to fail on a deliberately broken copy of the project:

- the window not resized
- `viewport` stretch: steps/pixel 1 at every factor
- fullscreen not left
- the keys rebound, or bound by key position instead of by label
- the keys not matched exactly
- the title bar left out of the fit, or the fit wrong by any amount
- the window placed without the client offset, off centre by the title bar
- a window of no whole multiple not snapped at an end, or `=` shrinking a window
  bigger than fits
- the title bar measured fresh after fullscreen instead of cached, caught on the runs
  where that fresh reading is zero, which is most of them
- a title bar taken from a reading mid-resize. That race does not come up on demand,
  so the harness checks `is_frame_reading` on the readings measured when it did:
  `Window.size` 320x180 against a decorated 640x360, with no window manager
- a title bar taken from a frame left by a resize `WindowScale` did not make: 320x180
  against 1922x1101 under Openbox, which capped `=` at x1
- a reading small enough for a title bar taken before `Window.size` has the size asked
  for
- a malformed `scale=` read as 0
- no refit once the title bar is first measured
- no snap for a start at a size that is no multiple
- the container stretched 1.5x vertically only
- the autoload paused with the game

The expected factors are worked out in the harness, from the engine's own frame and
the size the window opened at, never asked of `WindowScale`, so a wrong fit in the
script cannot agree with itself.

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

### `tests/scale.tscn`

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/main.tscn" id="1_scale"]
[ext_resource type="Script" path="res://tests/scale.gd" id="2_scale"]

[node name="ScaleRoot" type="Node"]

[node name="SubViewportContainer" parent="." instance=ExtResource("1_scale")]

[node name="Scale" type="Node" parent="." node_paths=PackedStringArray("container")]
script = ExtResource("2_scale")
container = NodePath("../SubViewportContainer")
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

### `tests/scale.gd`

Needs a window and a window manager; Xvfb with Openbox is enough. Sizes the window to
x1, x2, x3 and x4 and checks each on real rendered frames. It calls the `WindowScale`
autoload from `camera.md`.

```gdscript
class_name Scale extends Node

# Sizes the window to every integer factor up to 4 that fits the screen, x1 x2 x3 x4,
# in windowed mode, and checks each on real rendered frames:
#   godot tests/scale.tscn
# Needs a real window and a window manager, which is what makes a window fullscreen
# and gives it a title bar. Xvfb with Openbox is enough:
#   xvfb-run -a sh -c 'openbox & until xprop -root _NET_SUPPORTING_WM_CHECK |
#     grep -q "window id"; do sleep 0.2; done; exec godot tests/scale.tscn'
# Silent with exit 0 is a pass; each failure is printed with printerr and the run
# exits 1.
#
# The sub-pixel probes sit between screen pixel boundaries, never on one. An offset
# that puts an edge exactly on a pixel centre is a rasteriser tie, and a software
# rasteriser breaks ties differently from a GPU.

const FACTORS: Array[int] = [1, 2, 3, 4]
const PROBES_PER_SCREEN_PIXEL: int = 4
# How long a window manager may take to apply a new size, in frames.
const RESIZE_FRAMES: int = 60
const CAMERA_POSITION: Vector2 = Vector2(40.0, 120.0)

@export_category("Nodes")
@export var container: SubViewportContainer

var _failures: Array[String] = []
var _material: ShaderMaterial = null
var _event_position: Vector2 = Vector2.ZERO
var _started: bool = false


func _ready() -> void:
	assert(container, "scale.gd - @export container is not set in the editor on: " + self.name)


# The position the game actually receives for an injected event.
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
	var camera: PixelCamera = Global.camera
	if !camera:
		printerr("FAIL  the camera never registered with Global")
		get_tree().quit(1)
		return
	camera.set_physics_process(false)
	camera.global_position = CAMERA_POSITION
	if Global.player:
		Global.player.set_physics_process(false)
	_material = container.material as ShaderMaterial

	# A window sized before the window manager framed it is fitted again once it has.
	await WindowScale.wait_until_settled()
	if get_window().mode == Window.MODE_WINDOWED:
		await _wait_until_shown(WindowScale.game_size() * WindowScale.factor)
	_check_startup()
	var start_factor: int = WindowScale.factor
	# From a fullscreen start the title bar is not measured until the window is back.
	if get_window().mode != Window.MODE_WINDOWED:
		var _windowed: int = WindowScale.set_factor(start_factor)
		await WindowScale.wait_until_settled()
	var max_factor: int = _expected_max()
	_check("the screen fits at least x2", max_factor >= 2, "max x%d" % max_factor)
	_check(
		"the largest factor is x%d, the largest whose frame fits" % max_factor,
		WindowScale.max_factor() == max_factor,
		"WindowScale says x%d" % WindowScale.max_factor()
	)

	for factor: int in FACTORS:
		if factor > max_factor:
			continue
		await _check_factor(factor)

	_check(
		"after every resize the largest factor is still x%d" % max_factor,
		WindowScale.max_factor() == max_factor,
		"WindowScale says x%d" % WindowScale.max_factor()
	)
	_check_clamped(0, 1)
	_check_clamped(max_factor + 1, max_factor)
	_check_frame_readings()
	await _check_largest_fits(max_factor)
	if max_factor >= 2:
		await _check_keys(max_factor)
	await _check_leaves_fullscreen(max_factor)
	var _restored: int = WindowScale.set_factor(start_factor)
	_material.set_shader_parameter(&"cam_offset", Vector2.ZERO)

	for failure: String in _failures:
		printerr("FAIL  %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_startup() -> void:
	var window: Window = get_window()
	var windowed: bool = window.mode == Window.MODE_WINDOWED
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	var game: Vector2 = Vector2(WindowScale.game_size())
	# Worked out here from the engine and the command line, not asked of WindowScale.
	var expected: int = 0
	# The first whole-number scale= counts; a malformed one only names the run.
	var asked: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if !argument.begins_with("scale="):
			continue
		var value: String = argument.trim_prefix("scale=")
		if value.is_valid_int():
			asked = value
			break
		if asked.is_empty():
			asked = value
	if asked.is_valid_int():
		expected = clampi(asked.to_int(), 1, _expected_max())
	elif windowed:
		# The window opens at --resolution, or the project's size, shrunk to fit and
		# snapped to a whole multiple. A malformed scale= changes nothing.
		var opened: Vector2 = Vector2(WindowScale.opened_size)
		var whole: Vector2 = (opened / game).floor()
		expected = clampi(int(minf(whole.x, whole.y)), 1, _expected_max())
	else:
		# Fullscreen, the factor is the project window's, if it fits the screen; the
		# title bar is not known yet.
		var width: int = ProjectSettings.get_setting("display/window/size/window_width_override", 0)
		var height: int = ProjectSettings.get_setting("display/window/size/window_height_override", 0)
		var project_fit: Vector2 = (Vector2(width, height) / game).floor()
		var screen_fit: Vector2 = (Vector2(usable.size) / game).floor()
		expected = mini(maxi(1, int(minf(project_fit.x, project_fit.y))), int(minf(screen_fit.x, screen_fit.y)))
	var label: String = "scale=%s" % asked if !asked.is_empty() else "the start"
	_check("%s gives x%d" % [label, expected], WindowScale.factor == expected, "factor x%d" % WindowScale.factor)
	if !windowed:
		return
	_check(
		"%s opens a window of exactly x%d" % [label, expected],
		_shown_size() == WindowScale.game_size() * expected,
		"window %s" % _shown()
	)
	_check(
		"the starting window, title bar included, lies on its screen",
		usable.encloses(_frame_rect()),
		"frame %s, screen %s" % [_frame_rect(), usable]
	)


# The largest factor whose window and the frame the window manager draws around it fit
# the screen, from the engine's own frame. Needs a window, not fullscreen.
func _expected_max() -> int:
	var window: Window = get_window()
	var decorations: Vector2i = window.get_size_with_decorations() - window.size
	var usable: Vector2i = DisplayServer.screen_get_usable_rect(window.current_screen).size
	var fit: Vector2 = (Vector2(usable - decorations) / Vector2(WindowScale.game_size())).floor()
	return maxi(1, int(minf(fit.x, fit.y)))


func _check_factor(factor: int) -> void:
	var label: String = "x%d" % factor
	var applied: int = WindowScale.set_factor(factor)
	_check("%s is applied, not clamped" % label, applied == factor, "applied x%d" % applied)
	var window: Window = get_window()
	var expected: Vector2i = WindowScale.game_size() * factor
	await _wait_until_shown(expected)

	_check("%s window is windowed, not fullscreen" % label, window.mode == Window.MODE_WINDOWED, str(window.mode))
	_check("%s window is %s" % [label, expected], _shown_size() == expected, "got %s" % _shown())
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	_check(
		"%s window, title bar included, lies on its screen" % label,
		usable.encloses(_frame_rect()),
		"frame %s, screen %s" % [_frame_rect(), usable]
	)
	# Rounding puts the centre at most a pixel off.
	var off_centre: Vector2i = (_frame_rect().get_center() - usable.get_center()).abs()
	_check(
		"%s window, title bar included, is centred on its screen" % label,
		off_centre.x <= 1 and off_centre.y <= 1,
		"frame %s, screen %s" % [_frame_rect(), usable]
	)
	_check("%s factor reads back from the window" % label, WindowScale.current_factor() == factor)
	var visible: Vector2 = get_viewport().get_visible_rect().size
	_check(
		"%s root viewport stays the game size" % label, visible == Vector2(WindowScale.game_size()), "got %v" % visible
	)

	var image: Image = await _render(Vector2.ZERO)
	_check("%s renders at %s" % [label, expected], image.get_size() == expected, "got %s" % image.get_size())

	await _check_steps(label, factor)
	await _check_mouse(label, factor, expected)


# One distinct picture per screen pixel the shader can slide across: the sub-pixel
# offset still reaches the screen at every factor, and x1 has nothing to slide into.
# Every picture is also an exact integer upscale.
func _check_steps(label: String, factor: int) -> void:
	var probes: int = PROBES_PER_SCREEN_PIXEL * factor
	var previous: PackedByteArray = PackedByteArray()
	var distinct: int = 0
	var uneven: Array[String] = []
	for probe: int in probes:
		var offset: float = (float(probe) + 0.5) / float(probes)
		var image: Image = await _render(Vector2(offset, 0.0))
		var data: PackedByteArray = image.get_data()
		if probe > 0 and data != previous:
			distinct += 1
		previous = data
		# At x1 every run is a multiple of 1, so there is nothing to check.
		if factor > 1 and probe % PROBES_PER_SCREEN_PIXEL == 0 and !_runs_are_square(image, factor):
			uneven.append("%.3f" % offset)
	_check("%s steps/pixel is %d" % [label, factor], distinct == factor, "got %d" % distinct)
	_check("%s every game pixel is %dx%d screen pixels" % [label, factor, factor], uneven.is_empty(), ", ".join(uneven))


func _check_mouse(label: String, factor: int, window_size: Vector2i) -> void:
	var corner: Vector2 = Vector2(window_size) - Vector2.ONE
	for window_pixel: Vector2 in [Vector2.ZERO, Vector2(window_size) * 0.5, corner]:
		var root_position: Vector2 = await _point_at(window_pixel)
		var expected: Vector2 = window_pixel / float(factor)
		_check(
			"%s window %v arrives in game pixels as %v" % [label, window_pixel, expected],
			root_position.is_equal_approx(expected),
			"got %v" % root_position
		)


# - and = step the factor down and up, from the size the window really has.
func _check_keys(max_factor: int) -> void:
	var game: Vector2i = WindowScale.game_size()
	var _start: int = WindowScale.set_factor(1)
	await _wait_until_shown(game)
	await _press(KEY_EQUAL)
	await _wait_until_shown(game * 2)
	_check("= steps x1 up to x2", _shown_size() == game * 2, "window %s" % _shown())
	await _press(KEY_MINUS)
	await _wait_until_shown(game)
	_check("- steps x2 down to x1", _shown_size() == game, "window %s" % _shown())
	await _press(KEY_EQUAL, true)
	await _wait_for(func() -> bool: return false)
	_check("Ctrl+= is left for the game", _shown_size() == game, "window %s" % _shown())
	await _press(KEY_EQUAL, false, true)
	await _wait_until_shown(game * 2)
	_check("+, Shift+=, steps x1 up to x2", _shown_size() == game * 2, "window %s" % _shown())
	await _press(KEY_MINUS)
	await _wait_until_shown(game)
	# A layout with its own + key, German for one: there + is no Shift+=.
	await _press(KEY_PLUS)
	await _wait_until_shown(game * 2)
	_check("+ on its own key steps x1 up to x2", _shown_size() == game * 2, "window %s" % _shown())
	get_tree().paused = true
	await _press(KEY_MINUS)
	await _wait_until_shown(game)
	get_tree().paused = false
	_check("- works while the game is paused", _shown_size() == game, "window %s" % _shown())

	# Something else leaves the window at no whole multiple: a key snaps it back, even
	# - at x1, where there is nothing smaller to step to.
	var window: Window = get_window()
	var decorations: Vector2i = window.get_size_with_decorations() - window.size
	window.size = game + Vector2i(80, 20)
	await _wait_until_framed(game + Vector2i(80, 20), decorations)
	_check(
		"the window manager applies a window of no whole multiple",
		WindowScale.current_factor() == 1 and window.size == game + Vector2i(80, 20),
		"window %s" % _shown()
	)
	await _press(KEY_MINUS)
	await _wait_until_shown(game)
	_check("- at x1 snaps a window of no whole multiple to x1", _shown_size() == game, "window %s" % _shown())

	# Something else makes the window bigger than fits: = leaves it, - brings it back.
	var oversized: Vector2i = game * (max_factor + 1)
	window.size = oversized
	await _wait_until_framed(oversized, decorations)
	_check(
		"the window manager allows an oversized window",
		_shown_size() == oversized and WindowScale.current_factor() == max_factor + 1,
		"window %s" % _shown()
	)
	await _press(KEY_EQUAL)
	await _wait_for(func() -> bool: return false)
	_check("= does not shrink a window bigger than fits", _shown_size() == oversized, "window %s" % _shown())
	await _press(KEY_MINUS)
	await _wait_until_shown(game * max_factor)
	_check(
		"- brings a window bigger than fits back to x%d" % max_factor,
		_shown_size() == game * max_factor,
		"window %s" % _shown()
	)


# Asking for a factor from fullscreen drops back to a window of exactly that size, and
# asking for too much from fullscreen still keeps the title bar on the screen.
func _check_leaves_fullscreen(max_factor: int) -> void:
	var window: Window = get_window()
	var decorations: Vector2i = window.get_size_with_decorations() - window.size
	for asked: int in [2, max_factor + 1]:
		await _go_fullscreen()
		var applied: int = WindowScale.set_factor(asked)
		var expected: Vector2i = WindowScale.game_size() * mini(asked, max_factor)
		await _wait_until_shown(expected)
		# Waits for the title bar too, in case a window manager frames it after the size.
		await _wait_for(func() -> bool: return window.get_size_with_decorations() - window.size == decorations)
		var label: String = "x%d from fullscreen" % asked
		_check("%s is windowed" % label, window.mode == Window.MODE_WINDOWED, str(window.mode))
		_check("%s is %s" % [label, expected], _shown_size() == expected, "got %s, applied x%d" % [_shown(), applied])
		var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
		_check(
			"%s lies on its screen with its title bar" % label,
			usable.encloses(_frame_rect()),
			"frame %s, screen %s" % [_frame_rect(), usable]
		)


# Waits until the window really covers the screen, not just until mode reads back,
# which it does at once.
func _go_fullscreen() -> void:
	var window: Window = get_window()
	window.mode = Window.MODE_FULLSCREEN
	var screen: Vector2i = DisplayServer.screen_get_size(window.current_screen)
	await _wait_for(func() -> bool: return window.size == screen)
	_check(
		"the window went fullscreen first (no window manager running?)",
		window.size == screen,
		"got %s, screen %s" % [_shown(), screen]
	)


# The largest factor still keeps the title bar and borders on the screen.
func _check_largest_fits(max_factor: int) -> void:
	var window: Window = get_window()
	await _wait_until_shown(WindowScale.game_size() * max_factor)
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	_check(
		"x%d, the largest, lies on its screen with its title bar" % max_factor,
		usable.encloses(_frame_rect()),
		"frame %s, screen %s" % [_frame_rect(), usable]
	)


# The title bar is measured only from a window that has finished resizing. The race
# that breaks this does not come up on demand, so the rule is checked on the readings
# measured when it did: with no window manager, Window.size still 320x180 and the
# decorated size already 640x360.
func _check_frame_readings() -> void:
	var mid_resize: bool = WindowScale.is_frame_reading(Vector2i(320, 180), Vector2i(640, 360), Vector2i(640, 360))
	_check("a reading taken mid-resize is not a title bar", !mid_resize)
	var framed: bool = WindowScale.is_frame_reading(Vector2i(640, 360), Vector2i(642, 381), Vector2i(640, 360))
	_check("Openbox's 2x21 frame, once resized, is a title bar", framed)
	var bare: bool = WindowScale.is_frame_reading(Vector2i(640, 360), Vector2i(640, 360), Vector2i(640, 360))
	_check("no window manager reads as no title bar", !bare)
	# Under Openbox, after a resize WindowScale did not ask for.
	var stale: bool = WindowScale.is_frame_reading(Vector2i(320, 180), Vector2i(1922, 1101), Vector2i(320, 180))
	_check("a frame left from a resize nobody asked for is not a title bar", !stale)
	# Small enough for a title bar, but Window.size is not yet the size asked for.
	var early: bool = WindowScale.is_frame_reading(Vector2i(320, 180), Vector2i(342, 201), Vector2i(640, 360))
	_check("a reading before the window has the size asked for is not a title bar", !early)


func _check_clamped(asked: int, expected: int) -> void:
	var applied: int = WindowScale.set_factor(asked)
	_check("x%d is clamped to x%d" % [asked, expected], applied == expected, "applied x%d" % applied)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	var line: String = label
	if !detail.is_empty():
		line = "%s  (%s)" % [label, detail]
	_failures.append(line)


# Presses the key whose label is keycode, so the layout does not matter.
func _press(keycode: Key, ctrl: bool = false, shift: bool = false) -> void:
	for pressed: bool in [true, false]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = keycode
		key.ctrl_pressed = ctrl
		key.shift_pressed = shift
		key.pressed = pressed
		Input.parse_input_event(key)
		await get_tree().process_frame


# The window's size and the size its content is drawn at, as "WxH drawn WxH". The
# integer stretch draws at the largest whole multiple and letterboxes the rest, so the
# two agree only on a window that is a whole multiple of the game.
func _shown() -> String:
	return "%s drawn %s" % [get_window().size, get_viewport().get_texture().get_image().get_size()]


# The window's size when its content is drawn at exactly that size, which only a whole
# multiple of the game is; (-1, -1) otherwise.
func _shown_size() -> Vector2i:
	var window: Vector2i = get_window().size
	return window if get_viewport().get_texture().get_image().get_size() == window else Vector2i(-1, -1)


# Waits until condition is true, or RESIZE_FRAMES frames.
func _wait_for(condition: Callable) -> void:
	for _frame: int in RESIZE_FRAMES:
		var met: bool = condition.call()
		if met:
			return
		await get_tree().process_frame


# Waits until the window manager has applied a size Godot did not choose through
# WindowScale: the window and its frame both read it, three frames running.
func _wait_until_framed(expected: Vector2i, decorations: Vector2i) -> void:
	var window: Window = get_window()
	var steady: int = 0
	for _frame: int in RESIZE_FRAMES:
		var framed: bool = window.size == expected and window.get_size_with_decorations() == expected + decorations
		steady = steady + 1 if framed else 0
		if steady == 3:
			return
		await get_tree().process_frame


func _wait_until_shown(expected: Vector2i) -> void:
	await _wait_for(func() -> bool: return _shown_size() == expected)


# The window manager's frame as the engine reports it, title bar included.
func _frame_rect() -> Rect2i:
	var window: Window = get_window()
	var corner: Vector2i = DisplayServer.window_get_position_with_decorations(window.get_window_id())
	return Rect2i(corner, window.get_size_with_decorations())


func _render(offset: Vector2) -> Image:
	_material.set_shader_parameter(&"cam_offset", offset)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# Injects a motion event at a window pixel and returns the root-viewport position
# the game sees for it.
func _point_at(window_pixel: Vector2) -> Vector2:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = window_pixel
	motion.global_position = window_pixel
	# A sentinel no probe can arrive as, so an event that never arrives cannot pass.
	_event_position = Vector2(-1.0, -1.0)
	Input.parse_input_event(motion)
	await get_tree().process_frame
	return _event_position


# Every run of identical colour along a row or a column is a multiple of the factor,
# except the two runs each line's ends cut off. Columns start below the debug label,
# which is UI at native resolution, not game pixels.
func _runs_are_square(image: Image, factor: int) -> bool:
	var size: Vector2i = image.get_size()
	for row: int in range(int(float(size.y) * 0.55), int(float(size.y) * 0.95), 3 * factor):
		if !_line_is_square(image, factor, Vector2i(0, row), Vector2i.RIGHT, size.x):
			return false
	var top: int = int(float(size.y) * 0.25)
	for column: int in range(0, size.x, 7 * factor):
		if !_line_is_square(image, factor, Vector2i(column, top), Vector2i.DOWN, size.y - top):
			return false
	return true


func _line_is_square(image: Image, factor: int, start: Vector2i, step: Vector2i, length: int) -> bool:
	var run: int = 1
	var run_start: int = 0
	var previous: Color = image.get_pixelv(start)
	for along: int in range(1, length):
		var current: Color = image.get_pixelv(start + step * along)
		if current == previous:
			run += 1
			continue
		if run_start > 0 and run % factor != 0:
			return false
		run = 1
		run_start = along
		previous = current
	return true
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
# How long a window manager may take to apply a new size, in frames.
const RESIZE_FRAMES: int = 60
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

	# The probes are window pixels of a 1280x720 window. WindowScale shrinks the window
	# on a screen that cannot show it with its title bar; the window manager may still
	# allow it. Waits for WindowScale first, so it cannot resize the window mid-run.
	await WindowScale.wait_until_settled()
	var window: Window = get_window()
	var expected: Vector2i = Vector2i(GAME_SIZE * 4.0)
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	window.size = expected
	window.position = (usable.position + Vector2i(Vector2(usable.size - expected) * 0.5)).max(usable.position)
	# Both the window and the content drawn in it, which the integer stretch letterboxes
	# to a whole multiple: a bigger window would shift the probes off the content.
	for _frame: int in RESIZE_FRAMES:
		if window.size == expected and get_viewport().get_texture().get_image().get_size() == expected:
			break
		await get_tree().process_frame
	if window.size != expected or get_viewport().get_texture().get_image().get_size() != expected:
		printerr("FAIL  the window manager would not make the window the 1280x720 the probes are in")
		get_tree().quit(1)
		return

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
