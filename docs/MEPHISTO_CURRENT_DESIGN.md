# Mephisto — current character and kit direction

This page records current design direction, not a new release or a claim that every described change is in the downloadable build. Versioned patch notes describe their original release.

## Character

Mephisto's fighter is a young woman accompanied by her bonded shadow guardian. She leads the regular playable form; the guardian stays close behind her and is not independently targetable in that form. They remain a pair. The guardian's frightening silhouette does not establish an evil alignment, and the Story encounter is not a separate villain origin.

## Regular kit

The reference is **Super Smash Bros. Ultimate Zelda**, adapted to NRCU's simplified directional inputs and Smash 64-style game feel. This is not a claim that Zelda was playable in Smash 64 or that Nintendo animation assets were imported.

- **Neutral special — Barrier / reflect:** defensive magic and projectile reflection.
- **Side special — Slumber Ember:** steerable projectile, released to burst and inflict sleep; higher opponent damage increases sleep duration.
- **Up special — Paired Teleport:** the young woman and guardian disappear and return together.
- **Down special — Dream Hand:** the guardian reaches out, catches and lifts an opponent, then releases them asleep. Older release labels and internal identifiers use **Dream Grasp** for this move.

The regular kit does not use voluntary lead switching. In the **v0.6.1 candidate**, all eight directional ground/air basic slots route to the regular caster kit, not the historical demon-led brawler moveset. Grounded Down+basic selects the low basic; airborne Down+basic selects **Meteor Heel** (internally `FallingStar`). Its controller is connected to that route. This establishes candidate source installation, not final art approval of every basic or verification of a downloadable package.

## Story presentation direction — Boss_Meph (not installed-status evidence)

The approved encounter has four stocks. The first three use the regular companion presentation. On the last stock, the guardian raises a supporting hand and carries the young woman meditating on its palm.

**Boss_Meph retains the current Mephisto kit. Only the raised-hand carrying/meditation presentation returns from the older design.** Carrying must not switch the fighter back to the historical demon swipes, ground slam, spray, shadow chain, or lead-switch kit.

## Implementation boundary

The candidate's basic dispatcher calls the regular playable route before shared aerial routing. The move controller starts with demon form disabled, rejects lead-switch starts, and resets demon form on accepted move starts. Historical demon move definitions still present in source are not evidence that ordinary player input selects them.

Story creates Mephisto through the same current fighter factory as Versus; there is no separate historical demon boss selected by that factory. The current Story text describes non-Bobo opponents as three-stock normal bots. Do not read the four-stock/last-stock carrying design above as a claim that it is installed in this candidate.

Regular basics and Meteor Heel are therefore **installed in candidate source**, rather than merely waiting in a separate review build. Source inspection does not certify natural full Story completion, the Boss_Meph presentation direction, final visual approval of every basic, balance, or exported-package playback.

This documentation update changes no game code, downloadable packages, save data, or deployed gameplay.
