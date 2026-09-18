shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float clock=0.0;
uniform float seed=0.0;
uniform float opacity=.25;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y);}
void vertex(){MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);MODELVIEW_MATRIX[0]*=length(MODEL_MATRIX[0].xyz);MODELVIEW_MATRIX[1]*=length(MODEL_MATRIX[1].xyz);}
void fragment(){
 vec2 p=UV*2.0-1.0;
 vec2 q=UV*3.6+vec2(seed, -clock*.22);
 float f=n(q)*.55+n(q*2.1+vec2(clock*.06,0))*.30+n(q*4.3)*.15;
 float radial=1.0-smoothstep(.10,1.0,length(p+vec2((f-.5)*.38,0)));
 ALBEDO=mix(vec3(.085,.080,.078),vec3(.25,.235,.225),f);
 ALPHA=radial*radial*smoothstep(.22,.70,f)*opacity;
}
