extends "res://tests/test_core_top_support_roof.gd"
func step(m, frames := {}):
	var drop = Frame.new(); drop.pressed.down = true; drop.held.down = true
	frames = frames.duplicate(); frames[1] = drop
	await physics_frame; m.simulate(frames)
