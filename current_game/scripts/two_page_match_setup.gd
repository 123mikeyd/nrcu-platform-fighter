extends "res://scripts/portrait_match_setup.gd"
var stage_page:Control
var stage_cards=[]
var stage_caption:Label
var saved_visible=[]
func _ready():
 super._ready()
 for child in canvas.get_children():
  if child is Label and child.text.begins_with("CLICK A PLAYER"):child.hide()
  if child is Button and child.text in ["CONTROLLERS","HOW TO PLAY"]:child.hide()
 level.hide();level.select(2)
 mode.position=Vector2(1020,270);mode.size=Vector2(216,27)
 mode.add_theme_font_size_override("font_size",14)
 mode.add_theme_stylebox_override("normal",style(Color("203638"),Color("3d5353")))
 mode.add_theme_color_override("font_color",Color("a5b6ad"))
 var back=find_child("BackToMenu",true,false);back.position=Vector2(44,641);back.size=Vector2(125,37);red(back)
 var go=find_child("StartMatchButton",true,false);go.text="GO FIGHT";go.position=Vector2(912,625);go.size=Vector2(324, sixty());go.add_theme_font_size_override("font_size",28)
 for i in rows.size():
  var d=rows[i].device;d.reparent(cards[i].box);d.position=Vector2(102,257);d.size=Vector2(176,29);d.add_theme_font_size_override("font_size",12);d.visible=rows[i].kind.selected==0
  for field in ["kind","costume","difficulty","team","device"]:
   rows[i][field].clip_text=true
   rows[i][field].fit_to_longest_item=false
  rows[i].kind.item_selected.connect(func(_x):d.visible=rows[i].kind.selected==0)
 stage_page=Control.new();stage_page.name="StageSelectPage";stage_page.size=Vector2(1280,720);canvas.add_child(stage_page);stage_page.hide()
 text(stage_page,"NOUS RESEARCH  /  HERMES AGENT",Rect2(44,19,820,25),15,GOLD)
 text(stage_page,"CHOOSE YOUR STAGE",Rect2(40,54,1100,55),38)
 text(stage_page,"YOUR LINEUP IS READY",Rect2(44,123,800,26),15,Color("9bafa8"))
 var ids=["debug","toy_room","weaver","hall","meadow"];var names=["FORTRESS","TOY ROOM","HERMES WEAVER","MUSIC HALL","FLOWER MEADOW"]
 for i in ids.size():
  var card=button(stage_page,"",Rect2(44+i*240,205,232,277));card.name="Stage_"+ids[i]
  picture(card,tex("res://assets/menu/stage_"+ids[i]+".png"),Rect2(10,10,212,205))
  var caption=text(card,names[i],Rect2(10,227,212,32),18);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
  stage_cards.append(card);card.pressed.connect(choose_stage.bind(i))
 stage_caption=text(stage_page,"",Rect2(44,513,1192,44),22,GOLD);stage_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 var back_stage=button(stage_page,"BACK",Rect2(44,641,125,37));back_stage.name="StageBack";red(back_stage);back_stage.pressed.connect(return_to_fighters)
 var fight=button(stage_page,"GO FIGHT",Rect2(912,625,324,60));fight.name="StageGo";fight.add_theme_stylebox_override("normal",style(GOLD,CREAM,2));fight.add_theme_color_override("font_color",Color("112b30"));fight.add_theme_font_size_override("font_size",28);fight.pressed.connect(launch_match)
 choose_stage(2)
 _refresh()
func sixty():return 60
func red(b):
 b.add_theme_stylebox_override("normal",style(Color("6a3437"),Color("a45d59")));b.add_theme_stylebox_override("hover",style(Color("874046"),Color("ca8074")));b.add_theme_color_override("font_color",Color("f5d7cc"));b.add_theme_font_size_override("font_size",16)
func choose_stage(i):
 level.select(i)
 for j in stage_cards.size():
  stage_cards[j].add_theme_stylebox_override("normal",style(Color("304742") if i==j else Color("172f33"),GOLD if i==j else Color("476160"),3 if i==j else 1))
 stage_caption.text="SELECTED  /  "+["FORTRESS","TOY ROOM","HERMES WEAVER","MUSIC HALL","FLOWER MEADOW"][i]
func _lineup_error()->String:
 var slots=[]
 for row in rows:slots.append({"kind":["human","bot","empty"][row.kind.selected],"character":row.character.get_selected_metadata(),"costume":row.costume.get_selected_metadata(),"difficulty":Config.DIFFICULTIES[row.difficulty.selected],"team":row.team.selected,"device":row.device.get_item_metadata(row.device.selected)})
 var error=Config.validate(slots,mode.selected==1)
 for slot in slots:
  if error.is_empty() and slot.kind!="empty" and (not slot.character is String or Unlocks.is_locked(slot.character)):error="That fighter is still locked."
 return error
func _start():
 if stage_page==null or stage_page.visible or not is_visible_in_tree():return
 if settings.visible or is_instance_valid(help_page):return
 error_label.text=_lineup_error()
 if not error_label.text.is_empty():return
 saved_visible.clear()
 for child in canvas.get_children():
  if child is Control and child.visible and child!=glove and child!=stage_page:saved_visible.append(child);child.hide()
 stage_page.show()
 stage_cards[level.selected].grab_focus()
func return_to_fighters():
 if stage_page==null or not stage_page.visible:return
 stage_page.hide()
 for child in saved_visible:child.show()
 saved_visible.clear()
 _refresh()
 find_child("StartMatchButton",true,false).grab_focus()
