extends RefCounted
var save_path="user://v05_story_clearance.cfg"
func is_unlocked()->bool:
 var cfg=ConfigFile.new()
 return cfg.load(save_path)==OK and cfg.get_value("story","gauntlet_complete",false)==true
func record_run(run)->bool:
 if not run.complete() or run.route.size()!=7:return false
 var cfg=ConfigFile.new();cfg.set_value("story","gauntlet_complete",true)
 cfg.set_value("story","hero",run.hero)
 return cfg.save(save_path)==OK
