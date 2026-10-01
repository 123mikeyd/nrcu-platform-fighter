shader_type canvas_item;
render_mode unshaded;

// NRCU FX Lab vNext — layer quad shader (v0).
//
// Every vNext layer renders as a full-frame quad over the 1280x720 presentation
// canvas. The shader implements the fixed pipeline stage order
//   INPUT -> TRANSFORM -> DISPLACE -> LAYER FX -> MASK -> OPACITY/BLEND -> COMPOSITE
// where this pass covers TRANSFORM, DISPLACE, MASK, OPACITY and a passthrough
// LAYER FX hook (effect stage arrives with the FX-port unit).
//
// Spatial units: presentation pixels (specs/03 §6).

uniform sampler2D source_tex : filter_linear, repeat_disable;
uniform sampler2D disp_custom_tex : filter_linear, repeat_disable;
uniform sampler2D mask_custom_tex : filter_linear, repeat_disable;
uniform float disp_custom_loaded = 0.0;
uniform float mask_custom_loaded = 0.0;

// canvas / source placement
uniform vec2 canvas_size = vec2(1280.0, 720.0);
uniform vec4 source_rect = vec4(0.0, 0.0, 1280.0, 720.0); // x, y, w, h in presentation px
uniform vec2 source_tex_size = vec2(1280.0, 720.0);
uniform vec4 source_tint : source_color = vec4(1.0);

// INPUT selection: either the canonical source texture (ORIGINAL_SOURCE /
// TRANSFORMED_SOURCE) or a per-target offscreen stage (LAYER_BELOW /
// COMPOSITE_BELOW). With a viewport input the quad maps 1:1 to the canvas.
uniform sampler2D input_tex : filter_linear, repeat_disable;
uniform float input_is_viewport = 0.0;
uniform float input_empty = 0.0;        // viewport input with no lower layers → transparent

// TRANSFORM
uniform vec2 position_px = vec2(0.0);
uniform vec2 layer_scale = vec2(1.0);
uniform float rotation_deg = 0.0;
uniform vec2 pivot = vec2(0.5, 0.5);
uniform float flip_x = 0.0;
uniform float flip_y = 0.0;

// DISPLACE
uniform float disp_enabled = 0.0;
uniform float disp_driver = 0.0;      // 0 NOISE 1 DIRECTIONAL 2 WAVE 3 CELLULAR 4 FRINGE_DRIVER 5 CUSTOM_TEXTURE
uniform vec2 disp_amount_px = vec2(0.0);
uniform float disp_scale = 1.0;
uniform float disp_speed = 0.0;
uniform float disp_phase = 0.0;
uniform float disp_seed = 1.0;
uniform float disp_angle_deg = 0.0;
uniform float disp_edge_mode = 0.0;   // 0 TRANSPARENT 1 CLAMP 2 MIRROR 3 REPEAT
uniform float layer_time = 0.0;
uniform float free_time = 0.0;        // wall-clock for FREE_RUN displacement
uniform float disp_time_source = 0.0; // 0 PRESENTATION_TIME, 1 FREE_RUN

// MASK
uniform float mask_enabled = 0.0;
uniform float mask_source = 0.0;      // 0 NONE 1 ORIGINAL_SOURCE_ALPHA 2 POST_DISPLACEMENT_ALPHA 3 CUSTOM_MASK
uniform float mask_region = 0.0;      // 0 FULL 1 EDGE_BAND 2 OUTER_BAND 3 INNER_BAND
uniform float mask_space = 1.0;       // 0 SOURCE_SPACE 1 LAYER_SPACE 2 PRESENTATION_SPACE
uniform float mask_expand_contract_px = 0.0;
uniform float mask_width_px = 0.0;
uniform float mask_feather_px = 0.0;
uniform float mask_invert = 0.0;

// MK-05 displacement influence gate: scales the displacement offset by a mask
// field evaluated PRE-displacement (earns its semantics instead of only
// being persisted). Same source/region/space contract as layer.mask; shares
// no uniforms with it so both can be active independently.
uniform float disp_infl_enabled = 0.0;
uniform float disp_infl_source = 0.0;
uniform float disp_infl_region = 0.0;
uniform float disp_infl_space = 1.0;
uniform float disp_infl_expand_contract_px = 0.0;
uniform float disp_infl_width_px = 0.0;
uniform float disp_infl_feather_px = 0.0;
uniform float disp_infl_invert = 0.0;
uniform sampler2D disp_infl_custom_tex : filter_linear, repeat_disable;
uniform float disp_infl_custom_loaded = 0.0;

// OPACITY / output
uniform float layer_opacity = 1.0;
uniform float preview_emphasis = 1.0;

// TRANSFORMED_SOURCE stage: 1 = output the displaced canonical sample only
// (Transform + Displacement, before FX/Mask/Opacity/Blend).
uniform float stage_stop = 0.0;

// BLEND (spec 15 §12): straight RGB, Porter-Duff source-over alpha.
// 0 NORMAL · 1 ADD · 2 SCREEN · 3 MULTIPLY. NORMAL uses the plain mix path
// (bit-exact neutral parity); the others composite against the backbuffer so
// the spec math lands exactly, using the out = F replace trick.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float blend_mode = 0.0;

// v0.3 compatibility aliases (additive; written by the layer renderer).
uniform sampler2D custom_edge_mask_tex : filter_linear, repeat_disable;
uniform sampler2D treatment_mask_tex : filter_linear, repeat_disable;
uniform float custom_edge_mask_loaded = 0.0;
uniform float treatment_mask_loaded = 0.0;
uniform vec2 tex_size = vec2(1280.0,720.0);
uniform vec2 element_size = vec2(1280.0,720.0);
uniform vec2 viewport_size = vec2(1280.0,720.0);
uniform vec2 source_uv_scale = vec2(1.0);
uniform vec2 source_uv_offset = vec2(0.0);
uniform float source_flip_x = 0.0;
uniform float pure_continuous = 0.0;
uniform float pattern_scale = 1.0;    // dither/coverage/driver-grid cell scale
uniform float edge_width = 3.0;       // edge sample radius in geometry units
uniform float debug_view_mode = 0.0;
uniform float base_mode = 0.0;                 // 0 colour, 1 mono stamp
uniform float base_opacity = 1.0;              // source alpha only; generated fringe remains independent
uniform float base_grade_amount = 0.0;         // continuous; remains available in PURE CONTINUOUS
uniform float grade_black_point = 0.0;
uniform float grade_white_point = 1.0;
uniform float grade_gamma = 1.0;
uniform float grade_contrast = 1.0;
uniform float grade_brightness = 0.0;
uniform float grade_saturation = 1.0;
uniform float source_pixel_size = 0.0;
uniform float source_pixel_units = 1.0; // 0 source px, 1 presentation px         // independent source pixel grid
uniform float mono_threshold = 0.75;
uniform float mono_mode = 1.0;                 // 0 hard,1 Bayer,2 clustered noise,3 random,4 checker,5 halftone
uniform float mono_bayer_level = 2.0;
uniform float mono_pixel = 2.0;
uniform float mono_space = 1.0;                // 0 source,1 element,2 screen
uniform float fx_flow = 0.0;
uniform float dither_threshold = 0.75;
uniform float dither_black_point = 0.0;
uniform float dither_white_point = 1.0;
uniform float dither_gamma = 1.35;
uniform float dither_contrast = 1.6;
uniform float dither_brightness = 0.0;
uniform float dither_mode = 1.0;               // 0 hard,1 Bayer,2 clustered noise,3 random,4 checker,5 halftone
uniform float dither_bayer_level = 2.0;
uniform float dither_pixel = 2.0;
uniform float dither_levels = 6.0;
uniform float dither_space = 1.0;              // 0 source,1 element,2 screen
uniform float edge_source_mode = 2.0;           // 0 alpha,1 luma,2 both,3 custom edge mask
uniform float edge_alpha_weight = 1.2;
uniform float edge_luma_weight = 1.0;
uniform float edge_threshold = 0.08;
uniform float wind_reach = 32.0;
uniform float wind_trail = 0.35;
uniform float wind_cutoff = 0.22;
uniform float split_separation = 10.0;
uniform float wind_displace = 1.0;
uniform float signal_gain = 1.35;
uniform float color_blur = 0.0;
uniform float signal_softness = 0.08;
uniform float signal_posterize = 0.0;
uniform float fringe_coverage_mode = 0.0;       // 0 smooth,1 Bayer,2 clustered noise,3 random,4 checker,5 halftone
uniform float fringe_coverage_threshold = 0.12;
uniform float fringe_bayer_level = 2.0;
uniform float fringe_pixel = 2.0;
uniform float fringe_space = 1.0;
uniform float fringe_coverage_gain = 1.0;
uniform float rgb_gradient = 0.0;
uniform float rgb_gradient_balance = 0.0;
uniform float rgb_gradient_contrast = 1.0;
uniform vec4 fringe_color_a : source_color = vec4(0.25,0.95,1.0,1.0);
uniform vec4 fringe_color_b : source_color = vec4(1.0,0.4,0.85,1.0);
uniform float fringe_bleed = 0.65;
uniform float fringe_blend_mode = 0.0;          // 0 normal,1 additive,2 screen
uniform float geometry_units = 1.0;             // 0 source px,1 presentation px
uniform float effect_mask_enabled = 0.0;
uniform float effect_mask_invert = 0.0;
uniform float effect_mask_threshold = 0.5;
uniform float effect_mask_softness = 0.10;
uniform float effect_mask_base = 0.0;
uniform float driver_mode = 0.0;
uniform float driver_sampling_mode = 0.0;       // 0 continuous,1 pixel grid
uniform float driver_pixel_size = 2.0;
uniform float FIELD_STRENGTH = 0.42;
uniform float FIELD_SPEED = 0.55;
uniform float OUTWARDNESS = 0.55;
uniform float FIELD_BREAKUP = 0.85;
uniform float COORD_NUDGE = 0.18;
uniform float FIELD_SIZE = 1.0;
uniform vec2 FIELD_CENTER = vec2(1.25,1.45);
uniform float LEGACY_SCALE = 5.0;
uniform float LEGACY_SPEED = 0.3;
uniform float LEGACY_RADIAL = 0.45;
uniform vec2 DRIVER_CENTER = vec2(1.5,1.5);
uniform float DRIVER_SCALE = 1.0;
uniform float DRIVER_STRETCH = 0.0;
uniform float DRIVER_ANGLE = 0.0;
uniform float DRIVER_SPEED = 1.0;
uniform float DRIVER_DETAIL = 0.5;
uniform float DRIVER_FLOW = 0.5;
uniform float flow_strength = 12.0;
uniform float flow_center_x = 0.5;
uniform float flow_center_y = 0.5;
uniform float rgb_shift_amount = 6.0;
uniform float rgb_shift_angle = 0.0;
uniform float rgb_shift_units = 1.0;            // 0 source px,1 presentation px
uniform float rgb_shift_alpha = 0.0;
uniform float temporal_hold = 0.0;
uniform float fx_time_source = 0.0;                 // 0 presentation/layer time, 1 free-run time
uniform float palette_strategy = 0.0;               // 0 authored, 1 source-derived
uniform float palette_hue_offset = 0.0;
uniform float palette_saturation = 1.0;
uniform float palette_value = 1.0;
uniform float palette_lock_a = 0.0;
uniform float palette_lock_b = 0.0;
uniform float palette_swap = 0.0;
uniform vec3 palette_source_color = vec3(0.5);

// v0.3 compatibility uniforms. These are additive aliases used by the
// certified legacy math port; layer authors still persist the vNEXT fx keys.


