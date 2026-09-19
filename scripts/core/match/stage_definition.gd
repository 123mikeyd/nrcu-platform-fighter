extends Resource
## Gameplay plane bounds are strict, just like fighter.gd:652.
@export var blast_left: float = -16.0
@export var blast_right: float = 16.0
@export var blast_bottom: float = -8.0
@export var blast_top: float = 15.0
@export var spawns: Dictionary = {1: Vector3(-4, 1, 0), 2: Vector3(4, 1, 0)}
func outside(at: Vector3) -> bool:
	return at.x < blast_left or at.x > blast_right or at.y < blast_bottom or at.y > blast_top