func launch_match():
 if not is_visible_in_tree() or not stage_page.visible:return
 error_label.text=_lineup_error()
 if not error_label.text.is_empty():return_to_fighters();return
 super._start()
func _refresh():
 super._refresh()
 if not ready_ui:return
 for row in rows:
  row.device.visible=row.kind.selected==0
  row.device.size.x=84 if mode.selected==1 else 176
func _popup_open()->bool:
 for row in rows:
  for key in ["kind","costume","difficulty","team","device"]:
   if row[key].get_popup().visible:return true
 return mode.get_popup().visible
func _stage_step(step:int):
 using_pointer=false
 choose_stage(posmod(level.selected+step,stage_cards.size()))
 stage_cards[level.selected].grab_focus()
func _navigate(direction:int):
 using_pointer=false
 var focus=get_viewport().gui_get_focus_owner()
 if stage_page.visible:
  if direction in [SIDE_LEFT,SIDE_RIGHT]:_stage_step(-1 if direction==SIDE_LEFT else 1)
  elif direction==SIDE_BOTTOM:stage_page.get_node("StageGo").grab_focus()
  else:stage_cards[level.selected].grab_focus()
 elif (focus==null or focus in tiles.values()) and direction in [SIDE_LEFT,SIDE_RIGHT]:
  step_focus(-1 if direction==SIDE_LEFT else 1)
 elif is_instance_valid(focus):
  var next=focus.find_valid_focus_neighbor(direction)
  if next:next.grab_focus()
func _input(event):
 if not ready_ui or not is_visible_in_tree():return
 if settings.visible or is_instance_valid(help_page):
  super._input(event);return
 if event is InputEventMouseMotion:using_pointer=true
 if event is InputEventJoypadButton and event.button_index==JOY_BUTTON_A:
  # Route positional A through the same focused GUI path as Enter, including
  # OptionButton popups. Never confirm a hidden portrait behind another page.
  var accept=InputEventKey.new();accept.keycode=KEY_ENTER;accept.pressed=event.pressed
  var viewport=get_viewport()
  viewport.set_input_as_handled()
  viewport.push_input(accept) # Activation may remove this setup from the tree.
  return
 if _popup_open():return
 if not stage_page.visible:
  if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_C,KEY_V]:
   cycle_costume(active_slot,-1 if event.keycode==KEY_C else 1);get_viewport().set_input_as_handled();return
  if event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_X,JOY_BUTTON_Y]:
   cycle_costume(active_slot,-1 if event.button_index==JOY_BUTTON_X else 1);get_viewport().set_input_as_handled();return
 if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_B):
  get_viewport().set_input_as_handled()
  if stage_page.visible:return_to_fighters()
  else:back_requested.emit()
  return
 if event is InputEventJoypadMotion:
  if event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y] and absf(event.axis_value)>.6 and pad_wait<=0:
   _navigate((SIDE_RIGHT if event.axis_value>0 else SIDE_LEFT) if event.axis==JOY_AXIS_LEFT_X else (SIDE_BOTTOM if event.axis_value>0 else SIDE_TOP));pad_wait=.22
  get_viewport().set_input_as_handled();return
 if event is InputEventJoypadButton and event.pressed:
  using_pointer=false
  match event.button_index:
   JOY_BUTTON_DPAD_LEFT:_navigate(SIDE_LEFT)
   JOY_BUTTON_DPAD_RIGHT:_navigate(SIDE_RIGHT)
   JOY_BUTTON_DPAD_UP:_navigate(SIDE_TOP)
   JOY_BUTTON_DPAD_DOWN:_navigate(SIDE_BOTTOM)
   JOY_BUTTON_START:
    if stage_page.visible:launch_match()
    else:_start()
   JOY_BUTTON_LEFT_SHOULDER:
    if not stage_page.visible:activate_slot(posmod(active_slot-1,4))
   JOY_BUTTON_RIGHT_SHOULDER:
    if not stage_page.visible:activate_slot(posmod(active_slot+1,4))
   _ :return # A activates the focused visible control through Godot GUI.
  get_viewport().set_input_as_handled();return
 if stage_page.visible:
  if event is InputEventKey and event.pressed and not event.echo:
   match event.keycode:
    KEY_LEFT:_navigate(SIDE_LEFT)
    KEY_RIGHT:_navigate(SIDE_RIGHT)
    KEY_DOWN:_navigate(SIDE_BOTTOM)
    KEY_UP:_navigate(SIDE_TOP)
    _:return
   get_viewport().set_input_as_handled()
  return
 super._input(event)
func cycle_costume(slot:int,step:int):
 if stage_page!=null and stage_page.visible:return
 super.cycle_costume(slot,step)
func _process(delta):
 if not ready_ui or not is_visible_in_tree():return
 pad_wait=maxf(0,pad_wait-delta)
 glove.visible=not _popup_open()
 Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if glove.visible else Input.MOUSE_MODE_VISIBLE)
 if using_pointer:glove.position=canvas.get_local_mouse_position()-Vector2(29.4,3)
 else:
  var focus=get_viewport().gui_get_focus_owner()
  if is_instance_valid(focus) and focus.is_visible_in_tree():
   glove.position=canvas.get_global_transform().affine_inverse()*focus.get_global_rect().get_center()-Vector2(29.4,3)
func _unhandled_key_input(event):
 if stage_page!=null and stage_page.visible:return
 super._unhandled_key_input(event)
