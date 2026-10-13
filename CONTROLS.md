# 🎮 NRCU Platform Fighter — How to Play

Current instructions for the **v0.6.1 alpha**. See the [release notes and current playtest checklist](PATCH_NOTES_v0.6.1.md). Physical-controller and real-phone acceptance remain unverified.

## Buttons

| | Move / aim | Jump | Basic | Special |
|---|---|---|---|---|
| **Player 1 (keyboard)** | WASD | Space or W | F | G |
| **Player 2 (keyboard)** | Arrow keys | Enter or Up | K | L |
| **Gamepad** | Stick or D-pad | A | X | B |
| **Touch (phone)** | On-screen pad | Up | Attack | Special |

- **Direction + attack changes your move.** Neutral, side, up and down each do something different, on the ground and in the air.
- **Arrows below mean a direction:** ↔ = side (A/D) · ↑ = up (W) · ↓ = down (S). On a gamepad that's the stick or D-pad. Example: **↔+G** = hold left or right and press G for a side special.
- **Drop through a platform:** tap down while standing on an upper platform.
- **Pause:** Esc (keyboard). Gamepads don't have a pause button yet.
- **Rematch:** press R after a winner is shown.
- **Dev Mode:** Options → Dev Mode shows move text and unlocks everyone.
- **Players 3 and 4** need their own gamepads. Plug controllers in **before** you launch the game.
- There's no universal shield. Some fighters have their own defensive specials instead.

## Ledges

Teknium, Doge Man and TurboFit grab ledges automatically.
- **↑** or **toward the stage:** climb up
- **Space:** jump off
- **↓** or **away:** let go
- After 4 seconds you drop, and a hit knocks you off.

## Fighters

Moves below use Player 1 keys (F = basic, G = special).

**⚡ Teknium**
- F: jab → straight → scoop kick
- G: Laser Blast. A warning line, then the beam. Works in the air. A fresh jump or fresh G press before the white flash cancels. No stored charge: every use starts fresh; holding G does not extend the warning line or cancel the move.
- Grounded ↓+F: planted low sweep. Airborne ↓+F: descending stamp (provisional motion, awaiting art review).
- ↔+G: Shadow Kick · ↑+G: aimed recovery
- ↓+G: remote grenade. Press ↓+G again to detonate.

**🐕 Doge Man**
- F: 6-hit boxing combo. Keep tapping F.
- Grounded neutral G: Super Doge Punch. Tap to start a committed windup and punch; no hold-charge or voluntary early cancel. Hits and other interruptions can stop it.
- Grounded ↓+F: cape attack, not the historical Tyson route.
- ↔+G: flying tackle
- ↑+G: Air Doge. A Jordan-style leap that catches an opponent and spikes them down. Afterwards he falls helpless until he lands or grabs a ledge.
- ↓+G: finite counter. Get hit during the flash and he answers with a hook.

**🐝 GGB**
- Five jumps; hold jump to float down slowly
- F: double chomp · ↔+F: short sting · G: sticky goo
- ↔+G: Wing Gust. Tap to shove, hold to blow them away. No damage.
- ↑+G: wing rise / flip / dive / ripple
- ↓+G: Steel form. Up to 3 s, 40% damage resistance, and any hit breaks it.

**🎸 TurboFit**
- G: charged power chord · ↔+G: sound wave
- Grounded ↓+G: Sound Orb. Hold both Down and Special to sustain the orb and guitar performance. Release either button to end it; interruption or leaving the ground also ends the held orb. It pushes nearby opponents and reflects reflectable projectiles, not universal melee invulnerability.
- ↑+G: Snapline grapple recovery

**🥊 Bobo**
- G: Charge Blast (hold, then release) · ↔+G: Rocket Dash
- ↑+G: Thruster Rise recovery
- Grounded ↔+F: Thrust Slash · grounded ↓+F: Low Claw
- Airborne ↓+F: dedicated down-air. This is a basic attack, not a Down-special; Bobo has no ↓+G move.

**🌘 Mephisto**
- Grounded ↓+F: low basic attack · airborne ↓+F: Meteor Heel. Ground and air basics use the regular companion kit.
- G: barrier / reflect · ↔+G: steerable sleep ember
- ↑+G: paired teleport
- ↓+G: Dream Hand (called Dream Grasp in older builds). Her shadow guardian reaches out and lulls the opponent to sleep.

See [current Mephisto design](docs/MEPHISTO_CURRENT_DESIGN.md) for candidate installation status and the separate Boss_Meph presentation direction. Installed routing does not mean final approval of every basic or a naturally completed Story run.

**🦆 Witcheer**
- Grounded F: cane swipe · ↑+F: rising cane · ↓+F: low cane poke. Grounded ↔+F remains a kick.
- On solid ground, hold Down to crouch and release it to rise. Use a fresh F press for the poke; holding F does not repeat it. On pass-through platforms, Down drops first, before the attack routes. These cane mappings are grounded basics, not replacements for the aerial kit.
- ↔+G: coin toss · ↑+G: swim recovery · ↓+G: absorb
- Focused cane idle/airborne lifecycle checks pass; exhaustive matchup and physical-device coverage is not claimed.

**❄️ Ice Mage** (CPU only, Story mode)
- Frost Bolt · Frost Rise

## Modes

- **Versus:** up to 4 slots. Each can be a human, a CPU (easy / normal / hard) or empty. Everyone has 3 stocks. Teams need at least 3 fighters, and friendly fire is off.
- **Story:** fight through a run of encounters. Clear it to unlock challengers.
- **Heavy Bag:** 15 seconds, one bag. How hard can you hit?

Some fighters start locked. Play the game to unlock them.
