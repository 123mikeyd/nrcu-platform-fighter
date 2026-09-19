extends RefCounted
## Per-victim finite status clock. No actors, source clocks or presentation nodes.
var freeze_remaining := 0.0
var freeze_immunity := 0.0
var thaw_immunity := 1.0
func advance(delta: float) -> bool:
	freeze_immunity = maxf(0,freeze_immunity-maxf(0,delta))
	if freeze_remaining <= 0: return false
	freeze_remaining = maxf(0,freeze_remaining-maxf(0,delta))
	if freeze_remaining > 0: return false
	freeze_immunity = thaw_immunity
	return true
func apply(request: Dictionary) -> bool:
	if request.get("kind", "") != "freeze" or freeze_remaining > 0 or freeze_immunity > 0: return false
	if request.get("duration",0.0) <= 0: return false
	freeze_remaining = request.duration
	thaw_immunity = maxf(0,request.get("immunity",1.0))
	return true
func shatter(damage: float) -> bool:
	if damage <= 0 or freeze_remaining <= 0: return false
	freeze_remaining = 0
	freeze_immunity = thaw_immunity
	return true
func clear() -> void:
	freeze_remaining = 0
	freeze_immunity = 0
func snapshot() -> Dictionary:
	return {"freeze_remaining":freeze_remaining,"freeze_immunity":freeze_immunity}
