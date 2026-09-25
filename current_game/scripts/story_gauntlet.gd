extends "res://scripts/main.gd"
const Run=preload("res://scripts/story_run.gd")
const Roster=preload("res://scripts/roster.gd")
const CREDITS=["Mike","Quark","Arts Bro","Hermes Agent"]
var run=Run.new()
var screen="select"
var credits_names=CREDITS.duplicate()
var ui:Control
var page:Control
var token:Control
var route_line:Control
var motion:Tween
var primary:Button
var points:Array[Vector2]=[Vector2(135,320),Vector2(290,220),Vector2(455,365),Vector2(620,240),Vector2(785,395),Vector2(935,265),Vector2(1115,350)]
func _ready():
 super._ready()
 DisplayServer.window_set_title("NRCU — v0.5")
 var layer=CanvasLayer.new();layer.layer=30;add_child(layer)
 ui=Control.new();ui.name="StoryGauntlet";ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(ui)
 var theme=Theme.new()
 var font="res://assets/fonts/ZillaSlab-Bold.ttf"
 if ResourceLoader.exists(font):theme.default_font=load(font)
 theme.default_font_size=20;ui.theme=theme
 show_selection()
func _create_fighter(id:String,bobo_encounter:bool,slot:int):
 if screen=="briefing" and slot==1 and id=="mephisto":return load("res://story_boss/scripts/fighter.gd").new()
 return super._create_fighter(id,bobo_encounter,slot)
func clear_battle():
 _cancel_ready();story_state="";match_over=false
 setup.hide();story_panel.hide();result_panel.hide();winner_label.hide();bobo_health_bar.hide()
 for f in fighters:
  f.controls_enabled=false;f._clear_move_state();remove_child(f);f.queue_free()
 fighters.clear();player_one=null;player_two=null
 for p in get_tree().get_nodes_in_group("projectiles")+get_tree().get_nodes_in_group("goo_puddles"):p.queue_free()
 for l in hud_labels:l.text=""
func new_page(title:String,subtitle:String):
 if motion and motion.is_valid():motion.kill()
 for c in ui.get_children():ui.remove_child(c);c.queue_free()
 ui.show()
 page=Control.new();page.size=Vector2(1280,720);ui.add_child(page)
 var bg=TextureRect.new();bg.texture=load("res://assets/story_art/vs/stages/toy_room.png");bg.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;bg.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;bg.size=Vector2(1280,720);bg.modulate=Color(.25,.30,.34,1);page.add_child(bg)
 var wash=ColorRect.new();wash.color=Color(.025,.055,.085,.72);wash.size=Vector2(1280,720);page.add_child(wash)
 label(title,Vector2(55,35),Vector2(1170,60),38)
 label(subtitle,Vector2(58,100),Vector2(1160,50),18,Color("b2c5cd"))
 label("NRCU  /  v0.5",Vector2(55,684),Vector2(800,26),14,Color("8aa6b6"))
func label(text:String,pos:Vector2,extent:Vector2,font_size=20,color=Color.WHITE)->Label:
 var l=Label.new();l.text=text;l.position=pos;l.size=extent;l.add_theme_font_size_override("font_size",font_size);l.add_theme_color_override("font_color",color);page.add_child(l);return l
func button(text:String,pos:Vector2,extent:Vector2,callback:Callable)->Button:
 var b=Button.new();b.text=text;b.position=pos;b.size=extent
 var style=StyleBoxFlat.new();style.bg_color=Color("183341");style.border_color=Color("8baebe");style.set_border_width_all(2);style.set_corner_radius_all(7)
 b.add_theme_stylebox_override("normal",style);b.add_theme_font_size_override("font_size",22);b.pressed.connect(callback);page.add_child(b);return b
func portrait(id:String,pos:Vector2,extent:Vector2,right=false,parent:Control=null)->Control:
 var host=parent if parent else page
 var path="res://assets/story_art/vs/fighters/%s/primary.png"%id
 if ResourceLoader.exists(path):
  var t=TextureRect.new();t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.texture=load(path);t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;t.position=pos;t.size=extent;t.mouse_filter=Control.MOUSE_FILTER_IGNORE;t.flip_h=not right if id=="ggb" else right;host.add_child(t);return t
 var fallback=Label.new();fallback.text={"bobo":"B","ice_mage":"ICE","mephisto":"M"}.get(id,"?");fallback.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;fallback.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;fallback.add_theme_font_size_override("font_size",int(minf(extent.x,extent.y)*.48));fallback.position=pos;fallback.size=extent;fallback.mouse_filter=Control.MOUSE_FILTER_IGNORE;fallback.modulate=Color("e6bb9b") if id=="mephisto" else Color("bacfdd");host.add_child(fallback);return fallback
