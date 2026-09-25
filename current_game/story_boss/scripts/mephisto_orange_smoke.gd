extends Node3D
# Cosmetic only: never owns damage, colliders, or a target ledger.
var clock=0.0
var reach=1.6
var direction=1.0
var ground_dust=false
var material:ShaderMaterial
func _ready():
 add_to_group("mephisto_smoke")
 material=ShaderMaterial.new();material.shader=preload("res://story_boss/scripts/mephisto_orange_smoke.gdshader")
 var noise=FastNoiseLite.new();noise.seed=3003;noise.frequency=.035
 var texture=NoiseTexture2D.new();texture.width=128;texture.height=128;texture.noise=noise;texture.seamless=true
 material.set_shader_parameter("noise_tex",texture)
 for i in 18:
  var q=MeshInstance3D.new();var mesh=QuadMesh.new();var u=float(i%9)/8
  var radius=lerpf(.16,.48,u);mesh.size=Vector2.ONE*radius*2.4;q.mesh=mesh;q.material_override=material
  add_child(q);q.position=Vector3(direction*reach*u,sin(i*2.7)*radius*.35,float(i%2)*.12)
  if ground_dust:
   var theta=TAU*float(i)/18
   q.position=Vector3(cos(theta),.025,sin(theta))*reach*.65
   q.rotation.x=-PI/2;mesh.size=Vector2.ONE*.8
func _process(delta):
 clock+=delta
 material.set_shader_parameter("phase",clock)
 material.set_shader_parameter("opacity",.85*(1.0-smoothstep(.3,.85,clock)))
 if clock>.85:queue_free()
