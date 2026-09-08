# Pixel Perfect Camera

A smooth-following Camera2D that never jitters, in Godot **4.7.2**.

Reference implementation of `PIXEL_PERFECT_CAMERA_SKILL.md`.

## The trick

The game renders at 320x180 into a SubViewport that is **322x182** — one pixel
bigger on every side. The container sits at offset `-1, -1`, so that extra ring is
off screen.

Every frame the camera does two things:

1. Rounds its own position to a whole pixel.
2. Writes the leftover fraction into a shader on the container, which slides the
   whole finished image by less than one pixel.

Camera hops in whole pixels. Shader hides the hop. Sprites stay crisp.

The camera runs in `_physics_process`, on the same clock as the things it follows.
Run it in `_process` instead and the character steps backwards on about one frame in
six on a 144Hz screen, which looks like the sprite is broken.

## Run it

```sh
godot                       # play
godot --headless tests/verify.tscn    # self-test, exit 0 = pass
godot tests/screenshot.tscn           # write a PNG to user://screenshot.png
godot tests/diagnose.tscn             # measure sub-pixel steps per game pixel
godot --headless tests/motion.tscn    # measure the player's on-screen stepping
godot tests/mouse.tscn                # measure where the mouse lands, exit 0 = pass
```

Controls: `A` / `D` or arrows to move, `Space` / `W` to jump, `E` to shake.

Walk into a yellow marker box. The camera parks on the marker. Walk out, it comes
back to you.

## Three things that look like sprite bugs but are camera bugs

1. Camera updating in `_process` while sprites move in `_physics_process`. The
   followed character steps backwards on about one frame in six on a high refresh
   screen. Run the camera in `_physics_process`.
2. Shake written to `Camera2D.offset`. That is applied after your rounding, so it
   bypasses the shader and every sprite snaps on its own. Fold shake into the
   position before rounding. `offset` must stay zero.
3. A movement speed that is not a whole number of pixels per physics tick. 70 px/s
   at 60Hz is 1.167 px, so the sprite's rounding residual wobbles. 60 px/s is 1.000.

`tests/motion.tscn` measures all three.

## Layout

```
project.godot            settings, strict warnings, input map
shaders/viewport.gdshader   4 lines. the whole trick.
scripts/pixel_camera.gd     rounds, writes the shader uniform, shakes
scripts/camera_trigger.gd   Area2D swaps the camera target to a Marker2D
scripts/player.gd           CharacterBody2D
scripts/global.gd           autoload, typed refs registered by the nodes
scenes/main.tscn            SubViewportContainer + CanvasLayer + SubViewport
scenes/world.tscn           level content
tests/verify.gd             25 headless assertions
tests/mouse.gd              mouse position -> world position, measured on real frames
```

## Strictness

Every GDScript warning that matters is set to **error** in `project.godot`,
including `untyped_declaration`, `inferred_declaration` and all four `unsafe_*`
checks. The project will not run if a single one fires.

## Two settings to leave alone

- `rendering/2d/snap/snap_2d_transforms_to_pixel` — **off**. It jitters particles
  inside a SubViewport ([godot#98764](https://github.com/godotengine/godot/issues/98764)).
  `snap_2d_vertices_to_pixel` is on instead.
- `physics/common/physics_interpolation` — **off**. The camera writes its transform
  in `_process`, which the docs say produces jitter under interpolation. It would
  also apply the same sub-pixel fraction the shader already applies.

`tests/verify.gd` asserts both.
