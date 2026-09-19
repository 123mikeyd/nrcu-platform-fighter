extends SceneTree
const Specials = preload("res://scripts/core/kits/turbofit_specials.gd")
var failures := 0

class LegacyOrb:
	extends "res://scripts/fighter.gd"
	func _ready() -> void: set_physics_process(false)
	func can_hit(_target: Node) -> bool: return true

class Victim:
	extends Node3D
	var hits := 0
	var last_source: Node
	func receive_hit(_damage: float, _direction: Vector3, _knockback: float) -> void: hits += 1
	func receive_hit_from(damage: float, direction: Vector3, knockback: float, source: Node, _collateral := false) -> void:
		last_source = source
		receive_hit(damage, direction, knockback)

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: ", label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	# No target exists during the first interval. Introduce it only before
	# the next query, so this catches early expiry rather than an initial hit.
	for elapsed in [.5499995, .55, .5500005]:
		var kit = Specials.new()
		check(kit.start("edge:" + str(elapsed), Vector2.DOWN, 1), "boundary start")
		check(kit.collect(1, Vector3.ZERO, []).is_empty(), "initial empty query")
		var old := LegacyOrb.new()
		root.add_child(old)
		old.sound_orb_time = .55
		old._tick_sound_orb(elapsed)
		kit.tick(elapsed)
		var victim := Victim.new()
		root.add_child(victim)
		victim.position = Vector3(.5, 0, 0)
		victim.add_to_group("fighters")
		var targets := [{"id":2, "position":victim.position}]
		var shots := [{"id":"edge-shot", "owner":3, "reflectable":true, "position":Vector3.UP}]
		var expected := 1 if elapsed < .55 else 0
		check((kit.phase == "active") == (expected == 1), "exact active boundary at " + str(elapsed))
		check((old.sound_orb_time > 0) == (expected == 1), "source exact timer boundary")
		# Source queries then decrements; core host must collect then tick.
		var effects: Array = kit.collect(1, Vector3.ZERO, targets, shots)
		old._tick_sound_orb(1.0 / 60.0)
		check(victim.hits == expected, "source final interval query")
		check(victim.last_source == (old if expected else null), "v0.3 source attribution accompanies only real contact")
		check(effects.size() == expected * 2, "late target and reflection before decrement at " + str(elapsed))
		check(kit.collect(1, Vector3.ZERO, targets, shots).is_empty(), "final interval ledgers forbid rehit and rereflect")
		check(absf(kit.cooldown - (.75 - elapsed)) < 1e-12, "expiry does not retune cooldown")
		kit.tick(1.0 / 60.0)
		check(kit.phase == "recovery", "crossing interval expires")
		check(kit.collect(1, Vector3.ZERO, [{"id":4,"position":Vector3.ZERO}], shots).is_empty(), "no contact after decrement")
		check(not kit.start("premature", Vector2.DOWN, 1), "recovery retains cooldown gate")
		kit.tick(kit.cooldown)
		check(kit.phase == "idle" and kit.cooldown == 0, "original .75 cooldown completes")
		check(kit.start("fresh", Vector2.DOWN, 1), "new episode starts after cooldown")
		check(kit.collect(1, Vector3.ZERO, targets, shots).size() == 2, "new episode resets both ledgers")
		victim.free()
		old.free()
	# Ordinary 60Hz: collect throughout each active interval, then decrement.
	var scheduled = Specials.new()
	scheduled.start("60hz", Vector2.DOWN, 1)
	var seen := [{"id":2,"position":Vector3.RIGHT}]
	var shot := [{"id":"60hz-shot","owner":3,"reflectable":true,"position":Vector3.UP}]
	check(scheduled.collect(1, Vector3.ZERO, seen, shot).size() == 2, "60Hz initial contacts")
	for frame in 33:
		check(scheduled.phase == "active", "60Hz query remains active frame " + str(frame))
		check(scheduled.collect(1, Vector3.ZERO, seen, shot).is_empty(), "60Hz ledgers survive tick")
		if frame == 32:
			check(scheduled.collect(1, Vector3.ZERO, [{"id":4,"position":Vector3.RIGHT}]).size() == 1, "60Hz last active interval admits late target")
		scheduled.tick(1.0 / 60.0)
	check(scheduled.age == .55 and scheduled.phase == "recovery", "60Hz accumulated age expires exactly at .55")
	check(scheduled.collect(1, Vector3.ZERO, [{"id":5,"position":Vector3.RIGHT}]).is_empty(), "60Hz endpoint rejects fresh target")
	check(absf(scheduled.cooldown - .2) < 1e-12, "60Hz expiry retains .2 cooldown")
	for frame in 12: scheduled.tick(1.0 / 60.0)
	check(scheduled.phase == "idle" and scheduled.cooldown == 0, "60Hz unchanged .75 cooldown endpoint")
	if failures == 0: print("PASS core Turbofit exact Orb expiry, query-before-decrement, ledgers and 60Hz cooldown")
	quit(1 if failures else 0)
