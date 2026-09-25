shader_type canvas_item;
// Living side-field edge.
//
// Mechanism adapted from "Transparent noise border" (godotshaders.com, CC0):
// the field's own boundary is eroded by animated noise, instead of drawing a
// glow line on top of a hard polygon edge. Two changes make it work on the VS
// side fields:
//   * the distance comes from a baked signed-distance field of the actual
//     field shape (tools/bake_side_field_sdf.py), not from the quad's UV
//     rectangle, and the screen border is excluded by construction;
//   * a slow domain warp lets the edge flow like ink, while the fine erosion
//     noise tears it; a thin rim follows the eroded edge in the field's hue.
// All motion comes from the supplied presentation clock (edge_time), never
// from TIME, so seeking and review captures stay deterministic.

uniform sampler2D sdf_tex : filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float sdf_range_px = 128.0;
uniform vec2 canvas_px = vec2(1280.0, 720.0);
uniform float edge_time = 0.0;
uniform float edge_energy : hint_range(0.0, 1.5) = 0.35;
uniform float edge_pull_px = 0.0;
uniform float erosion_min_px = 1.5;
uniform float erosion_max_px = 7.0;
uniform float warp_min_px = 13.0;
uniform float warp_max_px = 52.0;
uniform float rim_px = 2.6;
uniform float rim_strength = 1.0;
// Ink body: a scanned ink-in-water density map (assets/vs/fx/side_field_ink.png,
// 1 = ink). Colour pools near the living edge and thins toward the screen
// border, so the field reads as ink rather than a flat tinted film.
uniform sampler2D ink_tex : filter_linear, repeat_enable;
uniform float ink_strength : hint_range(0.0, 1.0) = 0.0;
uniform float ink_scale_px = 900.0;
uniform float body_alpha = 0.34;
// The clash. Near the VS both fields give up their own edge and meet on ONE
// shared, torn boundary around the gap's centreline. Both proxies compute
// that boundary from the same inputs (pixel, time), so it is identical in
// each: the left field covers one side, the right field the other, and the
// white-hot contact line sits exactly on it. field_side: +1 left, -1 right.
uniform float field_side = 0.0;
uniform vec2 seam_top = vec2(391.0, 0.0);
uniform vec2 seam_bottom = vec2(888.5, 720.0);
uniform vec2 focus_px = vec2(622.0, 334.0);
uniform float press = 0.0;
uniform float press_radius_px = 300.0;
uniform float contact_strength = 0.0;
uniform float clash_amp_px = 26.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// Two octaves only: the boundary should sweep in a few big lobes; fine
// octaves turn the flow into crackle.
float fbm_coarse(vec2 p) {
	return 0.667 * value_noise(p) + 0.333 * value_noise(p * 2.03 + vec2(17.1, 9.2));
}

// COLOR in a Godot 4 canvas fragment already includes the proxy texture
// (the hard mask). The living edge must be able to grow OUTSIDE the mask,
// so it only takes the node modulate, captured in vertex().
varying vec4 node_modulate;

void vertex() {
	node_modulate = COLOR;
}

