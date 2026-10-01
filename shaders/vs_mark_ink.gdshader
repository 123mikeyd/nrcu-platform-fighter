shader_type canvas_item;
// Brush VS mark (assets/vs/ui/vs_mark_brush.png, white ink on alpha).
// The mark carries the collision: the V side glows in the left fighter's
// colour, the S side in the right fighter's, the ink core stays white-hot.
// Used on the UnderShadow node as a coloured light halo (glow_pass = true)
// and on the Mark node itself (glow_pass = false).

uniform bool glow_pass = false;
uniform vec4 left_color : source_color = vec4(0.3, 0.75, 1.0, 1.0);
uniform vec4 right_color : source_color = vec4(1.0, 0.25, 0.3, 1.0);
uniform vec2 mark_size = vec2(300.0, 220.0);
uniform float glow_px = 16.0;
uniform float glow_strength = 1.7;
uniform float impact = 0.0;

vec3 side_color(float x) {
	return mix(left_color.rgb, right_color.rgb, smoothstep(0.3, 0.7, x));
}

varying vec4 node_modulate;

void vertex() {
	node_modulate = COLOR;
}

void fragment() {
	vec3 col = side_color(UV.x);
	if (glow_pass) {
		vec2 step_uv = vec2(glow_px) / max(mark_size, vec2(1.0));
		float acc = 0.0;
		float wsum = 0.0;
		for (int ring = 1; ring <= 3; ring++) {
			float r = float(ring) / 3.0;
			for (int i = 0; i < 8; i++) {
				float ang = float(i) * 0.7853981634 + float(ring) * 0.39;
				float w = 1.0 - r * 0.6;
				acc += texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * step_uv * r).a * w;
				wsum += w;
			}
		}
		float g = acc / wsum;
		float strength = glow_strength * (1.0 + impact * 1.4);
		COLOR = vec4(col, clamp(g * strength, 0.0, 1.0)) * node_modulate;
	} else {
		float a = texture(TEXTURE, UV).a;
		// Thin coloured edge where the ink thins out (dry-brush fringe), white
		// core; at impact the core flashes toward the side colours' hot mix.
		float fringe = 1.0 - smoothstep(0.35, 0.95, a);
		vec3 rgb = mix(vec3(1.0), col, fringe * 0.85);
		rgb = mix(rgb, vec3(1.0, 0.97, 0.9), impact * 0.5);
		COLOR = vec4(rgb, a) * node_modulate;
	}
}
