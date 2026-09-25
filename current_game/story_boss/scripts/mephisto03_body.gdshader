shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D albedo_tex : source_color;
uniform vec4 tint : source_color = vec4(1.0);
uniform float fade_bottom = -0.19;
uniform float fade_top = 0.14;
varying float native_height;
varying vec3 soft_normal;
void vertex(){native_height=VERTEX.y;soft_normal=normalize(mat3(MODEL_MATRIX)*NORMAL);}
void fragment(){
 vec4 c=texture(albedo_tex,UV)*tint;
 float edge=0.025*sin(UV.x*41.0+TIME*1.5)*sin(UV.y*37.0-TIME);
 float soft_light=0.55+0.35*abs(dot(normalize(soft_normal),normalize(vec3(0.3,1.0,0.6))));
 ALBEDO=c.rgb*soft_light;ROUGHNESS=0.86;METALLIC=0.0;
 ALPHA=c.a*smoothstep(fade_bottom,fade_top,native_height+edge);
}
