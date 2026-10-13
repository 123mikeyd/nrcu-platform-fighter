extends "res://scripts/match_setup_legacy.gd"
const ORDER=["teknium","doge_man","turbofit","ggb","bobo","witcheer","mephisto"]
const CREAM=Color("f5ebd2")
const GOLD=Color("dab373")
const PC=Config.PLAYER_COLORS
var canvas:Control
var roster:HBoxContainer
var tiles={}
var cards=[]
var portraits={}
var active_slot=0
var hover_index=0
var glove:TextureRect
var using_pointer=true
var settings:Panel
var pad_wait=0.0
var ready_ui=false
var confirmations=0
var confirm_tween:Tween
var costume_memory: Array = [{}, {}, {}, {}]
var costume_characters: Array = ["", "", "", ""]
var costume_previews := {}
func tex(path:String)->Texture2D:return load(path) as Texture2D
func style(color:Color,border:Color,width:int=1)->StyleBoxFlat:
 var s=StyleBoxFlat.new();s.bg_color=color;s.border_color=border;s.set_border_width_all(width);s.set_corner_radius_all(5);return s
func text(parent:Node,value:String,rect:Rect2,font:int=18,color:Color=CREAM)->Label:
 var l=Label.new();l.text=value;l.position=rect.position;l.size=rect.size;l.add_theme_color_override("font_color",color);l.add_theme_font_size_override("font_size",font);l.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(l);return l
func button(parent:Node,value:String,rect:Rect2)->Button:
 var b=Button.new();b.text=value;b.position=rect.position;b.size=rect.size;b.add_theme_font_size_override("font_size",17)
 b.add_theme_stylebox_override("normal",style(Color("203d40"),Color("56706a")));b.add_theme_stylebox_override("hover",style(Color("365453"),GOLD,2));b.add_theme_stylebox_override("focus",style(Color.TRANSPARENT,GOLD,2));parent.add_child(b);return b
func picture(parent:Node,texture:Texture2D,rect:Rect2)->TextureRect:
 var t=TextureRect.new();t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;t.texture=texture;t.position=rect.position;t.size=rect.size;t.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(t);return t
func option(parent:Node,values:Array,rect:Rect2)->OptionButton:
 var o=OptionButton.new();parent.add_child(o)
 for v in values:o.add_item(v)
 o.position=rect.position;o.size=rect.size;o.add_theme_font_size_override("font_size",14);return o
