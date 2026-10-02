extends Node
# Heavy Bag mini-game round: 15 s timer (shown as a shrinking bar, no text), depth
# scoring with a combo multiplier, and a best score per fighter saved on this PC.
# Breaking a layer scores a bonus; shattering the core ends the round with a time bonus.
# Owned by main.gd; the clock only runs during live play (not READY/GO, menus or pause).
const ROUND_SECONDS := 15.0
const COMBO_WINDOW := 0.8
const BREAK_BONUS := [150, 300, 450, 600]
const SHATTER_BONUS := 1000
const TIME_BONUS_PER_SECOND := 100
const METER_FULL := 1500.0          # score that fills the bag's glow meter
var save_path := "user://heavy_bag_best.json"   # tests point this elsewhere

var main: Node
var bag
var hero_id := ""
var time_left := ROUND_SECONDS
var running := false
var finished := false
var score := 0
var hits := 0
var core_hits := 0
var chain := 0
var best_chain := 0
var since_hit := 99.0
var deepest := 0
var layers_broken := 0
var shattered := false
var time_bonus := 0
var timer_bar: ProgressBar

func setup(owner_main: Node, target, hero: String) -> void:
	main = owner_main; bag = target; hero_id = hero
	bag.bag_hit.connect(_on_bag_hit)
	bag.shell_broken.connect(_on_shell_broken)
	var layer := CanvasLayer.new(); layer.layer = 5; add_child(layer)
	timer_bar = ProgressBar.new()
	timer_bar.name = "HeavyBagTimer"
	timer_bar.show_percentage = false
	timer_bar.max_value = ROUND_SECONDS; timer_bar.value = ROUND_SECONDS
	timer_bar.anchor_left = 0.3; timer_bar.anchor_right = 0.7
	timer_bar.offset_top = 18; timer_bar.offset_bottom = 34
	var fill := StyleBoxFlat.new(); fill.bg_color = Color(0.35, 1.0, 0.9)
	var back := StyleBoxFlat.new(); back.bg_color = Color(0, 0, 0, 0.45)
	timer_bar.add_theme_stylebox_override("fill", fill)
	timer_bar.add_theme_stylebox_override("background", back)
	layer.add_child(timer_bar)

func _physics_process(delta: float) -> void:
	if finished or not is_instance_valid(bag): return
	running = main.ready_remaining <= 0.0 and main.go_remaining <= 0.0 and not main.match_over
	bag.scoring = running
	if not running: return
	since_hit += delta
	if since_hit > COMBO_WINDOW: chain = 0
	time_left = maxf(0.0, time_left - delta)
	timer_bar.value = time_left
	if time_left <= 0.0: finish()

func multiplier() -> float:
	return minf(1.0 + 0.1 * maxi(chain - 1, 0), 2.0)

func _on_bag_hit(points: int, layer: int, _impact: float) -> void:
	if finished or not running: return
	chain = chain + 1 if since_hit <= COMBO_WINDOW else 1
	since_hit = 0.0
	best_chain = maxi(best_chain, chain)
	hits += 1
	deepest = maxi(deepest, layer)
	if layer == bag.LAYERS - 1: core_hits += 1
	score += roundi(points * multiplier())
	bag.set_meter(score / METER_FULL)

func _on_shell_broken(index: int) -> void:
	if finished: return
	layers_broken = index + 1
	if index >= bag.LAYERS - 1:
		shattered = true
		time_bonus = ceili(time_left) * TIME_BONUS_PER_SECOND
		score += SHATTER_BONUS + time_bonus
		bag.set_meter(score / METER_FULL)
		finish()
	else:
		score += BREAK_BONUS[index]
		bag.set_meter(score / METER_FULL)

func load_best() -> Dictionary:
	if not FileAccess.file_exists(save_path): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	return data if data is Dictionary else {}

func finish() -> void:
	if finished: return
	finished = true
	running = false
	var best := load_best()
	var previous := int(best.get(hero_id, 0))
	var new_best := score > previous
	if new_best:
		best[hero_id] = score
		var file := FileAccess.open(save_path, FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(best))
	bag.scoring = false
	timer_bar.hide()
	if shattered:   # let the core burst play before the results screen
		await get_tree().create_timer(1.4, false).timeout
		if not is_inside_tree(): return
	main.finish_heavy_bag(self, maxi(previous, score), new_best)

func depth_name(layer: int) -> String:
	return ["Outer shell", "Layer 2", "Layer 3", "Layer 4", "THE CORE"][clampi(layer, 0, 4)]
