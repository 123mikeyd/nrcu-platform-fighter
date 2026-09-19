extends Resource
## Authored definition only. Runtime takes a detached snapshot at construction.
@export var run_speed: float = 8.0
@export var ground_acceleration: float = 60.0
@export var ground_friction: float = 70.0
@export var turn_acceleration: float = 90.0
@export var initial_dash_ticks: int = 6
@export var initial_dash_acceleration: float = 90.0
@export var run_threshold: float = 0.7
@export var jump_startup_ticks: int = 3
@export var full_jump_speed: float = 13.0
@export var short_jump_speed: float = 8.0
@export var air_jump_speed: float = 11.5
@export var air_jumps: int = 1
@export var gravity: float = 32.0
@export var air_speed: float = 7.0
@export var air_acceleration: float = 22.0
@export var fall_speed: float = 18.0
@export var fast_fall_speed: float = 26.0
@export var landing_ticks: int = 4
