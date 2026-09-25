shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float opacity=0.65;
uniform float phase=0.0;
void fragment(){
 vec2 p=UV*2.0-1.0;
 float edge=1.0-smoothstep(0.15,1.0,length(p));
 float n=texture(noise_tex,UV*1.4+vec2(phase*0.1,phase*0.07)).r;
 ALBEDO=mix(vec3(0.22,0.065,0.012),vec3(0.85,0.36,0.06),n);
 ALPHA=edge*edge*smoothstep(0.15,0.8,n)*opacity;
}
