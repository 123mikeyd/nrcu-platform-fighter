extends Node3D
# Damage-only native anatomy, both silhouettes, one receiving owner/ledger.
var actor
var view
var body:StaticBody3D
var shapes:Array[CollisionShape3D]=[]
func _ready():
 actor=get_parent();view=actor.get_node("VisualRoot/MephistoVisual")
 body=StaticBody3D.new();body.name="DamageOnlyBody";body.collision_layer=4;body.collision_mask=0
 body.set_meta("hurtbox_actor",actor);add_child(body)
 for n in ["DemonBody","DemonHead","DemonLeftThigh","DemonLeftShin","DemonRightThigh","DemonRightShin","DemonLeftArm","DemonLeftForearm","DemonRightArm","DemonRightForearm","GirlBody","GirlHead","GirlLeftLeg","GirlRightLeg"]:
  var shape=CollisionShape3D.new();shape.name=n;shape.shape=CapsuleShape3D.new();body.add_child(shape);shapes.append(shape)
 sync()
func fit(i:int,a:Vector3,b:Vector3,r:float):
 var c=shapes[i];c.shape.radius=r;c.shape.height=maxf(r*2,a.distance_to(b)+r*2)
 var axis=b-a
 c.global_transform=Transform3D(Basis.IDENTITY if axis.length_squared()<.0000001 else Basis(Quaternion(Vector3.UP,axis.normalized())),(a+b)*.5)
 c.force_update_transform()
func sync():
 if not view or not view.demon:return
 body.global_transform=Transform3D.IDENTITY;body.collision_layer=4 if actor.controls_enabled and actor.stocks>0 else 0
 fit(0,view.demon_point("DEF-spine"),view.demon_point("DEF-spine.003"),.30)
 var head=view.demon_point("DEF-spine.006")
 fit(1,head,head+Vector3.UP*.13,.22)
 for side in 2:
  var suffix=".L" if side==0 else ".R"
  fit(2+side*2,view.demon_point("DEF-thigh"+suffix),view.demon_point("DEF-shin"+suffix),.15)
  fit(3+side*2,view.demon_point("DEF-shin"+suffix),view.demon_point("DEF-foot"+suffix),.12)
  fit(6+side*2,view.demon_point("DEF-upper_arm"+suffix),view.demon_point("DEF-forearm"+suffix),.15)
  fit(7+side*2,view.demon_point("DEF-forearm"+suffix),view.demon_point("DEF-hand"+suffix),.13)
 fit(10,view.girl_point("Hips"),view.girl_point("neck"),.13)
 var gh=view.girl_point("Head")
 fit(11,gh,gh+Vector3.UP*.09,.12)
 fit(12,view.girl_point("LeftUpLeg"),view.girl_point("LeftFoot"),.08)
 fit(13,view.girl_point("RightUpLeg"),view.girl_point("RightFoot"),.08)
 body.force_update_transform()
