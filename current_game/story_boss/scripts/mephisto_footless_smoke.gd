extends Node3D
# Immutable anatomical ArrayMesh is shared; only material clocks are per actor.
static var mesh_cache={}
var view
var clock=0.0
var materials=[]
var cards=[]
var wisps=true
var audit={}
func setup(v):
 view=v;top_level=true
 set_meta("fuller",true)
 var started=Time.get_ticks_usec()
 view.native_model.scale=Vector3.ONE*.504
 view.pair.scale=Vector3.ONE*1.08
 view.pair.position.y=-.18
 for m in view.demon.find_children('*','MeshInstance3D',true,false):
  var source=m.mesh;var id=source.get_instance_id()
  if not mesh_cache.has(id):
   var mesh=ArrayMesh.new()
   for s in source.get_surface_count():
    var a=source.surface_get_arrays(s)
    var colors=PackedColorArray();colors.resize(a[0].size())
    var influences=int(a[Mesh.ARRAY_BONES].size()/a[0].size())
    for i in a[0].size():
     var leg=0.0;var arm_weight=0.0
     for j in influences:
      var bind=a[Mesh.ARRAY_BONES][i*influences+j]
      var bone=String(m.skin.get_bind_name(bind))
      var weight=a[Mesh.ARRAY_WEIGHTS][i*influences+j]
      if bone.begins_with('DEF-hand') or bone.begins_with('DEF-forearm') or bone.begins_with('DEF-upper_arm'):arm_weight+=weight
      if bone.begins_with('DEF-thigh') or bone.begins_with('DEF-shin') or bone.begins_with('DEF-foot') or bone.begins_with('DEF-toe'):leg+=weight
     # Smooth rest-space coverage through the thigh, never a world cut.
     leg=maxf(smoothstep(.08,.6,leg),1.0-smoothstep(.84,1.0,a[0][i].y))
     if arm_weight>.05:leg=0.0
     colors[i]=Color(leg,0,0,1)
    a[Mesh.ARRAY_COLOR]=colors
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a,[],{},source.surface_get_format(s)&Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
    mesh.surface_set_material(s,source.surface_get_material(s))
   mesh_cache[id]=mesh
  for s in source.get_surface_count():
   var old=m.get_active_material(s)
   var mat=ShaderMaterial.new();mat.shader=preload('res://story_boss/scripts/mephisto_leg_dissolve.gdshader')
   mat.set_shader_parameter('audition',1.0);mat.set_shader_parameter('variant',2.0)
   mat.set_shader_parameter('film_tex',preload('res://story_boss/assets/mephisto_paired/approved_rust_film.png'));mat.set_shader_parameter('albedo_tex',old.albedo_texture);mat.set_shader_parameter('tint',old.albedo_color)
   mat.set_shader_parameter('orm_tex',old.roughness_texture);mat.set_shader_parameter('normal_tex',old.normal_texture);mat.set_shader_parameter('normal_strength',old.normal_scale)
   m.set_surface_override_material(s,mat);materials.append(mat)
  m.mesh=mesh_cache[id]
 for i in 28:
  var m=MeshInstance3D.new();var quad=QuadMesh.new();quad.size=Vector2.ONE;m.mesh=quad;m.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  var mat=ShaderMaterial.new();mat.shader=preload('res://story_boss/scripts/mephisto_leg_wisp.gdshader');mat.set_shader_parameter('seed',float(i)*3.71);m.material_override=mat
  add_child(m);cards.append(m)
 audit={'cards':cards.size(),'shared_meshes':mesh_cache.size(),'setup_ms':(Time.get_ticks_usec()-started)/1000.0}
func _process(delta):
 if not is_instance_valid(view):queue_free();return
 var actor=view.actor()
 if actor.freeze_remaining<=0:clock+=delta
 for mat in materials:mat.set_shader_parameter('clock',clock)
 for i in cards.size():
  var m=cards[i];m.visible=wisps and view.is_visible_in_tree() and view.pair.is_visible_in_tree() and actor.stocks>0
  if not m.visible:continue
  var side='L' if i%2==0 else 'R'
  var knee=view.demon_point('DEF-shin.'+side);var hip=view.demon_point('DEF-thigh.'+side)
  var phase=fmod(clock*.33+float(i)/14.0,1.0);var angle=float(i)*2.399+clock*.14
  # Blend anatomically through crouch; a binary knee test popped on switch.
  var low=1.0-smoothstep(.08,.30,knee.y-actor.global_position.y)
  # Join the softened thigh rather than leave an isolated cloud at the ankle.
  var anchor=hip.lerp(knee,lerpf(.45,.24,low))
  anchor.y=maxf(anchor.y,actor.global_position.y+.23)
  m.global_position=anchor+Vector3(cos(angle)*(.08+phase*.18)+phase*.10,-.04+phase*lerpf(-.32,.22,low),sin(angle)*(.08+phase*.12))
  m.scale=Vector3(.64+phase*.38,.46+phase*.39,1)
  if get_meta("fuller",false):m.scale*=Vector3(1.85,1.55,1);m.global_position.x+=cos(angle)*.17
  m.material_override.set_shader_parameter('clock',clock)
  m.material_override.set_shader_parameter('opacity',sin(phase*PI)*lerpf(.72,.86,low)*(1.2 if get_meta('fuller',false) else 1.0))
