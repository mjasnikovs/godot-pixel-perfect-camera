shader_type canvas_item;

// Sub-pixel offset written every frame by PixelCamera.
// The SubViewport renders 1px larger on each side, so shifting the whole
// image by up to half a pixel never exposes a gap.
uniform vec2 cam_offset = vec2(0.0, 0.0);

void vertex() {
	VERTEX += cam_offset;
}
