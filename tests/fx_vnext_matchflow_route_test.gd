extends SceneTree
## End-to-end VS route proof: MainFlow -> CSS -> SSS -> MatchFlow launch
## -> gameplay destination -> production FX binding. This is the production
## route boundary; direct main.tscn tests remain separate fixtures.

const Setup := preload("res://tools/fx_review_setup.gd")
const VsRoute := preload("res://tests/fixtures/vs_route.gd")

var checks := 0
var failures := 0
var route
var arena: Node = null
var screen: CanvasLayer = null

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var out_dir := OS.get_environment("FXLAB_EVIDENCE_DIR").strip_edges()
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://fx_evidence/matchflow_route")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var data_dir := out_dir.path_join("production")
	var drafts_dir := out_dir.path_join("drafts")
	var seeded: Dictionary = Setup.seed("CLASH_OVERDRIVE", data_dir, drafts_dir)
	check(bool(seeded.get("ok", false)), "isolated production seed")
	if not bool(seeded.get("ok", false)):
		_finish()
		return
	OS.set_environment("NRCU_FX_DATA_DIR", data_dir)
	OS.set_environment("NRCU_FX_DRAFT_DIR", drafts_dir)

	route = VsRoute.new()
	var host: Node = await route.enter(self)
	check(host != null and is_instance_valid(host), "real MatchFlow host enters from VS route")
	if host == null or not is_instance_valid(host):
		_finish()
		return
	check(await route.wait_css_ready(host, self), "real Character Select settles")
	arena = await route.launch(self, host, ["ice_mage", "doge_man", "", ""], "debug")
	check(arena != null and is_instance_valid(arena), "real CSS -> SSS -> gameplay route launches")
	if arena == null or not is_instance_valid(arena):
		_finish()
		return

	var adapter = arena.get_node_or_null("VsPresentationAdapter")
	check(adapter != null and is_instance_valid(adapter), "production MatchFlow destination mounts VS adapter")
	if adapter != null and is_instance_valid(adapter):
		screen = adapter.screen()
		check(screen != null and is_instance_valid(screen), "production adapter owns a live VS screen")
		var binding = screen.get_node_or_null("ProductionFx") if screen != null else null
		check(binding != null and is_instance_valid(binding), "production route mounts one ProductionFx consumer")
		if binding != null:
			check(bool(binding.last_summary.get("ok", false)), "production route reports successful FX binding")
			check(binding.runtime != null and binding.runtime.subvp == null, "production route avoids a second screen viewport")
		check(adapter.route_id() == "DUEL_1V1", "production route preserves the duel presentation route")
		check(adapter.left_id() == "ice_mage" and adapter.right_id() == "doge_man", "production route preserves fighter order")
	check((arena.get("fighters") as Array).size() == 2, "production route spawns the configured pair")

	_cleanup()
	_finish()

func _cleanup() -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	if arena != null and is_instance_valid(arena):
		arena.queue_free()
	if route != null:
		await route.free_hosts(self)
	for _i in 8:
		await process_frame
	OS.set_environment("NRCU_FX_DATA_DIR", "")
	OS.set_environment("NRCU_FX_DRAFT_DIR", "")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[MATCHFLOW-ROUTE] FAIL ", label)
	else:
		print("[MATCHFLOW-ROUTE] PASS ", label)

func _finish() -> void:
	print("[MATCHFLOW-ROUTE] done checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
