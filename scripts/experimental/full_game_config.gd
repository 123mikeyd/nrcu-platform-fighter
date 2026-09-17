extends RefCounted
## Explicit allowlist. Unsupported selections stay in the original game.
const FIGHTERS = ["teknium", "turbofit"]
const OWNERS = ["sparring_easy", "human", "repo_easy", "repo_normal", "repo_hard"]
func validate(fighters: Array, stage: String, owner: String) -> String:
	if fighters.size() != 2: return "Experimental Freeplay supports exactly two fighters."
	for id in fighters:
		if id not in FIGHTERS: return "%s is available in Original Game; its new collision integration is not ready." % id
	if stage != "toy_room": return "Only Toy Shelf is integrated in this slice. Use Original Game for other stages."
	if owner not in OWNERS: return "Select a supported opponent input owner."
	return ""
