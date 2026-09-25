shader_type canvas_item;
// VS mark under-shadow (NRCU_VS_FINAL_IMPLEMENTATION_HANDOFF_v2_0,
// vs_layout_1280x720.json -> vs_mark.shadow_dilate_px / shadow_alpha).
//
// Godot has no built-in MaxFilter, so the authored square dilation of the mark
// alpha is approximated here by 17 taps (8 directions at the full radius, 8 at
// half) — an octagonal dilate instead of a 7x7 square one. The shadow is a hard
// black blob sitting 3-4 px behind an opaque mark, so the corner difference is
// sub-pixel in practice; the measured parity numbers are in the report.
//
// The dilation radius is authored in CANVAS pixels (the same unit the layout
// spec uses), which is why the mark's drawn size is a uniform.

uniform float dilate_px = 3.0;
uniform vec2 mark_size = vec2(211.0, 224.0);
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.66);
uniform bool mask_only = false;

void fragment() {
	vec2 step_uv = vec2(dilate_px) / max(mark_size, vec2(1.0));
	float a = texture(TEXTURE, UV).a;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.7853981634; // PI / 4
		vec2 dir = vec2(cos(angle), sin(angle));
		a = max(a, texture(TEXTURE, UV + dir * step_uv).a);
		a = max(a, texture(TEXTURE, UV + dir * step_uv * 0.5).a);
	}
	if (mask_only) {
		COLOR = vec4(1.0, 1.0, 1.0, a);
	} else {
		COLOR = vec4(shadow_color.rgb, shadow_color.a * a);
	}
}
