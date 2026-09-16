# v0.2 alpha playtest: Doge, Bobo, and the current fighters

**This is an unfinished public alpha playtest, not a finished game.** Use the build tag or commit ID in every report. Mephisto's unfinished kit and later experiments are outside this test pass. Homepage polish and incomplete fighter animation coverage are known work.

## Windows build

Download the Windows ZIP from this repository's Releases, extract the entire ZIP, and run `NRCU.exe`. Keep its companion PCK alongside it. Godot is not needed for the exported build. This build is unsigned; if Windows shows a warning, verify the repository and checksum before deciding whether to run it. Do not disable antivirus.

## Focused Doge pass

In Freeplay, select **Doge Man** for P1 and start the match. Wait for Ready/Go.

- Tap **F** without a direction: Lead jab; additional fresh taps chain into alternating punches. Holding F should not auto-repeat.
- Grounded **A/D + F**: roundhouse.
- **Space**, then neutral **F**: airborne Superman punch.
- **Space**, then **A/D + F**: edited airborne Drop Kick. Landing or interruption cancels it; late jumps can miss because the feet have a short active interval.
- Grounded **S + F** starts the existing Tyson route; try a fresh follow-up basic press.
- Repeat facing the opposite direction. Report inputs, spacing, and jump timing for misses rather than assuming every attack must connect.

## Story pass — one fighter at a time

1. Choose **Play**, then **Story Mode**.
2. Choose the fighter you want to test, then **START ENCOUNTER**. Wait for Ready/Go to finish.
3. Move with **A/D**, jump with **Space**, use **F** for basic attacks, **G** for specials, and **E** to shield. Direction plus an attack changes the move. Some attacks charge while held and fire on release.
4. Approach Bobo. Try a basic attack, a directional attack, an airborne attack, and one special separately. Test facing left and right where practical.
5. Watch whether visible contact matches HP loss and whether Bobo's reaction reads clearly. He starts with **400 HP**, stays in place, and attempts a slow two-part thrust/slash when you approach. Its timing and balance are provisional; he is not a complete boss AI.
6. Check that movement resumes after attacks and that jumping/landing does not leave an attack pose stuck.
7. Defeat Bobo, choose **Replay**, and confirm full HP and a fresh encounter. **Esc** returns to setup.
8. Repeat with a different fighter rather than testing every move in one sitting.

Record misses too: some moves have intentionally limited range, height, or grounded/airborne requirements. A miss needs setup evidence before being classified as a bug.

## Secondary pass

- Home → How to Play → Back → Play.
- Freeplay with bots; start, play, return to setup, and start again.
- Try each selectable stage. Report hidden fighters, missing textures, unreadable UI, or scenery that disagrees with collision.
- If available, connect physical gamepads before launch. Report the controller model, assigned slot, and actual input behavior. Keyboard/synthetic tests do not establish gamepad compatibility.

## Useful bug report

Open an Issue using the playtest form. Include:
- Build tag/commit and Windows version.
- Mode, stage, fighter(s), human/bot setup, and keyboard/gamepad.
- Exact steps and buttons, including whether held or tapped.
- Expected result versus actual result; how often it happens.
- A short clip or screenshot when helpful.

Remove private local paths or unrelated desktop information from attachments. Distinguish reproducible bugs from balance/design suggestions.

## Limits

Automated checks, visual inspection, actual keyboard play, and physical gamepad play are separate evidence. Consult the release notes for checks actually completed on that exact download. Do not assume every fighter move is finished or every controller is tested.