func _ready():
 theme=Style.make();set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var bg=TextureRect.new();bg.texture=load("res://assets/menu/weaver_menu.webp");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);bg.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;bg.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(bg)
 var tint=ColorRect.new();tint.color=Color(.025,.065,.07,.91);tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);tint.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(tint)
 canvas=Control.new();canvas.name="SelectCanvas";canvas.size=Vector2(1280,720);add_child(canvas)
 text(canvas,"NOUS RESEARCH  /  HERMES AGENT",Rect2(44,19,820,25),15,GOLD)
 text(canvas,"CHOOSE YOUR FIGHTER",Rect2(40,44,1050,52),38)
 var back=button(canvas,"BACK",Rect2(1100,32,136,42));back.name="BackToMenu";back.pressed.connect(func():back_requested.emit())
 text(canvas,"ROSTER",Rect2(44,105,200,20),14,GOLD);text(canvas,"POINT. PICK. PLAY.",Rect2(972,105,270,20),14,Color("8eaaa4"))
 roster=HBoxContainer.new();roster.name="RosterGrid";roster.position=Vector2(44,131);roster.size=Vector2(1192,130);roster.add_theme_constant_override("separation",12);canvas.add_child(roster)
 for i in ORDER.size():
  var id=ORDER[i];portraits[id]=tex("res://assets/character_select/"+id+"_full.png")
  var b=Button.new();b.name="Portrait_"+id;b.custom_minimum_size=Vector2(160,128);roster.add_child(b)
  picture(b,tex("res://assets/costume_previews/bobo_01_icon.png" if id=="bobo" else "res://assets/character_select/"+id+"_icon.png"),Rect2(7,5,146,96)).name="Portrait"
  var title=text(b,display_name(id),Rect2(2,99,156,22),16);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.name="Name"
  text(b,"",Rect2(5,4,150,22),14).name="Markers"
  tiles[id]=b;b.pressed.connect(select_fighter.bind(id));b.mouse_entered.connect(focus_portrait.bind(i,false));b.focus_entered.connect(focus_portrait.bind(i,true))
 text(canvas,"YOUR LINEUP",Rect2(44,274,200,20),14,GOLD);text(canvas,"CLICK A PLAYER HEADER TO CHANGE THEIR PICK",Rect2(670,274,560,20),13,Color("8eaaa4"))
 for i in 4:
  var box=Panel.new();box.name="PlayerPanel%d"%(i+1);box.position=Vector2(44+i*302,303);box.size=Vector2(286,294);canvas.add_child(box)
  var tab=button(box,"P%d"%(i+1),Rect2(8,6,270,31));tab.name="PlayerTab";tab.pressed.connect(activate_slot.bind(i));tab.add_theme_color_override("font_color",PC[i])
  var full=picture(box,null,Rect2(12,40,262,160));full.name="FullBodyIdle"
  var title=text(box,"",Rect2(12,202,262,24),19);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
  var character=OptionButton.new();character.visible=false;box.add_child(character)
  for c in Config.CHARACTERS.size():character.add_item(Config.NAMES[c]);character.set_item_metadata(c,Config.CHARACTERS[c])
  _select_default_character(character,i)
  var costume=OptionButton.new();costume.name="Costume";costume.position=Vector2(40,229);costume.size=Vector2(206,25);costume.add_theme_font_size_override("font_size",13);costume.clip_text=true;costume.fit_to_longest_item=false;box.add_child(costume)
  var previous=button(box,"‹",Rect2(8,229,28,25));previous.name="CostumePrevious";previous.pressed.connect(cycle_costume.bind(i,-1));previous.tooltip_text="Previous costume (C / Pad X)"
  var next=button(box,"›",Rect2(250,229,28,25));next.name="CostumeNext";next.pressed.connect(cycle_costume.bind(i,1));next.tooltip_text="Next costume (V / Pad Y)"
  costume.item_selected.connect(func(_x):_refresh())
  var kind=option(box,["Human","Bot","Empty"],Rect2(8,257,88,29));kind.select(0 if i==0 else 1)
  var difficulty=option(box,["Easy","Normal","Hard"],Rect2(102,257,84,29));difficulty.select(1)
  var team=option(box,["Team A","Team B"],Rect2(191,257,87,29));team.select(i%2)
  var device=OptionButton.new();device.add_item("Keyboard %d"%(i+1) if i<2 else "Gamepad required");device.set_item_metadata(0,-1)
  for pad in Input.get_connected_joypads():device.add_item("Pad %d: %s"%[pad+1,Input.get_joy_name(pad)]);device.set_item_metadata(device.item_count-1,pad)
  if i>=2 and device.item_count>1:device.select(mini(i-1,device.item_count-1))
  rows.append({"kind":kind,"character":character,"costume":costume,"difficulty":difficulty,"team":team,"device":device});cards.append({"box":box,"tab":tab,"full":full,"name":title})
  kind.item_selected.connect(func(_x):_refresh());character.item_selected.connect(func(_x):_refresh())
 mode=option(canvas,["Free-for-all","Teams"],Rect2(44,624,202,43))
 level=option(canvas,["Fortress","Toy Room","Hermes Weaver","Music Hall","Flower Meadow"],Rect2(260,624,228,43));level.name="LevelSelect"
 mode.item_selected.connect(func(_x):_refresh())
 var devices=button(canvas,"CONTROLLERS",Rect2(502,624,190,43));devices.pressed.connect(func():settings.visible=true;glove.visible=false)
 var help_button=button(canvas,"HOW TO PLAY",Rect2(706,624,190,43));help_button.name="SetupHelp";help_button.pressed.connect(func():help_page=Style.help(self,func():help_button.grab_focus()))
 var start=button(canvas,"READY TO BATTLE",Rect2(910,615,326,54));start.name="StartMatchButton";start.add_theme_stylebox_override("normal",style(GOLD,CREAM,2));start.add_theme_color_override("font_color",Color("112b30"));start.add_theme_font_size_override("font_size",23);start.pressed.connect(_start)
 error_label=text(canvas,"",Rect2(44,682,1192,24),14,Color("f4997c"))
 text(canvas,"ARROWS / STICK: MOVE   ENTER / A: PICK   Q/E · LB/RB: PLAYER   C/V · X/Y: COSTUME",Rect2(44,600,1192,20),13,Color("a5bcb3"))
 settings=Panel.new();settings.name="ControllerSettings";settings.position=Vector2(216,172);settings.size=Vector2(848,360);settings.add_theme_stylebox_override("panel",style(Color("112b30"),GOLD,2));settings.z_index=90;canvas.add_child(settings);settings.visible=false
 text(settings,"CONTROLLERS",Rect2(26,16,700,40),26)
 for i in 4:
  text(settings,"P%d"%(i+1),Rect2(28,74+i*57,60,36),22,PC[i]);settings.add_child(rows[i].device);rows[i].device.position=Vector2(105,74+i*57);rows[i].device.size=Vector2(705,38)
 button(settings,"DONE",Rect2(670,306,140,36)).pressed.connect(func():settings.hide())
 var story=Button.new();story.name="StoryModeButton";story.visible=false;canvas.add_child(story);story.pressed.connect(func():story_requested.emit())
 var bag=Button.new();bag.name="HeavyBagButton";bag.visible=false;canvas.add_child(bag);bag.pressed.connect(func():heavy_bag_requested.emit())
 glove=picture(canvas,tex("res://assets/character_select/glove_curled.svg"),Rect2(0,0,96,102));glove.name="SelectionGlove";glove.z_index=100
 ready_ui=true;resized.connect(fit_canvas);visibility_changed.connect(update_cursor);fit_canvas();_refresh();update_cursor()
