extends "res://tests/test_core_body_profile_native.gd"
# Run the same native head/status/body-block/hitstop matrix against actual
# generated drafts, in both role assignments. This is not balance approval.
func body_profile(radius: float, _height: float):
	var character = "turbofit" if radius >= 0.5 else "teknium"
	return load("res://data/collision/generated/"+character+".tres").duplicate(true)
