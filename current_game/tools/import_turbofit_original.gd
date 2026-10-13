@tool
extends EditorScenePostImport
# Restoration-only derivative. Existing 96-Hz Electrocution hook is retained.
# Replaces ONLY repaired native Idle with unoptimized 30-Hz data; the standard
# importer otherwise simplified its small wrist curves by ~0.21 degrees.
func _post_import(scene: Node) -> Object:
 var original_hook=load("res://tools/import_electrocution.gd")
 scene=original_hook.replace_reaction(scene,get_source_file())
 var doc:=GLTFDocument.new()
 var state:=GLTFState.new()
 if doc.append_from_file(get_source_file(),state)!=OK:
  push_error("Original33 Idle exact import failed")
  return scene
 var exact:=doc.generate_scene(state,30.0,false,true)
 var source:AnimationPlayer=exact.find_children("*","AnimationPlayer",true,false)[0]
 var target:AnimationPlayer=scene.find_children("*","AnimationPlayer",true,false)[0]
 var library:=target.get_animation_library("")
 if library.has_animation("Idle"): library.remove_animation("Idle")
 library.add_animation("Idle",source.get_animation("Idle").duplicate(true))
 exact.free()
 return scene
