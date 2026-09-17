extends Resource
## Separate from native core and bone hurtboxes. Actor-space gameplay envelope.
@export var character_id := ""
@export var source_sha256 := ""
@export var revision := "supported-idle-v2"
# 121 inclusive samples of unchanged Idle at canonical placement, plus margin.
# Head plane and sole anchor are independent; never subtract one from the other
# in authored data to disguise a below-head plane.
@export var height := 1.922
@export var supported_sole_offset := .001
@export var airborne_height := 2.13
@export var half_width := 0.40
@export var foot_radius := 0.12
@export var max_visual_excursion := 0.32
static func for_collision(profile: Resource) -> Resource:
	if profile == null or profile.character_id not in ["teknium","turbofit"]: return null
	var result = load("res://scripts/core/collision/fighter_top_support_profile.gd").new()
	result.character_id = profile.character_id
	result.source_sha256 = profile.source_sha256
	if profile.character_id == "turbofit":
		result.height = 2.396
		result.supported_sole_offset = .056
		result.airborne_height = 2.90
		result.half_width = 0.28
		result.max_visual_excursion = 0.55
	return result
func geometry() -> Dictionary:
	return {"supported_sole_offset":supported_sole_offset,"character_id":character_id,"source_sha256":source_sha256,"revision":revision,"pose_category":"upright","height":height,"half_width":half_width,"foot_radius":foot_radius,"max_visual_excursion":max_visual_excursion}
