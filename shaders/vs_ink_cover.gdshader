shader_type canvas_item;
// VS ink transition (exit into the match, and the mirrored entry from the
// menu). One move in three beats, driven from vs_screen.gd:
//   progress 0..1 : SLAM  the two side inks crash in from the far corners,
//                         fronts parallel to the VS diagonal, accelerating,
//                         droplets flung ahead of each front.
//   impact   1..0 : HIT   the fronts meet on one torn, white-hot seam; the
//                         flash decays with this value.
//   open     0..1 : TEAR  the seam rips; both masses are hurled back out with
//                         burning torn edges and lagging scraps, revealing
//                         what lies underneath.
// Ink body = the scanned ink-in-water density map of the side fields, in the
// saturated side colour, with a denser dark lip at the moving front.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float impact : hint_range(0.0, 1.0) = 0.0;
uniform float open : hint_range(0.0, 1.0) = 0.0;
uniform vec4 left_color : source_color = vec4(0.9, 0.2, 0.2, 1.0);
uniform vec4 right_color : source_color = vec4(0.2, 0.4, 1.0, 1.0);
uniform sampler2D ink_tex : filter_linear, repeat_enable;
uniform vec2 canvas_px = vec2(1280.0, 720.0);
uniform vec2 seam_top = vec2(391.0, 0.0);
uniform vec2 seam_bottom = vec2(888.5, 720.0);

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

// Multi-scale ragged edge along the seam direction: lobes, fingers, grain.
float ragged(float s, float lane, float amp) {
	return (noise(vec2(s / 170.0, lane)) - 0.5) * 2.0 * amp
		+ (noise(vec2(s / 46.0, lane + 3.7)) - 0.5) * amp * 0.75
		+ (noise(vec2(s / 11.0, lane + 8.1)) - 0.5) * amp * 0.22;
}

// Round blobs scattered in a cell grid over (along, depth): droplets/scraps.
float blobs(vec2 q, float cell, float density, float radius, float lane) {
	vec2 c = floor(q / cell);
	float cov = 0.0;
	for (int ox = -1; ox <= 1; ox++) {
		for (int oy = -1; oy <= 1; oy++) {
			vec2 id = c + vec2(float(ox), float(oy));
			if (hash(id + lane) < 1.0 - density) {
				continue;
			}
			vec2 centre = (id + vec2(hash(id + 1.3 + lane), hash(id + 7.1 + lane))) * cell;
			float r = radius * (0.45 + 0.55 * hash(id + 3.3 + lane));
			cov = max(cov, smoothstep(r + 1.2, r - 1.2, length(q - centre)));
		}
	}
	return cov;
}

