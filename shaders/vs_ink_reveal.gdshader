shader_type canvas_item;
// Ink reveal for the VS nameplate brush and the name text: the item is
// "written" along X by a ragged, slightly wet front. progress 0 = nothing,
// 1 = fully shown. COLOR already holds texture * modulate (Godot 4
// canvas_item), so it is only masked here, never re-sampled.
// Coordinates come from the local VERTEX (not UV), so the same shader works
// on a TextureRect and on a Label, whose UVs point into the glyph atlas.

uniform float progress : hint_range(0.0, 1.0) = 1.0;
// Local size of the item in px (x drives the write direction).
uniform vec2 item_size = vec2(512.0, 64.0);
// Write direction: false = left to right, true = right to left.
uniform bool from_right = false;
// Width of the soft, ragged front as a fraction of the item width.
uniform float front_width = 0.08;
// Ragged amplitude of the front, fraction of the item width.
uniform float rag = 0.035;
// Brief bright wet edge right at the front (0 = off).
uniform float wet_glow = 0.6;

varying vec2 local_uv;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(float y) {
	float i = floor(y);
	float f = fract(y);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash(vec2(i, 3.1)), hash(vec2(i + 1.0, 3.1)), u);
}

void vertex() {
	local_uv = VERTEX / max(item_size, vec2(1.0));
}

void fragment() {
	float x = from_right ? 1.0 - local_uv.x : local_uv.x;
	// Ragged front: two octaves along Y so the edge reads as brush, not a wipe.
	float r = (vnoise(local_uv.y * 9.0) - 0.5) + 0.5 * (vnoise(local_uv.y * 23.0 + 7.0) - 0.5);
	float head = progress * (1.0 + front_width * 2.0 + rag * 2.0) - front_width;
	float d = head + r * rag * 2.0 - x;
	float mask = smoothstep(0.0, front_width, d);
	float edge = (1.0 - smoothstep(0.0, front_width, abs(d - front_width * 0.5))) * step(progress, 0.999);
	vec4 c = COLOR;
	c.rgb = mix(c.rgb, vec3(1.0), clamp(edge * wet_glow, 0.0, 1.0));
	c.a *= mask;
	COLOR = c;
}