// LAYER FX — ported from the certified v0.2 effect stage (same math, layer
// context). Amounts 0..n; colors as authored.
uniform float fx_time = 0.0;
uniform float fx_pure_continuous = 0.0;
uniform float fx_size = 1.0;
uniform float fx_intensity = 1.0;
uniform float fx_pattern_scale = 1.0;
uniform float fx_fringe = 0.0;
uniform float fx_rgb = 0.0;
uniform float fx_dither = 0.0;
uniform float fx_edge_width = 3.0;
uniform float fx_edge_alpha_weight = 1.2;
uniform float fx_edge_luma_weight = 1.0;
uniform float fx_edge_threshold = 0.08;
uniform float fx_edge_source_mode = 2.0;   // 0 alpha 1 luma 2 both
uniform float fx_wind_reach = 32.0;
uniform float fx_wind_trail = 0.35;
uniform float fx_wind_cutoff = 0.22;
uniform float fx_split_separation = 10.0;
uniform float fx_signal_gain = 1.35;
uniform float fx_color_blur = 0.0;
uniform float fx_signal_softness = 0.08;
uniform float fx_signal_posterize = 0.0;
uniform float fx_coverage_mode = 0.0;
uniform float fx_coverage_threshold = 0.12;
uniform float fx_coverage_gain = 1.0;
uniform float fx_coverage_bayer_level = 2.0;
uniform float fx_coverage_pixel = 2.0;
uniform vec4 fx_fringe_color_a : source_color = vec4(0.25, 0.95, 1.0, 1.0);
uniform vec4 fx_fringe_color_b : source_color = vec4(1.0, 0.4, 0.85, 1.0);
uniform float fx_fringe_bleed = 0.65;
uniform float fx_fringe_blend = 0.0;       // 0 normal 1 add 2 screen
uniform float fx_rgb_shift_px = 6.0;
uniform float fx_rgb_angle = 0.0;
uniform float fx_rgb_alpha = 0.0;
uniform float fx_dither_black = 0.0;
uniform float fx_dither_white = 1.0;
uniform float fx_dither_gamma = 1.35;
uniform float fx_dither_contrast = 1.6;
uniform float fx_dither_brightness = 0.0;
uniform float fx_dither_mode = 1.0;
uniform float fx_dither_bayer_level = 2.0;
uniform float fx_dither_levels = 6.0;
uniform float fx_dither_pixel = 2.0;
uniform float fx_dither_space = 2.0;

// Gold local operators. These operate on the layer-selected input
// (ORIGINAL_SOURCE or an offscreen local stage), never on a fringe/RGB/dither
// alias. Their phase is driven by the renderer-supplied clocks.
uniform float gold_operator_mode = 0.0; // 0 NONE, 1 noise_erosion_border, 2 pixel_sort_smear
uniform float gold_operator_strength = 0.0;
uniform float gold_operator_scale = 1.0;
uniform float gold_operator_speed = 1.0;
uniform float gold_operator_threshold = 0.5;
uniform float gold_operator_softness = 0.1;
uniform float gold_operator_axis_x = 1.0;
uniform float gold_operator_axis_y = 0.0;
uniform float gold_operator_time_source = 0.0;
uniform vec4 gold_operator_color_a : source_color = vec4(0.25, 0.95, 1.0, 1.0);
uniform vec4 gold_operator_color_b : source_color = vec4(1.0, 0.35, 0.82, 1.0);

const float EPS = 0.0001;

// ============================ noise ============================
float rng(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float noise_val(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(rng(i), rng(i + vec2(1.0, 0.0)), u.x), mix(rng(i + vec2(0.0, 1.0)), rng(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 1.0;
	float f = 1.0;
	for (int i = 0; i < 3; i++) {
		v += a * noise_val(p * f);
		f *= 2.1;
		a *= 0.5;
	}
	return v / 1.75;
}
vec2 rotate_05(vec2 p) { float c = cos(0.5); float s = sin(0.5); return vec2(c * p.x + s * p.y, -s * p.x + c * p.y); }
float fbm_driver(vec2 p) { float v = 0.0; float a = 0.5; vec2 shift = vec2(100.0); for (int i = 0; i < 5; i++) { v += a * noise_val(p); p = rotate_05(p) * 2.0 + shift; a *= 0.5; } return v; }
vec2 hash22(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973)); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.xx + p3.yz) * p3.zy); }
vec3 hash33(vec3 p) { float n = sin(dot(p, vec3(7.0, 157.0, 113.0))); return fract(vec3(2097152.0, 262144.0, 32768.0) * n) * 2.0 - 1.0; }
vec3 hash33_01(vec3 p) { float n = sin(dot(p, vec3(7.0, 157.0, 113.0))); return fract(vec3(2097152.0, 262144.0, 32768.0) * n); }
float cell_noise(vec2 p, float seed) {
	vec2 cell = floor(p);
	float best = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 pt = c + vec2(rng(c + vec2(seed, seed * 1.7)), rng(c + vec2(seed * 2.3, seed)));
			best = min(best, length(p - pt));
		}
	}
	return best;
}

// ============================ source access ============================
// Maps presentation pixel -> source uv through the inverse layer transform.
vec2 inverse_transform_uv(vec2 pres_px) {
	vec2 rect_origin = source_rect.xy;
	vec2 rect_size = max(source_rect.zw, vec2(1.0));
	vec2 pivot_px = rect_origin + pivot * rect_size;
	vec2 p = pres_px - position_px - pivot_px;
	float th = radians(-rotation_deg);
	float c = cos(th);
	float s = sin(th);
	vec2 rotated = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
	vec2 unscaled = rotated / max(layer_scale, vec2(EPS));
	vec2 canvas_pt = unscaled + pivot_px;
	vec2 uv = (canvas_pt - rect_origin) / rect_size;
	if (flip_x > 0.5) { uv.x = 2.0 * pivot.x - uv.x; }
	if (flip_y > 0.5) { uv.y = 2.0 * pivot.y - uv.y; }
	return uv;
}

vec4 sample_source(vec2 uv) {
	// displacement edge modes
	if (disp_edge_mode < 0.5) {
		if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
			return vec4(0.0);
		}
	} else if (disp_edge_mode < 1.5) {
		uv = clamp(uv, vec2(0.0), vec2(1.0));
	} else if (disp_edge_mode < 2.5) {
		uv = abs(fract(uv * 0.5) * 2.0 - 1.0); // mirror
	} else {
		uv = fract(uv);
	}
	if (input_is_viewport > 0.5) {
		if (input_empty > 0.5) {
			return vec4(0.0); // defined transparent input (specs/F): no lower layer
		}
		return texture(input_tex, clamp(uv, vec2(0.0), vec2(1.0)));
	}
	return texture(source_tex, clamp(uv, vec2(0.0), vec2(1.0))) * source_tint;
}


// Legacy v0.3 effect stage samples the layer-selected input.
// accessors adjacent to sample_source make ORIGINAL_SOURCE, transformed
// source, and offscreen input paths share identical math.
float inside_source_uv_vnext(vec2 uv){return step(vec2(0.0),uv).x*step(vec2(0.0),uv).y*step(uv,vec2(1.0)).x*step(uv,vec2(1.0)).y;}
float raw_luma(vec2 uv) { return dot(sample_source(uv).rgb, vec3(0.299, 0.587, 0.114)); }
float raw_alpha(vec2 uv) { return sample_source(uv).a; }
float raw_edge_mask(vec2 uv) { return texture(custom_edge_mask_tex, clamp(uv, vec2(0.0), vec2(1.0))).r * inside_source_uv_vnext(uv); }
float raw_treatment_mask(vec2 uv) { return texture(treatment_mask_tex, clamp(uv, vec2(0.0), vec2(1.0))).r * inside_source_uv_vnext(uv); }
float fx_effect_mask_value(vec2 uv) {
	if (effect_mask_enabled < 0.5 || treatment_mask_loaded < 0.5) { return 1.0; }
	float m = raw_treatment_mask(uv);
	if (effect_mask_invert > 0.5) { m = 1.0 - m; }
	float soft = max(effect_mask_softness, 0.0001);
	return smoothstep(effect_mask_threshold - soft, effect_mask_threshold + soft, m);
}

float alpha_at_uv(vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		// Full-canvas sources (side-field proxies) continue past the screen:
		// the monitor edge is not a silhouette edge and must not grow a rim.
		if (source_rect.z >= canvas_size.x - 1.0 && source_rect.w >= canvas_size.y - 1.0) {
			uv = clamp(uv, vec2(0.0), vec2(1.0));
		} else {
			return 0.0;
		}
	}
	// Route through the input selection (canonical source OR the layer's
	// viewport input) so edge detection and silhouette masks always run on the
	// FX layer's actual input — never on the canonical texture by accident.
	// The silhouette is the SHAPE alpha: a canonical tint (e.g. a 12 % side
	// field) is paint, not coverage, and must not push the shape under the
	// 0.5 edge threshold.
	if (input_is_viewport < 0.5) {
		return clamp(sample_source(uv).a / max(source_tint.a, 0.0001), 0.0, 1.0);
	}
	return sample_source(uv).a;
}

// ============================ displacement ============================
vec2 displacement_offset(vec2 pres_px, float edge_dir_sign) {
	if (disp_enabled < 0.5) {
		return vec2(0.0);
	}
	vec2 rect_center = source_rect.xy + source_rect.zw * 0.5;
	float scale = max(disp_scale, EPS);
	float t = (disp_time_source > 0.5 ? free_time : layer_time) * disp_speed + disp_phase; // select, never mix: mix(a,b,1) leaks a via rounding
	vec2 field_p = pres_px / scale;
	vec2 offset_dir = vec2(0.0);
	float magnitude = 1.0;
	if (disp_driver < 0.5) {
		// NOISE
		float n1 = fbm(field_p + vec2(disp_seed * 13.1, disp_seed * 7.7) + t);
		float n2 = fbm(field_p + vec2(disp_seed * 5.3 + 31.0, disp_seed * 11.9) - t);
		offset_dir = vec2(n1, n2) * 2.0 - 1.0;
	} else if (disp_driver < 1.5) {
		// DIRECTIONAL
		float th = radians(disp_angle_deg);
		vec2 dir = vec2(cos(th), sin(th));
		float wave = sin(dot(field_p, dir) * 3.14159 + t * 2.0);
		offset_dir = dir * wave;
	} else if (disp_driver < 2.5) {
		// WAVE (radial)
		vec2 rel = pres_px - rect_center;
		float r = length(rel) / max(scale, EPS);
		float wave = sin(r * 3.14159 - t * 2.0);
		offset_dir = normalize(rel + vec2(EPS)) * wave;
	} else if (disp_driver < 3.5) {
		// CELLULAR
		float c1 = cell_noise(field_p + vec2(disp_seed * 3.1, disp_seed * 1.3) + t * 0.5, disp_seed);
		float c2 = cell_noise(field_p + vec2(disp_seed * 7.7 + 19.0, disp_seed * 2.9) - t * 0.5, disp_seed + 3.0);
		offset_dir = vec2(c1, c2) * 2.0 - 1.0;
	} else if (disp_driver < 4.5) {
		// FRINGE_DRIVER: outward from the silhouette (edge normal approximation)
		vec2 rel = pres_px - rect_center;
		offset_dir = normalize(rel + vec2(EPS)) * edge_dir_sign;
	} else {
		// CUSTOM_TEXTURE
		if (disp_custom_loaded > 0.5) {
			vec2 uv = pres_px / max(canvas_size, vec2(1.0));
			vec4 tex = texture(disp_custom_tex, uv);
			offset_dir = tex.rg * 2.0 - 1.0;
		} else {
			offset_dir = vec2(0.0);
		}
	}
	return offset_dir * disp_amount_px * magnitude;
}

// ============================ mask ============================
// Signed distance estimate to the alpha silhouette in presentation px
// (positive inside). Multi-direction scan with bisection.
float silhouette_distance_px(vec2 base_uv, float max_width_px) {
	vec2 rect_size = max(source_rect.zw, vec2(1.0));
	vec2 px_per_uv = rect_size;
	float max_r_uv = max_width_px / max(min(px_per_uv.x, px_per_uv.y), EPS);
	float a0 = alpha_at_uv(base_uv);
	float sign_in = a0 > 0.5 ? 1.0 : -1.0;
	float best = max_r_uv;
	bool found = false;
	float step = max_r_uv / 5.0;
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * 0.785398;
		vec2 dir = vec2(cos(ang), sin(ang));
		float prev = a0;
		for (int k = 1; k <= 5; k++) {
			float r = float(k) * step;
			float a = alpha_at_uv(base_uv + dir * r);
			if ((a > 0.5 ? 1.0 : -1.0) != sign_in) {
				// bisect between (k-1)*step and k*step
				float lo = float(k - 1) * step;
				float hi = r;
				for (int b = 0; b < 3; b++) {
					float mid = (lo + hi) * 0.5;
					float am = alpha_at_uv(base_uv + dir * mid);
					if ((am > 0.5 ? 1.0 : -1.0) == sign_in) {
						lo = mid;
					} else {
						hi = mid;
					}
				}
				best = min(best, hi);
				found = true;
				break;
			}
			prev = a;
		}
	}
	float d_px = best * min(px_per_uv.x, px_per_uv.y);
	return d_px * sign_in;
}

