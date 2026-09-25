extends SceneTree
func _initialize():
 for id in ["debug","hall","meadow"]:
  var image=Image.load_from_file("res://.verification/"+id+".png")
  var crop=image.get_region(Rect2i(200,110,1000,455));crop.resize(500,228)
  crop.save_png("res://assets/menu/stage_"+id+".png")
 quit()
