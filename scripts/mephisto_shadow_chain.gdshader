shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float phase=0.0;
void fragment(){
 vec2 p=UV*2.0-1.0;
 float edge=1.0-smoothstep(0.10,1.0,length(p));
 float n=texture(noise_tex,UV*1.6+vec2(phase*.23,-phase*.18)).r;
 ALBEDO=mix(vec3(.055,.025,.08),vec3(.40,.23,.52),n);
 ALPHA=edge*edge*smoothstep(.2,.72,n)*.7;
}
