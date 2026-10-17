extends Node3D
# Local, unlit geometry only: no lights, screen overlay, audio or collision.
var impact := false
var age := 0.0
var material: StandardMaterial3D
var pieces: Array[MeshInstance3D] = []
func _ready():
 material=StandardMaterial3D.new()
 material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
 # Keep the tiny contact marker legible when the true surface witness is on
 # the far-side arm. Its world anchor never moves to an actor-center proxy.
 material.no_depth_test=impact
 material.albedo_color=Color(1.0,.68,.18,.65)
 for i in (6 if impact else 3):
  var piece=MeshInstance3D.new()
  if impact:
   var mesh=CylinderMesh.new();mesh.top_radius=.006;mesh.bottom_radius=.018;mesh.height=.15;mesh.radial_segments=6
   piece.mesh=mesh
  else:
   var mesh=SphereMesh.new();mesh.radius=.027;mesh.height=.054;mesh.radial_segments=8;mesh.rings=4
   piece.mesh=mesh
  piece.material_override=material
  piece.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(piece);pieces.append(piece)
 pose(0)
func pose(time:float):
 var u=clampf(time/.18,0,1) if impact else 0.0
 material.albedo_color.a=(.8*(1-u)) if impact else .60
 for i in pieces.size():
  var angle=TAU*float(i)/pieces.size()+(0.0 if impact else time*5.0)
  var radial=Vector3(cos(angle),sin(angle),0)
  pieces[i].position=radial*(.07+u*.18 if impact else .13)
  if impact:pieces[i].rotation.z=angle-PI/2;pieces[i].scale=Vector3.ONE*(1.0-u*.45)
func _process(delta:float):
 if not impact:return # Wind-up is driven by the move's exact pose clock.
 age+=delta
 if age>=.18:queue_free();return
 pose(age)
