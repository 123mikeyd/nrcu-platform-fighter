extends "res://scripts/bot_controller.gd"
# Practice dummy emits no intents; damage/physics remain the current fighter.
func read(_fighter:Node3D,_delta:float)->Dictionary:
 return {"left":false,"right":false,"up":false,"down":false,"jump":false,"attack":false,"special":false,"shield":false}
