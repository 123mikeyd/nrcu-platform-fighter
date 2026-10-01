shader_type canvas_item;
// VS backdrop: a calm graphite ink-wash plate (assets/vs/ui/vs_backdrop.png)
// is the screen's ground. The stage plate stays as information, but only as a
// dim, desaturated hint that rises from the bottom edge; the side colours are
// the only saturated light on screen.
//
// A light seam runs along the centre of the gap between the two side fields:
// that is where the two sides collide. seam_energy is driven by the VS
// timeline (fx_layer_renderer.living_edge_state) and peaks at clash impact.

uniform sampler2D backdrop_tex : source_color, filter_linear;
uniform float stage_mix : hint_range(0.0, 1.0) = 0.45;
uniform float ground_gain = 0.62;
uniform float stage_band_top = 430.0;
uniform vec2 canvas_px = vec2(1280.0, 720.0);
// Gap centreline (layout polygons: left edge 290->850, right edge 492->927).
uniform vec2 seam_top = vec2(391.0, 0.0);
uniform vec2 seam_bottom = vec2(888.5, 720.0);
uniform float seam_width_px = 16.0;
uniform float seam_energy : hint_range(0.0, 2.0) = 0.35;
// 0 in FFA: the wedges draw their own seams.
uniform float seam_gain = 1.0;
uniform vec4 left_color : source_color = vec4(0.3, 0.75, 1.0, 1.0);
uniform vec4 right_color : source_color = vec4(1.0, 0.25, 0.3, 1.0);

varying vec4 node_modulate;

void vertex() {
	node_modulate = COLOR;
}

void fragment() {
	vec2 px = UV * canvas_px;
	vec3 ground = texture(backdrop_tex, UV).rgb * ground_gain;
	vec3 stage = texture(TEXTURE, UV).rgb;
	float stage_luma = dot(stage, vec3(0.299, 0.587, 0.114));
	vec3 stage_hint = mix(vec3(stage_luma), stage, 0.35) * 0.7;
	float band = smoothstep(stage_band_top, canvas_px.y, px.y);
	vec3 rgb = mix(ground, max(ground, stage_hint), stage_mix * band);

	// Distance to the seam centreline, signed: < 0 on the blue (left) side.
	vec2 axis = normalize(seam_bottom - seam_top);
	vec2 normal = vec2(axis.y, -axis.x);
	float side = dot(px - seam_top, normal);
	float core = exp(-pow(side / seam_width_px, 2.0));
	float halo = exp(-abs(side) / (seam_width_px * 4.0));
	// Brightest behind the VS mark, fading toward top and bottom.
	float along = dot(px - seam_top, axis) / length(seam_bottom - seam_top);
	float focus = exp(-pow((along - 0.42) / 0.38, 2.0));
	vec3 side_col = mix(left_color.rgb, right_color.rgb, smoothstep(-seam_width_px, seam_width_px, side));
	vec3 hot = mix(side_col, vec3(1.0, 0.95, 0.88), core);
	// Only a soft coloured bloom stays here; the contact line itself is drawn
	// where the two living fronts actually meet (side_field_edge.gdshader).
	rgb += side_col * halo * 0.3 * focus * seam_energy * seam_gain;
	COLOR = vec4(rgb, 1.0) * node_modulate;
}