vec2 inverse_transform_uv_clamped(vec2 pres_px) {
	vec2 uv = inverse_transform_uv(pres_px);
	return clamp(uv, vec2(0.0), vec2(1.0));
}

// PRESENTATION_SPACE silhouette scan: probes are taken in canvas px through the
// live Transform + Displacement mapping, so the scan frame stays anchored to
// the canonical 1280x720 canvas (content edges are still the drawn edges).
float alpha_at_pres(vec2 p) {
	return alpha_at_uv(inverse_transform_uv_clamped(p - displacement_offset(p, 1.0)));
}

float silhouette_distance_pres(vec2 base_px, float max_width_px) {
	float a0 = alpha_at_pres(base_px);
	float sign_in = a0 > 0.5 ? 1.0 : -1.0;
	float best = max_width_px;
	bool found = false;
	float step = max_width_px / 5.0;
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * 0.785398;
		vec2 dir = vec2(cos(ang), sin(ang));
		for (int k = 1; k <= 5; k++) {
			float r = float(k) * step;
			float a = alpha_at_pres(base_px + dir * r);
			if ((a > 0.5 ? 1.0 : -1.0) != sign_in) {
				float lo = float(k - 1) * step;
				float hi = r;
				for (int b = 0; b < 3; b++) {
					float mid = (lo + hi) * 0.5;
					float am = alpha_at_pres(base_px + dir * mid);
					if ((am > 0.5 ? 1.0 : -1.0) == sign_in) {
						lo = mid;
					} else {
						hi = mid;
					}
				}
				best = min(best, hi);
				found = true;
				break;
			}
		}
	}
	return best * sign_in;
}

float mask_factor(vec2 final_uv, vec2 uv_pre, vec2 pres_px) {
	if (mask_enabled < 0.5) {
		return 1.0;
	}
	if (mask_source > 2.5) {
		// CUSTOM_MASK: use custom texture alpha as the field, sampled in the
		// mask's coordinate space (SOURCE_SPACE: asset coords; LAYER_SPACE:
		// transformed coords; PRESENTATION_SPACE: canvas coords).
		vec2 custom_uv = pres_px / max(canvas_size, vec2(1.0));
		if (mask_space < 0.5) {
			custom_uv = uv_pre;
		} else if (mask_space < 1.5) {
			custom_uv = final_uv;
		}
		float a = 0.0;
		// MK-03 fail-closed: a CUSTOM_MASK source with no loaded asset samples
		// EMPTY, never full. Production validation rejects such docs at apply
		// time; this is the last line of defense for unvalidated render paths.
		if (mask_custom_loaded > 0.5) {
			a = texture(mask_custom_tex, clamp(custom_uv, vec2(0.0), vec2(1.0))).a;
		}
		float soft = max(mask_feather_px, 0.001) * 0.01 + 0.001;
		float f = smoothstep(0.5 - soft, 0.5 + soft, a);
		if (mask_region > 2.5) {
			f = 1.0 - f; // inner band of a custom field
		} else if (mask_region > 1.5) {
			f = 1.0 - f; // outer band of a custom field
		}
		return mask_invert > 0.5 ? 1.0 - f : f;
	}
	if (mask_source < 0.5) {
		return 1.0; // NONE: no mask field
	}
	if (mask_region < 0.5) {
		return mask_invert > 0.5 ? 0.0 : 1.0;
	}
	// Mask coordinate spaces (specs/05, specs/15 §7). All distances are
	// Presentation px; only the field/scan frame changes:
	//   SOURCE_SPACE       -> anchored to pre-Transform/-Displacement asset coords
	//   LAYER_SPACE        -> follows the layer's Transform + Displacement result
	//   PRESENTATION_SPACE -> anchored to the canonical 1280x720 canvas (scan
	//                         geometry in canvas axes; content edges are probed
	//                         through the live transform, so the band does not
	//                         rotate/ride with the layer)
	vec2 basis_uv = final_uv;
	vec2 scan_uv = final_uv;
	bool pres_scan = false;
	if (mask_space < 0.5) {
		basis_uv = uv_pre;
		scan_uv = uv_pre;
	} else if (mask_space > 1.5) {
		pres_scan = true;
	}
	if (mask_source < 1.5 && mask_space < 1.5) {
		// ORIGINAL_SOURCE_ALPHA: pre-transform silhouette in the same frame
		basis_uv = (mask_space < 0.5) ? uv_pre : inverse_transform_uv_clamped(pres_px);
		scan_uv = basis_uv;
	}
	float scan = max(mask_width_px + mask_feather_px + abs(mask_expand_contract_px), 1.0) + 2.0;
	float d_adj = 0.0;
	if (pres_scan) {
		d_adj = silhouette_distance_pres(pres_px, scan) + mask_expand_contract_px;
	} else {
		d_adj = silhouette_distance_px(scan_uv, scan) + mask_expand_contract_px;
	}
	float feather = max(mask_feather_px, 0.001);
	float f = 0.0;
	if (mask_region < 1.5) {
		// EDGE_BAND: centered on the adjusted edge
		float half_w = max(mask_width_px, 0.001) * 0.5;
		f = 1.0 - smoothstep(half_w - feather * 0.5, half_w + feather * 0.5, abs(d_adj));
	} else if (mask_region < 2.5) {
		// OUTER_BAND: from -width to 0 (outside the silhouette)
		f = smoothstep(-mask_width_px - feather, -mask_width_px + feather, d_adj) * (1.0 - smoothstep(-feather * 0.5, feather * 0.5, d_adj));
	} else {
		// INNER_BAND: 0..width inside the silhouette
		f = smoothstep(-feather * 0.5, feather * 0.5, d_adj) * (1.0 - smoothstep(mask_width_px - feather, mask_width_px + feather, d_adj));
	}
	return mask_invert > 0.5 ? 1.0 - f : f;
}

// MK-05: displacement influence gate. Same field contract as mask_factor but
// evaluated PRE-displacement (caller passes the transform-only uv as
// final_uv) and driven by the disp_infl_* uniforms, so layer.mask and the
// influence gate compose independently. Disabled = 1.0 (full displacement,
// backward compatible). CUSTOM asset missing = 0.0 (fail-closed, mirrors
// mask_factor).
float influence_factor(vec2 final_uv, vec2 uv_pre, vec2 pres_px) {
	if (disp_infl_enabled < 0.5) {
		return 1.0;
	}
	if (disp_infl_source > 2.5) {
		vec2 custom_uv = pres_px / max(canvas_size, vec2(1.0));
		if (disp_infl_space < 0.5) {
			custom_uv = uv_pre;
		} else if (disp_infl_space < 1.5) {
			custom_uv = final_uv;
		}
		float a = 0.0;
		if (disp_infl_custom_loaded > 0.5) {
			a = texture(disp_infl_custom_tex, clamp(custom_uv, vec2(0.0), vec2(1.0))).a;
		}
		float soft = max(disp_infl_feather_px, 0.001) * 0.01 + 0.001;
		float f = smoothstep(0.5 - soft, 0.5 + soft, a);
		if (disp_infl_region > 2.5) {
			f = 1.0 - f;
		} else if (disp_infl_region > 1.5) {
			f = 1.0 - f;
		}
		return disp_infl_invert > 0.5 ? 1.0 - f : f;
	}
	if (disp_infl_source < 0.5) {
		return 1.0;
	}
	if (disp_infl_region < 0.5) {
		return disp_infl_invert > 0.5 ? 0.0 : 1.0;
	}
	vec2 basis_uv = final_uv;
	vec2 scan_uv = final_uv;
	bool pres_scan = false;
	if (disp_infl_space < 0.5) {
		basis_uv = uv_pre;
		scan_uv = uv_pre;
	} else if (disp_infl_space > 1.5) {
		pres_scan = true;
	}
	if (disp_infl_source < 1.5 && disp_infl_space < 1.5) {
		basis_uv = (disp_infl_space < 0.5) ? uv_pre : inverse_transform_uv_clamped(pres_px);
		scan_uv = basis_uv;
	}
	float scan = max(disp_infl_width_px + disp_infl_feather_px + abs(disp_infl_expand_contract_px), 1.0) + 2.0;
	float d_adj = 0.0;
	if (pres_scan) {
		d_adj = silhouette_distance_pres(pres_px, scan) + disp_infl_expand_contract_px;
	} else {
		d_adj = silhouette_distance_px(scan_uv, scan) + disp_infl_expand_contract_px;
	}
	float feather = max(disp_infl_feather_px, 0.001);
	float f = 0.0;
	if (disp_infl_region < 1.5) {
		float half_w = max(disp_infl_width_px, 0.001) * 0.5;
		f = 1.0 - smoothstep(half_w - feather * 0.5, half_w + feather * 0.5, abs(d_adj));
	} else if (disp_infl_region < 2.5) {
		f = smoothstep(-disp_infl_width_px - feather, -disp_infl_width_px + feather, d_adj) * (1.0 - smoothstep(-feather * 0.5, feather * 0.5, d_adj));
	} else {
		f = smoothstep(-feather * 0.5, feather * 0.5, d_adj) * (1.0 - smoothstep(disp_infl_width_px - feather, disp_infl_width_px + feather, d_adj));
	}
	return disp_infl_invert > 0.5 ? 1.0 - f : f;
}

// ============================ v0.3 flow/driver catalogue ============================
// =========== travelling whisp driver ===========
vec2 ripple_vector(vec2 uv,vec2 center,float time,float scale,float speed){
	vec2 to_pixel=uv-center;
	float d=length(to_pixel)+0.0001;
	vec2 dir=to_pixel/d;
	float phase=d*scale-time*speed;
	float wave=cos(phase);
	float falloff=exp(-d*1.05);
	return dir*wave*falloff;
}
float ripple_line(vec2 uv,vec2 center,float time,float scale,float speed){
	float d=distance(uv,center);
	float phase=d*scale-time*speed;
	float wave=sin(phase);
	float falloff=exp(-d*1.2);
	return wave*falloff;
}
vec4 travelling_whisp_core(vec2 st,float time){
	float size=max(FIELD_SIZE,0.0001);
	float ripple_scale=32.0/size;
	float speed=FIELD_SPEED;
	vec2 uv=st/3.0;
	vec2 center=FIELD_CENTER/3.0;

	vec2 breaker;
	breaker.x=fbm_driver(uv*mix(0.8,2.4,FIELD_BREAKUP)+vec2(time*0.025,3.1));
	breaker.y=fbm_driver(uv*mix(0.8,2.4,FIELD_BREAKUP)+vec2(8.7,-time*0.022));
	breaker=breaker*2.0-1.0;
	vec2 ripple_uv=uv+breaker*0.095;

	vec2 c0=center;
	vec2 c1=center+vec2(-0.54,-0.30)*size;
	vec2 c2=center+vec2(1.01,0.28)*size;

	vec2 push=vec2(0.0);
	float ring=0.0;
	push+=ripple_vector(ripple_uv,c0,time,ripple_scale,speed*3.05)*1.00;
	push+=ripple_vector(ripple_uv,c1,time,ripple_scale*0.75,speed*2.10)*0.45;
	push+=ripple_vector(ripple_uv,c2,time,ripple_scale*0.59,speed*1.55)*0.35;
	ring+=ripple_line(ripple_uv,c0,time,ripple_scale,speed*3.05)*1.00;
	ring+=ripple_line(ripple_uv,c1,time,ripple_scale*0.75,speed*2.10)*0.35;
	ring+=ripple_line(ripple_uv,c2,time,ripple_scale*0.59,speed*1.55)*0.25;

	float matter_mask=fbm_driver(uv*0.75+vec2(0.0,time*0.018));
	matter_mask=smoothstep(0.18,0.92,matter_mask);
	push*=matter_mask;
	ring*=matter_mask;

	vec2 base_uv=uv+push*0.052;
	vec2 q;
	q.x=fbm_driver(base_uv*2.0+ring*0.18);
	q.y=fbm_driver(base_uv*2.0+vec2(5.2,1.3)-ring*0.18);
	vec2 r;
	r.x=fbm_driver(base_uv*2.0+4.0*q+vec2(1.7,9.2)+ring*0.45);
	r.y=fbm_driver(base_uv*2.0+4.0*q+vec2(8.3,2.8)-ring*0.45);
	float f=fbm_driver(base_uv*2.0+q+r*1.65)+ring*0.055;
	f=smoothstep(0.18,0.92,f);

	vec2 smoke=normalize((q-vec2(0.5))+(r-vec2(0.5))*0.65+vec2(0.0001));
	vec2 field=mix(smoke,push*18.0,clamp(OUTWARDNESS,0.0,1.0));
	return vec4(field,f-0.5,ring);
}
vec2 travelling_whisp_field(vec2 st,float time){ return travelling_whisp_core(st,time).xy; }
float travelling_whisp_amount(vec2 st,float time){ return travelling_whisp_core(st,time).z; }

