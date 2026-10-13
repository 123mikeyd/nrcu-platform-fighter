extends SceneTree
# Source-runtime acceptance; synthetic UI activation, not physical-phone/gamepad proof.
const U = preload("res://scripts/unlocks.gd")
const Config = preload("res://scripts/match_config.gd")
var checks := 0
var failures := 0
func _initialize():
 root.unfocusable = true
 call_deferred("run")
func check(ok: bool, label: String):
 checks += 1
 print(("PASS " if ok else "FAIL ") + label)
 if not ok: failures += 1
func frames(n: int):
 for i in n: await process_frame
func capture(name: String):
 var out := OS.get_environment("NRCU_CAPTURE_DIR")
 if out != "" and DisplayServer.get_name() != "headless":
  await RenderingServer.frame_post_draw
  DirAccess.make_dir_recursive_absolute(out)
  root.get_texture().get_image().save_png(out.path_join(name + ".png"))
func material_paths(actor) -> Array:
 var paths: Array = []
 for mesh in actor.find_children("*", "MeshInstance3D", true, false):
  if mesh.mesh == null: continue
  for i in mesh.mesh.get_surface_count():
   var material = mesh.get_active_material(i)
   if material is BaseMaterial3D and material.albedo_texture != null:
    paths.append(material.albedo_texture.resource_path)
 return paths
func run():
 U.path_override = "user://release_frontend_unlocks.json"
 U.bag_path_override = "user://release_frontend_bag.json"
 FileAccess.open(U.path_override, FileAccess.WRITE).store_string(JSON.stringify({"unlocked": U.CHALLENGERS}))
 change_scene_to_file("res://scenes/startup.tscn")
 await frames(3)
 check(current_scene.has_method("request_skip"), "launch enters startup")
 current_scene.request_skip()
 for i in 2000:
  await process_frame
  if is_instance_valid(current_scene) and current_scene.get_script().resource_path == "res://scripts/home.gd": break
 check(current_scene.get_script().resource_path == "res://scripts/home.gd", "startup skip earns home")
 await capture("home")
 current_scene.buttons.play.pressed.emit()
 for i in 2000:
  await process_frame
  if is_instance_valid(current_scene) and current_scene.has_method("start_match"): break
 var arena = current_scene
 check(arena.has_method("start_match"), "home Local Match earns setup")
 if not arena.has_method("start_match"): quit(1); return
 check(arena.setup.stage_cards.size() == 5, "all five public stages retained")
 check(arena.setup.rows.size() == 4, "four player panels")
 await capture("selector")
 var total := 0
 for id in ["teknium", "doge_man", "ggb", "bobo", "witcheer"]:
  for costume in Config.costume_ids(id):
   arena.show_setup(); arena.setup.return_to_fighters()
   arena.setup.activate_slot(0)
   arena.setup.tiles[id].pressed.emit()
   for i in arena.setup.rows[0].costume.item_count:
    if arena.setup.rows[0].costume.get_item_metadata(i) == costume: arena.setup.rows[0].costume.select(i)
   arena.setup.rows[1].kind.select(0)
   arena.setup.rows[2].kind.select(2); arena.setup.rows[3].kind.select(2)
   arena.setup._refresh()
   arena.setup.find_child("StartMatchButton", true, false).pressed.emit()
   check(arena.setup.stage_page.visible and arena.setup.visible, "fighter confirmation opens stage page " + id + costume)
   var stage_index := total % 5
   arena.setup.stage_cards[stage_index].pressed.emit()
   if total == 0: await capture("stages")
   arena.setup.stage_page.get_node("StageGo").pressed.emit()
   await frames(4)
   check(not arena.setup.visible and arena.player_one.character_id == id and arena.player_one.costume_id == costume, "actual actor carries selection " + id + costume)
   check(arena.active_level == arena.SetupScript.LEVEL_IDS[stage_index], "actual selected stage " + arena.active_level)
   var paths := material_paths(arena.player_one)
   var matched := false
   for path in paths:
    if path.contains("/costumes/" + id + "/") and (path.contains("/" + costume + "/") or path.get_file().begins_with(costume + "_")): matched = true
   check(matched, "actual native material matches " + id + costume)
   if costume == Config.default_costume(id): await capture("match_" + id)
   total += 1
 check(total == 22, "all 22 approved costume choices spawned")
 arena.show_setup()
 await frames(3)
 print("V069420_FRONTEND checks=", checks, " failures=", failures)
 print("V069420_FRONTEND_COMPLETE")
 quit(1 if failures else 0)
