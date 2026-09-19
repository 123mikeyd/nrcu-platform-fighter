extends "res://tests/test_core_stage_navigation_routes.gd"
func run():
	trace_route = false
	await journey("repo_normal","turbofit","grounded_jostle","main_left")
	await journey("repo_hard","teknium","grounded_jostle","left_top")
	await journey("repo_easy","turbofit","legacy_solid","main_top")
	if not failures: print("PASS: interrupted navigation finite retries")
	quit(1 if failures else 0)
