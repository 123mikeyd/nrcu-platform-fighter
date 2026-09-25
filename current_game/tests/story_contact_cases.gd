extends RefCounted
# Real input/contact regressions. Health/position fixtures shorten the test, not
# damage dispatch. Stock and cancellation cases are explicitly lifecycle fixtures.
var tree:SceneTree
var arena
var verify:Callable
var observed=false
var contact_stack:Array=[]
func frames(n:int):
 for i in n:await tree.physics_frame
func key(code:int,down:bool):
 var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e)
func start(hero="turbofit",index=0):
 arena.choose_hero(hero);arena.run.index=index;arena.briefing();arena.fight()
 await frames(125)
func watch_contact(hero,target,kind:String):
 observed=false
 target.eliminated.connect(func(_loser):
  observed=true;contact_stack=get_stack()
  print("CONTACT_STACK ",kind," ",contact_stack)
  verify.call(hero.is_inside_tree() and target.is_inside_tree(),kind+" actors attached inside lethal callback")
  verify.call(arena.screen=="battle" and arena.match_over,kind+" outcome latched before teardown")
  # Re-entrant/duplicate elimination cannot schedule another result.
  arena._on_fighter_eliminated(target)
 )
func run_cases(owner:SceneTree,battle,checker:Callable):
 tree=owner;arena=battle;verify=checker
 await start()
 var hero=arena.player_one;var target=arena.player_two
 hero.reset_fighter(Vector3(-1,0.2,0),true);hero.controls_enabled=true;hero.facing=1
 await frames(30)
 target.health=1;watch_contact(hero,target,"melee")
 for swing in 4:
  key(KEY_F,true);await frames(8);key(KEY_F,false);await frames(40)
  if observed:break
 verify.call(observed,"ordinary melee causes lethal contact")
 verify.call(str(contact_stack).contains("_directional_hit") and str(contact_stack).contains("_physics_process"),"melee elimination comes from live attack physics stack")
 verify.call(arena.screen=="board" and arena.run.index==1,"melee advances exactly once")
 verify.call(not is_instance_valid(hero) and not is_instance_valid(target),"retired melee actors freed after dispatch")
 verify.call(tree.get_nodes_in_group("projectiles").is_empty(),"result clears old projectiles")
 verify.call(not arena.clearance.is_unlocked(),"first win cannot unlock")
 await frames(60)
 verify.call(arena.screen=="board" and arena.fighters.is_empty(),"board never autostarts next encounter")
 arena.briefing();verify.call(arena.screen=="briefing" and arena.fighters.is_empty(),"next requires explicit Start")
 arena.fight();await frames(125)
 verify.call(arena.player_two.character_id=="ice_mage" and arena.player_one.character_id=="turbofit","Ice starts with retained hero")
 # Native physics blast-zone loss, not a direct result handler call.
 hero=arena.player_one;target=arena.player_two
 hero.stocks=1;hero.global_position=Vector3(0,-40,0)
 await frames(4)
 verify.call(arena.screen=="lost" and arena.run.index==1,"physics last stock loss retains node")
 arena.retry();verify.call(arena.screen=="briefing","retry remains explicit")
 arena.fight();await frames(125)
 verify.call(arena.player_one.stocks==3 and arena.player_two.stocks==3,"retry fresh stocks")
 target=arena.player_two;target._bot=preload("res://scripts/practice_idle_bot.gd").new()
 target.global_position=Vector3(0,-40,0);await frames(4)
 verify.call(arena.screen=="battle" and target.stocks==2 and not arena.match_over,"nonfinal stock revives without result")
 target.reset_fighter(Vector3(0,-40,0),false);target.stocks=1;await frames(4)
 verify.call(arena.screen=="board" and arena.run.index==2,"physics enemy last stock advances once")
 # Ordinary melee knockback must also reach a stock-based outcome through
 # real movement/blast-zone physics (high-percent, one-stock setup only).
 await start("turbofit",1)
 hero=arena.player_one;target=arena.player_two
 target._bot=preload("res://scripts/practice_idle_bot.gd").new()
 hero.reset_fighter(Vector3(-1,0.2,0),true);hero.facing=1
 target.reset_fighter(Vector3(1,0.2,0),true)
 await frames(30)
 target.damage_percent=1000;target.stocks=1
 var damage_seen=[false]
 target.state_changed.connect(func():
  if is_instance_valid(target) and target.damage_percent>1000:damage_seen[0]=true
 )
 watch_contact(hero,target,"stock launch")
 key(KEY_F,true);await frames(8);key(KEY_F,false);await frames(120)
 verify.call(damage_seen[0],"ordinary melee actually damages stock opponent")
 verify.call(observed and str(contact_stack).contains("_handle_blast_zone"),"melee launch reaches production stock elimination")
 verify.call(arena.screen=="board" and arena.run.index==2,"ordinary stock launch advances once")
 # TurboFit side special emits the real swept sound-wave projectile.
 await start()
 hero=arena.player_one;target=arena.player_two
 hero.reset_fighter(Vector3(-3,0.2,0),true);hero.controls_enabled=true;hero.facing=1
 await frames(30)
 target.health=1;watch_contact(hero,target,"projectile")
 for shot in 4:
  key(KEY_D,true);key(KEY_G,true);await frames(8);key(KEY_G,false);key(KEY_D,false);await frames(50)
  if observed:break
 verify.call(observed,"ordinary projectile causes lethal contact")
 verify.call(str(contact_stack).contains("_sweep_wave") and str(contact_stack).contains("_physics_process"),"projectile elimination comes from swept contact physics")
 verify.call(arena.screen=="board" and arena.run.index==1,"projectile advances once")
 verify.call(tree.get_nodes_in_group("projectiles").is_empty(),"lethal projectile cleaned after dispatch")
 # Queue a result outside physics, then abort/replace before deferred delivery.
 # These are cancellation fixtures, not claimed natural contact wins.
 for leave in ["board","selection","replacement"]:
  await start()
  target=arena.player_two;target.apply_status_damage(400)
  verify.call(arena.match_over and arena.screen=="battle","result pending before "+leave)
  if leave=="board":arena.show_board(false)
  elif leave=="selection":arena.show_selection()
  else:arena.choose_hero("teknium");arena.briefing();arena.fight()
  await frames(4)
  verify.call(arena.run.index==0,"aborted result cannot advance "+leave)
  verify.call(arena.screen=={"board":"board","selection":"select","replacement":"battle"}[leave],"stale result cannot replace "+leave)
  if leave=="replacement":verify.call(arena.player_one.character_id=="teknium","replacement actors retained")
 # Forced final-node fixture exercises delayed persistence and credits routing.
 await start("turbofit",6)
 target=arena.player_two;target.stocks=1;target.global_position=Vector3(0,-40,0)
 await frames(4)
 verify.call(arena.run.complete() and arena.screen=="board","final physics elimination completes once")
 verify.call(arena.clearance.is_unlocked(),"deferred final board persists clearance")
 arena.show_victory();verify.call(arena.screen=="victory","final victory route")
 arena.show_credits();verify.call(arena.screen=="credits","final credits route")
 arena.show_selection();verify.call(arena.screen=="select" and arena.fighters.is_empty(),"credits return clears actors")
 arena.clear_battle()