func show_selection():
 clear_battle();screen="select"
 new_page("Story Mode","CHOOSE YOUR HERO  /  Fight through the roster. Seven encounters. Your chosen hero is skipped.")
 for i in Run.HEROES.size():
  var id=Run.HEROES[i];var x=55+i*205
  var panel=ColorRect.new();panel.color=Color(.08,.16,.21,.8);panel.position=Vector2(x,175);panel.size=Vector2(180,340);page.add_child(panel)
  portrait(id,Vector2(x+15,180),Vector2(155,300))
  button(Roster.display_name(id).to_upper(),Vector2(x,560),Vector2(180,60),choose_hero.bind(id))
 label("A / D move  ·  Space jump  ·  F basic  ·  G special  ·  WASD aim",Vector2(145,640),Vector2(1030,32),20)
 page.get_child(page.get_child_count()-2).grab_focus()
func choose_hero(id:String):
 if id not in Run.HEROES:return
 clear_battle();run.choose(id);show_board(false)
func show_board(advance=false):
 screen="board";clear_battle()
 new_page("%s / THE GAUNTLET"%Roster.display_name(run.hero).to_upper(),"ROUTE COMPLETE" if run.complete() else "%d / %d CLEARED  ·  NEXT: %s"%[run.index,run.route.size(),Roster.display_name(run.opponent()).to_upper()])
 route_line=preload("res://scripts/story_route_line.gd").new();route_line.points=points;route_line.completed=run.index;page.add_child(route_line)
 for i in run.route.size():
  var id=run.route[i];var boss=id=="mephisto";var side=132 if boss else 88
  var badge=Panel.new();badge.position=points[i]-Vector2.ONE*side/2;badge.size=Vector2.ONE*side
  var style=StyleBoxFlat.new();style.bg_color=Color("281c2d") if boss else Color("162b38");style.border_color=Color("bd8569") if boss else (Color("b4efc6") if i<run.index else Color("7a929e"));style.set_border_width_all(3);style.set_corner_radius_all(18);badge.add_theme_stylebox_override("panel",style);page.add_child(badge)
  portrait(id,Vector2(6,6),Vector2.ONE*(side-12),false,badge)
  var name_label=label(Roster.display_name(id).replace(" (Prototype)","").to_upper(),points[i]+Vector2(-85,side/2+12),Vector2(170,35),18);name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
  if i<run.index:
   var stamp=label("CLEARED",points[i]+Vector2(-54,-14),Vector2(108,28),20,Color("b4efc6"));stamp.add_theme_color_override("font_shadow_color",Color.BLACK);stamp.add_theme_constant_override("shadow_outline_size",8)
  if boss:label("FINAL BOSS",points[i]+Vector2(-64,side/2+49),Vector2(155,25),18,Color("dda68c"))
 var target=token_position(run.index);var origin=token_position(maxi(0,run.index-1)) if advance else target
 token=Panel.new();token.name="HeroPortraitToken";token.position=origin;token.size=Vector2(52,66);page.add_child(token)
 portrait(run.hero,Vector2(2,2),Vector2(48,62),false,token)
 var text="VICTORY" if run.complete() else "NEXT MATCH"
 primary=button(text,Vector2(820,594),Vector2(400,62),show_victory if run.complete() else briefing)
 button("CHOOSE HERO",Vector2(55,600),Vector2(265,52),show_selection)
 label("B / ICE / M are text emblems where no approved portrait exists.",Vector2(360,661),Vector2(850,25),14,Color("8aa6b6"))
 if advance:
  primary.disabled=true;motion=create_tween();motion.tween_interval(.3);motion.tween_property(token,"position",target,.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT);motion.tween_callback(func():primary.disabled=false;primary.grab_focus())
 else:primary.grab_focus()
func token_position(index:int)->Vector2:
 return points[mini_index(index)]+Vector2(-26,-122 if mini_index(index)==6 else -104)
