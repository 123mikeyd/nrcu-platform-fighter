extends Control
const Style = preload("res://scripts/demo_style.gd")
const Motion = preload("res://scripts/weaver_menu_motion.gd")
const MATCH_SCENE := "res://scenes/main.tscn"
@export var background_texture: Texture2D
var buttons: Dictionary = {}
var page: Control
var state := "home"
var motion: Control
var veil: ColorRect
var status: Label
var entry := "freeplay"
var pending := false
var elapsed := 0.0
var requested := false
var progress: Array = []
var entering := false
var transition_started := 0
func _ready():
 get_window().title="The Legends of Nous Research: Hermes, Breaking Containment"
 if not OS.has_feature("web"): get_window().min_size=Vector2i(800,450)
 theme=Style.make()
 var background=TextureRect.new()
 background.name="WeaverBackground";background.texture=background_texture
 background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
 background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
 background.mouse_filter=Control.MOUSE_FILTER_IGNORE
 background.modulate=Color(.82,.87,.94)
 add_child(background)
 var gradient=Gradient.new()
 gradient.colors=PackedColorArray([Color(.015,.025,.045,.98),Color(.015,.025,.045,.90),Color(.01,.02,.04,.05)])
 gradient.offsets=PackedFloat32Array([0,.30,.72])
 var tex=GradientTexture2D.new();tex.gradient=gradient;tex.width=256;tex.height=1;tex.fill_from=Vector2.ZERO;tex.fill_to=Vector2.RIGHT
 var shade=TextureRect.new();shade.texture=tex;shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(shade)
 motion=Motion.new();add_child(motion)
 get_tree().auto_accept_quit=false
 get_window().close_requested.connect(func(): show_page("quit"))
 show_page("home")
 resized.connect(fit_page)
 get_node("/root/FrontendCache").start()
func label(text: String,pos: Vector2,font_size: int,color: Color) -> Label:
 var l=Label.new();l.text=text;l.position=pos;l.add_theme_font_size_override("font_size",font_size);l.add_theme_color_override("font_color",color);page.add_child(l);return l
func show_page(next: String):
 pending=false;entering=false;motion.loading=false
 state=next;buttons.clear()
 if is_instance_valid(page):remove_child(page);page.queue_free()
 page=Control.new();page.name="HomeCanvas";page.size=Vector2(1280,720);add_child(page);fit_page()
 if next=="help":
  var help=Style.help(page,func():show_page("home"));buttons["home"]=help.find_child("HelpBack",true,false);buttons.home.grab_focus();return
 label("NOUS RESEARCH  /  HERMES AGENT",Vector2(60,45),15,Color("c5bc9f"))
 var badge=TextureRect.new();badge.name="NousFightBadge";badge.texture=load("res://assets/select_identity/badge.svg");badge.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;badge.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;badge.position=Vector2(56,90);badge.size=Vector2(136,136);badge.mouse_filter=Control.MOUSE_FILTER_IGNORE;page.add_child(badge)
 var game_title=label("The Legends of Nous Research: Hermes, Breaking Containment",Vector2(205,96),36,Color("fff0cf"))
 game_title.name="GameTitle";game_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;game_title.set_deferred("size",Vector2(1000,126))
 label("N R C U   /   T H E   S H A R E D   U N I V E R S E",Vector2(64,238),16,Color("dcb775"))
 if next=="home":
  add_button("LOCAL MATCH","play",294,func():enter_game("freeplay"))
  buttons.play.size=Vector2(482,86);buttons.play.add_theme_font_size_override("font_size",33)
  buttons.play.add_theme_stylebox_override("normal",Style.box(Color("d7ae68"),Color("fff0cf"),2));buttons.play.add_theme_color_override("font_color",Color("142f33"))
  add_button("Story Mode","story",398,func():enter_game("story"));buttons.story.size=Vector2(234,60)
  add_button("Heavy Bag","bag",398,func():enter_game("heavy_bag"));buttons.bag.position.x=310;buttons.bag.size=Vector2(232,60)
  add_button("Controls / Moves","help",476,func():show_page("help"));buttons.help.size=Vector2(482,54)
  label("YOUR CREW. YOUR COLORS. YOUR FIGHT.",Vector2(64,549),14,Color("b7c8bc"))
  add_button("QUIT","quit",640,func():show_page("quit"));buttons.quit.size=Vector2(138,40);buttons.quit.add_theme_font_size_override("font_size",17)
  buttons.quit.add_theme_stylebox_override("normal",Style.box(Color("5c3034"),Color("a65c5b"),1));buttons.quit.add_theme_color_override("font_color",Color("f5d7cc"))
  label("HERMES WEAVER  /  NRCU",Vector2(968,668),13,Color("c1a36f"))
 else:
  label("Leave the game?",Vector2(64,295),26,Color("fff0cf"))
  add_button("Stay here","home",370,func():show_page("home"))
  add_button("Quit","exit",446,func():get_tree().quit())
 var values=buttons.values()
 for i in values.size():
  values[i].focus_neighbor_bottom=values[(i+1)%values.size()].get_path()
  values[i].focus_neighbor_top=values[(i-1+values.size())%values.size()].get_path()
 values[0].grab_focus()
