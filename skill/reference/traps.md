# Traps and measurements

Why the settings in `../SKILL.md` are what they are, what breaks when they are not,
and the numbers behind every claim.

All measurements taken on Godot 4.7.2, a 320x180 game in a 1280x720 window, on a
Hyprland desktop with three monitors (two at 59.95Hz, one at 143.98Hz) and an NVIDIA
GPU on Vulkan.

## Geometry, and why the numbers are those numbers

Get these numbers right and everything else follows.

| Thing | Value | Why |
|---|---|---|
| Game area | 320 x 180 | what the player sees |
| SubViewport | **322 x 182** | one pixel of slack on every side |
| Container rect | left -1, top -1, right 321, bottom 181 | 322 x 182, positioned at -1,-1 |
| Container scale | **1, 1** | the window stretch does the scaling |
| Base viewport | **320 x 180** | same as the game area |
| Window | 1280 x 720 | 4x, an integer factor |

Read the container offsets carefully. Width is `321 - (-1) = 322`. Height is
`181 - (-1) = 182`. Position is `-1, -1`, so the extra row and column sit just off
screen at the top and left. There is a matching spare pixel at the right and bottom
because 322 is two wider than 320.

The camera's `anchor_mode` is Drag Center, so it centres on the 322x182 viewport at
`161, 91`. Both are whole numbers because 322 and 182 are even. **Keep the SubViewport
dimensions even.** An odd size puts the camera centre on a half pixel forever.

---

## Project settings, in full

Complete and measured. `project.godot`:

```ini
[application]

config/name="Pixel Perfect Camera"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")

[autoload]

Global="*res://scripts/global.gd"

[display]

; Base viewport IS the game size. Not doubled.
window/size/viewport_width=320
window/size/viewport_height=180
window/size/resizable=false
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/stretch/scale_mode="integer"

[rendering]

textures/canvas_textures/default_texture_filter=0
; Root viewport must NOT snap, or it rounds away the shader offset.
; Snapping goes on the SubViewport node instead.
2d/snap/snap_2d_vertices_to_pixel=false
```

Line by line.

- **`viewport_width/height = 320x180`.** The base viewport is the game size. The
  container therefore needs no scale of its own.
- **`resizable=false`.** Not cosmetic. See the tiling window manager trap below.
- **`window_width/height_override = 1280x720`.** The window the editor opens. Exactly
  4x the base.
- **`stretch/mode="canvas_items"`.** The important one, and **not** what the official
  pixel-art page recommends. See the next heading.
- **`stretch/scale_mode="integer"`.** The window only scales by whole numbers, so
  pixels never come out uneven.
- **`default_texture_filter=0`.** Nearest. See the Nearest filter section.
- **`snap_2d_vertices_to_pixel=false`.** On the *root* viewport. See the snapping trap below.

`window/stretch/aspect` is left alone. Its default is already `keep`, and Godot strips
default values when it rewrites `project.godot`, so writing it in has no effect.

### Why `canvas_items` and not `viewport`

The official docs say: use `viewport` stretch mode with `integer` scale mode. For a
plain pixel-art game that is right. For **this** technique it throws away half the
smoothness, and that is what makes a correct camera still feel juddery.

`stretch/mode="viewport"` renders the whole frame at the base size, then upscales the
finished image to the window. The root viewport really is only 640x360 pixels (in the
old two-repo layout). The sub-pixel shader offset is applied to a quad **inside** that
root viewport, so it is rasterised at 640x360. One game pixel is 2 root pixels wide
there. The offset can land on 2 positions per game pixel and no more.

`stretch/mode="canvas_items"` keeps the same logical coordinate space but rasterises
at the **native window resolution**. One game pixel is 4 screen pixels at 1280x720, so
the offset lands on 4 positions per game pixel.

**Measured.** `tests/diagnose.tscn` sweeps `cam_offset` from 0 to 1 game pixel in
sixteenths and counts visually distinct frames. Window 1280x720, game 320x180, so 4 is
the ceiling.

| Configuration | Rasterised at | Steps per game pixel |
|---|---|---|
| `viewport` stretch, base 640x360, container scale 2 | 640x360 | **2** of 4 |
| same, root vertex snapping off | 640x360 | 3 of 4 |
| same, plus transform *and* vertex snapping on the root | 640x360 | **2** of 4 |
| **`canvas_items`, base 320x180, container scale 1** | **1280x720** | **4 of 4** |

