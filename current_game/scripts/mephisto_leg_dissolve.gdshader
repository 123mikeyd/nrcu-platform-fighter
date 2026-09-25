shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;
uniform sampler2D albedo_tex : source_color;
uniform sampler2D orm_tex;
uniform sampler2D normal_tex : hint_normal;
uniform float normal_strength=1.0;
uniform vec4 tint : source_color=vec4(1.0);
uniform float clock=0.0;
uniform float audition=0.0;
uniform float variant=1.0;
uniform sampler2D film_tex : source_color;
varying vec3 rest;
float hash(vec3 p){p=fract(p*.3183099+vec3(.1,.2,.3));p*=17.0;return fract(p.x*p.y*p.z*(p.x+p.y+p.z));}
float noise(vec3 p){vec3 i=floor(p);vec3 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
void vertex(){rest=VERTEX;}
void fragment(){
 float n=noise(rest*15.0+vec3(clock*.13,-clock*.27,clock*.09))*.68+noise(rest*33.0+vec3(0,-clock*.35,0))*.32;
 float fade=smoothstep(.62,1.04,rest.y+(n-.5)*.19);
 float leg=COLOR.r;
 float a=mix(1.0,fade,leg);
 vec3 body=texture(albedo_tex,UV).rgb*tint.rgb;
 vec3 film=texture(film_tex,fract(rest.xy*vec2(.85,.48)+vec2(.22,clock*.002))).rgb;
 vec3 warm=film*(variant<1.5 ? vec3(.45,.42,.40) : vec3(.9,.65,.5));
 float grain=hash(floor(rest*1100.0)+floor(clock*9.0))-.5;
 warm+=grain*.025;
 float edge=pow(1.0-abs(dot(NORMAL,VIEW)),3.0);
 if(variant>2.5){warm+=vec3(.40,.06,.008)*edge;}
 body=mix(body,warm,audition);
 ALBEDO=mix(body,vec3(.075,.068,.067),leg*(1.0-fade)*.70);
 EMISSION=warm*audition*.12;
 ROUGHNESS=texture(orm_tex,UV).g;METALLIC=texture(orm_tex,UV).b;SPECULAR=.5;
 NORMAL_MAP=texture(normal_tex,UV).rgb;NORMAL_MAP_DEPTH=normal_strength;ALPHA=a;
 if(a<.015)discard;
}
