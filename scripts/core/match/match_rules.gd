extends Resource
## Explicit opt-in FFA stock rules; source values from legacy fighter/main.
const Stage = preload("res://scripts/core/match/stage_definition.gd")
@export var stock_count: int = 3
@export var respawn_hitstun_ticks: int = 33 # legacy .55 seconds at 60Hz
@export var respawn_protection_ticks: int = 0
@export var stage: Resource = Stage.new()