// =========== driver catalogue (modes 2-13) ===========
float voronoi2(vec2 p,float time){
	vec2 g=floor(p);
	vec2 f=fract(p);
	float d=1.0;
	for(int y=-1;y<=1;y++){
		for(int x=-1;x<=1;x++){
			vec2 cell=vec2(float(x),float(y));
			vec2 h=hash22(g+cell);
			vec2 jitter=0.5+mix(0.16,0.48,DRIVER_DETAIL)*sin(time*0.55+6.2831853*h);
			vec2 r=cell+jitter-f;
			d=min(d,dot(r,r));
		}
	}
	return 1.0-smoothstep(mix(0.08,0.012,DRIVER_DETAIL),mix(0.92,0.52,DRIVER_DETAIL),d);
}
float voronoi_layers(vec2 p,float time){
	float a=0.55;
	float v=0.0;
	float s=0.0;
	for(int i=0;i<4;i++){
		v+=voronoi2(p,time)*a;
		s+=a;
		p=rotate_05(p*mix(1.35,2.25,DRIVER_DETAIL)+vec2(3.7,1.9));
		time*=mix(1.12,1.72,DRIVER_DETAIL);
		a*=mix(0.42,0.68,DRIVER_DETAIL);
	}
	return v/max(s,0.001);
}
float combustible_voronoi(vec3 p){
	vec3 g=floor(p);
	p=fract(p);
	float d=1.0;
	for(int y=-1;y<=1;y++){
		for(int x=-1;x<=1;x++){
			vec3 b=vec3(float(x),float(y),-1.0);
			vec3 r=b-p+hash33_01(g+b);
			d=min(d,dot(r,r));
			b.z=0.0;
			r=b-p+hash33_01(g+b);
			d=min(d,dot(r,r));
			b.z=1.0;
			r=b-p+hash33_01(g+b);
			d=min(d,dot(r,r));
		}
	}
	return d;
}
float combustible_noise_layers(vec3 p,float time){
	vec3 t=vec3(0.0,0.0,p.z+time*0.45);
	float total=0.0;
	float sum=0.0;
	float amp=1.0;
	for(int i=0;i<5;i++){
		total+=combustible_voronoi(p+t)*amp;
		p*=2.0;
		t*=1.5;
		sum+=amp;
		amp*=0.5;
	}
	return total/max(sum,0.001);
}
float combustible_voronoi_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 uv=(p-vec2(1.5))*mix(0.42,1.25,detail);
	uv+=vec2(time*0.006,-time*0.0035)*smoothstep(0.35,1.0,detail);
	float z=0.35+time*mix(0.012,0.085,detail);
	float sample_scale=mix(0.72,1.85,detail);
	float blur=mix(0.16,0.025,detail);
	float c=combustible_noise_layers(vec3(uv,z)*sample_scale,time);
	c+=combustible_noise_layers(vec3(uv+vec2( blur,0.0),z)*sample_scale,time)*0.18;
	c+=combustible_noise_layers(vec3(uv+vec2(-blur,0.0),z)*sample_scale,time)*0.18;
	c+=combustible_noise_layers(vec3(uv+vec2(0.0, blur),z)*sample_scale,time)*0.18;
	c+=combustible_noise_layers(vec3(uv+vec2(0.0,-blur),z)*sample_scale,time)*0.18;
	c/=1.72;
	float soft=pow(clamp(c,0.0,1.0),mix(0.72,1.18,detail));
	float hard=smoothstep(0.22,0.70,c);
	return clamp(mix(soft,hard,smoothstep(0.72,1.0,detail)),0.0,1.0);
}
vec2 phasorish(vec2 position,vec2 direction,float phase_offset,float scale_variation){
	vec2 i=floor(position);
	vec2 f=fract(position);
	vec2 u=f*f*(3.0-2.0*f);
	vec2 n00=hash22(i+vec2(0.0,0.0));
	vec2 n10=hash22(i+vec2(1.0,0.0));
	vec2 n01=hash22(i+vec2(0.0,1.0));
	vec2 n11=hash22(i+vec2(1.0,1.0));
	vec2 d00=position-(i+vec2(0.0,0.0));
	vec2 d10=position-(i+vec2(1.0,0.0));
	vec2 d01=position-(i+vec2(0.0,1.0));
	vec2 d11=position-(i+vec2(1.0,1.0));
	float a00=dot(direction,d00)*(1.0+scale_variation*(2.0*n00.y-1.0))+n00.x*6.2831853+phase_offset;
	float a10=dot(direction,d10)*(1.0+scale_variation*(2.0*n10.y-1.0))+n10.x*6.2831853+phase_offset;
	float a01=dot(direction,d01)*(1.0+scale_variation*(2.0*n01.y-1.0))+n01.x*6.2831853+phase_offset;
	float a11=dot(direction,d11)*(1.0+scale_variation*(2.0*n11.y-1.0))+n11.x*6.2831853+phase_offset;
	vec2 c00=vec2(cos(a00),sin(a00));
	vec2 c10=vec2(cos(a10),sin(a10));
	vec2 c01=vec2(cos(a01),sin(a01));
	vec2 c11=vec2(cos(a11),sin(a11));
	return mix(mix(c00,c10,u.x),mix(c01,c11,u.x),u.y);
}
vec2 phasor_flow(vec2 p,float time){
	float n1=fbm_driver(p*0.38+vec2(time*0.06,-time*0.035));
	float n2=fbm_driver(p*0.61+vec2(-time*0.02,time*0.05));
	vec2 base=normalize(vec2(1.0,0.72)+vec2(n1-0.5,n2-0.5)*2.1);
	return normalize(mix(base,vec2(-base.y,base.x),DRIVER_FLOW*0.65));
}
float phasor_amount(vec2 p,float time){
	vec2 flow=phasor_flow(p,time);
	vec2 normal=vec2(-flow.y,flow.x);
	vec2 s0=phasorish(p*7.5+flow*time*0.55,normal*8.0,time*1.6,DRIVER_DETAIL);
	vec2 s1=phasorish(p*12.0-flow*time*0.28+vec2(31.7,12.4),normal*5.5,-time*1.1,DRIVER_DETAIL);
	float line=mix(s0.x,s1.x,0.35);
	return smoothstep(-0.45,0.45,line);
}
float tetra_noise(vec3 p){
	vec3 i=floor(p+dot(p,vec3(0.333333)));
	p-=i-dot(i,vec3(0.166666));
	vec3 i1=step(p.yzx,p);
	vec3 i2=max(i1,1.0-i1.zxy);
	i1=min(i1,1.0-i1.zxy);
	vec3 p1=p-i1+0.166666;
	vec3 p2=p-i2+0.333333;
	vec3 p3=p-0.5;
	vec4 v=max(0.5-vec4(dot(p,p),dot(p1,p1),dot(p2,p2),dot(p3,p3)),0.0);
	vec4 d=vec4(dot(p,hash33(i)),dot(p1,hash33(i+i1)),dot(p2,hash33(i+i2)),dot(p3,hash33(i+1.0)));
	return clamp(dot(d,v*v*v*8.0)*1.732+0.5,0.0,1.0);
}
float isoline_amount(vec2 p,float time,float source_drive){
	p+=vec2(-time*0.24,time*0.07);
	float n=tetra_noise(vec3(p*1.15,source_drive*1.8))*0.55;
	n*=tetra_noise(vec3(p*0.37+vec2(8.0,-4.0),time*0.08))*1.55;
	n=mix(n,dot(p,vec2(-0.66,1.0))*0.22+source_drive*0.42,0.55);
	float spacing=mix(0.055,0.018,DRIVER_DETAIL);
	float lines=abs(fract(n/spacing)-0.5)*2.0;
	return 1.0-smoothstep(0.18,0.74,lines);
}
float spiral_amount(vec2 p,float time){
	vec2 q=p-vec2(1.5);
	float r=length(q);
	float a=atan(q.x,q.y)+time*0.22;
	vec2 ring=vec2(cos(a),sin(a))*mix(14.0,42.0,DRIVER_DETAIL);
	float c=fbm_driver(ring+vec2(fbm_driver(q+time*0.18),-fbm_driver(q-time*0.12))*18.0);
	return smoothstep(0.30,0.42,c)*(1.0-smoothstep(2.4,4.2,r));
}
float curl_smoke_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 q=p;
	vec2 drift=vec2(time*0.11,-time*0.07);
	float n1=fbm_driver(q*mix(0.42,0.92,detail)+drift);
	float n2=fbm_driver(q*mix(0.68,1.65,detail)+vec2(-time*0.06,time*0.09)+vec2(7.2,-3.1));
	vec2 curl=vec2(n1-0.5,n2-0.5);
	q+=vec2(-curl.y,curl.x)*mix(1.2,3.8,detail);
	float smoke=fbm_driver(q*mix(0.55,1.45,detail)+curl*1.7+drift*0.55);
	return smoothstep(mix(0.24,0.36,detail),mix(0.78,0.62,detail),smoke);
}
float wavefront_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 dir=normalize(vec2(0.78,0.38)+vec2(DRIVER_FLOW-0.5,0.0));
	float warp=fbm_driver(p*mix(0.35,1.1,detail)+vec2(time*0.05,-time*0.03));
	float freq=mix(1.6,7.5,detail);
	float phase=dot(p,dir)*freq-time*mix(0.55,2.4,detail)+warp*mix(1.2,4.8,detail);
	float wave=0.5+0.5*sin(phase);
	return smoothstep(mix(0.18,0.35,detail),mix(0.82,0.65,detail),wave);
}
float cellular_wind_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 wind=normalize(vec2(1.0,0.22)+vec2(0.0,DRIVER_FLOW-0.5));
	vec2 q=p*vec2(mix(0.55,1.3,detail),mix(1.6,3.2,detail));
	q+=wind*time*mix(0.22,1.25,detail);
	q+=vec2(fbm_driver(p*0.42+time*0.03),fbm_driver(p*0.57-time*0.04))*mix(0.2,1.1,detail);
	float cells=voronoi2(q,time*mix(0.35,1.4,detail));
	float grain=fbm_driver(p*mix(0.45,1.7,detail)-wind*time*0.22);
	return clamp(mix(cells,grain,0.28),0.0,1.0);
}
float ridge_flow_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 q=p+vec2(time*0.12,-time*0.04);
	float n=fbm_driver(q*mix(0.55,1.8,detail));
	n+=fbm_driver((q+vec2(n,-n))*mix(1.0,3.4,detail)-time*0.05)*0.45;
	float ridge=1.0-abs(fract(n*mix(2.0,7.5,detail))-0.5)*2.0;
	return smoothstep(mix(0.18,0.34,detail),mix(0.86,0.62,detail),ridge);
}
float source_warp_amount(vec2 p,float time,float source_drive){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	float source=clamp(source_drive,0.0,1.0);
	vec2 q=p+(source-0.5)*mix(1.4,5.0,detail);
	q+=vec2(fbm_driver(p*0.8+time*0.08),fbm_driver(p*1.1-time*0.05))*mix(0.4,2.2,detail);
	float n=fbm_driver(q*mix(0.55,2.4,detail)+vec2(time*0.04,-time*0.06));
	return clamp(mix(n,source,0.35)+smoothstep(0.35,0.82,source)*mix(0.05,0.22,detail),0.0,1.0);
}
float datamosh_river_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	float block=mix(0.85,0.18,detail);
	vec2 q=floor((p+vec2(time*mix(0.15,0.75,detail),0.0))/block)*block;
	float row=floor(q.y/max(block,0.001));
	float lane=rng(vec2(row,floor(time*mix(0.45,1.8,detail))));
	q.x+=lane*mix(1.4,5.5,detail)+time*mix(0.25,1.1,detail);
	q.y+=floor(fbm_driver(q*0.37+time*0.08)*mix(2.0,9.0,detail))*block*0.35;
	float smear=fbm_driver(q*mix(0.75,2.2,detail)+vec2(row*0.07,time*0.05));
	float tear=step(mix(0.72,0.52,detail),fract((p.x+lane*2.1)*mix(2.2,8.5,detail)+time*0.4));
	return clamp(mix(smear,tear,0.22+detail*0.28),0.0,1.0);
}
float magnetic_field_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 a=vec2(sin(time*0.31),cos(time*0.23))*mix(0.55,1.35,detail);
	vec2 b=vec2(cos(time*0.19+2.1),sin(time*0.27-0.4))*mix(0.65,1.55,detail);
	vec2 q=p-vec2(1.5);
	vec2 pa=q-a;
	vec2 pb=q+b;
	float da=length(pa)+0.04;
	float db=length(pb)+0.04;
	float angle=atan(pa.y,pa.x)-atan(pb.y,pb.x);
	float field=sin(angle*mix(3.0,10.0,detail)+(1.0/da-1.0/db)*mix(0.9,2.8,detail)+time*mix(0.35,1.4,detail));
	float noise=fbm_driver(p*mix(0.35,1.2,detail)+time*0.04);
	return smoothstep(mix(-0.55,-0.18,detail),mix(0.75,0.38,detail),field+noise*0.45);
}
float liquid_scanner_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 dir=normalize(mix(vec2(0.0,1.0),normalize(vec2(0.82,0.36)),DRIVER_FLOW));
	float sweep=dot(p,dir)*mix(1.4,4.8,detail)-time*mix(0.45,1.9,detail);
	float wobble=fbm_driver(p*mix(0.45,1.7,detail)+vec2(time*0.07,-time*0.05));
	float band=abs(fract(sweep+wobble*mix(0.45,1.8,detail))-0.5)*2.0;
	float scanner=1.0-smoothstep(mix(0.28,0.08,detail),mix(0.72,0.22,detail),band);
	float liquid=fbm_driver((p+vec2(wobble,-wobble))*mix(0.75,2.4,detail)-dir*time*0.15);
	return clamp(scanner*mix(0.65,1.1,liquid)+liquid*mix(0.12,0.32,detail),0.0,1.0);
}
vec2 driver_shape_local(vec2 coord,vec2 center){
	vec2 q=coord-center;
	float a=radians(DRIVER_ANGLE);
	float cs=cos(a);
	float sn=sin(a);
	q=vec2(q.x*cs-q.y*sn,q.x*sn+q.y*cs);
	float stretch=clamp(DRIVER_STRETCH,-1.0,1.0);
	float aspect=pow(4.0,abs(stretch));
	if(stretch>=0.0)q.x*=aspect;
	else q.y*=aspect;
	q=vec2(q.x*cs+q.y*sn,-q.x*sn+q.y*cs);
	return q;
}
float generic_driver_amount(float mode,vec2 st,float time,float source_drive){
	float scale=max(DRIVER_SCALE,0.0001);
	float speed=max(DRIVER_SPEED,0.0);
	vec2 q=driver_shape_local(st,DRIVER_CENTER);
	vec2 p=q*scale+vec2(1.5);
	float t=time*speed;
	if(mode<2.5)return combustible_voronoi_amount(p,t*0.08);
	if(mode<3.5)return phasor_amount(p,t);
	if(mode<4.5)return isoline_amount(p,t,source_drive);
	if(mode<5.5)return spiral_amount(p,t);
	if(mode<6.5)return curl_smoke_amount(p,t);
	if(mode<7.5)return wavefront_amount(p,t);
	if(mode<8.5)return cellular_wind_amount(p,t);
	if(mode<9.5)return ridge_flow_amount(p,t);
	if(mode<10.5)return source_warp_amount(p,t,source_drive);
	if(mode<11.5)return datamosh_river_amount(p,t);
	if(mode<12.5)return magnetic_field_amount(p,t);
	return liquid_scanner_amount(p,t);
}
vec2 generic_driver_flow(float mode,vec2 st,float time,float source_drive){
	float scale=max(DRIVER_SCALE,0.0001);
	float e=clamp(0.018/max(scale,0.02),0.018,4.0);
	float cx1=generic_driver_amount(mode,st+vec2(e,0.0),time,source_drive);
	float cx0=generic_driver_amount(mode,st-vec2(e,0.0),time,source_drive);
	float cy1=generic_driver_amount(mode,st+vec2(0.0,e),time,source_drive);
	float cy0=generic_driver_amount(mode,st-vec2(0.0,e),time,source_drive);
	vec2 grad=vec2(cx1-cx0,cy1-cy0)/(2.0*e);
	if(length(grad)<0.00001){
		return normalize(vec2(1.0,0.35)+vec2(DRIVER_FLOW-0.5,0.25-DRIVER_FLOW)*0.35);
	}
	vec2 tangent=normalize(vec2(-grad.y,grad.x)+vec2(0.0001));
	vec2 downhill=normalize(-grad+vec2(0.0001));
	return normalize(mix(downhill,tangent,DRIVER_FLOW)+vec2(0.0001));
}

