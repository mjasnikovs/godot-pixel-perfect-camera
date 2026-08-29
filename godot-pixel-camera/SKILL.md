---
name: godot-pixel-camera
description: >
  Build or fix a smooth pixel-perfect Camera2D in Godot 4, using a SubViewport with
  1px of slack and a sub-pixel offset shader. Use when a low-resolution 2D game's
  camera judders, smears, or the followed character appears to snap or vibrate;
  when setting up stretch mode, texture filtering, or pixel snapping for pixel art;
  or when deciding whether to enable physics interpolation in a 2D game.
  Triggers: pixel perfect, pixel art camera, SubViewport, SubViewportContainer,
  camera jitter, camera judder, sub-pixel, snap_2d_vertices_to_pixel,
  stretch mode, canvas_items, integer scaling, Camera2D smoothing.
---

# Pixel perfect camera (Godot 4)

Verified against Godot 4.7.2 by building the project and measuring the result.

The game renders at a low resolution and the window is a whole-number multiple of it.
A low-res image can only move in whole pixels, and scaled up each jump is several
screen pixels. That is the judder.

Two moves fix it.

- **Round once.** The camera's position is rounded to a whole pixel. Everything the
  camera does — follow, shake, anything else — feeds one float position that gets
  rounded exactly once.
- **Spend the slack.** The SubViewport renders 1px bigger on every side. A shader
  slides the whole finished picture back by the fraction that rounding threw away.
  The slack is the room it slides into, so sliding never exposes a gap.

The camera hops in whole pixels. The shader hides the hop. Sprites stay crisp.

It must be a shader, not a fractional camera position. Move the camera by a fraction
and each sprite snaps to the grid on its own, so sprites shift against *each other*.
The shader moves the finished picture as one object, after everything is already
rasterised.

## Geometry

For a 320x180 game in a 1280x720 window. One game pixel is four screen pixels.

| Thing | Value |
|---|---|
| Game area | 320 x 180 |
| SubViewport | **322 x 182** — the slack |
| Container rect | left -1, top -1, right 321, bottom 181 |
| Container scale | **1, 1** |
| Base viewport | **320 x 180** |
| Window | 1280 x 720 |

Keep both SubViewport dimensions **even**. Drag Center puts the camera at `size / 2`;
an odd size parks it on a half pixel forever.

## Project settings

```ini
[display]
window/size/viewport_width=320      ; base viewport IS the game size
window/size/viewport_height=180
window/size/resizable=false
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/stretch/scale_mode="integer"

[rendering]
textures/canvas_textures/default_texture_filter=0
2d/snap/snap_2d_vertices_to_pixel=false
```

`canvas_items`, **not** `viewport`. This contradicts the official pixel-art page, and
the measurement is in `reference/traps.md`. `viewport` stretch rasterises the whole
frame at the base size, so the shader offset lands on 2 of 4 possible sub-pixel
positions. `canvas_items` rasterises at native window resolution and gets 4 of 4.

Snapping is **off** here because this applies to the root viewport, where the
container lives. Turn it on per-node instead:

```
# the SubViewport node
snap_2d_vertices_to_pixel = true
```

`snap_2d_transforms_to_pixel` stays off everywhere. Open engine bug, `reference/traps.md`.

Nearest filtering must be set in two places: the project default above, **and**
`canvas_item_default_texture_filter = 0` on the SubViewport. A SubViewport does not
inherit the project default.

## The shader

```glsl
shader_type canvas_item;

uniform vec2 cam_offset = vec2(0.0, 0.0);

void vertex() {
	VERTEX += cam_offset;
}
```

The uniform is `round(position) - position`, range -0.5 to +0.5. That sign, not the
other one: the camera is drawn at `round(C)` and should look like it is at `C`, and
moving a camera right moves its image left.

## Scene tree

```
SubViewportContainer          <- root, owns the shader material, scale (1,1)
├── CanvasLayer               <- UI, OUTSIDE the pixel viewport, native resolution
└── SubViewport               <- 322x182, Nearest, update Always, snap vertices on
    ├── World
    └── PixelCamera           <- Camera2D, anchor_mode left at Drag Center
```

Wire references with `@export` node paths and an autoload that nodes register
themselves into. Hardcoded `get_node("A/B/C")` chains break on any rename.

## The camera loop

```gdscript
func _physics_process(delta: float) -> void:
	if target == null:
		return

	var weight: float = minf(camera_speed * delta, 1.0)
	_actual_position = _actual_position.lerp(target.global_position, weight)

	var shake: Vector2 = Vector2.ZERO
	if shake_strength > 0.0:
		shake_strength = lerpf(shake_strength, 0.0, SHAKE_DECAY * delta)
		shake = _get_noise_offset(delta, shake_strength)

	# One float position. One round.
	var desired_position: Vector2 = _actual_position + shake
	var rounded_position: Vector2 = desired_position.round()

	offset = Vector2.ZERO
	global_position = rounded_position
	_shader_material.set_shader_parameter("cam_offset", rounded_position - desired_position)
```

`_physics_process`, on the **same clock** as everything it follows.
`Camera2D.offset` forced to zero, because it is applied after the round and escapes it.

Full script, camera triggers, shake and time effects: `reference/camera.md`.

## The five bugs

Present in nearly every existing implementation. Check these first when something
feels wrong.

| # | Bug | Symptom | Fix |
|---|---|---|---|
| 1 | `viewport` stretch with a doubled base viewport | world judders; 2 of 4 sub-pixel steps | base = game size, `canvas_items`, container scale 1 |
| 2 | Snapping on the **root** viewport | rounds away the shader offset | off in project settings, on the SubViewport node |
| 3 | Camera in `_process` | followed character steps **backwards** ~1 frame in 6 on a high-refresh screen | `_physics_process` |
| 4 | Shake written to `Camera2D.offset` | shake looks mushy, sprites shift against each other | fold shake in before the round; `offset` stays zero |
| 5 | Window left resizable | a tiling WM resizes it, integer factor collapses 4x to 1x | `window/size/resizable=false` |

Bug 1 makes the world judder. Bug 3 makes the character judder against the world.
Those are the two you feel.

Physics interpolation looks like the cure for bug 3. It is not — it re-applies the
fraction the shader already applies, and carries four open engine bugs. Leave it off.
`reference/traps.md`.

## Build order

1. Project settings above, plus GDScript warnings at level `2` (`reference/verify.md`).
2. Root `SubViewportContainer`, rect -1/-1/321/181, scale (1,1), shader material.
3. `SubViewport` child, 322x182, Nearest, update Always, `snap_2d_vertices_to_pixel` on.
4. World under the SubViewport. `Camera2D` beside it, Drag Center, camera script.
5. `CanvasLayer` sibling of the SubViewport for UI. Small font sizes, game-space coords.
6. Move at a whole number of pixels per physics tick (60 px/s at 60Hz = 1.000).
7. Import sprites Lossless, no mipmaps, fix alpha border.
8. Copy the test harness from `reference/verify.md` and keep it green.

## Reference

- `reference/camera.md` — full camera script, camera triggers, shake, time effects,
  the autoload pattern, UI placement.
- `reference/traps.md` — snapping, physics interpolation, tiling window managers,
  frame rate on multi-monitor Wayland, and the measurements behind every claim above.
- `reference/verify.md` — the strict-typing settings and the full test harness that
  proves the result.
