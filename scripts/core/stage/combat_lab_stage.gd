extends Resource
## Fixed world-space combat lab authoring; no scene discovery or simulation.
const Anchor = preload("res://scripts/core/stage/ledge_anchor.gd")

func create_anchors() -> Array:
	var anchors: Array = []
	for side in [-1, 1]:
		var anchor = Anchor.new()
		anchor.anchor_id = "combat_lab.main.left" if side == -1 else "combat_lab.main.right"
		anchor.outward = side
		anchor.edge = Vector3(-12, 0, 0) if side == -1 else Vector3(12, 0, 0)
		anchor.hang_offset = Vector3(0.65, -1.5, 0)
		anchor.climb_offset = Vector3(-0.7, 0.06, 0)
		anchor.approach_width = 1.4
		anchor.approach_depth = 0.5
		anchor.min_foot_y = -1.8
		anchor.max_foot_y = -0.4
		anchors.append(anchor)
	return anchors

## Read-only containers with value-only fields (no mutable shapes or Nodes).
## Positions/sizes are explicit collider authoring, not measured mesh bounds.
func geometry() -> Array:
	var main := {
		"id": "combat_lab.main",
		"position": Vector3(0, -0.4, 0),
		"size": Vector3(24, 0.8, 3),
		"collision_layer": 1,
		"collision_mask": 0,
		"pass_through": false,
	}
	main.make_read_only()
	var descriptors: Array = [main]
	descriptors.make_read_only()
	return descriptors
