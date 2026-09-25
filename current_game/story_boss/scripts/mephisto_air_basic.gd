extends "res://scripts/humanoid_air_basic.gd"
# Retain the accepted donor clock/behavior; query visible recipient anatomy.
func present(time:float):
 super.present(time)
 view.show_native_girl(direction)
 view.native_air_from_donor()
func bone_point(bone:String)->Vector3:
 return view.girl_point(bone)
