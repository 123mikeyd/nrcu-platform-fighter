extends SceneTree
const OUT="res://.verification/evidence/latest/"
var rows=[]
var arena
func _initialize():call_deferred("run")
func frames(n):
 for i in n:await physics_frame;await process_frame
func key(k,p):
 var e=InputEventKey.new();e.keycode=k;e.pressed=p;Input.parse_input_event(e)
func run():
 arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
 var config=load("res://scripts/match_config.gd")
 for enemy in ["doge_man","teknium","turbofit"]:
  load("res://tools/play_mephisto.gd").configure(arena);arena.setup.rows[1].character.select(config.CHARACTERS.find(enemy));arena.setup._start();await frames(210)
  var f=arena.fighters[0];var t=arena.fighters[1]
  for face in [1.0,-1.0]:
   for spec in [[0,"RightSwipe"],[KEY_D if face>0 else KEY_A,"FrontKick"],[KEY_W,"RisingForearm"],[KEY_S,"Stomp"]]:
    for gap in [1.12,1.5,5.0,-2.0]:
     f.reset_fighter(Vector3(-8,.1,0),true);t.reset_fighter(Vector3(8,.1,0),true);await frames(8)
     f.reset_fighter(Vector3(0,.1,0),false);t.reset_fighter(Vector3(face*gap,.1,0),false)
     f.mephisto_moves.demon_form=true;f.facing=face;t.facing=-face;await frames(25)
     var startgap=absf(t.position.x-f.position.x)
     if spec[0]:key(spec[0],true)
     key(KEY_F,true);await frames(2);key(KEY_F,false)
     if spec[0]:key(spec[0],false)
     await frames(72)
     var row={"enemy":enemy,"face":face,"move":spec[1],"requested_gap":gap,"actual_gap":startgap,"damage":t.damage_percent,"contacts":f.mephisto_moves.contacts.duplicate(true)}
     rows.append(row);print("CONTACT_ROW ",JSON.stringify(row))
  arena.show_setup();await frames(2)
 var file=FileAccess.open(OUT+"ground_contacts.json",FileAccess.WRITE);file.store_string(JSON.stringify(rows," "));file.close()
 var failures=0
 for r in rows:
  if r.requested_gap in [5.0,-2.0] and r.damage!=0:failures+=1
  if r.requested_gap==1.12 and r.move!="RisingForearm" and r.damage<=0:failures+=1
  if absf(r.actual_gap-absf(r.requested_gap))>.05:failures+=1
 if rows.size()!=96:failures+=1
 print("PAIRED_GROUND_MATRIX_COMPLETE rows=",rows.size()," failures=",failures)
 if failures:printerr("FAIL: ground matrix reach/miss/fixture assertions")
 quit(1 if failures else 0)
