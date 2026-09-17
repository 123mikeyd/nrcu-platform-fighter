extends RefCounted
## Candidates are already eligible snapshots. Never recheck canceled sources here.
var _seen: Dictionary = {}
func resolve(candidates: Array, percents: Dictionary) -> Array:
	var ordered := candidates.duplicate(true)
	ordered.sort_custom(func(a, b):
		if a.source != b.source: return a.source < b.source
		if a.activation_id != b.activation_id: return a.activation_id < b.activation_id
		return a.victim < b.victim)
	var groups: Dictionary = {}
	for hit in ordered:
		var key := "%s/%d" % [hit.activation_id, hit.victim]
		if _seen.has(key): continue
		_seen[key] = true
		if not groups.has(hit.victim): groups[hit.victim] = []
		groups[hit.victim].append(hit)
	var results: Array = []
	var ids := groups.keys()
	ids.sort()
	for victim in ids:
		var percent: float = percents.get(victim, 0.0)
		for hit in groups[victim]: percent += hit.damage * hit.get("damage_scale",1.0)
		var best: Dictionary = {}
		for hit in groups[victim]:
			var strength: float = (hit.base_knockback + percent * 0.065 + hit.damage * 0.12) * hit.get("knockback_scale",1.0)
			if best.is_empty() or strength > best.strength:
				best = {"victim": victim, "source": hit.source, "activation_id": hit.activation_id,
					"percent": percent, "strength": strength, "launch": hit.direction.normalized() * strength,
					"hitstun_ticks": ceili((0.08 + strength * 0.025) * 60.0)}
		best["accepted_hits"] = groups[victim]
		results.append(best)
	return results
