extends Node3D
# Per-character overlay + fixed-size world-space puff/spark pool. No screen flash.
var actor
var overlay: StandardMaterial3D
var meshes: Array = []
var particles: Array = []
var cursor := 0
var emit_clock := 0.0
var strength := 0.0
var flashing := false
func setup(owner_actor):
 actor=owner_actor
 top_level=true
 overlay=StandardMaterial3D.new()
 overlay.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
 overlay.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 overlay.albedo_color=Color(1,.78,.42,0)
 for mesh in actor._visual_root.find_children("*","MeshInstance3D",true,false):
  meshes.append({"mesh":mesh,"old":mesh.material_overlay})
 for i in 32:
  var mesh=MeshInstance3D.new()
  var sphere=SphereMesh.new();sphere.radius=.16;sphere.height=.32
  sphere.radial_segments=8;sphere.rings=4;mesh.mesh=sphere
  var mat=StandardMaterial3D.new();mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
  mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
  mesh.material_override=mat;mesh.visible=false;add_child(mesh)
  particles.append({"mesh":mesh,"life":0.0,"max":.35,"velocity":Vector3.ZERO,"spark":false,"power":0.0})
func emit_at(point: Vector3, power: float, spark := false):
 var p=particles[cursor];cursor=(cursor+1)%particles.size()
 p.life=.24 if spark else .4;p.max=p.life;p.power=power;p.spark=spark
 p.mesh.global_position=point
 var angle=cursor*2.399
 p.velocity=Vector3(cos(angle),sin(angle),.2)*3 if spark else Vector3(0,.6,0)
 p.mesh.scale=Vector3(.2,.2,.2) if spark else Vector3.ONE
 p.mesh.visible=true
func impact(point: Vector3, power: float):
 for i in 8:emit_at(point,power,true)
func update(delta: float, dangerous: bool, clock: float, speed: float):
 strength=clampf((speed-7)/10,0,1) if dangerous else 0.0
 # Two short, low-opacity localized pulses per second, never full screen.
 flashing=dangerous and fmod(clock,.5)<.09
 overlay.albedo_color=Color(1,.78,.42,.24*strength if flashing else 0)
 for entry in meshes:
  if is_instance_valid(entry.mesh):entry.mesh.material_overlay=overlay if flashing else entry.old
 emit_clock+=delta
 if dangerous and emit_clock>=.035:
  emit_clock=0
  emit_at(actor.global_position+Vector3.UP, strength)
 for p in particles:
  if p.life<=0:continue
  p.life=maxf(0,p.life-delta)
  p.mesh.global_position+=p.velocity*delta
  var fade=p.life/p.max
  p.mesh.material_override.albedo_color=Color(1,.72,.25,fade*p.power) if p.spark else Color(.65,.70,.77,fade*.35*p.power)
  if not p.spark:p.mesh.scale=Vector3.ONE*(1+(1-fade)*1.6)
  p.mesh.visible=p.life>0
func _exit_tree():
 clear()
func clear():
 flashing=false;strength=0
 for entry in meshes:
  if is_instance_valid(entry.mesh):entry.mesh.material_overlay=entry.old
 for p in particles:p.life=0;p.mesh.visible=false