void fragment() {
	vec2 px = UV * canvas_px;
	vec2 axis = normalize(seam_bottom - seam_top);
	vec2 n = vec2(axis.y, -axis.x);
	float d = dot(px - seam_top, n);        // < 0 left of the seam, > 0 right
	float s = dot(px - seam_top, axis);      // position along the seam
	// Distance from the seam to the farthest screen corner on each side, so
	// both fronts start fully off-screen and arrive together.
	float c0 = dot(vec2(0.0) - seam_top, n);
	float c1 = dot(vec2(canvas_px.x, 0.0) - seam_top, n);
	float c2 = dot(vec2(0.0, canvas_px.y) - seam_top, n);
	float c3 = dot(canvas_px - seam_top, n);
	float reach_l = max(max(-c0, -c1), max(-c2, -c3)) + 90.0;
	float reach_r = max(max(c0, c1), max(c2, c3)) + 90.0;

	// The ONE shared torn seam the masses meet on.
	float jag = ragged(s, 41.0, 13.0);
	float rel = d - jag;

	// --- SLAM ------------------------------------------------------------
	float p = clamp(progress, 0.0, 1.0);
	float ps = pow(p, 1.7);                  // accelerating: they crash, not slide
	float seal = smoothstep(0.8, 1.0, p);
	float amp = mix(52.0, 14.0, ps);
	float edge_l = -mix((1.0 - ps) * reach_l + ragged(s, 3.1, amp) + amp * 0.5, -jag, seal);
	float edge_r = mix((1.0 - ps) * reach_r + ragged(s, 7.7, amp) + amp * 0.5, jag, seal);
	float cov_l = smoothstep(edge_l + 1.4, edge_l - 1.4, d);
	float cov_r = smoothstep(edge_r - 1.4, edge_r + 1.4, d);
	if (p <= 0.0) {
		cov_l = 0.0;
		cov_r = 0.0;
	}
	if (p > 0.02 && p < 0.95) {
		float ahead_l = d - edge_l;
		float ahead_r = edge_r - d;
		cov_l = max(cov_l, max(blobs(vec2(s, ahead_l), 28.0, 0.3, 6.0, 1.0), blobs(vec2(s * 0.5, ahead_l), 40.0, 0.2, 13.0, 11.0)) * smoothstep(150.0, 15.0, ahead_l) * step(0.0, ahead_l));
		cov_r = max(cov_r, max(blobs(vec2(s, ahead_r), 28.0, 0.3, 6.0, 2.0), blobs(vec2(s * 0.5, ahead_r), 40.0, 0.2, 13.0, 12.0)) * smoothstep(150.0, 15.0, ahead_r) * step(0.0, ahead_r));
	}

	// --- TEAR ------------------------------------------------------------
	float o = clamp(open, 0.0, 1.0);
	float oe = 1.0 - pow(1.0 - o, 3.0);      // explosive, then settles
	float tear_amp = 34.0 * smoothstep(0.0, 0.12, o);
	float gl = oe * reach_l + ragged(s, 13.0, tear_amp) + tear_amp * 0.35;
	float gr = oe * reach_r + ragged(s, 19.0, tear_amp) + tear_amp * 0.35;
	float scraps = 0.0;
	if (o > 0.0) {
		cov_l *= smoothstep(-gl + 1.4, -gl - 1.4, rel);
		cov_r *= smoothstep(gr - 1.4, gr + 1.4, rel);
		if (o < 0.85) {
			float in_l = rel + gl;
			float in_r = gr - rel;
			float lag = 1.0 - smoothstep(0.15, 0.85, o);
			float sl = blobs(vec2(s, in_l), 24.0, 0.3, 6.5, 5.0) * smoothstep(120.0, 8.0, in_l) * step(0.0, in_l) * step(rel, 0.0);
			float sr = blobs(vec2(s, in_r), 24.0, 0.3, 6.5, 6.0) * smoothstep(120.0, 8.0, in_r) * step(0.0, in_r) * step(0.0, rel);
			cov_l = max(cov_l, sl * lag);
			cov_r = max(cov_r, sr * lag);
		}
	}

	bool is_left = cov_l >= cov_r ? (cov_l > 0.0 ? true : rel < 0.0) : false;
	float cov = max(cov_l, cov_r);
	vec3 col = is_left ? left_color.rgb : right_color.rgb;

	// --- ink body --------------------------------------------------------
	float ink = texture(ink_tex, px / 760.0 + (is_left ? vec2(0.13, 0.41) : vec2(0.62, 0.07))).r;
	float behind = is_left ? (edge_l - d) : (d - edge_r);
	if (o > 0.0) {
		behind = is_left ? (-gl - rel) : (rel - gr);
	}
	float lip = exp(-max(behind, 0.0) / 12.0) * (1.0 - seal);
	// deep, dense ink like the VS side fields: nearly flat colour, the scan
	// only as faint tone steps, a wet sheen, a darker pooled lip at the front
	float tone = smoothstep(0.25, 0.75, ink);
	vec3 rgb = col * (0.34 + 0.08 * tone);
	float sheen = smoothstep(0.8, 0.96, texture(ink_tex, px / 300.0 + vec2(0.31, 0.77)).r);
	rgb += col * sheen * 0.1;
	rgb = mix(rgb, col * 0.14, lip * 0.85);
	rgb *= 0.97 + 0.06 * hash(floor(px / 2.0));

	// --- the seam --------------------------------------------------------
	float sd = abs(rel);
	float live = seal * (1.0 - smoothstep(0.0, 0.2, o));
	float core = exp(-pow(sd / 2.6, 2.0));
	float halo = exp(-sd / 18.0);
	rgb += mix(col, vec3(1.0, 0.9, 0.8), 0.35) * halo * live * (0.45 + 1.0 * impact);
	rgb = mix(rgb, vec3(1.0, 0.97, 0.92), core * live);
	rgb += vec3(1.0, 0.95, 0.88) * impact * 0.5 * exp(-sd / 170.0);

	// burning torn edges while the masses fly out
	if (o > 0.0) {
		float burn = exp(-max(behind, 0.0) / 6.0) * pow(1.0 - o, 1.2);
		rgb = mix(rgb, mix(col * 1.3, vec3(1.0, 0.96, 0.9), 0.4), burn);
	}

	float a = cov;
	if (p >= 0.999 && o <= 0.0) {
		a = 1.0;
	}
	// rupture flash in the fresh gap, over whatever is revealed
	if (o > 0.0) {
		float fa = (1.0 - smoothstep(0.0, 0.06, o)) * exp(-sd / 24.0) * 0.7 * (1.0 - a);
		vec3 hot = vec3(1.0, 0.96, 0.9);
		rgb = (rgb * a + hot * fa) / max(a + fa, 0.0001);
		a += fa;
	}
	COLOR = vec4(min(rgb, vec3(1.0)), a);
}