// ============================ v0.3 base/quantisation math =======================
float luma_gradient(vec2 uv,vec2 t){
    float xl=raw_luma(uv-vec2(t.x,0.0));
    float xr=raw_luma(uv+vec2(t.x,0.0));
    float yu=raw_luma(uv-vec2(0.0,t.y));
    float yd=raw_luma(uv+vec2(0.0,t.y));
    return abs(xr-xl)+abs(yd-yu);
}
float alpha_gradient(vec2 uv,vec2 t){
    float xl=raw_alpha(uv-vec2(t.x,0.0));
    float xr=raw_alpha(uv+vec2(t.x,0.0));
    float yu=raw_alpha(uv-vec2(0.0,t.y));
    float yd=raw_alpha(uv+vec2(0.0,t.y));
    return abs(xr-xl)+abs(yd-yu);
}
float custom_edge_gradient(vec2 uv,vec2 t){
    float xl=raw_edge_mask(uv-vec2(t.x,0.0));
    float xr=raw_edge_mask(uv+vec2(t.x,0.0));
    float yu=raw_edge_mask(uv-vec2(0.0,t.y));
    float yd=raw_edge_mask(uv+vec2(0.0,t.y));
    return abs(xr-xl)+abs(yd-yu);
}
float edge_source(vec2 uv,vec2 t){
    float a=alpha_gradient(uv,t)*edge_alpha_weight;
    float l=luma_gradient(uv,t)*edge_luma_weight;
    if(edge_source_mode<0.5)return a;
    if(edge_source_mode<1.5)return l;
    if(edge_source_mode<2.5)return max(a,l);
    if(custom_edge_mask_loaded>0.5)return custom_edge_gradient(uv,t);
    return a;
}
float edge_mask(vec2 uv,vec2 t){
    float e=edge_source(uv,t);
    return smoothstep(edge_threshold,edge_threshold*3.0,e);
}
vec2 pixelate_uv(vec2 uv,float size,vec2 dims){
    if(size<=0.5)return uv;
    if(uv.x<0.0||uv.y<0.0||uv.x>1.0||uv.y>1.0)return uv;
    vec2 effective_size=vec2(max(size*max(pattern_scale,0.0001),0.0001));
    vec2 px=floor(uv*dims/effective_size)*effective_size+vec2(effective_size*0.5);
    return px/dims;
}
vec2 space_px(vec2 uv,vec2 frag_px,float space){
    if(space<0.5)return uv*tex_size;
    if(space<1.5)return uv*max(element_size,vec2(1.0));
    return frag_px;
}
float early_bayer_level(vec2 p,float level){
    // Keep the legacy-compatible call site, but dispatch every Bayer level.
    // The previous hardcoded 4x4 table silently collapsed levels 1/3/4/5
    // into level 2; the recursive construction matches get_bayer_level().
    int lvl=int(level);
    if(lvl<=1)lvl=1;
    else if(lvl==2)lvl=2;
    else if(lvl==3)lvl=3;
    else if(lvl>=5)lvl=5;
    float size=pow(2.0,float(lvl));
    vec2 q=mod(floor(p),size);
    float value=0.0;
    float weight=size*size*0.25;
    for(int i=0;i<5;i++){
        if(weight<1.0)break;
        float qx=mod(q.x,2.0);
        float qy=mod(q.y,2.0);
        float code=0.0;
        if(qx<0.5&&qy<0.5)code=0.0;
        else if(qx>0.5&&qy<0.5)code=2.0;
        else if(qx<0.5&&qy>0.5)code=3.0;
        else code=1.0;
        value+=code*weight;
        q=floor(q*0.5);
        weight*=0.25;
    }
    return value/(size*size);
}
float pattern_value(vec2 uv,vec2 frag_px,float mode,float bayer_level,float cell_size,float space){
    vec2 px=space_px(uv,frag_px,space);
    float effective_cell=max(cell_size*max(pattern_scale,0.0001),1.0);
    vec2 cell=floor(px/effective_cell);
    if(mode<0.5)return 0.5;
    if(mode<1.5)return early_bayer_level(cell,bayer_level);
    if(mode<2.5){
        float r=rng(cell);
        float n=(r+rng(cell+vec2(19.7,41.3))+rng(cell+vec2(-31.1,7.9)))/3.0;
        return clamp(r*1.35-n*0.35,0.0,1.0);
    }
    if(mode<3.5)return rng(cell);
    if(mode<4.5)return mix(0.25,0.75,mod(cell.x+cell.y,2.0));
    vec2 local=fract(px/effective_cell)-vec2(0.5);
    float dist=clamp(length(local)*1.41421356,0.0,1.0);
    return 1.0-dist;
}

float prep_luma(vec2 uv){
    float l=raw_luma(uv);
    float v=(l-dither_black_point)/max(dither_white_point-dither_black_point,0.001);
    v=clamp(v,0.0,1.0);
    v=pow(v,1.0/max(dither_gamma,0.01));
    v=(v-0.5)*dither_contrast+0.5+dither_brightness;
    return clamp(v,0.0,1.0);
}
vec3 grade_colour(vec3 c){
    vec3 v=(c-vec3(grade_black_point))/max(grade_white_point-grade_black_point,0.001);
    v=clamp(v,vec3(0.0),vec3(1.0));
    v=pow(v,vec3(1.0/max(grade_gamma,0.01)));
    v=(v-vec3(0.5))*grade_contrast+vec3(0.5+grade_brightness);
    float l=dot(v,vec3(0.299,0.587,0.114));
    return clamp(mix(vec3(l),v,max(grade_saturation,0.0)),vec3(0.0),vec3(1.0));
}
float mono_stamp(float base_luma,vec2 uv,vec2 frag_px){
    float lv=clamp(base_luma,0.0,1.0);
    if(mono_mode<0.5)return step(mono_threshold,lv);
    float p=pattern_value(uv,frag_px,mono_mode,mono_bayer_level,mono_pixel,mono_space);
    if(mono_mode<4.5)return step(mono_threshold,lv+p-0.5);
    return step(1.0-lv,p);
}
float fringe_coverage(float signal,vec2 uv,vec2 frag_px){
    float s=clamp(signal*fringe_coverage_gain,0.0,1.0);
    float soft=max(signal_softness,0.0001);
    if(pure_continuous>0.5||fringe_coverage_mode<0.5){
        return smoothstep(fringe_coverage_threshold-soft,fringe_coverage_threshold+soft,s);
    }
    float p=pattern_value(uv,frag_px,fringe_coverage_mode,fringe_bayer_level,fringe_pixel,fringe_space);
    float th=1.0-s;
    return smoothstep(th-soft,th+soft,p);
}

