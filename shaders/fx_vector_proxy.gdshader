shader_type canvas_item;
// Vector-proxy surface (Round-2 neutral-parity fix).
//
// Generated proxy/mask textures carry SHAPE/ALPHA information only. The
// canonical fill/tint/material of the underlying composition element must stay
// authoritative - this surface applies the element's own colour (captured as
// `tint` from the polygon/line it replaces) to the mask shape. Without this,
// an unstyled side field / name plate / accent line would render as flat white.
//
// Shape selection and visual treatment stay separate: switching the mask
// texture changes the shape only; `tint` keeps carrying the canonical colour.

uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	// COLOR arrives as the vertex colour (modulate * self_modulate). Keep it:
	// dropping it made the proxy ignore the entry fade and the styled-stack
	// self_modulate hide, so a styled side field was drawn twice.
	COLOR = vec4(mask.rgb * tint.rgb, mask.a * tint.a) * COLOR;
}
