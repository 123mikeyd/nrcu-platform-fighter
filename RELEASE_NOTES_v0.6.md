# NRCU v0.6 — unfinished tester update: Ledges are here!

This is a development playtest, not a finished or fully certified game. The browser and Windows packages are built from the same source commit.

## What's new
Full patch notes: [PATCH_NOTES_v0.6.md](https://github.com/123mikeyd/nrcu-platform-fighter/blob/main/PATCH_NOTES_v0.6.md)
- **Ledge grab** for Teknium, Doge Man and TurboFit (on Fortress, Toy Shelf and Hermes Weaver).
- **Unlockable challengers:** start with Teknium, TurboFit and Doge Man; earn GGB, Bobo, Witcheer and Mephisto.
- **Story glow-up:** VS splash, Smash-style victory screen, new ending and credits.
- **New mode: Heavy Bag** — 15 seconds, one bag, chase your best score.
- **Victory screens** for every winner (Teknium has four random dances).
- **New moves:** Teknium Laser Blast + jab string, Doge Man 6-hit boxing combo, TurboFit Snapline Grapple, GGB Wing Gust, Mephisto Dream Grasp, Ice Mage full movement kit (Story, CPU-only).
- **New stage:** Hermes Weaver replaces Sky Sanctuary.
- **Smaller download:** the browser build is about 700 MB (v0.5 was about 990 MB).

## Controls
P1: WASD move/aim, Space jump, F basic, G special. Escape pauses. Touch (browser): left pad + right Attack/Special; Up jumps. Ledge: ↑ / toward climbs, Space jumps, ↓ lets go.

## Please test and report
- Ledges: can you get stuck, or fall through one?
- Unlocks: did a challenger show up, and did they join your roster?
- Story runs: which hero, which encounter, and what happened if anything broke (crash, stuck screen, wrong result).
- Phones: what loaded, what felt slow, and whether the touch buttons worked.

## Known issues / verification boundary
- **Teknium's up-air (backflip kick) can make the game stutter, especially on phones.** It is getting reworked in v0.7.
- Unlock progress starts fresh in v0.6 (v0.5 saves are not carried over).
- Nobody has naturally played the whole Story run through the final boss yet. Story, unlock and Heavy Bag outcome tests use forced results; they do not prove every fight can be won normally. The real exported game was hand-tested through menus, Local Match, the first Story fight and Heavy Bag on Windows and in a desktop browser, and briefly on one real phone.
- Physical controllers, long sessions and every roster/stage matchup are not certified. Hall and Meadow have no ledges yet.
- Balance, HUD/layout and inherited gameplay issues remain. The legacy full test suite is not claimed green.

## Download
Keep `SHA256SUMS.txt` with your download. Windows: extract the entire ZIP and run `NRCU.exe` next to `NRCU.pck`. Preserve the bundled Godot/font notices in `third_party/`. Public visibility does not grant separate asset-reuse rights.
