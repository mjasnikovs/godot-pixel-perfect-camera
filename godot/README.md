# Pixel Perfect Camera

A smooth-following Camera2D that never jitters, in Godot **4.7.2**.

Reference implementation of `godot-pixel-camera/SKILL.md`.

## The trick

The game renders at 320x180 into a SubViewport that is **322x182** — one pixel
bigger on every side. The container sits at offset `-1, -1`, so that extra ring is
off screen.

Every physics tick the camera does two things:

1. Rounds its own position to a whole pixel.
2. Writes the leftover fraction into a shader on the container, which slides the
   whole finished image by less than one pixel.

Camera hops in whole pixels. Shader hides the hop. Sprites stay crisp.

The camera runs in `_physics_process`, on the same clock as the things it follows.
Run it in `_process` instead and the character steps backwards on about one frame in
six on a 144Hz screen, which looks like the sprite is broken.

## Run it

```sh
godot                                      # play
godot --headless tests/verify.tscn         # the invariants
godot tests/screenshot.tscn                # write a PNG to user://screenshot.png
godot tests/diagnose.tscn                  # 4 of 4 sub-pixel steps, square pixels
godot --headless tests/motion.tscn         # the player never steps backwards on screen
godot tests/mouse.tscn                     # the mouse lands on its own pixel
godot tests/fps.tscn -- screen=0 vsync=on  # the frame rate keeps up with physics
gdformat --check scripts/ tests/
gdlint scripts/ tests/
```

Every harness prints nothing and exits 0 on a pass. A failure is printed with
`printerr` and exits 1.

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

`tests/motion.tscn` checks the first and third, `tests/verify.tscn` the second.

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
tests/verify.gd             headless invariants, every frame
tests/mouse.gd              mouse position -> world position, measured on real frames
tests/mouse_listener.gd     records where mouse events land inside the SubViewport
```

## Strictness

All 49 GDScript warnings are set to **error** in `project.godot`, as godot-code-style
sets them, and nothing is suppressed. The project will not run if a single one fires.
`.gdlintrc` and `.gdformatrc` are godot-code-style's.

## Two settings to leave alone

- `rendering/2d/snap/snap_2d_transforms_to_pixel` — **off**. It jitters particles
  inside a SubViewport ([godot#98764](https://github.com/godotengine/godot/issues/98764)).
  `snap_2d_vertices_to_pixel` is on instead.
- `physics/common/physics_interpolation` — **off**. The camera already rounds its
  position every physics tick, and interpolation would draw it at a fraction between
  two rounded positions: the same sub-pixel fraction the shader already applies.

`tests/verify.gd` asserts both.