func mini_index(index:int)->int:return clampi(index,0,6)
func briefing():
 if run.complete():return
 screen="briefing"
 new_page("ENCOUNTER %02d / %02d"%[run.index+1,run.route.size()],"Opposing cards  /  Confirm when ready. No fight starts automatically.")
 portrait(run.hero,Vector2(80,155),Vector2(390,385))
 portrait(run.opponent(),Vector2(810,155),Vector2(390,385),true)
 label(Roster.display_name(run.hero).to_upper(),Vector2(80,535),Vector2(440,50),30)
 var opponent_label=label(Roster.display_name(run.opponent()).replace(" (Prototype)","").to_upper(),Vector2(760,535),Vector2(450,50),30);opponent_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
 var vs=TextureRect.new();vs.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;vs.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;vs.texture=load("res://assets/story_art/vs/ui/vs_mark.png");vs.position=Vector2(525,290);vs.size=Vector2(230,155);vs.mouse_filter=Control.MOUSE_FILTER_IGNORE;page.add_child(vs)
 var detail="400 HP · stationary two-hit claws · punish recovery" if run.opponent()=="bobo" else "Three stocks each · %s bot"%difficulty()
 if run.opponent()=="mephisto":detail="FINAL BOSS · Preserved girl / demon forms · shared stocks"
 label(detail,Vector2(230,585),Vector2(1000,35),18,Color("b2c5cd"))
 button("BACK TO BOARD",Vector2(55,624),Vector2(330,52),show_board.bind(false))
 primary=button("FIGHT",Vector2(825,624),Vector2(395,52),fight);primary.grab_focus()
func difficulty()->String:return "easy" if run.index<3 else "normal"
func fight():
 if screen!="briefing" or run.complete():return
 var slots=Config.default_slots();slots[0].character=run.hero;slots[0].kind="human";slots[0].device=-1
 slots[1].character=run.opponent();slots[1].kind="bot";slots[1].difficulty=difficulty();slots[1].device=-1
 slots[2].kind="empty";slots[3].kind="empty"
 if not start_match(slots,false,run.opponent()=="bobo"):return
 ui.hide();screen="battle";story_state="playing"
 hud_title.text="STORY %02d / %s VS %s"%[run.index+1,player_one.fighter_name,player_two.fighter_name]
 hud_controls.text="A/D move · Space jump · F basic · G special · WASD aim\nEsc: pause · Three fresh stocks each attempt"
 player_one.reset_fighter(p1_spawn,true);player_two.reset_fighter(Vector3(.6,1,0) if run.opponent()=="bobo" else p2_spawn,true)
 player_one.facing=1;player_two.facing=-1;_begin_ready()
func _on_fighter_eliminated(loser:CharacterBody3D):
 if story_state!="playing":
  super._on_fighter_eliminated(loser);return
 if match_over:return
 if player_one.stocks>0 and player_two.stocks>0:return
 match_over=true
 var won=player_one.stocks>0 and player_two.stocks<=0
 run.finish(won)
 if won:show_board(true)
 else:
  clear_battle();screen="lost"
  new_page("TRY AGAIN","Your route is safe. Retry this encounter with fresh stocks.")
  portrait(run.hero,Vector2(140,185),Vector2(340,340))
  label("%s / ENCOUNTER %02d"%[Roster.display_name(run.opponent()).to_upper(),run.index+1],Vector2(570,255),Vector2(680,80),28)
  primary=button("RETRY CURRENT MATCH",Vector2(590,400),Vector2(570,70),retry);primary.grab_focus()
  button("BOARD",Vector2(590,500),Vector2(570,52),show_board.bind(false))
func retry():
 if screen=="lost":briefing()
func show_victory():
 if not run.complete():return
 screen="victory";new_page("YOU DID IT!","GAUNTLET COMPLETE  /  Every opponent defeated.")
 portrait(run.hero,Vector2(120,180),Vector2(400,370))
 label("%s\nROUTE COMPLETE"%Roster.display_name(run.hero).to_upper(),Vector2(650,240),Vector2(550,150),36,Color("b4efc6"))
 primary=button("CREDITS",Vector2(690,495),Vector2(480,65),show_credits);primary.grab_focus()
func show_credits():
 if not run.complete():return
 screen="credits";new_page("NRCU / CREDITS","Thanks for playing.")
 for i in CREDITS.size():label(CREDITS[i],Vector2(430,205+i*72),Vector2(500,60),36)
 primary=button("PLAY AGAIN",Vector2(430,565),Vector2(420,60),show_selection);primary.grab_focus()
func show_setup():
 if not is_instance_valid(ui):return
 if run.route.is_empty():show_selection()
 else:show_board(false)
func open_story():show_selection()
func back_to_menu():show_selection()
func _reset_match():
 if screen=="lost":retry()
 elif screen=="board":
  if run.complete():show_victory()
  else:briefing()
func _unhandled_key_input(event:InputEvent):
 if not event is InputEventKey or not event.pressed or event.echo:return
 if event.keycode==KEY_ESCAPE:
  if screen=="select":return
  if screen=="battle" or screen=="briefing" or screen=="lost":show_board(false)
  else:show_selection()
  get_viewport().set_input_as_handled()
 elif event.keycode==KEY_R:
  _reset_match();get_viewport().set_input_as_handled()
