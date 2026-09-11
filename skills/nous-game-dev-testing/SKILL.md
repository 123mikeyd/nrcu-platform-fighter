---
name: nous-game-dev-testing
description: Use when developing or playtesting Godot games.
version: 0.1.0
author: Mike, Hermes Agent
platforms: [windows, linux, macos]
---

# Godot development and playtesting

A portable workflow for collaborating on a Godot game with approved character art. Applicable to fighters, racers, and other genres; discover each project's actual mechanics rather than importing assumptions from another game.

## When to use

- Investigating gameplay bugs or planning a bounded playtest.
- Integrating reviewed models and animation clips.
- Preparing a reproducible contributor or tester handoff.
- Do not use this as a character-lore authority, an asset license, or evidence that a build has passed tests.

## Prerequisites

- Access to the intended repository or supplied build and permission for the requested work.
- The project's documented Godot version and any declared dependencies.
- Git LFS if the repository's attributes require it.
- For agent-assisted work, file read/edit tools and terminal execution. Human collaborators can follow the same procedure with their editor and terminal.

## Discover first

1. Locate `project.godot`, the README, contributor rules, input configuration, scenes, and existing test runners. Trace the relevant behavior from input through mechanics and presentation.
2. Inspect current Git status and branch before editing. Preserve uncommitted work; do not reset, commit, push, or publish without authorization.
3. Verify the engine executable with `--version` using `terminal`. Use the repository's pinned version rather than assuming the newest engine is compatible.
4. Identify the intended test target: source project, exported build, or installed/running instance. These are different verification targets.
5. Inspect a test or review harness before running it: find output destinations, external asset dependencies, and any production writes. Put new evidence in a separate ignored output directory; never overwrite baseline or approved review evidence.

## Bound the task

- Choose one concrete question with observable acceptance criteria, such as visible contact matching damage, a vehicle recovering from a collision, or a results screen restarting cleanly.
- Separate functioning mechanics, unfinished presentation, provisional design, known defects, and user approval.
- Preserve working features outside the requested scope. A visual complaint does not authorize changing damage, acceleration, cooldowns, or other rules.
- Use a stable fixture when helpful, then vary the relevant actor, opponent, track, stage, or controller. Do not repeatedly require a human tester to replay unrelated cases.
- Keep experimental characters and mechanics separate from approved defaults. Ask before assigning a new animation or ability to an input.

## Implement and verify

1. Reproduce the issue with the current build. Record the build revision, setup, exact inputs, expected result, actual result, and reproduction frequency. If it does not reproduce, say so instead of inventing a cause.
2. For a code change, add a focused regression test and verify that it fails for the intended reason before implementing the smallest fix.
3. Keep deterministic rules separable from engine callbacks where practical, but also exercise the real scene lifecycle and input path. Helper-level tests do not prove runtime behavior.
4. Run the focused test, relevant neighboring tests, and the project's full regression command where feasible. Inspect logs as well as exit codes: a printed PASS after a script error is not success.
5. Run a bounded project startup check and verify the actual game window. Headless checks cannot establish visual clarity, camera framing, controller feel, or animation quality.
6. Test cleanup at relevant boundaries: interruption, elimination/reset, scene changes, menu return, results, and replay. Ensure effects and input state cannot leak into the next session.
7. Report exactly what was exercised and what remains unverified. Do not label synthetic controller events as physical controller testing.

## Models and animation

- Keep approved source models and manually edited assets unchanged. Export protected derivatives; do not repair weights or redesign anatomy without permission.
- Inventory the supplied mesh, rig, materials, Actions, key spacing, and actual source timing before assigning clips. A matching clip name does not prove compatible skeletons or correct motion.
- Preserve textures, source speed, approved cuts, signature props, and intended scale. Avoid duplicate props already present in an imported model.
- Verify source and engine poses at meaningful samples, including contact/release and transitions. Distinguish source-art defects from export defects and runtime routing problems.
- Keep gameplay movement and collision separate from visual animation. Explicitly decide who owns root travel; avoid double movement or unintended cancellation of authored lift.
- Synchronize visible contact/release with gameplay events. Do not silently delay an immediate mechanic merely to fit a longer animation.
- Test both relevant directions, interruptions, duplicate character instances, and return to ordinary movement. Shared mutable animation/material resources must not make one instance change another.
- Require visual review at gameplay camera distance, not only close-up renders. Review approval, installation, and final acceptance are separate gates unless the user explicitly combines them.

## Human playtest handoff

- Supply an exact build/revision and a short sequence the tester can perform without reading code.
- Give one main question per pass; list known unfinished features so testers do not waste effort rediscovering them.
- Leave the build at a safe menu or ready screen. Do not leave an unattended human character losing while instructions are being delivered.
- Ask for a short clip or screenshot plus inputs and setup. Capture native logs without exposing private local paths or unrelated machine information.
- Track reproducible issues separately from subjective feedback. Preserve both without claiming that passing automated tests disproves a visible problem.

## Collaboration and sharing

- Share runtime source and required assets, not caches, credentials, private conversations, source-acquisition notes, or entire personal asset libraries.
- Use repository-relative paths and configurable engine/output locations. Git-ignore generated import caches and test outputs; preserve import settings and script identifiers required by the project.
- Coordinate ownership when multiple contributors touch shared controllers, roster/configuration files, or the same binary asset. Parallel work on separate files is safer than competing asset replacements.
- Use Git LFS according to repository policy. Track storage and download quotas; changing a binary can store another full version.
- Keep playable builds in the project's chosen release channel rather than repeatedly committing exported binaries.
- A private repository is not a redistribution license. Review rights and permission for included art, models, music, fonts, and third-party material before sharing or making a repository public.
- Do not automatically apply a code license to artwork or infer that a contributor may reuse assets in a different game.

## Completion checklist

- [ ] The requested behavior and scope are explicit.
- [ ] Tests and logs refer to the actual final source or build.
- [ ] Relevant real-input and live-window checks are recorded separately from headless checks.
- [ ] Editable originals and prior evidence remain intact.
- [ ] Known limitations, provisional choices, and pending approvals are stated.
- [ ] A collaborator can reproduce the setup without the author's machine paths.
- [ ] If a release was requested, a fresh extraction of the actual exported executable was tested; source-project success alone is insufficient.