Both repos use the first row.

The same tool walks every scanline and measures how wide each run of identical colour
is. Under `canvas_items` every run is a multiple of 4 except one partial column at the
very edge of the screen — that is the hidden 1px border doing its job, not a defect.

### The bonus of `canvas_items`

Under `canvas_items` the UI on the `CanvasLayer` is rendered at native resolution too.
Text comes out crisp over a chunky pixel world. Under `viewport` stretch, everything
including the UI is drawn at the base size and blown up.

### Optional, unrelated to the camera

```ini
[rendering]
environment/defaults/default_clear_color=Color(0.09, 0.1, 0.13, 1)

[layer_names]
2d_physics/layer_1="world"
2d_physics/layer_2="player"
```

Naming the physics layers is what makes `collision_mask = 2` in the camera trigger
readable as "the player".

---

## Nearest filter — set it in two places

"Nearest" means no blur when a texture is scaled. It is the single most important
setting for pixel art. Miss one of these and part of your game goes soft.

**1. Project-wide default.**

```ini
[rendering]
textures/canvas_textures/default_texture_filter=0
```

`0` is Nearest. Every `CanvasItem` inherits it.

**2. The SubViewport node.**

```
canvas_item_default_texture_filter = 0
```

A `SubViewport` does **not** inherit the project default. It has its own. Set it, or
your entire game render is blurry while the UI stays sharp.

**3. Per node, only if you ever override.** `CanvasItem.texture_filter`. Leave it on
`Inherit` for pixel sprites.

There is **no filter setting in the `.import` file**. Filtering is not an import
property in Godot 4. It comes only from these three places.

---

## Texture import settings

Every PNG. From `sprites/player.png.import`:

```ini
[params]
compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
```

The three that matter:

- **`compress/mode=0`** — Lossless. VRAM compression destroys pixel art.
- **`mipmaps/generate=false`** — Mipmaps are downscaled copies. You never downscale
  pixel art, so they waste memory and can bleed.
- **`process/fix_alpha_border=true`** — Fills the RGB of fully transparent pixels with
  the neighbouring colour. Stops dark halos on sprite edges.

Set these once in the Import dock and press **Set as Default for 'Texture'**.

### A word on test art

Do not use a 2-pixel checkerboard or scattered single-pixel stars as a background
while you are evaluating smoothness. A pattern with a period near the pixel grid
moirés under any sub-pixel motion and makes a perfectly correct camera look broken.
Use art with 8px-or-larger features and high-contrast vertical edges instead.

---

## Scene tree, in full

`scenes/main.tscn`, the main scene:

```
SubViewportContainer          <- root, owns the shader material
├── CanvasLayer               <- UI, OUTSIDE the pixel viewport, native resolution
│   └── DebugLabel
├── SubViewport               <- the 322x182 game render
│   ├── World                 <- world.tscn instance
│   │   ├── Background
│   │   ├── Ground
│   │   ├── Cameras
│   │   │   ├── CameraTriggerLeft
│   │   │   └── CameraTriggerRight
│   │   └── Player
│   └── PixelCamera           <- Camera2D, script pixel_camera.gd
```

`World` comes before `PixelCamera`, so the player's `_ready` runs first. The camera
does not rely on that — it takes an `@export` reference — but the ordering costs
nothing.

### SubViewportContainer (root)

```
material      = ShaderMaterial (shaders/viewport.gdshader)
                shader_parameter/cam_offset = Vector2(0, 0)
offset_left   = -1.0
offset_top    = -1.0
offset_right  = 321.0
offset_bottom = 181.0
```

**Leave `scale` at (1, 1).** With a base viewport of 320x180 the window stretch
already does the scaling. The common setup sets `scale = (2, 2)` here, which only
works because its base viewport is 640x360 — the arrangement measured as half as
smooth in 3.1.

`stretch` is left off. The SubViewport draws at its own size.

### SubViewport

```
disable_3d                         = true
handle_input_locally               = false
canvas_item_default_texture_filter = 0      (Nearest)
snap_2d_vertices_to_pixel          = true
audio_listener_enable_2d           = true
size                               = Vector2i(322, 182)
render_target_update_mode          = 4      (Always)
```

322x182, not 320x180. That is the whole trick.

