shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float life = 0.0;
uniform float seed = 0.0;
uniform float opacity = 0.19;
uniform vec3 readable_center = vec3(0.0);
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float hash2(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float smoke_noise(vec2 p) {
    vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(hash2(i),hash2(i+vec2(1,0)),f.x),mix(hash2(i+vec2(0,1)),hash2(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
    vec2 p=(UV-.5)*2.0;
    // Low-frequency rolling density: soft tongues, never glowing rings or sparks.
    float curl=sin(p.y*4.0+seed+life*4.0)*.24;
    vec2 q=vec2(p.x+curl,p.y);
    float billow=smoke_noise(q*3.2+vec2(seed,-life*1.8));
    float radius=length(vec2(q.x*1.05,q.y))+(billow-.5)*.26;
    float soft=1.0-smoothstep(.14,.96,radius);
    float lobe=smoothstep(.12,.82,billow)*.65+.35;
    float fade=smoothstep(0.0,.13,life)*(1.0-smoothstep(.4,1.0,life));
    // Keep the girl's upper silhouette clear even when a hand crosses it.
    float clear_girl=smoothstep(.30,.63,length((world_position-readable_center).xy));
    ALBEDO=mix(vec3(.12,.034,.020),vec3(.23,.066,.028),lobe*.45);
    ALPHA=soft*lobe*fade*opacity*clear_girl;
}