float blurred_edge(vec2 uv,vec2 edge_texel){
    vec2 r1=edge_texel*0.35;
    vec2 r2=edge_texel*0.70;
    vec2 r3=edge_texel;
    float e=0.0;
    e+=edge_mask(uv,edge_texel)*0.16;
    e+=edge_mask(uv+vec2(r1.x,0.0),edge_texel)*0.07;
    e+=edge_mask(uv-vec2(r1.x,0.0),edge_texel)*0.07;
    e+=edge_mask(uv+vec2(0.0,r1.y),edge_texel)*0.07;
    e+=edge_mask(uv-vec2(0.0,r1.y),edge_texel)*0.07;
    e+=edge_mask(uv+vec2(r2.x,r2.y),edge_texel)*0.065;
    e+=edge_mask(uv+vec2(-r2.x,r2.y),edge_texel)*0.065;
    e+=edge_mask(uv+vec2(r2.x,-r2.y),edge_texel)*0.065;
    e+=edge_mask(uv-vec2(r2.x,r2.y),edge_texel)*0.065;
    e+=edge_mask(uv+vec2(r3.x,0.0),edge_texel)*0.05;
    e+=edge_mask(uv-vec2(r3.x,0.0),edge_texel)*0.05;
    e+=edge_mask(uv+vec2(0.0,r3.y),edge_texel)*0.05;
    e+=edge_mask(uv-vec2(0.0,r3.y),edge_texel)*0.05;
    return clamp(e,0.0,1.0);
}
float wind_edge(vec2 uv,vec2 edge_texel,vec2 move_texel,vec2 wind,float reach){
    vec2 wd=normalize(wind+vec2(0.0001));
    float local=blurred_edge(uv,edge_texel)*0.72;
    float trail=0.0;
    trail+=blurred_edge(uv-wd*move_texel*reach*0.25,edge_texel)*0.34;
    trail+=blurred_edge(uv-wd*move_texel*reach*0.50,edge_texel)*0.27;
    trail+=blurred_edge(uv-wd*move_texel*reach*0.78,edge_texel)*0.20;
    trail+=blurred_edge(uv-wd*move_texel*reach*1.10,edge_texel)*0.14;
    return smoothstep(wind_cutoff,1.0,clamp(local+trail*wind_trail,0.0,1.0));
}
float color_signal(vec2 uv,vec2 edge_texel,vec2 move_texel,vec2 wind,float reach){
    float center=wind_edge(uv,edge_texel,move_texel,wind,reach);
    if(color_blur<=0.01)return center;
    vec2 axis=normalize(wind+vec2(0.0001));
    vec2 side=vec2(-axis.y,axis.x);
    vec2 bs=move_texel*color_blur*max(fx_size,0.0);
    float b=center*0.40;
    b+=wind_edge(uv+axis*bs,edge_texel,move_texel,wind,reach)*0.15;
    b+=wind_edge(uv-axis*bs,edge_texel,move_texel,wind,reach)*0.15;
    b+=wind_edge(uv+side*bs,edge_texel,move_texel,wind,reach)*0.15;
    b+=wind_edge(uv-side*bs,edge_texel,move_texel,wind,reach)*0.15;
    float a=clamp((color_blur*max(fx_size,0.0))/160.0,0.0,1.0);
    return clamp(mix(center,b,a)*mix(1.0,1.18,a),0.0,1.0);
}
float posterize_signal(float v){
    if(pure_continuous>0.5||signal_posterize<1.5)return v;
    float levels=max(signal_posterize,2.0);
    return floor(clamp(v,0.0,1.0)*levels+0.5)/levels;
}
vec3 rgb_to_hsv(vec3 c){
    vec4 K=vec4(0.0,-1.0/3.0,2.0/3.0,-1.0);
    vec4 p=mix(vec4(c.bg,K.wz),vec4(c.gb,K.xy),step(c.b,c.g));
    vec4 q=mix(vec4(p.xyw,c.r),vec4(c.r,p.yzx),step(p.x,c.r));
    float d=q.x-min(q.w,q.y);float e=0.000001;
    return vec3(abs(q.z+(q.w-q.y)/(6.0*d+e)),d/(q.x+e),q.x);
}
vec3 hsv_to_rgb(vec3 c){vec3 p=abs(fract(c.xxx+vec3(0.0,2.0/3.0,1.0/3.0))*6.0-3.0);return c.z*mix(vec3(1.0),clamp(p-1.0,0.0,1.0),c.y);}
vec3 hue_gradient(vec3 a,vec3 b,float t){
    vec3 ah=rgb_to_hsv(a);vec3 bh=rgb_to_hsv(b);float dh=bh.x-ah.x;
    if(abs(dh)>0.5){if(dh>0.0)ah.x+=1.0;else bh.x+=1.0;}
    vec3 h=mix(ah,bh,clamp(t,0.0,1.0));h.x=fract(h.x);return hsv_to_rgb(h);
}
vec2 geometry_texel(){return geometry_units<0.5?1.0/max(tex_size,vec2(1.0)):1.0/max(element_size,vec2(1.0));}
vec2 rgb_texel(){return rgb_shift_units<0.5?1.0/max(tex_size,vec2(1.0)):1.0/max(element_size,vec2(1.0));}
vec2 driver_uv(vec2 uv){
    if(pure_continuous>0.5||driver_sampling_mode<0.5)return uv;
    return pixelate_uv(uv,max(driver_pixel_size,1.0),max(element_size,vec2(1.0)));
}
vec4 preview_output(vec4 c){
    float e=clamp(preview_emphasis,0.0,1.0);
    return vec4(c.rgb*e,c.a*e);
}

float effect_time(){ return fx_time_source > 0.5 ? free_time : fx_time; }

// ============================ layer fx (v0.2 parity port) ============================
// Bayer tables (identical to the certified v0.2 stage).
float bayer2(vec2 p) {
	ivec2 q = ivec2(mod(p, 2.0));
	if (q.x == 0 && q.y == 0) { return 0.0 / 4.0; }
	if (q.x == 1 && q.y == 0) { return 2.0 / 4.0; }
	if (q.x == 0 && q.y == 1) { return 3.0 / 4.0; }
	return 1.0 / 4.0;
}
float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	if (q.x == 0 && q.y == 0) { return 0.0 / 16.0; }
	if (q.x == 1 && q.y == 0) { return 8.0 / 16.0; }
	if (q.x == 2 && q.y == 0) { return 2.0 / 16.0; }
	if (q.x == 3 && q.y == 0) { return 10.0 / 16.0; }
	if (q.x == 0 && q.y == 1) { return 12.0 / 16.0; }
	if (q.x == 1 && q.y == 1) { return 4.0 / 16.0; }
	if (q.x == 2 && q.y == 1) { return 14.0 / 16.0; }
	if (q.x == 3 && q.y == 1) { return 6.0 / 16.0; }
	if (q.x == 0 && q.y == 2) { return 3.0 / 16.0; }
	if (q.x == 1 && q.y == 2) { return 11.0 / 16.0; }
	if (q.x == 2 && q.y == 2) { return 1.0 / 16.0; }
	if (q.x == 3 && q.y == 2) { return 9.0 / 16.0; }
	if (q.x == 0 && q.y == 3) { return 15.0 / 16.0; }
	if (q.x == 1 && q.y == 3) { return 7.0 / 16.0; }
	if (q.x == 2 && q.y == 3) { return 13.0 / 16.0; }
	return 5.0 / 16.0;
}
float bayer8(vec2 p) {
	ivec2 q = ivec2(mod(p, 8.0));
	if (q.y == 0) { if (q.x == 0) { return 0.0 / 64.0; } if (q.x == 1) { return 32.0 / 64.0; } if (q.x == 2) { return 8.0 / 64.0; } if (q.x == 3) { return 40.0 / 64.0; } if (q.x == 4) { return 2.0 / 64.0; } if (q.x == 5) { return 34.0 / 64.0; } if (q.x == 6) { return 10.0 / 64.0; } return 42.0 / 64.0; }
	if (q.y == 1) { if (q.x == 0) { return 48.0 / 64.0; } if (q.x == 1) { return 16.0 / 64.0; } if (q.x == 2) { return 56.0 / 64.0; } if (q.x == 3) { return 24.0 / 64.0; } if (q.x == 4) { return 50.0 / 64.0; } if (q.x == 5) { return 18.0 / 64.0; } if (q.x == 6) { return 58.0 / 64.0; } return 26.0 / 64.0; }
	if (q.y == 2) { if (q.x == 0) { return 12.0 / 64.0; } if (q.x == 1) { return 44.0 / 64.0; } if (q.x == 2) { return 4.0 / 64.0; } if (q.x == 3) { return 36.0 / 64.0; } if (q.x == 4) { return 14.0 / 64.0; } if (q.x == 5) { return 46.0 / 64.0; } if (q.x == 6) { return 6.0 / 64.0; } return 38.0 / 64.0; }
	if (q.y == 3) { if (q.x == 0) { return 60.0 / 64.0; } if (q.x == 1) { return 28.0 / 64.0; } if (q.x == 2) { return 52.0 / 64.0; } if (q.x == 3) { return 20.0 / 64.0; } if (q.x == 4) { return 62.0 / 64.0; } if (q.x == 5) { return 30.0 / 64.0; } if (q.x == 6) { return 54.0 / 64.0; } return 22.0 / 64.0; }
	if (q.y == 4) { if (q.x == 0) { return 3.0 / 64.0; } if (q.x == 1) { return 35.0 / 64.0; } if (q.x == 2) { return 11.0 / 64.0; } if (q.x == 3) { return 43.0 / 64.0; } if (q.x == 4) { return 1.0 / 64.0; } if (q.x == 5) { return 33.0 / 64.0; } if (q.x == 6) { return 9.0 / 64.0; } return 41.0 / 64.0; }
	if (q.y == 5) { if (q.x == 0) { return 51.0 / 64.0; } if (q.x == 1) { return 19.0 / 64.0; } if (q.x == 2) { return 59.0 / 64.0; } if (q.x == 3) { return 27.0 / 64.0; } if (q.x == 4) { return 49.0 / 64.0; } if (q.x == 5) { return 17.0 / 64.0; } if (q.x == 6) { return 57.0 / 64.0; } return 25.0 / 64.0; }
	if (q.y == 6) { if (q.x == 0) { return 15.0 / 64.0; } if (q.x == 1) { return 47.0 / 64.0; } if (q.x == 2) { return 7.0 / 64.0; } if (q.x == 3) { return 39.0 / 64.0; } if (q.x == 4) { return 13.0 / 64.0; } if (q.x == 5) { return 45.0 / 64.0; } if (q.x == 6) { return 5.0 / 64.0; } return 37.0 / 64.0; }
	if (q.x == 0) { return 63.0 / 64.0; } if (q.x == 1) { return 31.0 / 64.0; } if (q.x == 2) { return 55.0 / 64.0; } if (q.x == 3) { return 23.0 / 64.0; } if (q.x == 4) { return 61.0 / 64.0; } if (q.x == 5) { return 29.0 / 64.0; } if (q.x == 6) { return 53.0 / 64.0; } return 21.0 / 64.0;
}
float get_bayer_level(vec2 p, float level) {
	int lvl = int(level);
	if (lvl <= 1) { return bayer2(p); }
	if (lvl == 2) { return bayer4(p); }
	if (lvl == 3) { return bayer8(p); }
	float size = 16.0;
	if (lvl >= 5) { size = 32.0; }
	vec2 q = mod(floor(p), size);
	float v = 0.0;
	float weight = size * size * 0.25;
	for (int i = 0; i < 5; i++) {
		if (weight < 1.0) { break; }
		float qx = mod(q.x, 2.0);
		float qy = mod(q.y, 2.0);
		float code = 0.0;
		if (qx < 0.5 && qy < 0.5) { code = 0.0; }
		else if (qx > 0.5 && qy < 0.5) { code = 2.0; }
		else if (qx < 0.5 && qy > 0.5) { code = 3.0; }
		else { code = 1.0; }
		v += code * weight;
		q = floor(q * 0.5);
		weight *= 0.25;
	}
	return v / (size * size);
}

vec2 space_px_v(vec2 uv, vec2 frag_px, float space) {
	if (space < 0.5) { return uv * source_tex_size; }
	if (space < 1.5) { return uv * max(source_rect.zw, vec2(1.0)); }
	return frag_px;
}

float pattern_value_v(vec2 uv, vec2 frag_px, float mode, float bayer_level, float cell_size, float space) {
	vec2 px = space_px_v(uv, frag_px, space);
	float effective_cell = max(cell_size * max(fx_pattern_scale, 0.0001), 1.0);
	vec2 cell = floor(px / effective_cell);
	if (mode < 0.5) { return 0.5; }
	if (mode < 1.5) { return get_bayer_level(cell, bayer_level); }
	if (mode < 2.5) {
		float r = rng(cell);
		float n = (r + rng(cell + vec2(19.7, 41.3)) + rng(cell + vec2(-31.1, 7.9))) / 3.0;
		return clamp(r * 1.35 - n * 0.35, 0.0, 1.0);
	}
	if (mode < 3.5) { return rng(cell); }
	if (mode < 4.5) { return mix(0.25, 0.75, mod(cell.x + cell.y, 2.0)); }
	vec2 local = fract(px / effective_cell) - vec2(0.5);
	float dist = clamp(length(local) * 1.41421356, 0.0, 1.0);
	return 1.0 - dist;
}

float prep_luma_v(vec2 uv) {
	float l = dot(sample_source(uv).rgb, vec3(0.299, 0.587, 0.114));
	float v = (l - fx_dither_black) / max(fx_dither_white - fx_dither_black, 0.001);
	v = clamp(v, 0.0, 1.0);
	v = pow(v, 1.0 / max(fx_dither_gamma, 0.01));
	v = (v - 0.5) * fx_dither_contrast + 0.5 + fx_dither_brightness;
	return clamp(v, 0.0, 1.0);
}