`snap_2d_vertices_to_pixel = true` **on this node**, not in project settings. The game
content snaps to the grid; the container in the root viewport must not.

### PixelCamera

```
[node name="PixelCamera" type="Camera2D" parent="SubViewport"
  node_paths=PackedStringArray("viewport_container", "initial_target")]
script = ExtResource("pixel_camera.gd")
viewport_container = NodePath("../..")
initial_target = NodePath("../World/Player")
```

No `anchor_mode` in the scene. It stays at the default **Drag Center**, so the camera
centres on its target. `anchor_mode = 0` (Fixed Top Left) is fine only for a camera
that never moves.

References are `@export` node paths, not hardcoded `get_node("A/B/C")` strings. Rename
a node and the editor fixes the path for you.

---

## The shader

`shaders/viewport.gdshader`. Four lines. This is the entire trick.

```glsl
shader_type canvas_item;

// Sub-pixel offset written every frame by PixelCamera.
// The SubViewport renders 1px larger on each side, so shifting the whole
// image by up to half a pixel never exposes a gap.
uniform vec2 cam_offset = vec2(0.0, 0.0);

void vertex() {
	VERTEX += cam_offset;
}
```

`VERTEX` is in the container's local space, where one unit is one game pixel. The
uniform is set to `round(position) - position`, which is in the range -0.5 to +0.5.

It runs in `vertex()`, so it costs nothing. It moves four corners, not 58,000 pixels.

### The sign

The camera is drawn at `round(C)`. You want the picture to look as if the camera were
at the true float position `C`. Moving the camera right moves the image left, so:

```
image shift = round(C) - C
```

Which is exactly the uniform. Get the sign backwards and motion looks doubled and
wrong.

---

## The traps

### Trap: snapping on the root viewport eats the shader offset

There are two snap settings, and one place they must not be applied.

- `snap_2d_vertices_to_pixel` — rounds the **vertices** of a drawn quad.
- `snap_2d_transforms_to_pixel` — rounds the whole node **transform**.

Both are project-wide. Project-wide includes the **root** viewport, and the
`SubViewportContainer` lives in the root viewport. Its quad is the thing your shader
nudges by a fraction of a pixel. Snapping rounds that nudge away.

Set them per-viewport instead:

```ini
; project.godot - root viewport, no snapping
2d/snap/snap_2d_vertices_to_pixel=false
2d/snap/snap_2d_transforms_to_pixel=false
```

```
# the SubViewport node, in the scene
snap_2d_vertices_to_pixel = true
```

`Viewport` exposes both as node properties. Use them.

### Trap: transform snapping breaks particles

`snap_2d_transforms_to_pixel` has an open engine bug,
**[godot#98764](https://github.com/godotengine/godot/issues/98764)**: particles (CPU or
GPU) jitter when they move by non-integer amounts inside a SubViewport with transform
snapping on. Confirmed, reported November 2024, still open.

If you have transform snapping on, render inside a SubViewport, and emit particles on
hit, this is you.

You lose nothing by turning it off. The camera already rounds itself, and vertex
snapping handles the sprites.

### Trap: a tiling window manager will resize your window

If `window/size/resizable` is left at its default of `true`, a tiling window manager
gives your window whatever size the tile happens to be.

Measured on Hyprland: the build described here opened at **941x1150** instead of
1280x720.
With `scale_mode="integer"` and that size, the integer factor drops from 4 to 1. The
game renders postage-stamp sized in the corner of a tall window.

```ini
window/size/resizable=false
```

Omit it and the game can look broken on the very first run, for this reason alone.

### Trap: physics interpolation

Neither repo uses it. Keep it that way.

**What it is.** Physics runs on a fixed tick. Rendering runs as fast as your monitor.
Physics interpolation stores each node's previous and current transform and draws it
partway between them. Built in since Godot 4.3.

```
Project Settings > Physics > Common > Physics Interpolation
```

**Why it breaks this camera.** The rounding is the entire point of the technique.
Interpolation would draw the camera at a *fraction* between two rounded positions.
That fraction is precisely what the shader already applies. You would apply it twice.

There is a second reason if your camera is still in `_process`. The docs are blunt:

> *"If you attempt to set the transform of interpolated objects outside the physics
> tick, the calculations for the interpolated position will be incorrect, and you will
> get jitter."*

