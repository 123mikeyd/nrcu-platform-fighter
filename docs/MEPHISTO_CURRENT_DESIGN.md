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

The regular kit does not use voluntary lead switching. Its basic attacks are being developed as a Zelda-inspired caster kit, not as the historical demon-led brawler moveset. The revised Meteor Heel-inspired down-air has visual approval in a separate review build; that approval alone does not establish release installation or final approval of every other basic attack.

## Story presentation — Boss_Meph

The approved encounter has four stocks. The first three use the regular companion presentation. On the last stock, the guardian raises a supporting hand and carries the young woman meditating on its palm.

**Boss_Meph retains the current Mephisto kit. Only the raised-hand carrying/meditation presentation returns from the older design.** Carrying must not switch the fighter back to the historical demon swipes, ground slam, spray, shadow chain, or lead-switch kit.

## Implementation boundary

The provisional local Story implementation restored historical demon attack routing and therefore still needs correction to match the design above. Its earlier lifecycle tests do not certify this corrected kit. The new regular basics/down-air remain separate review work pending integration verification.

This documentation update changes no game code, downloadable packages, save data, or deployed gameplay.
