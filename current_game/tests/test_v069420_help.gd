extends SceneTree
var failures := 0
func _initialize():
 root.unfocusable = true
 call_deferred("run")
func check(ok: bool, description: String):
 print(("PASS " if ok else "FAIL ") + description)
 if not ok: failures += 1
func run():
 var host := Control.new()
 host.size = Vector2(1280,720)
 root.add_child(host)
 var page = load("res://scripts/demo_style.gd").help(host, func(): pass)
 for i in 4: await process_frame
 var scroll = page.get_node_or_null("MovesScroll")
 check(scroll is ScrollContainer, "long move guide has an independently scrollable column")
 if scroll:
  check(scroll.position.y + scroll.size.y < page.get_node("HelpBack").position.y, "move column never covers Back")
  check(scroll.get_child(0).text.ends_with("Frost Rise"), "entire move guide remains present")
  check(scroll.get_child(0).text.contains("Ground: hold Down+Special") and scroll.get_child(0).text.contains("Release either to end"), "Turbo hold and release instructions")
  check(scroll.get_child(0).text.contains("Air Down+basic: Claw Hammer Drop"), "Bobo airborne down-basic instructions")
  scroll.scroll_vertical = 10000
  for i in 3: await process_frame
  check(scroll.scroll_vertical > 0, "bottom moves are reachable by scrolling")
 var controls: Label
 for label in page.find_children("*", "Label", true, false):
  if label.text == load("res://scripts/demo_style.gd").CONTROLS: controls = label
 check(controls != null, "full controls text remains present")
 if controls:
  var visible_rect: Rect2 = controls.get_global_rect()
  if controls.get_parent() is ScrollContainer:
   visible_rect = visible_rect.intersection(controls.get_parent().get_global_rect())
   controls.get_parent().scroll_vertical = 10000
   for i in 3: await process_frame
   check(controls.get_parent().scroll_vertical > 0, "lower controls remain reachable")
  check(not visible_rect.intersects(page.get_node("HelpKeyLegend").get_global_rect()), "controls never overlap key legend")
 var out := OS.get_environment("NRCU_CAPTURE_DIR")
 if out != "" and DisplayServer.get_name() != "headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(out.path_join("help_bottom.png"))
 host.queue_free()
 await process_frame
 print("V069420_HELP_COMPLETE")
 quit(1 if failures else 0)
