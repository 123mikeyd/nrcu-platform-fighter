shader_type spatial;
render_mode cull_disabled;
uniform float dissolve_height = 0.14;
uniform float darkening = 0.0;
uniform float feather_width = 0.16;
uniform float height_min = 0.0;
uniform float height_span = 1.0;
uniform float flow_clock = 0.0;
uniform float band_strength = 0.30;
uniform float surface_y = 0.0;
varying float world_y;
varying vec3 local_position;
float hash3(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise3(vec3 p) {
 vec3 i=floor(p); vec3 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { local_position=VERTEX; world_y=(MODEL_MATRIX*vec4(VERTEX,1.0)).y; }
void fragment() {
 if(world_y < surface_y + .012) { discard; }
 vec3 p=local_position/max(height_span,0.0001);
 float h=(local_position.y-height_min)/max(height_span,0.0001);
 float n=noise3(p*5.0+vec3(flow_clock*.13,flow_clock*.08,-flow_clock*.16));
 float distance_to_edge=h+(n-.5)*.22-dissolve_height;
 float coverage=smoothstep(-feather_width*.5,feather_width*.5,distance_to_edge);
 // Opaque stochastic coverage works on Compatibility: no blended sorting or glow.
 float stipple=fract(52.9829189*fract(dot(floor(FRAGCOORD.xy),vec2(.06711056,.00583715))));
 if (coverage<=stipple || dissolve_height>=1.24) { discard; }
 float edge=1.0-smoothstep(0.0,.28,distance_to_edge);
 float band=smoothstep(-.55,.7,sin(h*10.0+p.x*3.0+n*2.0-flow_clock*.85));
 float shade=clamp(max(darkening,edge)+band*band_strength+(n-.5)*.06,0.0,1.0);
 vec3 orange=vec3(.235,.034,.009);vec3 maroon=vec3(.070,.007,.009);vec3 umber=vec3(.017,.004,.002);
 vec3 body=shade<.53?mix(orange,maroon,shade/.53):mix(maroon,umber,(shade-.53)/.47);
 float rim=pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),2.0)*.16;
 vec3 linear_albedo=mix(body,vec3(.15,.025,.007),rim);
 // Blender's reference ramp is linear; Compatibility shades in sRGB space.
 ALBEDO=OUTPUT_IS_SRGB ? (1.055*pow(max(linear_albedo,vec3(0.0)),vec3(1.0/2.4))-.055) : linear_albedo;
 ROUGHNESS=.76; METALLIC=0.0; SPECULAR=.13;
}
