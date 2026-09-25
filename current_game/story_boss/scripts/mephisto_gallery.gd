extends CanvasLayer
const Kit=preload("res://story_boss/scripts/mephisto_kit.gd")
var arena
var panel:PanelContainer
var status:Label
var choice:OptionButton
var flip=1.0
func _ready():
 panel=PanelContainer.new();add_child(panel);panel.position=Vector2(12,110)
 var box=VBoxContainer.new();panel.add_child(box)
 var title=Label.new();title.text="MEPHISTO — PROVISIONAL KIT v001";box.add_child(title)
 var keys=Label.new();keys.text="F basic / G special + W/S/A/D\nSpace jump | E guard | Esc setup\nP2 passive human: physics + damage intact";box.add_child(keys)
 choice=OptionButton.new();box.add_child(choice)
 for id in Kit.MOVES:choice.add_item(id)
 var row=HBoxContainer.new();box.add_child(row)
 for text in ["PLAY ONCE","RESET","FLIP"]:
  var button=Button.new();button.text=text;row.add_child(button);button.pressed.connect(action.bind(text));button.focus_mode=Control.FOCUS_NONE
 status=Label.new();box.add_child(status)
func action(text):
 if arena.fighters.size()<2:return
 if text=="FLIP":flip=-flip
 var f=arena.fighters[0];var t=arena.fighters[1]
 var id=choice.get_item_text(choice.selected)
 var air=id in ["VeilCross","AirSwat","CrownHook","FallingClaw","UmberPlunge"]
 f.reset_fighter(Vector3(-1,3.2 if air else 0,0),true)
 t.reset_fighter(Vector3(-1+flip*(2.8 if id=="ShadowUppercut" else (3.4 if id=="RubberGuillotine" else 1.1)),0,0),true)
 f.facing=flip
 if text=="PLAY ONCE":f.mephisto_moves.start_kit(id,flip)
func _process(_delta):
 panel.visible=not arena.setup.visible and arena.fighters.size()>=2
 if not panel.visible:return
 var f=arena.fighters[0]
 var m=f.mephisto_moves
 status.text="%s  %.2fs\nP2 damage %.1f | tuning unapproved"%[m.move if not m.move.is_empty() else "READY",m.elapsed,arena.fighters[1].damage_percent]
