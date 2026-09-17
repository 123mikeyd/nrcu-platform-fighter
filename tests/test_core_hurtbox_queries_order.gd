extends "res://tests/test_core_hurtbox_queries.gd"
func run() -> void:
	check(q.has_method("earliest_contact"), "earliest_contact API exists")
	if not q.has_method("earliest_contact"): return
	var later := cap("early-name"); later.a.x = 5; later.b.x = 5
	var capsules := [cap("z-arm"), later, cap("a-leg"), {}, "invalid"]
	var original := capsules.duplicate(true)
	var contact: Dictionary = q.earliest_contact(Vector3(-10, 0, 0), Vector3(10, 0, 0), 0.5, capsules, "source", "victim")
	check(contact == {"t": 0.45, "source_id": "source", "victim_id": "victim", "hurtbox_id": "a-leg"}, "earliest time then lexical id; only one contact")
	check(capsules == original, "no input mutation")
	capsules.reverse()
	check(q.earliest_contact(Vector3(-10, 0, 0), Vector3(10, 0, 0), 0.5, capsules, "source", "victim") == contact, "input ordering independent")
	check(q.earliest_contact(Vector3(-10, 0, 0), Vector3(10, 0, 0), 0.5, capsules, "source", "victim") == contact, "no hidden dedup state")
	check(q.earliest_contact(Vector3.ZERO, Vector3.ONE, 0.0, []).is_empty(), "empty collection")
	check(q.earliest_contact(Vector3(0, 0, 20), Vector3(0, 0, 30), 0.0, capsules).is_empty(), "no contact collection")
