extends SceneTree
var a
var rows=[]
var failures=[]
func _initialize():call_deferred("run_test")
func frames(n):
 for i in n:await physics_frame
func key(code,down):
 var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e)
func check(ok,label):
 if not ok:failures.append(label);print("FAIL ",label)
func run_test():
 a=load("res://scenes/main.tscn").instantiate();root.add_child(a);current_scene=a
 a.clearance.save_path="user://world_fixture.cfg"
 a.choose_hero("turbofit");a.briefing();a.fight();await frames(125)
 # Ordinary key attack against live Bobo, no injected damage for this check.
 a.player_one.reset_fighter(Vector3(-1,0.2,0),true);a.player_one.controls_enabled=true;a.player_one.facing=1
 await frames(30)
 var hp=a.player_two.health
 for i in 4:
  key(KEY_F,true);await frames(8);key(KEY_F,false);await frames(40)
 check(a.player_two.health<hp,"ordinary basic input damages live Bobo")
 rows.append({"basic_bobo_health_before":hp,"after":a.player_two.health})
 for world in ["hall","meadow"]:
  a.show_setup();a.setup.level.select(a.SetupScript.LEVEL_IDS.find(world))
  var slots=a.Config.default_slots();slots[0].character="turbofit";slots[1].character="ggb";slots[1].kind="bot";slots[2].kind="empty";slots[3].kind="empty"
  a.start_match(slots,false);await frames(125)
  var starting=a.player_two.position
  var min_distance=100.0
  var contacts=0
  for i in 600:
   await physics_frame
   if a.player_two.is_on_floor():contacts+=1
   min_distance=minf(min_distance,a.player_one.position.distance_to(a.player_two.position))
  rows.append({"world":world,"bot_start":str(starting),"bot_end":str(a.player_two.position),"stocks":a.player_two.stocks,"floor_frames":contacts,"minimum_distance":min_distance})
  check(a.player_two.stocks>0,"bot remains alive "+world)
  check(contacts>20,"bot floor contacts "+world)
  check(min_distance<3.0,"bot reaches opponent "+world)
  # Deterministic double-jump recovery trial through native key edges; not a natural match.
  a.player_two.control_type="human";a.player_two.controls_enabled=false
  a.player_one.reset_fighter(Vector3(-4,2,0),true);a.player_one.controls_enabled=true
  await frames(50)
  key(KEY_D,true);key(KEY_SPACE,true);await frames(5);key(KEY_SPACE,false);await frames(20)
  key(KEY_SPACE,true);await frames(5);key(KEY_SPACE,false);await frames(30);key(KEY_D,false);await frames(45)
  rows.append({"world":world,"recovery_end":str(a.player_one.position),"floor":a.player_one.is_on_floor(),"stocks":a.player_one.stocks})
  check(a.player_one.stocks==3,"recovery retains stock "+world)
  check(a.player_one.is_on_floor(),"recovery lands "+world)
  var moving=a.world.moving
  a.player_one.reset_fighter(Vector3(moving.position.x,moving.get_meta("top_y")+0.08,0),true);a.player_one.controls_enabled=true
  await frames(20)
  var platform_before=moving.position.y;var rider_before=a.player_one.position.y
  await frames(30)
  var carry_error=absf((a.player_one.position.y-rider_before)-(moving.position.y-platform_before))
  check(a.player_one.is_on_floor() and carry_error<0.12,"moving platform rider carry "+world)
  key(KEY_S,true);await frames(14);key(KEY_S,false);await frames(6)
  check(a.player_one.position.y<moving.get_meta("top_y"),"one-way down drop "+world)
  rows.append({"world":world,"rider_carry_error":carry_error,"drop_y":a.player_one.position.y,"platform_top":moving.get_meta("top_y")})
  var camera=root.get_camera_3d()
  check(not camera.is_position_behind(a.player_one.position),"camera tracks recovery "+world)
 var path="res://.verification/worlds.json";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.verification"))
 var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify({"rows":rows,"failures":failures},"  "));f.close()
 a.clear_battle();root.remove_child(a);a.queue_free();await frames(3)
 print("V05_WORLDS_COMPLETE ",JSON.stringify(rows));quit(0 if failures.is_empty() else 1)
