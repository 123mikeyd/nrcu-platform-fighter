extends SceneTree
var arena
var home
func _initialize():call_deferred("capture")
func frames(n):
 for i in n:await process_frame
func snap(name):
 await frames(6)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://.verification/"+name+".png")
func capture():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.verification"))
 home=load("res://scenes/home.tscn").instantiate();root.add_child(home);current_scene=home
 await snap("opening");home.show_page("title");await snap("title");home.show_page("home");await snap("home")
 root.remove_child(home);home.queue_free();await frames(2)
 arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);current_scene=arena
 arena.clearance.save_path="user://v05_capture_fixture.cfg"
 await snap("heroes");arena.choose_hero("turbofit");await snap("board");arena.briefing();await snap("briefing")
 for id in ["toy_room","debug","hall","meadow"]:
  arena.show_setup();arena.setup.level.select(arena.SetupScript.LEVEL_IDS.find(id))
  var slots=arena.Config.default_slots();slots[0].character="turbofit";slots[1].character="ggb";slots[1].kind="human";slots[2].kind="empty";slots[3].kind="empty"
  arena.start_match(slots,false);await frames(140);await snap(id)
 arena.pause_game();await snap("pause");arena.resume_game();arena.show_setup();await snap("setup")
 arena.run.choose("turbofit");arena.run.index=7;arena.show_victory();await snap("victory");arena.show_credits();await snap("credits")
 arena.clear_battle();root.remove_child(arena);arena.queue_free();await frames(3)
 home=load("res://scenes/home.tscn").instantiate();home.clearance.save_path="user://v05_capture_fixture.cfg";root.add_child(home);current_scene=home
 home.show_page("lab");await snap("lab")
 var fixture_path=home.clearance.save_path
 node_added.connect(func(n):
  if n.get_script()==load("res://scripts/v05_main.gd"):n.clearance.save_path=fixture_path)
 home.buttons.practice.pressed.emit();await frames(12)
 var lab=current_scene
 if not lab.practice:push_error("capture fixture failed to enter Battle Lab");quit(1);return
 lab.setup._start();await frames(150);await snap("lab_practice")
 lab.pause_game();await snap("lab_practice_pause");lab.resume_game()
 DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
 print("V05_CAPTURE_COMPLETE");quit()
