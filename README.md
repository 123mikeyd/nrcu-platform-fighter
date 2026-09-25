# NRCU Platform Fighter — v0.5

**Unfinished alpha — a consolidated Story, roster and character-world update.** Frontend portrait/layout adaptation credits [Arts Bro](https://github.com/realartsbro); current state-coordinator work credits Quarker. [Release notes and testing boundaries](RELEASE_NOTES_v0.5.md).

## Play

[Play in your browser](https://123mikeyd.github.io/nrcu-platform-fighter/) · [Windows release and checksums](https://github.com/123mikeyd/nrcu-platform-fighter/releases/tag/v0.5)

The browser game is a large initial download. Click **Play Now** and keep the tab active. WebGL 2 is required. Desktop browser testing is not physical-phone certification.

For Windows, extract the entire `NRCU-v0.5-Windows.zip` into a folder, then run `NRCU.exe` beside `NRCU.pck`. Keep the bundled notices and other files together.

P1: **A/D** move, **W/S** aim, **Space** jump, **F** basic, **G** special. **Escape** pauses gameplay. P2 uses arrows, Enter, K and L. In-game help explains current controls; there is no universal shield.

## What is together in v0.5?

- Current eight-fighter freeplay roster, including playable Bobo, and current character kits.
- Six selectable Story heroes and seven encounters per run, omitting the chosen hero from the opponent route. Explicit briefings, current-encounter retries, route board and final credits.
- A separately preserved historical paired Mephisto Story boss; the playable Mephisto kit remains current.
- Fortress, TurboFit music hall, GGB meadow and the current single-platform Toy Room. Story assigns worlds explicitly; Sky is legacy freeplay-only.
- Unified opening/title/home, Story selection, pause and results.
- Final Story completion unlocks **Battle Lab**, an in-process practice mode with current fighters and idle opponents. Browser and Windows saves are separate.

Quarker's experimental two-fighter engine and collision-authoring tools remain separate. They are not required to run this release and are not presented as working v0.5 workshop features.

## Open the right source project

Install **Godot 4.7.2**, Git and Git LFS. Clone the repository and run `git lfs pull`.

**For v0.5, import `current_game/project.godot`, let import finish, then press F5.** The root `project.godot` is the preserved earlier public frontend, not the v0.5 release entrypoint. The nested project has its own import/cache boundary. Do not merge their generated caches.

Use matching official 4.7.2 export templates and the **Windows Playtest** or **Web Browser** presets inside `current_game`. Export outside the source checkout. Preserve import hooks, `.import` and `.uid` companions.

Bounded v0.5 contract:

```sh
python tools/release_v05_runner.py --engine PATH_TO_GODOT --project current_game --output .verification/v05 --import-project --timeout 600
python -m unittest discover -s tests -p 'test_release_v05*.py' -v
```

The earlier root release-contract checks remain in CI separately. Runtime source and immutable release packages are distinct from the reviewed-archive Pages deployment; changing main alone does not deploy the browser build.

## Testing and feedback

This is not an all-green legacy suite or a balance certification. Campaign lifecycle tests use explicitly forced outcomes, distinct from natural combat input tests. Full natural campaign clears, exhaustive matchups, physical controllers/phones and long-session performance remain tester work. Report the exact release, hero/opponent/stage, inputs and expected/actual behavior with a screenshot or clip.

## Sharing boundaries

Use separate branches/PRs and avoid concurrent binary or fighter-controller edits. Public source and the author's local working projects do not automatically synchronize. Private provenance, source libraries, Blender masters and test evidence are excluded.

No blanket asset redistribution license is granted. Public visibility is not permission to reuse character art or other assets separately. Preserve bundled Godot/font/material notices and contributor credits. See `current_game/third_party/ASSET-NOTICES.txt`.
