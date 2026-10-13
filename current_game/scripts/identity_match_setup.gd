extends "res://scripts/two_page_match_setup.gd"
var motifs=[]
func _ready():
 super._ready()
 for page in [canvas,stage_page]:
  for child in page.get_children():
   if child is Label and child.text.begins_with("CHOOSE YOUR"):
    child.position.x=207;child.position.y=51;child.add_theme_font_size_override("font_size",34)
  picture(page,tex("res://assets/select_identity/badge.svg"),Rect2(44,38,142,64))
  var badge_name=text(page,"NRCU",Rect2(44,84,142,16),12,GOLD);badge_name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 for i in cards.size():
  var motif=picture(cards[i].box,null,Rect2(12,40,262,185));motif.name="CharacterMotif";cards[i].box.move_child(motif,0);motifs.append(motif)
 for i in stage_cards.size():
  for child in stage_cards[i].get_children():
   if child is TextureRect:
    child.texture=tex(("res://assets/select_identity/stage_"+["debug","toy_room","weaver"][i]+".png") if i < 3 else ("res://assets/menu/stage_"+["hall","meadow"][i-3]+".png"))
    child.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;child.clip_contents=true
 refresh_motifs()
func _refresh():
 super._refresh()
 refresh_motifs()
func refresh_motifs():
 for i in motifs.size():
  var id=rows[i].character.get_selected_metadata()
  motifs[i].texture=tex("res://assets/select_identity/"+id+".svg")
  motifs[i].visible=rows[i].kind.selected!=2