**Four open engine bugs**, even with the camera correctly in `_physics_process`:

| Issue | Problem |
|---|---|
| [godot#95869](https://github.com/godotengine/godot/issues/95869) | Camera2D position smoothing runs faster with interpolation on, at the same speed setting. Only above 60Hz. Confirmed, open. |
| [godot#92875](https://github.com/godotengine/godot/issues/92875) | Camera2D interpolates wrongly when the viewport aspect ratio changes. Jelly wobble on resize. |
| [godot#101195](https://github.com/godotengine/godot/issues/101195) | Enabling interpolation at runtime makes Camera2D stop scrolling entirely. |
| [godot#97957](https://github.com/godotengine/godot/issues/97957) | Setting a Camera2D's `physics_interpolation_mode` to `Off` spams `Parameter 'data.tree' is null` in the editor and at runtime. |

That last one kills the obvious workaround. You cannot cleanly opt the camera out
per-node.

**What to do instead.** Nothing. The default is off. This technique already updates
the camera every physics tick, coherently with everything it follows.

### Trap: frame rate on a multi-monitor Wayland desktop

Measured on Hyprland with three monitors (two at 59.95Hz, one at 143.98Hz), NVIDIA,
Vulkan:

| Condition | Frame rate |
|---|---|
| Window visible and focused, any monitor | **60.0 fps** |
| Window on a monitor you are not looking at, occluded | **13–15 fps**, reproducible |
| Window moved between monitors at runtime | erratic, 14–112 fps |

The low numbers are the compositor throttling frame callbacks to an unfocused or
occluded surface. They are not a game bug — an empty scene with no SubViewport behaves
identically.

Two things worth knowing:

1. The game presents at **60 fps even on the 143.98Hz monitor**, so a 60Hz physics tick
   maps 1:1 onto drawn frames. No cadence judder.
2. Do not benchmark by moving the window between screens at runtime. Launch with
   `--position X,Y` instead, or your numbers are meaningless.

### Trap: odd SubViewport dimensions

The camera's Drag Center anchor puts the camera at `size / 2`. 322/2 = 161 and
182/2 = 91, both whole. An odd dimension puts the camera centre on a half pixel
permanently, and no amount of rounding elsewhere will fix it.

---

## Sources

Checked August 2026 against Godot 4.7.2 (released 18 August 2026, 57 fixes, 39
contributors — nothing in it touches cameras, viewports, or pixel snapping).

**Official**

- [Maintenance release: Godot 4.7.2](https://godotengine.org/article/maintenance-release-godot-4-7-2/)
- [Multiple resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)
  — stretch modes, scale modes, the pixel-art recommendation this document overrides
- [Using physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html)
  — the `_process` warning quoted in 15.4
- [Camera2D class reference](https://docs.godotengine.org/en/stable/classes/class_camera2d.html)
  — `anchor_mode` default is `1`, Drag Center

**Open engine issues that affect this setup**

- [godot#98764](https://github.com/godotengine/godot/issues/98764) — particles jitter in
  a SubViewport with transform snapping
- [godot#95869](https://github.com/godotengine/godot/issues/95869) — interpolation speeds
  up Camera2D smoothing above 60Hz
- [godot#92875](https://github.com/godotengine/godot/issues/92875) — Camera2D
  interpolation wrong on aspect ratio change
- [godot#101195](https://github.com/godotengine/godot/issues/101195) — Camera2D stops
  scrolling if interpolation is enabled at runtime
- [godot#97957](https://github.com/godotengine/godot/issues/97957) — errors when a
  Camera2D sets `physics_interpolation_mode` to Off

**Closed, worth knowing**

- [proposal#6389](https://github.com/godotengine/godot-proposals/issues/6389) — a
  built-in `PixelCamera2D` node. **Closed as not planned.** The hand-rolled shader
  approach in this document is the correct answer in 4.7, not a workaround for a
  missing feature.
- [discussion#9256](https://github.com/godotengine/godot-proposals/discussions/9256) —
  long-running thread on pixel perfect games in Godot

**Other implementations of the same trick**

- [apples/godot-smooth-pixel-subviewport-container](https://github.com/apples/godot-smooth-pixel-subviewport-container)
- [voithos/godot-smooth-pixel-camera-demo](https://github.com/voithos/godot-smooth-pixel-camera-demo)