func fit_page():
 if not is_instance_valid(page):return
 var factor=minf(size.x/1280.0,size.y/720.0)
 page.scale=Vector2.ONE*factor;page.position=(size-Vector2(1280,720)*factor)*.5
func add_button(text: String,id: String,y: float,action: Callable):
 var b=Button.new();b.name=id;b.text="  "+text;b.alignment=HORIZONTAL_ALIGNMENT_LEFT;b.position=Vector2(60,y);b.size=Vector2(350,54)
 b.add_theme_font_size_override("font_size",23)
 for pair in [["normal",Color(.045,.065,.085,.84),Color(.32,.34,.32,.45)],["hover",Color(.13,.17,.19,.94),Color("d0ad70")],["focus",Color(.13,.17,.19,.94),Color("d0ad70")],["pressed",Color(.25,.21,.14,.98),Color("f4d197")]]:
  var box=Style.box(pair[1],pair[2],1);box.set_corner_radius_all(2);box.border_width_left=3;b.add_theme_stylebox_override(pair[0],box)
 page.add_child(b);b.pressed.connect(action);buttons[id]=b
func enter_game(mode: String):
 if pending:return
 entry=mode;pending=true;state="loading";elapsed=0;transition_started=Time.get_ticks_msec();motion.loading=true
 for b in buttons.values():b.disabled=true
 veil=ColorRect.new();veil.color=Color(.008,.018,.035,0);veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);page.add_child(veil)
 status=label("WEAVING THE ARENA",Vector2(64,310),28,Color("f3d599"))
 label("Esc to return",Vector2(66,361),15,Color("a7b9c8"))
 page.move_child(veil,0)
 for b in buttons.values():b.hide()
 requested=get_node("/root/FrontendCache").start()
 if not requested:status.text="Could not load. Esc to return."
func _process(delta):
 if not pending:return
 elapsed+=delta
 veil.color.a=minf(.96,elapsed*3.8)
 if not requested or entering:return
 var cache=get_node("/root/FrontendCache")
 if cache.failed:
  requested=false;status.text="Could not load. Esc to return.";return
 if cache.is_ready and elapsed>=.25:
  entering=true
  finish_entry.call_deferred()
 else:status.text="WEAVING THE ARENA"+".".repeat(int(elapsed*2)%4)
func finish_entry():
 if not pending:return
 # Large resources are cached; compile scripts on the main thread to avoid
 # Godot 4.7.2 zero-reference parser leaks from worker-first script loading.
 var scene=get_node("/root/FrontendCache").prime_scene() as PackedScene
 get_tree().set_meta("nrcu_entry",entry)
 get_tree().set_meta("weaver_menu_transition_ms",Time.get_ticks_msec()-transition_started)
 get_tree().auto_accept_quit=true
 get_tree().change_scene_to_packed(scene)
func _input(event):
 if event is InputEventJoypadButton:
  var mapping={JOY_BUTTON_A:KEY_ENTER,JOY_BUTTON_B:KEY_ESCAPE,JOY_BUTTON_DPAD_UP:KEY_UP,JOY_BUTTON_DPAD_DOWN:KEY_DOWN,JOY_BUTTON_DPAD_LEFT:KEY_LEFT,JOY_BUTTON_DPAD_RIGHT:KEY_RIGHT}
  if not mapping.has(event.button_index):return
  var key=InputEventKey.new();key.keycode=mapping[event.button_index];key.pressed=event.pressed
  var viewport=get_viewport();viewport.set_input_as_handled();viewport.push_input(key)
func _unhandled_key_input(event):
 if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
  show_page("quit" if state=="home" else "home")
  get_viewport().set_input_as_handled()
