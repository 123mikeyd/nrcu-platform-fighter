extends Resource
@export_enum("finite", "legacy") var policy_id: String = "finite"
## Proposed finite-defense tuning, measured in caller-committed ticks.
@export var shield_max: float = 100.0
@export var shield_drain: float = 0.4
@export var shield_hit_base: float = 2.0
@export var shield_hit_scale: float = 1.0
@export var break_ticks: int = 90
@export var shield_regen: float = 0.6
@export var regen_delay_ticks: int = 45
@export var break_restore_fraction: float = 0.5
@export var ground_startup_ticks: int = 3
@export var ground_invulnerable_ticks: int = 10
@export var ground_recovery_ticks: int = 15
@export var air_startup_ticks: int = 4
@export var air_invulnerable_ticks: int = 8
@export var air_recovery_ticks: int = 20
@export var dodge_cooldown_ticks: int = 20
@export var dodge_shield_cost: float = 15.0
@export var air_dodges_per_flight: int = 1
@export var ground_dodge_speed: float = 10.0
@export var air_dodge_speed: float = 8.0