float luma_at_uv(vec2 uv) { return dot(sample_source(uv).rgb, vec3(0.299, 0.587, 0.114)); }

float luma_gradient_at(vec2 uv, vec2 t) {
	float xl = luma_at_uv(uv - vec2(t.x, 0.0));
	float xr = luma_at_uv(uv + vec2(t.x, 0.0));
	float yu = luma_at_uv(uv - vec2(0.0, t.y));
	float yd = luma_at_uv(uv + vec2(0.0, t.y));
	return abs(xr - xl) + abs(yd - yu);
}
float alpha_gradient_at(vec2 uv, vec2 t) {
	float xl = alpha_at_uv(uv - vec2(t.x, 0.0));
	float xr = alpha_at_uv(uv + vec2(t.x, 0.0));
	float yu = alpha_at_uv(uv - vec2(0.0, t.y));
	float yd = alpha_at_uv(uv + vec2(0.0, t.y));
	return abs(xr - xl) + abs(yd - yu);
}
float edge_source_at(vec2 uv, vec2 t) {
	float a = alpha_gradient_at(uv, t) * fx_edge_alpha_weight;
	float l = luma_gradient_at(uv, t) * fx_edge_luma_weight;
	if (fx_edge_source_mode < 0.5) { return a; }
	if (fx_edge_source_mode < 1.5) { return l; }
	return max(a, l);
}
float edge_mask_at(vec2 uv, vec2 t) {
	float e = edge_source_at(uv, t);
	return smoothstep(fx_edge_threshold, fx_edge_threshold * 3.0, e);
}
float blurred_edge_at(vec2 uv, vec2 edge_texel) {
	vec2 r1 = edge_texel * 0.35;
	vec2 r2 = edge_texel * 0.70;
	vec2 r3 = edge_texel;
	float e = 0.0;
	e += edge_mask_at(uv, edge_texel) * 0.16;
	e += edge_mask_at(uv + vec2(r1.x, 0.0), edge_texel) * 0.07;
	e += edge_mask_at(uv - vec2(r1.x, 0.0), edge_texel) * 0.07;
	e += edge_mask_at(uv + vec2(0.0, r1.y), edge_texel) * 0.07;
	e += edge_mask_at(uv - vec2(0.0, r1.y), edge_texel) * 0.07;
	e += edge_mask_at(uv + vec2(r2.x, r2.y), edge_texel) * 0.065;
	e += edge_mask_at(uv + vec2(-r2.x, r2.y), edge_texel) * 0.065;
	e += edge_mask_at(uv + vec2(r2.x, -r2.y), edge_texel) * 0.065;
	e += edge_mask_at(uv - vec2(r2.x, r2.y), edge_texel) * 0.065;
	e += edge_mask_at(uv + vec2(r3.x, 0.0), edge_texel) * 0.05;
	e += edge_mask_at(uv - vec2(r3.x, 0.0), edge_texel) * 0.05;
	e += edge_mask_at(uv + vec2(0.0, r3.y), edge_texel) * 0.05;
	e += edge_mask_at(uv - vec2(0.0, r3.y), edge_texel) * 0.05;
	return clamp(e, 0.0, 1.0);
}
float wind_edge_at(vec2 uv, vec2 edge_texel, vec2 move_texel, vec2 wind, float reach) {
	vec2 wd = normalize(wind + vec2(0.0001));
	float local = blurred_edge_at(uv, edge_texel) * 0.72;
	float trail = 0.0;
	trail += blurred_edge_at(uv - wd * move_texel * reach * 0.25, edge_texel) * 0.34;
	trail += blurred_edge_at(uv - wd * move_texel * reach * 0.50, edge_texel) * 0.27;
	trail += blurred_edge_at(uv - wd * move_texel * reach * 0.78, edge_texel) * 0.20;
	trail += blurred_edge_at(uv - wd * move_texel * reach * 1.10, edge_texel) * 0.14;
	return smoothstep(fx_wind_cutoff, 1.0, clamp(local + trail * fx_wind_trail, 0.0, 1.0));
}
float color_signal_at(vec2 uv, vec2 edge_texel, vec2 move_texel, vec2 wind, float reach) {
	float center = wind_edge_at(uv, edge_texel, move_texel, wind, reach);
	if (fx_color_blur <= 0.01) { return center; }
	vec2 axis = normalize(wind + vec2(0.0001));
	vec2 side = vec2(-axis.y, axis.x);
	vec2 bs = move_texel * fx_color_blur * max(fx_size, 0.0);
	float b = center * 0.40;
	b += wind_edge_at(uv + axis * bs, edge_texel, move_texel, wind, reach) * 0.15;
	b += wind_edge_at(uv - axis * bs, edge_texel, move_texel, wind, reach) * 0.15;
	b += wind_edge_at(uv + side * bs, edge_texel, move_texel, wind, reach) * 0.15;
	b += wind_edge_at(uv - side * bs, edge_texel, move_texel, wind, reach) * 0.15;
	float a = clamp((fx_color_blur * max(fx_size, 0.0)) / 160.0, 0.0, 1.0);
	return clamp(mix(center, b, a) * mix(1.0, 1.18, a), 0.0, 1.0);
}
float posterize_signal_v(float v) {
	if (fx_pure_continuous > 0.5 || fx_signal_posterize < 1.5) { return v; }
	float levels = max(fx_signal_posterize, 2.0);
	return floor(clamp(v, 0.0, 1.0) * levels + 0.5) / levels;
}
float fringe_coverage_v(float signal, vec2 uv, vec2 frag_px) {
	float s = clamp(signal * fx_coverage_gain, 0.0, 1.0);
	float soft = max(fx_signal_softness, 0.0001);
	if (fx_pure_continuous > 0.5 || fx_coverage_mode < 0.5) {
		return smoothstep(fx_coverage_threshold - soft, fx_coverage_threshold + soft, s);
	}
	float p = pattern_value_v(uv, frag_px, fx_coverage_mode, fx_coverage_bayer_level, fx_coverage_pixel, 2.0);
	float th = 1.0 - s;
	return smoothstep(th - soft, th + soft, p);
}

vec3 palette_a_color(){return palette_swap>0.5?fx_fringe_color_b.rgb:fx_fringe_color_a.rgb;}
vec3 palette_b_color(){return palette_swap>0.5?fx_fringe_color_a.rgb:fx_fringe_color_b.rgb;}

vec4 apply_gold_local_operator(vec4 source, vec2 uv, vec2 pres_px) {
	float strength = clamp(gold_operator_strength, 0.0, 1.0);
	float clock = gold_operator_time_source > 0.5 ? free_time : fx_time;
	if (gold_operator_mode > 0.5 && gold_operator_mode < 1.5) {
		// The signed distance is measured from the actual sampled alpha field.
		// Transparent pixels outside the silhouette cannot create a rectangle or
		// radial border because the scan fails closed at the source alpha edge.
		float width = max(gold_operator_scale * 30.0, 1.0);
		float distance_px = silhouette_distance_px(uv, width);
		float border = 1.0 - smoothstep(0.0, width, abs(distance_px));
		// Noise lives in presentation pixels (aspect-true, same grain on a
		// full-screen side field and on a fighter), not in stretched source UV.
		vec2 noise_p = uv * max(source_rect.zw, vec2(1.0)) / (26.0 / max(gold_operator_scale, 0.25));
		float noise = fbm(noise_p + vec2(clock * gold_operator_speed, -clock * gold_operator_speed * 0.63));
		float live = smoothstep(gold_operator_threshold - max(gold_operator_softness, 0.001), gold_operator_threshold + max(gold_operator_softness, 0.001), noise);
		float coverage = clamp(border * live * strength, 0.0, 1.0);
		vec3 border_color = mix(gold_operator_color_b.rgb, gold_operator_color_a.rgb, noise);
		// A coloured source (side field, accent) keeps its own identity: the
		// rim burns in the element's hue instead of the generic palette.
		float tint_sat = max(max(source_tint.r, source_tint.g), source_tint.b) - min(min(source_tint.r, source_tint.g), source_tint.b);
		vec3 tint_hot = clamp(source_tint.rgb / max(max(max(source_tint.r, source_tint.g), source_tint.b), 0.001), vec3(0.0), vec3(1.0));
		border_color = mix(border_color, mix(tint_hot, vec3(1.0), noise * 0.35), smoothstep(0.1, 0.4, tint_sat));
		// Hue-preserving energy: only the hottest noise crests approach white,
		// the body of the rim keeps the element colour instead of clipping.
		float crest = smoothstep(0.62, 0.9, noise);
		vec3 energized = clamp(mix(border_color * (0.85 + strength * 0.5), vec3(1.0), crest * 0.55) + source.rgb * 0.25, vec3(0.0), vec3(1.0));
		return vec4(mix(source.rgb, energized, coverage), max(source.a, coverage * 0.92));
	}
	if (gold_operator_mode > 1.5 && gold_operator_mode < 2.5) {
		// Directional luminance-run selection. Bright regions are selected from
		// the local input, while dark regions remain readable instead of receiving
		// a uniform quad displacement. The clocked tangent jitter breaks the run
		// into a controlled melt without becoming RGB split or dither.
		vec2 axis = normalize(vec2(gold_operator_axis_x, gold_operator_axis_y) + vec2(EPS));
		vec2 tangent = vec2(-axis.y, axis.x);
		vec2 texel = 1.0 / max(source_tex_size, vec2(1.0));
		float stride = max(gold_operator_scale, 0.25) * 28.0;
		float source_key = dot(source.rgb, vec3(0.299, 0.587, 0.114));
		vec4 selected = source;
		float selected_key = source_key;
		for (int i = 1; i <= 12; i++) {
			float distance = float(i) * stride;
			float turbulence = (noise_val(uv * (9.0 + gold_operator_scale * 4.0) + vec2(clock * gold_operator_speed, -clock * 0.7)) - 0.5) * stride * 0.8;
			vec2 jitter = tangent * turbulence;
			vec4 forward = sample_source(uv + axis * texel * distance + jitter * texel);
			vec4 backward = sample_source(uv - axis * texel * distance + jitter * texel);
			float forward_key = dot(forward.rgb, vec3(0.299, 0.587, 0.114));
			float backward_key = dot(backward.rgb, vec3(0.299, 0.587, 0.114));
			if (forward_key > selected_key) { selected = forward; selected_key = forward_key; }
			if (backward_key > selected_key) { selected = backward; selected_key = backward_key; }
		}
		float gate = smoothstep(gold_operator_threshold - max(gold_operator_softness, 0.001), gold_operator_threshold + max(gold_operator_softness, 0.001), source_key);
		float amount = strength * gate;
		vec4 trail_forward = sample_source(uv + axis * texel * stride * 1.4);
		vec4 trail_backward = sample_source(uv - axis * texel * stride * 0.65);
		vec3 directional_trail = mix(trail_forward.rgb, trail_backward.rgb, 0.22);
		vec3 chroma = mix(gold_operator_color_b.rgb, gold_operator_color_a.rgb, noise_val(uv * 18.0 + vec2(clock * 1.7, -clock * 0.9)));
		vec3 melted = mix(mix(selected.rgb, directional_trail, 0.58), chroma, 0.28);
		return vec4(mix(source.rgb, melted, amount), mix(source.a, max(source.a, selected.a), amount));
	}
	return source;
}

