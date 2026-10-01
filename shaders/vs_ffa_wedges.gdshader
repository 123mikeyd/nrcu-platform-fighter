shader_type canvas_item;
// FFA ink wedges: 3 or 4 ink fields that meet at the VS. Wedge i spans from
// ray i to ray i+1 (clockwise on screen); every ray runs from the centre (the
// VS) to a point on the screen border. Each wedge carries its player colour
// as dense ink; the seams between them are the contact lines, hottest at the
// centre, where everyone collides.
//   progress 0..1 : the inks run in from the screen border toward the VS
//   energy        : seam heat (peaks at the clash, rests at hold level)

uniform vec2 canvas_px = vec2(1280.0, 720.0);
uniform vec2 centre = vec2(640.0, 330.0);
uniform int count = 4;
uniform vec2 ray0 = vec2(640.0, 0.0);
uniform vec2 ray1 = vec2(1280.0, 300.0);
uniform vec2 ray2 = vec2(640.0, 720.0);
uniform vec2 ray3 = vec2(0.0, 300.0);
uniform vec4 color0 : source_color = vec4(0.85, 0.35, 0.31, 1.0);
uniform vec4 color1 : source_color = vec4(0.31, 0.5, 0.85, 1.0);
uniform vec4 color2 : source_color = vec4(0.85, 0.75, 0.31, 1.0);
uniform vec4 color3 : source_color = vec4(0.35, 0.85, 0.31, 1.0);
uniform sampler2D ink_tex : filter_linear, repeat_enable;
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float energy : hint_range(0.0, 2.0) = 0.35;
uniform float body_alpha = 0.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec2 ray_at(int i) {
	int k = i % count;
	if (k == 0) return ray0;
	if (k == 1) return ray1;
	if (k == 2) return ray2;
	return ray3;
}

vec4 color_at(int i) {
	if (i == 0) return color0;
	if (i == 1) return color1;
	if (i == 2) return color2;
	return color3;
}

float ang(vec2 v) {
	return atan(v.y, v.x);
}

void fragment() {
	vec2 px = UV * canvas_px;
	// One shared domain warp: every seam is torn the same way for both of the
	// wedges it separates, so neighbours always meet exactly.
	vec2 warp = vec2(noise(px / 95.0) - 0.5, noise(px / 95.0 + 17.3) - 0.5) * 22.0
		+ vec2(noise(px / 23.0 + 5.1) - 0.5, noise(px / 23.0 + 9.7) - 0.5) * 6.0;
	vec2 q = px + warp;
	vec2 v = q - centre;
	float a = ang(v);
	int wedge = 0;
	float seam_d = 1e6;
	for (int i = 0; i < 4; i++) {
		if (i >= count) {
			break;
		}
		vec2 r0 = ray_at(i) - centre;
		vec2 r1 = ray_at(i + 1) - centre;
		float a0 = ang(r0);
		float span = mod(ang(r1) - a0, 6.2831853);
		if (mod(a - a0, 6.2831853) < span) {
			wedge = i;
		}
		vec2 u = normalize(r0);
		float t = dot(v, u);
		float d = t > 0.0 ? abs(v.x * u.y - v.y * u.x) : length(v);
		seam_d = min(seam_d, d);
	}
	vec3 col = color_at(wedge).rgb;
	float r = length(v);

	// The ink arrives from the border and runs in toward the VS.
	float reach = length(canvas_px) * 0.62;
	float front = (1.0 - progress) * reach + (noise(vec2(a * 7.0, 3.3)) - 0.5) * 60.0 * (1.0 - progress);
	float cov = progress >= 1.0 ? 1.0 : smoothstep(front - 2.0, front + 2.0, r);

	// Dense ink body: mostly flat, faint tone steps from the scanned map, a
	// little deeper toward the border so the centre (the clash) carries light.
	float ink = texture(ink_tex, px / 760.0 + vec2(0.17 * float(wedge), 0.29 * float(wedge))).r;
	float tone = smoothstep(0.25, 0.75, ink);
	vec3 rgb = col * (0.5 + 0.14 * tone);
	float alpha = body_alpha * (0.75 + 0.25 * tone) * mix(1.0, 0.72, smoothstep(160.0, 760.0, r));

	// Seams: hot core, coloured halo; strongest near the VS.
	float focus = exp(-r / 420.0);
	float core = exp(-pow(seam_d / 3.2, 2.0));
	float halo = exp(-seam_d / 22.0);
	float heat = energy * (0.55 + 0.75 * focus) * smoothstep(0.85, 1.0, progress);
	vec3 hot = vec3(1.0, 0.96, 0.9);
	rgb = mix(rgb, mix(col, hot, 0.55), clamp(halo * heat * 0.8, 0.0, 1.0));
	rgb = mix(rgb, hot, clamp(core * heat * 1.6, 0.0, 1.0));
	alpha = max(alpha, clamp((core * 0.95 + halo * 0.45) * heat, 0.0, 1.0));
	// Clash glow at the centre (under the VS).
	float glow = exp(-r / 150.0) * energy * 0.7 * smoothstep(0.85, 1.0, progress);
	rgb = mix(rgb, hot, clamp(glow, 0.0, 1.0) * 0.6);
	alpha = max(alpha, clamp(glow, 0.0, 1.0));

	// The converging front carries light: the last gap closes as a flare, never
	// as a dark hole.
	if (progress < 1.0) {
		float rim = exp(-abs(r - front) / 10.0) * smoothstep(0.3, 0.9, progress);
		vec3 hotc = vec3(1.0, 0.96, 0.9);
		float inner = exp(-r / 90.0) * smoothstep(0.75, 1.0, progress) * (1.0 - cov);
		rgb = mix(rgb, mix(col, hotc, 0.6), clamp(rim, 0.0, 1.0));
		COLOR = vec4(min(mix(rgb, hotc, inner), vec3(1.0)), max(alpha * cov, max(rim * 0.9 * cov, inner)));
	} else {
		COLOR = vec4(min(rgb, vec3(1.0)), alpha * cov);
	}
}
