extends RefCounted

static func ids() -> Array[String]:
    return ["teknium", "doge_man", "ggb", "turbofit", "ice_mage", "witcheer", "mephisto"]

static func display_name(id: String) -> String:
    return {"teknium": "Teknium", "doge_man": "Doge Man", "ggb": "GGB", "turbofit": "Turbofit", "ice_mage": "Ice Mage", "witcheer": "Witcheer", "mephisto": "Mephisto"}.get(id, "Unknown")

# HUD/projectile palettes distinguish slots; GGB preserves original painted materials.
static func palette(id: String, slot_index_zero_based: int) -> Color:
    var bases := {"teknium": 0.36, "doge_man": 0.09, "ggb": 0.60, "turbofit": 0.94, "ice_mage": 0.57, "mephisto": 0.065}
    var hue: float = bases.get(id, 0.36)
    return Color.from_hsv(fposmod(hue + posmod(slot_index_zero_based, 4) * 0.18, 1.0), 0.76, 0.95)
