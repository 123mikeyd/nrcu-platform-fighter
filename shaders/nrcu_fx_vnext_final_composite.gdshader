shader_type canvas_item;
render_mode unshaded;

// NRCU FX Lab vNext — explicit final-composite pass.
//
// BackBufferCopy captures the already-composited canvas before this quad is
// drawn. The default amount is exactly neutral: the captured pixel is returned
// without a blend or color change. A non-zero amount applies one deterministic
// tint/scan operator whose phase is driven only by supplied clocks.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D scope_mask : repeat_disable, filter_nearest;
uniform sampler2D primary_scope_mask : repeat_disable, filter_nearest;
uniform float final_scope_mode = 0.0; // 0 ALL, 1 ECHO_ONLY, 2 PRIMARY_ONLY, 3 EXCLUDE_PRIMARY
uniform float final_tint_amount = 0.0;
uniform vec4 final_tint_color : source_color = vec4(1.0);
uniform float presentation_time = 0.0;
uniform float free_run_time = 0.0;
uniform float final_time_source = 0.0; // 0 = presentation, 1 = free-run
uniform float final_operator_event_start = 0.0;
uniform float final_operator_duration = 0.5;
uniform float final_operator_mode = 0.0; // 0 tint, 1 speedlines_field

uniform float final_operator_strength = 0.0;
uniform float final_operator_scale = 1.0;
uniform float final_operator_speed = 1.0;
uniform float final_operator_softness = 0.12;
uniform float final_operator_pattern_mode = 0.0;
uniform float final_operator_pattern_family = 0.0;
uniform float final_operator_distortion = 0.0;
uniform vec2 final_operator_center = vec2(0.5, 0.5);
uniform vec2 final_operator_axis = vec2(1.0, 0.0);
uniform float final_operator_progress = 0.5;
uniform float final_operator_progress_start = 0.0;
uniform float final_operator_progress_end = 1.0;
uniform float final_operator_progress_animated = 0.0;
uniform float final_operator_polarity = 0.0; // 0 pull, 1 push
uniform float final_operator_mix_mode = 0.0; // speedlines: 0 lines, 1 distortion, 2 combined
uniform vec4 final_operator_color_a : source_color = vec4(0.25, 0.95, 1.0, 1.0);
uniform vec4 final_operator_color_b : source_color = vec4(1.0, 0.35, 0.82, 1.0);
const float EPS = 0.0001;

const float FINAL_PI = 3.14159265359;
uniform sampler2D speedlines_noise : repeat_enable, filter_linear;

// Radial speedlines adapted from "Anime Style Speedlines (w/ or w/o distortion)"
// by Profesor Shader (MIT, github.com/profesorshader/shader-speed-lines; see
// assets/vs/fx/SPEEDLINES_SOURCE_NOTICE.txt). Mechanism kept verbatim: noise is
// sampled in polar space with a TINY radial zoom (so each angle keeps one value
// along the whole ray = a spoke) and the angle repeated around the circle; power
// + 2-level posterize gives crisp anime streaks; the same noise, raised to
// dist_power, pushes the captured frame toward/away from the center. Changes:
// supplied clock instead of the engine clock, aspect-correct center, event envelope.
const float SL_RADIAL_ZOOM = 0.01;
const float SL_RADIAL_REPEAT = 20.0; // our noise tile is ~half as fine as the reference 512px/freq 0.1 noise
const float SL_POWER = 3.0;
const float SL_COLOR_LEVELS = 4.0;
const float SL_DIST_POWER = 4.0;

float speedline_raw(vec2 uv, float clock) {
    vec2 dir = (uv - final_operator_center) * vec2(1.7777778, 1.0);
    float radius = length(dir) * 2.0;
    float angle = atan(dir.y, dir.x) / (2.0 * FINAL_PI);
    float repeat = SL_RADIAL_REPEAT * max(final_operator_scale, 0.25);
    vec2 src_uv = mod(vec2(radius * SL_RADIAL_ZOOM - clock * 0.1, angle * repeat), 1.0);
    float noi = texture(speedlines_noise, src_uv).r;
    // Radial vignette: clear center around the focal point, lines toward edges.
    float vig = smoothstep(0.05, 0.75, length(dir) / 1.0);
    return pow(noi * vig, SL_POWER);
}

