class_name CombatMath
extends RefCounted

static func apply_damage(current_percent: float, hit_damage: float) -> float:
    return maxf(0.0, current_percent + hit_damage)

static func knockback_strength(current_percent: float, hit_damage: float, base_knockback: float) -> float:
    return base_knockback + current_percent * 0.065 + hit_damage * 0.12