func display_name(id:String)->String:return "Bobo" if id=="bobo" else Config.NAMES[Config.CHARACTERS.find(id)]
func fit_canvas():
 if not is_instance_valid(canvas):return
 var s=minf(size.x/1280,size.y/720);canvas.scale=Vector2.ONE*s;canvas.position=(size-Vector2(1280,720)*s)*.5
func update_cursor():
 if ready_ui:Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if is_visible_in_tree() else Input.MOUSE_MODE_VISIBLE)
func _exit_tree():Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
func activate_slot(i:int):
 if settings.visible or is_instance_valid(help_page):return
 active_slot=clampi(i,0,3);_refresh()
func focus_portrait(i:int,keyboard:bool):
 hover_index=i
 if keyboard:using_pointer=false
 refresh_tiles()
func select_fighter(id:String):
 if settings.visible or is_instance_valid(help_page):return
 if Unlocks.is_locked(id):error_label.text="Win this fighter's challenger battle to unlock them.";return
 if rows[active_slot].kind.selected==2:rows[active_slot].kind.select(1 if active_slot>0 else 0)
 rows[active_slot].character.select(Config.CHARACTERS.find(id));confirmations+=1;error_label.text="";_refresh()
 if confirm_tween:confirm_tween.kill()
 for card in cards:card.full.modulate.a=1.0
 cards[active_slot].full.modulate.a=.5
 confirm_tween=create_tween();confirm_tween.tween_property(cards[active_slot].full,"modulate:a",1.0,.16)
func _refresh():
 if not ready_ui:return
 super._refresh()
 for i in rows.size():
  var id=rows[i].character.get_selected_metadata();var empty=rows[i].kind.selected==2
  var previous=rows[i].costume.get_selected_metadata() if rows[i].costume.item_count>0 else null
  if costume_characters[i]==id and previous!=null:costume_memory[i][id]=previous
  previous=costume_memory[i].get(id,Config.default_costume(id))
  costume_characters[i]=id
  rows[i].costume.clear()
  var selected_costume_index:=0
  for costume_id in Config.costume_ids(id):
   rows[i].costume.add_item(Config.costume_name(id,costume_id));rows[i].costume.set_item_metadata(rows[i].costume.item_count-1,costume_id)
   if costume_id==previous:selected_costume_index=rows[i].costume.item_count-1
  rows[i].costume.select(selected_costume_index)
  var has_costumes=Config.costume_ids(id).size()>1
  rows[i].costume.visible=not empty;rows[i].costume.disabled=not has_costumes
  for n in ["CostumePrevious","CostumeNext"]:
   cards[i].box.get_node(n).visible=not empty;cards[i].box.get_node(n).disabled=not has_costumes
  var path=Config.costume_portrait(id,rows[i].costume.get_selected_metadata())
  if not costume_previews.has(path) and ResourceLoader.exists(path):costume_previews[path]=tex(path)
  cards[i].full.texture=costume_previews.get(path,portraits.get(id));cards[i].full.visible=not empty;cards[i].name.text="JOIN THE LINEUP" if empty else display_name(id)
  cards[i].tab.text="P%d  /  %s"%[i+1,["HUMAN","CPU","OPEN SLOT"][rows[i].kind.selected]]
  cards[i].box.add_theme_stylebox_override("panel",style(Color("203a3e") if active_slot==i else Color("122c31"),PC[i] if active_slot==i else Color("476160"),3 if active_slot==i else 1))
  rows[i].team.visible=mode.selected==1;rows[i].difficulty.visible=rows[i].kind.selected==1
 refresh_tiles()