vec4 apply_layer_fx(vec4 input_src, vec2 layer_uv, vec2 pres_px){
    vec4 result=input_src;
vec2 move_texel=geometry_texel();
    vec2 edge_texel=move_texel*max(edge_width*max(fx_size,0.0),0.0001);
    vec2 uv=layer_uv;
    vec2 frag_px=pres_px;
    vec2 base_uv=uv;
    if(source_pixel_size>0.5&&pure_continuous<0.5){
        vec2 source_pixel_dims=source_pixel_units<0.5?tex_size:max(element_size,vec2(1.0));
        base_uv=pixelate_uv(uv,source_pixel_size,source_pixel_dims);
    }
    vec4 src=sample_source(base_uv);
    // Gold local operators own their output from the layer-selected source.
    // The remaining legacy FX stages continue to compose after this pass.
    src=apply_gold_local_operator(src,base_uv,pres_px);
    float source_opacity=clamp(base_opacity,0.0,1.0);
    float src_alpha=src.a*source_opacity;
    float mask=fx_effect_mask_value(uv);
    float debug_edge=edge_source(uv,edge_texel);
    float debug_coverage=0.0;
    vec3 debug_driver=vec3(0.5,0.5,0.0);

    vec3 col=src.rgb;
    if(base_grade_amount>0.001){
        float gm=mix(1.0,mask,step(0.5,effect_mask_base));
        float grade_amount=max(base_grade_amount*gm,0.0);
        vec3 graded=grade_colour(col);
        col=clamp(col+(graded-col)*grade_amount,vec3(0.0),vec3(1.0));
    }
    if(base_mode>=0.5&&pure_continuous<0.5){
        float bm=mix(1.0,mask,step(0.5,effect_mask_base));
        float mono_luma=dot(col,vec3(0.299,0.587,0.114));
        col=mix(col,vec3(mono_stamp(mono_luma,uv,frag_px)),bm);
    }

    vec3 debug_base_col=col;
    float debug_base_alpha=src_alpha;

    if(fx_rgb>0.001){
        vec2 dir=vec2(cos(radians(rgb_shift_angle)),sin(radians(rgb_shift_angle)));
        vec2 off=dir*rgb_texel()*max(rgb_shift_amount,0.0)*max(fx_size,0.0);
        vec3 plus=sample_source(base_uv+off).rgb;
        vec3 minus=sample_source(base_uv-off).rgb;
        if(base_grade_amount>0.001){
            float gm=mix(1.0,mask,step(0.5,effect_mask_base));
            float grade_amount=max(base_grade_amount*gm,0.0);
            vec3 plus_graded=grade_colour(plus);
            vec3 minus_graded=grade_colour(minus);
            plus=clamp(plus+(plus_graded-plus)*grade_amount,vec3(0.0),vec3(1.0));
            minus=clamp(minus+(minus_graded-minus)*grade_amount,vec3(0.0),vec3(1.0));
        }
        vec3 shifted=col;shifted.r=plus.r;shifted.b=minus.b;
        float amount=max(fx_rgb*mask*max(fx_intensity,0.0),0.0);
        col=clamp(col+(shifted-col)*amount,vec3(0.0),vec3(1.0));
        float shifted_alpha=max(src.a,max(sample_source(base_uv+off).a,sample_source(base_uv-off).a))*source_opacity;
        src_alpha=mix(src_alpha,shifted_alpha,clamp(rgb_shift_alpha*amount,0.0,1.0));
    }

    if(base_mode<0.5&&fx_dither>0.001&&pure_continuous<0.5){
        float lv=prep_luma(base_uv);
        float p=pattern_value(uv,frag_px,dither_mode,dither_bayer_level,dither_pixel,dither_space);
        float lev=max(dither_levels,2.0);
        float dl=clamp(floor(lv*lev+(p-0.5))/lev,0.0,1.0);
        float lum=max(dot(col,vec3(0.299,0.587,0.114)),0.0001);
        vec3 q=clamp(col*(dl/lum),vec3(0.0),vec3(1.0));
        float amount=max(fx_dither*mask*max(fx_intensity,0.0),0.0)*clamp(src_alpha*4.0+0.25,0.0,1.0);
        col=clamp(col+(q-col)*amount,vec3(0.0),vec3(1.0));
    }

    vec3 fringe_col=vec3(0.0);float show=0.0;
    if(fx_fringe>0.001){
        float t=effect_time();
        if(temporal_hold>0.01&&pure_continuous<0.5){float fps=max(temporal_hold,1.0);t=floor(effect_time()*fps)/fps;}
        float flow_amt=max(fx_flow,0.0);
        vec2 guv=driver_uv(uv);
        vec2 radial=normalize(guv-vec2(flow_center_x,flow_center_y)+vec2(0.0001));
        vec2 whispy=radial;float shimmer=1.0;float energy=1.0;vec2 field_offset=vec2(0.0);float outward=OUTWARDNESS;
        if(flow_amt>0.001){
            vec2 st=guv*3.0;float eff=t;
            vec2 ff=travelling_whisp_field(st,eff);float fa=travelling_whisp_amount(st,eff);
            energy=smoothstep(0.015,0.18,abs(fa)*FIELD_STRENGTH);
            whispy=normalize(ff+radial*0.0001+vec2(0.0001));
            shimmer=smoothstep(-0.12,0.16,fa);
            field_offset=(ff*FIELD_STRENGTH*COORD_NUDGE)/3.0;
            if(driver_mode>0.5&&driver_mode<1.5){
                vec2 luv=(guv-DRIVER_CENTER/3.0+vec2(0.5))*LEGACY_SCALE+vec2(eff*LEGACY_SPEED,-eff*LEGACY_SPEED*0.73);
                float n1=fbm(luv);float n2=fbm(luv*1.71+vec2(9.2,-3.4));ff=vec2(n1-0.5,n2-0.5);fa=fbm(luv*2.4+eff*LEGACY_SPEED*0.37)-0.5;
                energy=smoothstep(0.04,0.42,abs(fa));whispy=normalize(ff+radial*LEGACY_RADIAL+vec2(0.0001));shimmer=smoothstep(-0.22,0.22,fa);field_offset=ff*FIELD_STRENGTH*COORD_NUDGE*0.02;outward=clamp(LEGACY_RADIAL,0.0,1.0);
            }else if(driver_mode>1.5){
                float source_drive=raw_luma(guv);
                fa=generic_driver_amount(driver_mode,st,eff,source_drive)-0.5;ff=generic_driver_flow(driver_mode,st,eff,source_drive);
                energy=smoothstep(0.02,0.38,abs(fa)*mix(1.0,2.0,DRIVER_DETAIL));whispy=normalize(ff+radial*(1.0-DRIVER_FLOW)*0.45+vec2(0.0001));shimmer=smoothstep(-0.30,0.30,fa);field_offset=ff*FIELD_STRENGTH*COORD_NUDGE*0.026;outward=clamp(1.0-DRIVER_FLOW,0.0,1.0);
            }
            field_offset*=wind_displace*flow_amt;
        }
        debug_driver=vec3(whispy*0.5+0.5,clamp(energy,0.0,1.0));
        float spatial_scale=max(fx_size,0.0);
        vec2 driver_offset=field_offset*(flow_strength*32.0)*move_texel*spatial_scale;
        vec2 displaced=guv+driver_offset+whispy*(flow_strength*wind_displace*mix(0.18,0.72,energy))*move_texel*flow_amt*spatial_scale;
        vec2 split_axis=normalize(whispy+vec2(-radial.y,radial.x)*(1.0-outward)*0.35);
        vec2 split=split_axis*split_separation*move_texel*spatial_scale;
        vec2 wind=normalize(whispy*0.65+split_axis*0.35);
        float reach=max(wind_reach,0.0)*spatial_scale;
        float a=color_signal(displaced+split,edge_texel,move_texel,wind,reach)*mix(0.35,1.0,shimmer)*mix(0.35,1.0,energy);
        float b=color_signal(displaced-split,edge_texel,move_texel,wind,reach)*mix(1.0,0.55,shimmer)*mix(0.35,1.0,energy);
        a=posterize_signal(clamp(a*signal_gain,0.0,1.0));b=posterize_signal(clamp(b*signal_gain,0.0,1.0));
        float oa=fringe_coverage(a,guv,frag_px);float ob=fringe_coverage(b,guv,frag_px);
        debug_coverage=max(oa,ob);
        show=debug_coverage*max(fx_fringe*mask,0.0)*max(fx_intensity,0.0);
        float choose=step(b,a);float bal=a/max(a+b,0.001);float gt=clamp(mix(bal,shimmer,0.55),0.0,1.0);
        gt=clamp((gt-0.5)*rgb_gradient_contrast+0.5+rgb_gradient_balance*0.5,0.0,1.0);
        fringe_col=mix(mix(palette_b_color(),palette_a_color(),choose),hue_gradient(palette_b_color(),palette_a_color(),gt),rgb_gradient);
    }
    float fringe_alpha=clamp(show*clamp(fringe_bleed,0.0,1.0),0.0,1.0);
    float out_alpha=max(src_alpha,fringe_alpha);
    vec3 out_rgb=col;
    if(fringe_blend_mode<0.5)out_rgb=mix(out_rgb,fringe_col,clamp(show,0.0,1.0));
    else if(fringe_blend_mode<1.5)out_rgb=clamp(out_rgb+fringe_col*show,vec3(0.0),vec3(1.0));
    else out_rgb=mix(out_rgb,vec3(1.0)-(vec3(1.0)-out_rgb)*(vec3(1.0)-fringe_col),clamp(show,0.0,1.0));

    if(debug_view_mode>0.5&&debug_view_mode<1.5){
        result=preview_output(vec4(debug_base_col,debug_base_alpha));
    }else if(debug_view_mode>1.5&&debug_view_mode<2.5){
        vec3 delta=abs(out_rgb-debug_base_col);
        delta=max(delta,fringe_col*clamp(show,0.0,1.0));
        result=preview_output(vec4(delta,max(fringe_alpha,length(delta))));
    }else if(debug_view_mode>2.5&&debug_view_mode<3.5){
        result=preview_output(vec4(vec3(clamp(debug_edge,0.0,1.0)),1.0));
    }else if(debug_view_mode>3.5&&debug_view_mode<4.5){
        result=preview_output(vec4(vec3(clamp(debug_coverage,0.0,1.0)),1.0));
    }else if(debug_view_mode>4.5&&debug_view_mode<5.5){
        result=preview_output(vec4(vec3(clamp(mask,0.0,1.0)),1.0));
    }else if(debug_view_mode>5.5&&debug_view_mode<6.5){
        result=preview_output(vec4(clamp(debug_driver,vec3(0.0),vec3(1.0)),1.0));
    }else{
        result=preview_output(vec4(out_rgb,out_alpha));
    }
    return result;
}

// ============================ fragment ============================

void fragment() {
	// The canvas vertex color carries modulate/self_modulate; a canvas_item
	// shader that assigns COLOR would discard it, so fold it in explicitly.
	vec4 modulate_col = COLOR;
	vec2 pres_px = UV * canvas_size;
	vec2 uv_nodisp = inverse_transform_uv(pres_px);
	vec2 uv_pre_nodisp = (pres_px - source_rect.xy) / max(source_rect.zw, vec2(1.0));
	vec2 offset = displacement_offset(pres_px, 1.0) * influence_factor(uv_nodisp, uv_pre_nodisp, pres_px);
	vec2 uv = inverse_transform_uv(pres_px - offset);
	// Pre-Transform/-Displacement asset coordinate (SOURCE_SPACE mask basis and
	// the TRANSFORMED_SOURCE stage output).
	vec2 uv_pre = (pres_px - source_rect.xy) / max(source_rect.zw, vec2(1.0));
	vec4 sampled = sample_source(uv);
	if (stage_stop > 0.5) {
		// TRANSFORMED_SOURCE stage: Transform + Displacement only — no FX,
		// mask, opacity or blend (specs/03 §3, specs/02 §4).
		COLOR = sampled * modulate_col;
	} else {
	float mask = mask_factor(uv, uv_pre, pres_px);
	// LAYER FX runs after DISPLACE, before MASK (specs/03 §3 stage order).
	vec4 fx_out = apply_layer_fx(sampled, uv, pres_px);
	float alpha = fx_out.a * mask * layer_opacity;
	if (blend_mode > 0.5) {
		// Spec 15 §12: B per mode, Porter-Duff source-over onto the current
		// backbuffer (Cb, ab). COLOR carries the final straight colour with
		// alpha 1 so the canvas mix writes exactly F.
		vec3 cs = fx_out.rgb * modulate_col.rgb * preview_emphasis;
		float as_eff = alpha * modulate_col.a * preview_emphasis;
		vec4 back = texture(screen_tex, SCREEN_UV);
		vec3 cb = back.rgb;
		float ab = back.a;
		vec3 b = cs;
		if (blend_mode < 1.5) {
			b = min(vec3(1.0), cb + cs);
		} else if (blend_mode < 2.5) {
			b = cb + cs - cb * cs;
		} else {
			b = cb * cs;
		}
		float ao = as_eff + ab * (1.0 - as_eff);
		vec3 co_p = as_eff * (1.0 - ab) * cs + as_eff * ab * b + (1.0 - as_eff) * ab * cb;
		vec3 f = co_p / max(ao, 0.0001);
		COLOR = vec4(f, 1.0);
	} else {
		COLOR = vec4(fx_out.rgb, alpha) * modulate_col * preview_emphasis;
	}
	}
}
