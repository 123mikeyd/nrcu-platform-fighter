shader_type canvas_item;
// FFA version of the VS ink transition (vs_ink_cover.gdshader): the same
// three beats, but with one ink per player wedge. Same uniforms for the beats,
// so vs_screen.gd drives both identically.
//   progress 0..1 : SLAM  every wedge's ink runs in from the border and they
//                         close on the VS, where the last gap flares shut.
//   impact   1..0 : HIT   the seams and the centre burn white, then decay.
//   open     0..1 : TEAR  the ink rips open from the VS outward, burning
//                         edges, revealing what lies underneath.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float impact : hint_range(0.0, 1.0) = 0.0;
uniform float open : hint_range(0.0, 1.0) = 0.0;
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

// Ragged radius offset around the centre: lobes, fingers, grain.
float ragged(float a, float lane, float amp) {
	return (noise(vec2(a * 5.0, lane)) - 0.5) * 2.0 * amp
		+ (noise(vec2(a * 19.0, lane + 3.7)) - 0.5) * amp * 0.75
		+ (noise(vec2(a * 70.0, lane + 8.1)) - 0.5) * amp * 0.22;
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

void fragment() {
	vec2 px = UV * canvas_px;
	// Same shared warp as vs_ffa_wedges: the seams line up with the fields.
	vec2 warp = vec2(noise(px / 95.0) - 0.5, noise(px / 95.0 + 17.3) - 0.5) * 22.0
		+ vec2(noise(px / 23.0 + 5.1) - 0.5, noise(px / 23.0 + 9.7) - 0.5) * 6.0;
	vec2 v = px + warp - centre;
	float a = atan(v.y, v.x);
	int wedge = 0;
	float seam_d = 1e6;
	for (int i = 0; i < 4; i++) {
		if (i >= count) {
			break;
		}
		vec2 r0 = ray_at(i) - centre;
		vec2 r1 = ray_at(i + 1) - centre;
		float a0 = atan(r0.y, r0.x);
		float span = mod(atan(r1.y, r1.x) - a0, 6.2831853);
		if (mod(a - a0, 6.2831853) < span) {
			wedge = i;
		}
		vec2 u = normalize(r0);
		float t = dot(v, u);
		float d = t > 0.0 ? abs(v.x * u.y - v.y * u.x) : length(v);
		seam_d = min(seam_d, d);
	}
	vec3 col = color_at(wedge).rgb;
	float r = length(px - centre);
	// farthest screen corner from the VS: the fronts start off-screen
	float reach = max(max(length(centre), length(centre - vec2(canvas_px.x, 0.0))),
		max(length(centre - vec2(0.0, canvas_px.y)), length(centre - canvas_px))) + 80.0;

	// --- SLAM: accelerating fronts from the border toward the VS ----------
	float p = clamp(progress, 0.0, 1.0);
	float ps = pow(p, 1.7);
	float amp = mix(60.0, 10.0, ps);
	float front = (1.0 - ps) * reach + ragged(a, 3.1, amp) + amp * 0.5;
	front = max(front, 0.0) * (1.0 - smoothstep(0.9, 1.0, p));
	float cov = p <= 0.0 ? 0.0 : smoothstep(front - 1.5, front + 1.5, r);
	if (p >= 0.999) {
		cov = 1.0;
	}
	// the front edge carries light; the last gap closes as a flare
	float lip = exp(-max(r - front, 0.0) / 12.0) * (1.0 - smoothstep(0.9, 1.0, p));

	// --- TEAR: the ink rips open from the VS outward ----------------------
	float o = clamp(open, 0.0, 1.0);
	float oe = 1.0 - pow(1.0 - o, 3.0);
	float tear_amp = 40.0 * smoothstep(0.0, 0.12, o);
	float gap = oe * reach + ragged(a, 13.0, tear_amp) + tear_amp * 0.35;
	float behind = r - front;
	if (o > 0.0) {
		cov *= smoothstep(gap - 1.5, gap + 1.5, r);
		behind = r - gap;
	}

	// --- ink body ----------------------------------------------------------
	float ink = texture(ink_tex, px / 760.0 + vec2(0.17 * float(wedge), 0.29 * float(wedge))).r;
	float tone = smoothstep(0.25, 0.75, ink);
	vec3 rgb = col * (0.34 + 0.08 * tone);
	float sheen = smoothstep(0.8, 0.96, texture(ink_tex, px / 300.0 + vec2(0.31, 0.77)).r);
	rgb += col * sheen * 0.1;
	rgb *= 0.97 + 0.06 * hash(floor(px / 2.0));
	vec3 hot = vec3(1.0, 0.96, 0.9);
	rgb = mix(rgb, mix(col * 1.2, hot, 0.35), clamp(lip * 0.8, 0.0, 1.0));

	// --- seams: live once the wedges have closed ----------------------------
	float seal = smoothstep(0.85, 1.0, p);
	float live = seal * (1.0 - smoothstep(0.0, 0.25, o));
	float core = exp(-pow(seam_d / 2.8, 2.0));
	float halo = exp(-seam_d / 18.0);
	float focus = exp(-r / 380.0);
	rgb += mix(col, vec3(1.0, 0.9, 0.8), 0.35) * halo * live * (0.35 + 0.6 * focus) * (0.5 + 1.0 * impact);
	rgb = mix(rgb, hot, clamp(core * live * (0.6 + 0.4 * focus), 0.0, 1.0));
	// the hit: the centre where everyone met burns white, then decays
	rgb += hot * impact * 0.7 * exp(-r / 160.0);

	// burning torn edges while the ink flies out
	if (o > 0.0) {
		float burn = exp(-max(behind, 0.0) / 6.0) * pow(1.0 - o, 1.2);
		rgb = mix(rgb, mix(col * 1.3, hot, 0.4), clamp(burn, 0.0, 1.0));
	}

	float alpha = cov;
	// the closing gap at the VS reads as light, never as a hole
	if (p > 0.6 && o <= 0.0 && alpha < 1.0) {
		float fa = exp(-r / 70.0) * smoothstep(0.6, 1.0, p) * (1.0 - alpha);
		rgb = (rgb * alpha + hot * fa) / max(alpha + fa, 0.0001);
		alpha += fa;
	}
	// rupture flash in the fresh gap, one beat only
	if (o > 0.0) {
		float fa = (1.0 - smoothstep(0.0, 0.06, o)) * exp(-r / 90.0) * 0.8 * (1.0 - alpha);
		rgb = (rgb * alpha + hot * fa) / max(alpha + fa, 0.0001);
		alpha += fa;
	}
	COLOR = vec4(min(rgb, vec3(1.0)), alpha);
}