func cycle_costume(slot:int,step:int):
 if not ready_ui or not is_visible_in_tree() or settings.visible or is_instance_valid(help_page):return
 if rows[slot].kind.selected==2:return
 var choice:OptionButton=rows[slot].costume
 if choice.item_count<2:return
 choice.select(posmod(choice.selected+step,choice.item_count));_refresh()
func refresh_tiles():
 if not ready_ui:return
 for i in ORDER.size():
  var id=ORDER[i];var b=tiles[id];var locked=Unlocks.is_locked(id)
  b.get_node("Portrait").modulate=Color(.06,.12,.13,1) if locked else Color.WHITE;b.get_node("Name").text="???" if locked else display_name(id)
  var marks=""
  for j in rows.size():
   if rows[j].kind.selected!=2 and rows[j].character.get_selected_metadata()==id:marks+="P%d "%(j+1)
  b.get_node("Markers").text=marks;b.get_node("Markers").add_theme_color_override("font_color",GOLD)
  b.add_theme_stylebox_override("normal",style(Color("2e4847") if hover_index==i else Color("1a3438"),PC[active_slot] if hover_index==i else Color("58706a"),3 if hover_index==i else 1))
func _process(delta):
 if not ready_ui or not is_visible_in_tree():return
 pad_wait=maxf(0,pad_wait-delta);glove.visible=not settings.visible and not is_instance_valid(help_page)
 Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if glove.visible else Input.MOUSE_MODE_VISIBLE)
 if using_pointer:glove.position=canvas.get_local_mouse_position()-Vector2(29.4,3)
 else:glove.position=roster.position+Vector2(hover_index*172+80,52)
 if pad_wait<=0 and not settings.visible and not is_instance_valid(help_page):
  for pad in Input.get_connected_joypads():
   var axis=Input.get_joy_axis(pad,JOY_AXIS_LEFT_X)
   if absf(axis)>.6:step_focus(1 if axis>0 else -1);pad_wait=.22;break
func step_focus(step:int):using_pointer=false;hover_index=posmod(hover_index+step,ORDER.size());tiles[ORDER[hover_index]].grab_focus();refresh_tiles()
func _input(event):
 if not ready_ui or not is_visible_in_tree():return
 if event is InputEventMouseMotion:using_pointer=true
 if settings.visible:
  if event is InputEventMouseButton and not settings.get_global_rect().has_point(event.position):get_viewport().set_input_as_handled();return
  if event.is_action_pressed("ui_cancel"):settings.hide();get_viewport().set_input_as_handled()
  return
 if is_instance_valid(help_page):return
 if event is InputEventKey and event.pressed and not event.echo:
  var focus=get_viewport().gui_get_focus_owner()
  if event.keycode in [KEY_Q,KEY_E] or focus==null or focus in tiles.values():
   _unhandled_key_input(event)
 if event is InputEventJoypadButton and event.pressed:
  match event.button_index:
   JOY_BUTTON_DPAD_LEFT:step_focus(-1)
   JOY_BUTTON_DPAD_RIGHT:step_focus(1)
   JOY_BUTTON_A:select_fighter(ORDER[hover_index])
   JOY_BUTTON_START:_start()
   JOY_BUTTON_LEFT_SHOULDER:activate_slot(posmod(active_slot-1,4))
   JOY_BUTTON_RIGHT_SHOULDER:activate_slot(posmod(active_slot+1,4))
   _:return
  get_viewport().set_input_as_handled()
func _start():
 if settings.visible or is_instance_valid(help_page):return
 super._start()
func _unhandled_key_input(event):
 if not ready_ui or not is_visible_in_tree() or settings.visible or is_instance_valid(help_page):return
 if not event is InputEventKey or not event.pressed or event.echo:return
 match event.keycode:
  KEY_Q:activate_slot(posmod(active_slot-1,4))
  KEY_E:activate_slot(posmod(active_slot+1,4))
  KEY_LEFT:step_focus(-1)
  KEY_RIGHT:step_focus(1)
  KEY_ENTER,KEY_SPACE:select_fighter(ORDER[hover_index])
  _:return
 get_viewport().set_input_as_handled()
