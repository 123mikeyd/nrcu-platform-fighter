extends Node3D
# Fixed .72-world-radius shadow dust, centered on the actual palm's stage hit.
var age=0.0
var cards=[]
func _ready():
 for i in 12:
  var card=MeshInstance3D.new();var quad=QuadMesh.new();quad.size=Vector2(.48,.24);card.mesh=quad
  card.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  var mat=ShaderMaterial.new();mat.shader=preload("res://story_boss/scripts/mephisto_leg_wisp.gdshader");mat.set_shader_parameter("seed",float(i)*3.71);mat.set_shader_parameter("opacity",.85);card.material_override=mat
  add_child(card);cards.append(card)
 _process(0)
func _process(delta):
 age+=delta
 if age>.48:queue_free();return
 for i in cards.size():
  var angle=float(i)*TAU/12.0
  var radius=.47
  cards[i].position=Vector3(cos(angle)*radius,.05+age*.12,sin(angle)*radius)
  cards[i].material_override.set_shader_parameter("clock",age)
  cards[i].material_override.set_shader_parameter("opacity",.85*(1.0-smoothstep(.22,.48,age)))
