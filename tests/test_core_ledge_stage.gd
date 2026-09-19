extends "res://tests/test_core_ledge_policy.gd"

func run():
	var path := "res://scripts/core/stage/combat_lab_stage.gd"
	check(ResourceLoader.exists(path), "authored combat lab stage Resource exists")
	if failures: finish(); return
	var stage = load(path).new()
	check(stage is Resource and stage.has_method("create_anchors"), "passive stage anchor factory")
	if failures: finish(); return
	var anchors: Array = stage.create_anchors()
	check(anchors.size() == 2, "only main platform left/right ledges")
	if anchors.size() != 2: finish(); return
	for i in range(2):
		var a = anchors[i]
		var side := -1 if i == 0 else 1
		check(a.anchor_id == ("combat_lab.main.left" if i == 0 else "combat_lab.main.right"), "stable unique authored ID")
		check(a.outward == side and a.edge == Vector3(side * 12, 0, 0), "authored collider top edge")
		check(a.hang() == Vector3(side * 12.65, -1.5, 0), "mirrored foot-origin hang")
		check(a.climb() == Vector3(side * 11.3, 0.06, 0), "mirrored top landing")
		check(a.approach_width == 1.4 and a.approach_depth == 0.5 and a.min_foot_y == -1.8 and a.max_foot_y == -0.4, "explicit approach window")
	anchors[0].edge = Vector3.ZERO
	anchors[0].hang_offset = Vector3.ZERO
	anchors.clear()
	var fresh: Array = stage.create_anchors()
	check(fresh[0].edge == Vector3(-12, 0, 0) and fresh[0].hang_offset == Vector3(0.65, -1.5, 0), "factory returns independent anchors")
	check(load(path).new().create_anchors()[0] != fresh[0], "stage instances do not share mutable anchors")
	finish()