vec4 speedlines_composite(vec2 uv, vec4 captured, float clock, float strength, float scale) {
    float raw = speedline_raw(uv, clock);
    float lines = floor(raw * SL_COLOR_LEVELS) / (SL_COLOR_LEVELS - 1.0);
    // Two-sided VS: lines take side A's colour left of the focal point and
    // side B's to the right, with a white-hot blend through the centre.
    float side_t = smoothstep(-0.06, 0.06, uv.x - final_operator_center.x);
    vec3 line_color = mix(final_operator_color_a.rgb, final_operator_color_b.rgb, side_t);
    vec4 base = captured;
    if (final_operator_mix_mode > 0.5) {
        // Distortion toward the focal point, scaled by the event strength so it
        // is exactly zero outside the event window.
        vec2 dir = -(uv - final_operator_center);
        float dist_val = pow(raw, SL_DIST_POWER) * final_operator_distortion * 2.0 * strength;
        base = texture(screen_tex, clamp(uv + dir * dist_val, vec2(0.0), vec2(1.0)));
    }
    if (final_operator_mix_mode > 0.5 && final_operator_mix_mode < 1.5) {
        return base;
    }
    return vec4(mix(base.rgb, line_color, clamp(lines * strength, 0.0, 1.0)), captured.a);
}

// Pattern families are transition geometry, never default visible content.
// Progress 0 is captured-only and progress 1 is a controlled alternate capture;
// the pattern decides where that alternate state appears.
vec4 pattern_transition(vec2 uv, vec4 captured, float clock, float strength, float scale, float progress) {
    vec2 axis = normalize(final_operator_axis + vec2(EPS));
    vec2 perpendicular = vec2(-axis.y, axis.x);
    // A spatial gradient advances a front; continuous local shape distances
    // break up only that front. No binary checker/color overlay. Axis rotates
    // both the progression and the pattern; speed scrolls the pattern only.
    float gradient = 0.5 + dot(uv - vec2(0.5), axis) / (abs(axis.x) + abs(axis.y));
    vec2 oriented = vec2(dot(uv * vec2(1.7777778, 1.0), axis), dot(uv * vec2(1.7777778, 1.0), perpendicular));
    vec2 cell = abs(fract(oriented * 14.0 * max(scale, 0.25) + vec2(clock * final_operator_speed * 0.35, 0.0)) - vec2(0.5)) * 2.0;
    float shape = max(cell.x, cell.y);
    if (final_operator_pattern_family > 0.5 && final_operator_pattern_family < 1.5) {
        shape = length(cell) / 1.41421356;
    } else if (final_operator_pattern_family >= 1.5) {
        shape = (cell.x + cell.y) * 0.5;
    }
    float threshold = gradient * 0.76 + shape * 0.24;
    float softness = max(final_operator_softness * 0.25, 0.001);
    float reveal = smoothstep(threshold - softness, threshold + softness, progress);
    if (progress <= 0.001) { reveal = 0.0; }
    if (progress >= 0.999) { reveal = 1.0; }
    float alternate_amount = reveal * clamp(strength, 0.0, 1.0);
    vec2 fragment_offset = perpendicular * (shape - 0.5) * 0.035 * clamp(strength, 0.0, 1.0);
    vec4 alternate = texture(screen_tex, clamp(uv + fragment_offset, vec2(0.0), vec2(1.0)));
    // A restrained captured-frame cut, not a second scene texture. Event
    // release returns to the original; static progress 1 shows the full cut.
    alternate.rgb *= 0.45;
    return mix(captured, alternate, alternate_amount);
}