void fragment() {
	vec2 px = UV * canvas_px;
	float energy = clamp(edge_energy, 0.0, 1.5);
	float d = (texture(sdf_tex, UV).r - 0.5) * 2.0 * sdf_range_px;

	// Slow ink-like flow of the whole boundary.
	float t = edge_time;
	// Domain-warped flow (noise of noise) gives sweeping ink curls instead
	// of jitter; it drifts slowly so the edge breathes rather than boils.
	vec2 flow_p = px / 260.0;
	vec2 q = vec2(fbm_coarse(flow_p + vec2(0.0, t * 0.32)), fbm_coarse(flow_p + vec2(5.2, 1.3) - vec2(t * 0.26, 0.0)));
	float warp = (fbm_coarse(flow_p + 1.4 * q + vec2(t * 0.18, -t * 0.14)) - 0.5) * 2.0 * mix(warp_min_px, warp_max_px, clamp(energy, 0.0, 1.0));

	// Fine burn/erosion noise drifting along +y like the reference burnSpeed.
	vec2 burn_p = px / 70.0 + vec2(0.0, t * 0.8) + 1.5 * q;
	float burn = fbm(burn_p);
	float erosion = (burn - 0.5) * 2.0 * mix(erosion_min_px, erosion_max_px, energy);

	float de = d + warp + erosion + edge_pull_px;

	// Shared clash boundary (identical in both fields).
	float d_shared = 0.0;
	float clash_w = 0.0;
	float seal = 0.0;
	if (field_side != 0.0) {
		vec2 axis = normalize(seam_bottom - seam_top);
		vec2 normal = vec2(axis.y, -axis.x);
		float across = dot(px - seam_top, normal);
		float along_px = dot(px - focus_px, axis);
		// The line is a 1D curve along the seam (no dependence on `across`,
		// which would fold it into a zipper). Three scales: a slow sway, torn
		// chunks whose strength varies along the line, and a little grain.
		float sway = (fbm_coarse(vec2(along_px / 130.0, t * 0.55)) - 0.5) * 3.0 * clash_amp_px;
		float chunk = (fbm(vec2(along_px / 48.0, t * 1.4)) - 0.5) * 2.0;
		float chunk_gain = smoothstep(0.3, 0.75, value_noise(vec2(along_px / 110.0 + 3.7, t * 0.8)));
		float shard = (value_noise(vec2(along_px / 20.0, t * 2.2)) - 0.5) * 2.0;
		float curve = sway + clash_amp_px * (0.8 * chunk * (0.5 + 0.5 * chunk_gain) + 0.3 * shard * (0.4 + 0.6 * chunk_gain));
		d_shared = field_side * (curve - across);
		float a_n = along_px / press_radius_px;
		clash_w = clamp(press, 0.0, 1.0) * exp(-a_n * a_n);
		// Ownership: a front may reach the shared line but never cross it,
		// so the two living edges touch instead of crossing into an X.
		de = min(de, d_shared);
		// Near the VS, once pressed, both fields lock onto the shared line;
		// with full press the whole seam seals (no dark wedge at the ends).
		seal = smoothstep(0.35, 1.0, clamp(press, 0.0, 1.0));
		de = mix(de, d_shared, max(smoothstep(0.15, 0.45, clash_w), seal));
	}
	float aa = 0.9;
	float coverage = smoothstep(-aa, aa, de);

	// Depth: the field is slightly denser right behind its living edge.
	float inner = exp(-max(de, 0.0) / 46.0);
	float fill_a = tint.a * (1.0 + 0.45 * inner);
	if (ink_strength > 0.0) {
		// Mirrored sampling hides the seam of the non-tiling scan; the ink
		// drifts slowly with the same flow field as the edge.
		vec2 iuv = (px + q * 60.0) / ink_scale_px + vec2(t * 0.012, -t * 0.008);
		vec2 m = abs(mod(iuv, 2.0) - 1.0);
		float ink = texture(ink_tex, m).r;
		float pool = exp(-max(de, 0.0) / 170.0);
		float body = body_alpha * (0.25 + 0.75 * ink) * (0.35 + 0.65 * pool);
		fill_a = mix(fill_a, body, ink_strength);
	}

	// Rim in the field's own hue; only the hottest noise crests go white.
	float rim = 1.0 - smoothstep(0.0, rim_px + energy * 1.6, abs(de));
	float peak = max(max(tint.r, tint.g), tint.b);
	vec3 hue = clamp(tint.rgb / max(peak, 0.001), vec3(0.0), vec3(1.0));
	float crest = smoothstep(0.58, 0.8, burn);
	// Keep the rim in the field hue; lift dark hues (red reads darker than
	// blue at equal value) so both sides carry the same perceived light.
	float hue_luma = dot(hue, vec3(0.299, 0.587, 0.114));
	vec3 rim_rgb = mix(hue, vec3(1.0), 0.12 + crest * 0.25);
	// Blue sits on a navy backdrop: give low-luma hues more rim light.
	float luma_lift = clamp(0.75 / max(hue_luma, 0.2), 1.0, 2.2);
	rim_rgb = mix(rim_rgb, vec3(1.0), clamp(0.45 - hue_luma, 0.0, 0.3));
	// Soft outer glow beyond the eroded edge sells the rim as light.
	float glow = exp(-max(-de, 0.0) / (3.5 + energy * 3.5)) * step(de, 0.0);
	float rim_a = clamp(max(rim, glow * 0.35) * rim_strength * (0.5 + 0.5 * clamp(energy, 0.0, 1.0)) * luma_lift, 0.0, 1.0);

	// The clash line: white-hot core exactly on the shared boundary; each
	// field paints only its own side (a strict partition), falling off into
	// its own saturated hue.
	float contact_a = 0.0;
	vec3 contact_rgb = vec3(1.0);
	if ((clash_w > 0.0 || seal > 0.0) && contact_strength > 0.0) {
		float own = step(0.0, d_shared);
		float width = 2.2 + 3.2 * fbm_coarse(px / 70.0 + vec2(0.0, t * 1.3));
		float core = exp(-pow(d_shared / width, 2.0));
		float bloom = exp(-max(d_shared, 0.0) / 26.0);
		// Equal perceived bloom on both sides: darker hues get more light.
		float bloom_gain = clamp(0.5 / max(tint.a, 0.2), 1.0, 1.9);
		float flicker = 0.8 + 0.2 * sin(t * 21.0 + dot(px, vec2(0.031, 0.047)));
		// Hot at the VS; along the rest of the seam a calmer thread of the
		// same light carries the line off both screen edges.
		float w = max(smoothstep(0.05, 0.5, clash_w), 0.42 * seal) * contact_strength;
		contact_a = clamp(own * w * (core * flicker + bloom * 0.35 * bloom_gain), 0.0, 1.0);
		contact_rgb = mix(hue, vec3(1.0), core);
		// The wire rim hands over to the clash line.
		rim_a *= 1.0 - max(smoothstep(0.1, 0.5, clash_w), seal);
	}

	float a = max(coverage * fill_a, rim_a);
	vec3 rgb = mix(tint.rgb, rim_rgb, clamp(rim_a / max(a, 0.0001), 0.0, 1.0));
	if (contact_a > 0.0) {
		float a2 = max(a, contact_a);
		rgb = mix(rgb, contact_rgb, clamp(contact_a / max(a2, 0.0001), 0.0, 1.0));
		a = a2;
	}
	COLOR = vec4(rgb, clamp(a, 0.0, 1.0)) * node_modulate;
}
