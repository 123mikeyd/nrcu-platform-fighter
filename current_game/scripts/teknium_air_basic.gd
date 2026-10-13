extends "res://scripts/humanoid_air_basic.gd"
# Tek-only provisional right-foot descending stamp. Shared aerials, gravity,
# body-contact query, once-per-target ledger, cancel and release latch stay native.
func _ready():
 super._ready()
 player.remove_animation_library("humanoid_air_down")
 player.add_animation_library("humanoid_air_down",load("res://assets/teknium/polish/down_air_stamp_provisional.tres"))
func start(aim:Vector2)->bool:
 if not super.start(aim):return false
 if move=="down":
  duration=.64;active_start=.20;active_end=.29
  wrist_name="RightToeBase";elbow_name="RightFoot"
  actor.attack_cooldown=duration
  actor.last_move="AIR DOWN STAMP"
  present(0)
 return true