// Dedicated screen-space vacuum: a single center-anchored impulse, after
// "Vacuum collapse" (godotshaders.com, MIT). PULL samples OUTWARD, so the
// image is drawn INTO the focal point (content shrinks toward the VS mark and
// stays hidden behind it); PUSH samples inward (content bulges out). A faint
// radial ripple rides the impulse like a droplet hitting water.
vec4 vacuum_burst(vec2 uv, float clock, float strength, float scale, vec4 captured) {
    vec2 p = (uv - final_operator_center) * vec2(1.7777778, 1.0);
    float radius = length(p);
    vec2 outward = normalize(p + vec2(EPS));
    float falloff = smoothstep(1.0, 0.05, radius);
    float ripple = 1.0 + 0.6 * sin(radius * 26.0 - clock * 24.0);
    float warp_amount = falloff * ripple * strength * 0.11 * max(scale, 0.25);
    float polarity_sign = final_operator_polarity < 0.5 ? 1.0 : -1.0;
    vec2 warped_uv = clamp(uv + outward * warp_amount * polarity_sign / vec2(1.7777778, 1.0), vec2(0.0), vec2(1.0));
    return texture(screen_tex, warped_uv);
}
float final_event_envelope(float clock) {
	float duration = final_operator_duration;
	if (duration <= 0.0001) { return 1.0; }
	float p = (clock - final_operator_event_start) / duration;
	if (p <= 0.0 || p >= 1.0) { return 0.0; }
	if (p < 0.16) { return smoothstep(0.0, 1.0, p / 0.16); }
	if (p < 0.64) { return 1.0; }
	return 1.0 - smoothstep(0.0, 1.0, (p - 0.64) / 0.36);
}

float final_pattern_progress(float clock) {
	if (final_operator_progress_animated < 0.5) {
		return clamp(final_operator_progress, 0.0, 1.0);
	}
	float duration = final_operator_duration;
	if (duration <= 0.0001) { return clamp(final_operator_progress_end, 0.0, 1.0); }
	float p = clamp((clock - final_operator_event_start) / duration, 0.0, 1.0);
	return mix(clamp(final_operator_progress_start, 0.0, 1.0), clamp(final_operator_progress_end, 0.0, 1.0), p);
}

float scope_factor(vec2 uv) {
    if (final_scope_mode < 0.5) {
        return 1.0;
    }
    float semantic_alpha = clamp(texture(scope_mask, uv).a, 0.0, 1.0);
    // EXCLUDE_PRIMARY uses the primary silhouette as its matte. Inverting here
    // is required: a white clear-layer plus black primary quads preserves alpha
    // at 1.0 under normal CanvasItem blending and would otherwise scope ALL.
    if (final_scope_mode > 2.5) {
        return 1.0 - semantic_alpha;
    }
    if (final_scope_mode < 1.5) {
        return semantic_alpha * (1.0 - clamp(texture(primary_scope_mask, uv).a, 0.0, 1.0));
    }
    return semantic_alpha;
}

void fragment() {
    vec4 captured = texture(screen_tex, SCREEN_UV);
    float amount = clamp(final_tint_amount, 0.0, 1.0);
    float operator_strength = clamp(final_operator_strength, 0.0, 1.0);
    float supplied_clock = final_time_source > 0.5 ? free_run_time : presentation_time;
    operator_strength *= final_event_envelope(supplied_clock);
    vec4 operated = captured;
    if (final_operator_mode > 2.5 && final_operator_mode < 3.5) {
        operated = vacuum_burst(SCREEN_UV, supplied_clock, operator_strength, final_operator_scale, captured);
    } else if (final_operator_mode > 1.5 && final_operator_mode < 2.5) {
        operated = pattern_transition(SCREEN_UV, captured, supplied_clock, operator_strength, final_operator_scale, final_pattern_progress(supplied_clock));
    } else if (final_operator_mode > 0.5 && final_operator_mode < 1.5) {
        operated = speedlines_composite(SCREEN_UV, captured, supplied_clock * max(final_operator_speed, 0.0), operator_strength, final_operator_scale);
    } else if (amount > 0.00001) {
        float scan = 0.5 + 0.5 * sin(UV.y * 720.0 * FINAL_PI + supplied_clock * 2.0);
        float strength = amount * (0.75 + 0.25 * scan);
        vec3 tinted = mix(captured.rgb, captured.rgb * final_tint_color.rgb, strength);
        operated = vec4(tinted, captured.a);
    }
    // Scope is a semantic alpha matte, not a rectangle. The effect may alter
    // only the selected role pixels; untouched pixels remain the captured frame.
    float selected = scope_factor(SCREEN_UV);
    COLOR = mix(captured, operated, selected);
}
