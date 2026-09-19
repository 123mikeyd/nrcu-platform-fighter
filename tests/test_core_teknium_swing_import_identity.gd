extends SceneTree
const D = preload("res://scripts/core/presentation/teknium_swing_source.gd")
var failures := 0
func check(ok: bool, label: String):
 if not ok: failures += 1; print("FAIL: ",label)
func _initialize():
 check(D._source_content(1.0) == [TYPE_FLOAT, "f64le", "000000000000f03f"],"float encoding is explicit IEEE754 binary64 little-endian")
 check(D._source_content({&"z":1,&"a":2}) == D._source_content({&"a":2,&"z":1}),"unordered maps sorted by textual keys")
 var source: PackedScene = load(D.ASSET)
 check(D.source_content_authenticated(source),"import source authenticated")
 var copy: PackedScene = source.duplicate(true)
 var bundle: Dictionary = copy.get("_bundled").duplicate(true)
 var ids: PackedInt32Array = bundle.node_ids
 for i in ids.size(): ids[i] = 1000 + i
 bundle.node_ids = ids
 copy.set("_bundled",bundle)
 check(D.source_content_authenticated(copy),"fresh-import node IDs do not alter source identity")
 var errors := []
 check(D.assembled_source(copy,errors) != null and errors.is_empty(),"fresh-import identity assembles without instantiating caller")
 # Change only a resource in the otherwise identical serialized bundle: no
 # repacking/default-property differences can accidentally satisfy rejection.
 for mutation in ["key", "time", "path", "interpolation", "enabled", "metadata"]:
  var altered: PackedScene = source.duplicate(true)
  var variants: Array = altered.get("_bundled").variants
  var library: AnimationLibrary
  for value in variants:
   if value is AnimationLibrary: library = value
  check(library != null,"fixture has the original animation library")
  if library == null: continue
  var clip := library.get_animation("Punch")
  check(D.source_content_authenticated(altered),"unmodified deep resource copy authenticated")
  match mutation:
   "key": clip.track_set_key_value(0,0,clip.track_get_key_value(0,0)+Vector3(.001,0,0))
   "time": clip.track_set_key_time(0,0,clip.track_get_key_time(0,0)+.000001)
   "path": clip.track_set_path(0,NodePath("Teknium_Master_Armature/Skeleton3D:WrongBone"))
   "interpolation": clip.track_set_interpolation_type(0,Animation.INTERPOLATION_NEAREST)
   "enabled": clip.track_set_enabled(0,not clip.track_is_enabled(0))
   "metadata": library.set_meta("node_ids",PackedInt32Array([1001]))
  check(not D.source_content_authenticated(altered),"reject exact serialized resource tamper: "+mutation)
  errors.clear()
  check(D.assembled_source(altered,errors) == null and not errors.is_empty(),"tampered resource rejected before caller instance: "+mutation)
  check(D.source_content_authenticated(source),"tamper fixture leaves original untouched")
 # Source remains independently authenticated after alternate instance IDs.
 check(D.source_content_authenticated(source),"original still authenticated")
 if not failures: print("PASS: Teknium swing import identity")
 quit(1 if failures else 0)
