# Rain Street — five-fighter browser tester

Teknium, Doge Man, TurboFit, Witcheer and Don Piedro meet on Rain Street. Local keyboard play and CPU opponents; no Story or online multiplayer. Original motion samples are retained; image imports are capped at 32 pixels. Numerical animation textures are not artwork and are not downscaled.

## Controls
P1: A/D move, W/S aim, Space jump, F basic, G special, E taunt.
P2: arrow keys, Enter jump, K basic, L special, semicolon taunt.
Escape pauses; R rematches from Results. Direction plus attack chooses a move.

## Tested and limits
Actual desktop Chromium/Edge WASM testing covers all five fighters, movement, jumps, damaging attacks, ordinary movement across blast zones, results and rematch. Loading failure/retry was exercised for both engine and game data. Tests are not every move against every matchup, a naturally fought tournament, or physical phone certification. Firefox and Safari were not available for this run.

This remains a large first download, roughly 927 MiB before HTTP compression, despite small artwork textures. Animation buffers dominate. Do not mistake smaller textures for a demonstrated low-memory-device guarantee. Desktop recommended. Touch remains experimental.

Doge ground Down+Basic is unavailable; crouch is retained. Don's close-standing Air Down contact gaps remain; the five-kick side-air does not guarantee five contacts. The neutral chop may miss at spacing where the forward kick connects. RKO, Spirit Bomb and a new hip-charge animation are not included. No universal shield or online multiplayer is added.

## Build identity
The export receipt and input hash manifest identify the local derivative and exported files. The receipt commit is not represented as a full reproducible source checkout. The original native project and previous release remain separate. Previous releases: https://github.com/123mikeyd/nrcu-platform-fighter/releases

Please report your browser/device, selected fighters, inputs, and a screenshot or clip of any failure.
