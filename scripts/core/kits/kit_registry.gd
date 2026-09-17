extends RefCounted
## Per-match factory table. Null adapter delegates the preserved Teknium path.
var factories := {"teknium": null, "turbofit": preload("res://scripts/core/kits/turbofit_host.gd"), "ice_mage": preload("res://scripts/core/kits/ice_mage_host.gd")}
func register_factory(id: String, factory: Script) -> void:
	assert(not id.is_empty() and factory != null)
	factories[id] = factory
func contains(id: String) -> bool:
	return factories.has(id)
func create(id: String):
	assert(contains(id), "Unknown fighter kit")
	return factories[id].new() if factories[id] != null else null
