extends "res://scripts/story_gauntlet.gd"
var clearance=preload("res://scripts/v05_clearance.gd").new()
var pause_menu:Panel
var fortress:Node3D
var practice=false
var world:Node3D
var world_environment:Dictionary={}
func _process(delta:float):
 super._process(delta)
 if is_instance_valid(bobo_health_bar):
  bobo_health_bar.position.x=660
  bobo_health_bar.position.y=145 if get_node_or_null("/root/MobileTouch") and get_node("/root/MobileTouch").touch_mode else 624
func _build_hud():
 super._build_hud()
 var layer=hud_title.get_parent()
 for row in [Vector2(0,0),Vector2(0,600)]:
  var shade=ColorRect.new();shade.position=row;shade.size=Vector2(1280,65 if row.y==0 else 120);shade.color=Color(0.02,0.03,0.05,0.68);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
  layer.add_child(shade);layer.move_child(shade,0)
func _ready():
 super._ready()
 var layer=CanvasLayer.new();layer.layer=60;add_child(layer)
 pause_menu=preload("res://scripts/candidate_pause.gd").new();layer.add_child(pause_menu)
 pause_menu.resume_requested.connect(resume_game)
 pause_menu.setup_requested.connect(func():
  resume_game()
  if screen=="battle":show_board(false)
  else:show_setup())
 pause_menu.home_requested.connect(func():resume_game();back_to_menu())
 if get_tree().has_meta("v05_entry"):
  var entry=get_tree().get_meta("v05_entry");get_tree().remove_meta("v05_entry")
  if entry=="freeplay":show_setup()
  elif entry=="lab" and clearance.is_unlocked():practice=true;show_setup()
func _build_environment():
 super._build_environment()
 for n in get_children():
  if n is Camera3D:remove_child(n);n.queue_free()
 add_child(preload("res://scripts/fortress_shared_camera.gd").new())
func _build_hangar_backdrop():
 fortress=preload("res://scripts/v05_fortress_stage.gd").new();add_child(fortress)
func show_setup():
 if not is_instance_valid(ui):return
 clear_battle();ui.hide();screen="setup";setup.show()
 setup.find_child("StartMatchButton",true,false).grab_focus()
func open_story():
 practice=false;show_selection()
func back_to_menu():
 get_tree().paused=false
 get_tree().change_scene_to_file("res://scenes/home.tscn")
func start_match(slots:Array,teams:bool,bobo_encounter=false)->bool:
 var is_story=screen=="briefing"
 var actual=slots.duplicate(true)
 if practice and not is_story:
  # Current fighters, ordinary combat, idle training opponent; no subprocess.
  for i in range(1,actual.size()):
   if actual[i].kind!="empty":actual[i].kind="bot";actual[i].device=-1
 var ok=super.start_match(actual,teams,bobo_encounter)
 if ok and not is_story:
  screen="practice" if practice else "freeplay";ui.hide()
  if active_level in ["hall","meadow"]:
   for i in fighters.size():fighters[i].reset_fighter(Vector3(([-4.0,4.0] if fighters.size()==2 else [-8.0,-4.0,4.0,8.0])[i],3,0),true)
  if practice:
   for f in fighters:
    if f.player_index>1:f._bot=preload("res://scripts/practice_idle_bot.gd").new()
   hud_title.text="BATTLE LAB / CURRENT KITS";hud_controls.text="Practice: ordinary controls · R reset damage/stocks · Esc pause / setup"
 return ok
func encounter_world()->String:
 return {"bobo":"toy_room","ice_mage":"toy_room","witcheer":"debug","ggb":"meadow","turbofit":"hall","doge_man":"toy_room","teknium":"debug","mephisto":"debug"}.get(run.opponent(),"debug")
func fight():
 if screen!="briefing":return
 setup.level.select(SetupScript.LEVEL_IDS.find(encounter_world()))
 super.fight()
 if screen=="battle":hud_controls.text="A/D move · Space jump · F basic · G special · WASD aim
Esc pause · Seven encounters · Fresh stocks each attempt"
func apply_level(id:String):
 var env=find_children("*","WorldEnvironment",false,false)[0].environment
 for k in world_environment:env.set(k,world_environment[k])
 world_environment.clear()
 if is_instance_valid(world):remove_child(world);world.queue_free();world=null
 if id in ["hall","meadow"]:
  super.apply_level("debug")
  active_level=id
  for n in preload("res://scripts/stage_layouts.gd").NAMES:
   var body=get_node(n);body.collision_layer=0;body.get_child(0).hide()
  for v in debug_visuals:v.hide()
  world=preload("res://scripts/character_world.gd").new();world.world_id=id;add_child(world)
  for k in ["background_color","ambient_light_color","ambient_light_energy"]:world_environment[k]=env.get(k)
  env.background_color=Color("9ebabe") if id=="meadow" else Color("17191d")
  env.ambient_light_color=Color("bccac1") if id=="meadow" else Color("e0cfb6")
  env.ambient_light_energy=0.85
 else:
  # Force restoration after custom worlds, retaining the base collider RIDs.
  if active_level in ["hall","meadow"]:active_level=""
  super.apply_level(id)
func show_victory():
 if not run.complete():return
 clearance.record_run(run)
 super.show_victory()
func show_credits():
 super.show_credits()
 if run.complete():
  label("Battle Lab unlocked · Current-game practice
Quark experimental tools are separate and not included.",Vector2(55,610),Vector2(1120,55),18)
  button("HOME",Vector2(920,565),Vector2(280,60),back_to_menu)
func _on_fighter_eliminated(loser:CharacterBody3D):
 super._on_fighter_eliminated(loser)
 if story_state=="" and screen=="board" and run.complete():clearance.record_run(run)
func pause_game():
 if not screen in ["battle","freeplay","practice"]:return
 for child in pause_menu.get_children():
  if child is Button and child.text in ["Match Setup","Story Board"]:child.text="Story Board" if screen=="battle" else "Match Setup"
 pause_menu.show();get_tree().paused=true
func resume_game():
 get_tree().paused=false
 if is_instance_valid(pause_menu):pause_menu.hide()
func _unhandled_key_input(event:InputEvent):
 if not event is InputEventKey or not event.pressed or event.echo:return
 if event.keycode==KEY_ESCAPE:
  if screen in ["battle","freeplay","practice"]:pause_game()
  elif screen=="setup":back_to_menu()
  elif screen=="select":back_to_menu()
  else:show_board(false)
  get_viewport().set_input_as_handled()
 elif event.keycode==KEY_R:
  if screen=="practice":_reset_match()
  elif screen in ["freeplay","setup"]:
   if match_over:_reset_match()
  else:_reset_match()
  get_viewport().set_input_as_handled()
func _reset_match():
 if screen in ["freeplay","practice"]:
  match_over=false;winner_label.hide();result_panel.hide()
  for f in fighters:f.process_mode=Node.PROCESS_MODE_INHERIT;f.reset_fighter(f.spawn_position,true)
  _begin_ready()
 else:super._reset_match()
