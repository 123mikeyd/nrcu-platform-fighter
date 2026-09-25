shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec4 mist_color : source_color = vec4(0.42,0.19,0.065,0.24);
uniform float phase = 0.0;
void vertex(){
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment(){
 vec2 p=(UV-0.5)*2.0;
 float r=length(p);
 float clouds=0.63+0.2*sin(p.x*8.0+phase)*sin(p.y*7.0-phase*0.73)+0.13*sin((p.x+p.y)*16.0-phase);
 ALBEDO=mist_color.rgb;
 ALPHA=mist_color.a*pow(max(0.0,1.0-r),1.7)*clouds;
}
