extends SceneTree
var arena
var failures:Array=[]
var checks=0
func _initialize():call_deferred("run_suite")
func check(ok:bool,description:String):
 checks+=1
 if not ok:failures.append(description);print("FAIL ",description)
func frames(n:int):
 for i in n:await physics_frame
func key(code:int,down:bool):
 var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e)
func run_suite():
 var home=load("res://scenes/home.tscn").instantiate();root.add_child(home);current_scene=home
 await frames(2)
 check(home.state=="opening","default opening")
 home.show_page("title");check(home.buttons.has("start"),"title Start")
 home.show_page("home");check(home.buttons.has("story"),"home Story")
 root.remove_child(home);home.queue_free();await frames(1)
 arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);current_scene=arena
 arena.clearance.save_path="user://v05_release_fixture.cfg"
 DirAccess.remove_absolute(ProjectSettings.globalize_path(arena.clearance.save_path))
 await frames(2)
 check(not arena.clearance.is_unlocked(),"fresh clearance locked")
 check(arena.fortress.get_script().resource_path.ends_with("v05_fortress_stage.gd"),"normal scene owns public Fortress architecture adapter")
 check(load("res://scripts/roster.gd").ids().size()==8,"current roster eight including Bobo")
 check(arena.Run.HEROES.size()==6,"six Story heroes")
 for hero in arena.Run.HEROES:
  DirAccess.remove_absolute(ProjectSettings.globalize_path(arena.clearance.save_path))
  arena.choose_hero(hero)
  check(arena.run.route.size()==7 and hero not in arena.run.route,"skip selected hero "+hero)
  for node in 7:
   arena.briefing();check(arena.screen=="briefing","explicit briefing")
   var opponent=arena.run.opponent();arena.fight();await frames(2)
   check(arena.screen=="battle" and arena.player_one.character_id==hero and arena.player_two.character_id==opponent,"real route actors "+hero+" / "+opponent)
   check(arena.active_level==arena.encounter_world() and arena.active_level!="sky","curated world "+opponent)
   if hero=="mephisto":check(arena.player_one.get_script().resource_path=="res://scripts/fighter.gd","current companion hero independent")
   if opponent=="mephisto":check(arena.player_two.get_script().resource_path=="res://story_boss/scripts/fighter.gd","historical boss independent")
   arena.pause_game();check(paused and arena.pause_menu.visible,"pause route");arena.resume_game()
   if node==0 or node==6:
    # Forced production elimination path; NOT natural campaign wins.
    arena.player_one.stocks=1;arena.player_one._handle_blast_zone();await frames(1)
    check(arena.screen=="lost" and arena.run.index==node,"loss retains current route")
    check(not arena.clearance.is_unlocked(),"loss never unlocks")
    arena.retry();check(arena.screen=="briefing","retry requires explicit Start");arena.fight();await frames(2)
   if opponent=="bobo":
    arena.player_two.controls_enabled=true;arena.player_two.apply_status_damage(400)
   else:
    arena.player_two.stocks=1;arena.player_two._handle_blast_zone()
   await frames(1)
   check(arena.run.index==node+1,"forced victory progresses once")
   check(arena.clearance.is_unlocked()==(node==6),"only final victory unlocks")
  arena.show_victory();arena.show_credits();check(arena.screen=="credits","final credits")
  var reload=load("res://scripts/v05_clearance.gd").new();reload.save_path=arena.clearance.save_path
  check(reload.is_unlocked(),"persistent unlock reload")
 # Ordinary lethal contact must unwind before Story tears down actors.
 DirAccess.remove_absolute(ProjectSettings.globalize_path(arena.clearance.save_path))
 await preload("res://tests/story_contact_cases.gd").new().run_cases(self,arena,check)
 # Current freeplay factory: all eight current actors, never historical boss.
 arena.show_setup()
 for id in load("res://scripts/roster.gd").ids():
  var slots=arena.Config.default_slots();slots[0].character=id;slots[1].character="ice_mage";slots[1].kind="human";slots[2].kind="empty";slots[3].kind="empty"
  arena.start_match(slots,false);await frames(2)
  check(arena.player_one.character_id==id,"freeplay roster "+id)
  check(arena.player_one.get_script().resource_path==("res://scripts/bobo_player.gd" if id=="bobo" else "res://scripts/fighter.gd"),"current factory "+id)
 # Ordinary basic input against live health encounter; no injected damage here.
 arena.choose_hero("turbofit");arena.briefing();arena.fight();await frames(125)
 arena.player_one.reset_fighter(Vector3(-1,0.2,0),true);arena.player_one.controls_enabled=true;arena.player_one.facing=1
 await frames(30)
 var hp=arena.player_two.health
 for swing in 4:
  key(KEY_F,true);await frames(8);key(KEY_F,false);await frames(40)
 check(arena.player_two.health<hp,"ordinary basic damages live Bobo")
 # Ordinary viewport keyboard input against passive opponent (no bot interference).
 arena.show_setup();arena.setup.level.select(1)
 var slots=arena.Config.default_slots();slots[0].character="turbofit";slots[1].character="ice_mage";slots[1].kind="human";slots[2].kind="empty";slots[3].kind="empty"
 arena.start_match(slots,false);await frames(120)
 var start:Vector3=arena.player_one.position
 key(KEY_D,true);await frames(12);key(KEY_D,false);await frames(2)
 check(arena.player_one.position.x>start.x+0.2,"ordinary move input")
 var y:float=arena.player_one.position.y
 key(KEY_SPACE,true);await frames(8);key(KEY_SPACE,false);await frames(2)
 check(arena.player_one.position.y>y+0.3,"ordinary jump input")
 # World geometry is real collision plus authored art, not scene-only screenshots.
 for world in ["hall","meadow"]:
  arena.apply_level(world);arena.player_one.reset_fighter(Vector3(-4,2,0),true);arena.player_two.reset_fighter(Vector3(4,3,0),true)
  await frames(100)
  check(arena.world.moving is AnimatableBody3D,"moving world contact "+world)
  check(arena.player_one.is_on_floor(),"native floor contact "+world)
  check(arena.world.get_node("WorldArt")!=null if arena.world.has_node("WorldArt") else arena.world.get_child_count()>4,"world art integrated "+world)
 # Public release omits the local-only decorative character sequence entirely.
 check(not FileAccess.file_exists("res://scripts/fortress_snake_shootout_v9.gd"),"no local-only sequence source")
 check(arena.fortress.find_children("*","CollisionObject3D",true,false).is_empty(),"fortress visual adapter has no physics")
 check(arena.has_node("KainanTerminal"),"authorized Kainan reference retained")
 # Starting Story after any freeplay world resolves explicit world.
 arena.choose_hero("turbofit");arena.briefing();arena.fight();await frames(2)
 check(arena.active_level=="toy_room","Story ignores previous freeplay world")
 arena.clear_battle();arena.practice=true;arena.show_setup();arena.start_match(slots,false);await frames(2)
 check(arena.screen=="practice" and arena.player_two._bot.get_script().resource_path.ends_with("practice_idle_bot.gd"),"in-process Battle Lab current game")
 arena.clear_battle();arena.show_setup()
 check(arena.start_match(arena.Config.default_slots(),false),"Battle Lab default four-slot Start succeeds")
 await frames(2)
 check(arena.fighters.size()==4,"Battle Lab default four fighters")
 arena.player_one.damage_percent=50;arena._reset_match();check(arena.player_one.damage_percent==0,"practice reset")
 arena.clear_battle();DirAccess.remove_absolute(ProjectSettings.globalize_path(arena.clearance.save_path))
 root.remove_child(arena);arena.queue_free();await frames(3)
 print("V05 checks=",checks," failures=",failures.size(),"; route outcomes are forced fixtures, not natural clears")
 if failures.is_empty():print("V05_RELEASE_COMPLETE")
 quit(0 if failures.is_empty() else 1)
