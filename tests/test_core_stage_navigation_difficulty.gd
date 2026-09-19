extends "res://tests/test_core_stage_navigation_routes.gd"
func run():
	for kind in ["repo_normal","repo_hard"]:
		for id in ["teknium","turbofit"]:
			for mode in ["grounded_jostle","legacy_solid"]:
				for trip in ["main_left","left_top","left_main"]:
					await journey(kind,id,mode,trip)
	if not failures: print("PASS: native navigation retains Normal and Hard source difficulty")
	quit(1 if failures else 0)
