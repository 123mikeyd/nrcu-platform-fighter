# Frontend presentation parity

The experimental Toy Shelf uses the untouched v0.2 `main.gd` environment
builder through `full_game_presentation.gd`. The temporary legacy node never
enters the scene tree: only its environment, two lights and camera are moved
into the adapter. Original fighter/input/stage lifecycle is not invoked.
`stage_theme.gd` remains the material/detail authority, including its warm
Toy Shelf ambient-color override.

The original camera is static perspective, FOV 48°, at `(0, 5.8, 19.5)`, looking
at `(0, 2, 0)`. There is no authored dynamic follow or zoom to port. The adapter
preserves the exact transform and defaults rather than the previous flattened
orthographic size-17 view. Original key shadows and the weaker fill are restored.
No actor, movement, collision, navigation, ledge or stage-layout values change.

`test_full_game_presentation.gd` compares the runtime original Toy Shelf with
the adapter. `test_full_game_camera.gd` independently projects both installed
bodies at floor ends, maximum full-plus-air-jump height, and both ledge routes
in 1280×720 and 960×540 SubViewports. It retains the 9%-height readability gate
and checks actual outer HUD panels with a 12-pixel clearance. Removed upper
platform sample points are not valid current Toy Shelf requirements.

Native before/after and packaged-original evidence is recorded in the ignored
`.verification/core/original-presentation-parity/REPORT.md`. Software-rendered
Compatibility captures do not certify hardware rendering or a new Web export.
