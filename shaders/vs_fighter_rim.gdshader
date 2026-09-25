shader_type canvas_item;
// Directional rim light for a VS fighter, in their side colour, on the edge
// that faces the centre (where the collision light is). Integrates the
// fighters into their field instead of letting them read as pasted cut-outs.
// toward_centre is in texture UV space (flip_h is already accounted for by
// the caller).

uniform vec4 rim_color : source_color = vec4(0.3, 0.75, 1.0, 1.0);
uniform vec2 toward_centre = vec2(1.0, 0.0);
uniform vec2 texel_px = vec2(0.000729, 0.000651);
uniform float rim_width_px = 7.0;
uniform float rim_strength = 0.8;
// The renders end in a straight crop at the texture bottom: dissolve it.
// UV.y where the fade starts / is complete (1.0 = texture bottom).
uniform float bottom_fade_start = 0.8;
uniform float bottom_fade_end = 0.985;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// COLOR already carries texture * modulate in a Godot 4 canvas fragment.
	vec4 base = COLOR;
	float outside = 0.0;
	for (int i = 1; i <= 4; i++) {
		float r = float(i) / 4.0;
		outside = max(outside, (1.0 - texture(TEXTURE, UV + toward_centre * texel_px * rim_width_px * r).a) * (1.0 - r * 0.5));
	}
	// A little from above too: key light comes from the seam, high up.
	// Only edges whose outward normal faces the centre get light: the
	// opposite direction must be covered (inside the figure).
	float back = texture(TEXTURE, UV - toward_centre * texel_px * rim_width_px).a;
	float rim = clamp(outside, 0.0, 1.0) * back * base.a * rim_strength;
	vec3 light = mix(rim_color.rgb, vec3(1.0), 0.3);
	vec3 rgb = base.rgb + light * rim;
	// Ragged ink dissolve: coarse tongues plus fine grain, so the figure
	// sinks into the wash instead of ending on a ruler line.
	float n = 0.65 * vnoise(vec2(UV.x * 7.0, UV.y * 3.0)) + 0.35 * vnoise(UV * vec2(38.0, 20.0));
	float span = max(bottom_fade_end - bottom_fade_start, 0.001);
	float f = clamp((UV.y - bottom_fade_start) / span, 0.0, 1.0);
	float keep = 1.0 - smoothstep(n * 0.55, n * 0.55 + 0.45, f);
	COLOR = vec4(min(rgb, vec3(1.0)), base.a * keep);
}
