# Optional core Ice: retained IceStrike, not v0.2 aerial parity

The optional core Ice kit retains **IceStrike for all basic attacks**, including air: .55-second action, .2-second impact, analytic cone contact (8 damage, 3.8 knockback, 2.5 range), without landing cancellation. This remains an explicit prerequisite in `test_core_ice_basics.gd`, `test_core_ice_match_basics.gd` and `test_core_ice_present_source.gd`. It is **not full upstream v0.2 Ice compatibility** and this clarification does not change production behavior.

The unchanged original-game `scripts/fighter.gd` public air dispatch selects different authorities before its IceStrike branch:

| Air aim | Authority / source clip | Declared duration |
| --- | --- | --- |
| Neutral | HumanoidAirBasic / Neutral | .5 s |
| Horizontal | HumanoidAirSide / Superman | 10/24 s |
| Up (including diagonals) | HumanoidAirBasic / Up | .6 s |
| Down (including diagonals) | HumanoidAirBasic / Down | 38/30 s |

Those routes have native-limb contacts, different source-time/payload behavior and landing/status cancellation. Changing the core cooldown alone cannot provide parity. A future production migration needs separately authorized move identities, timing, contacts, presentation, cancellation and input acceptance tests.

## What the tests establish

- `test_core_ice_source.gd` keeps **ground public-dispatch** comparison and every original lock-endpoint, special/cast clock, freeze/shatter/immunity and asset-immutability assertion. Its four airborne aims now explicitly call the unchanged upstream `_start_ice_attack("IceStrike", direction)` helper. Direction is independently derived from source aim/facing rules, not from the core snapshot. Accepted clip, zero source age, .55 duration and successful host acceptance are prerequisites; live source age is compared exactly. This is narrow **authored-helper parity**, not public-air parity. No module is disabled to force dispatch.
- `test_core_ice_v02_dispatch.gd` separately characterizes actual public aerial dispatch: both facings, neutral, left/right, up/down and all four vertical diagonals (18 routes). It asserts the selected module/source and absence of IceStrike, accepted age/duration/direction, and one real authority-hook tick. It is a no-floor manual-hook fixture, not a native-input, landing or damage integration test. Reset cancels an authority but retains its historical age; the unselected module must remain inactive with unchanged age, not fabricated zero age.
- The original source-test RED remains evidence of the public-air compatibility gap, not a production regression repaired by this patch. The helper oracle's GREEN must not be substituted for that unmet requirement. Evidence in `.verification/core/ice-oracle-clarification/REPORT.md` records the reproduced original RED and wrong-identity/extra-tick negative controls.

## Frontend scope

Ice is optional in the core registry/combat lab but **unsupported in the new full-game frontend**. `scripts/experimental/full_game_config.gd` still allowlists only Teknium and Turbofit. Original-game Ice retains upstream v0.2 dispatch. These test/doc changes neither expand the supported roster nor certify a new frontend playtest.

The known installed Ice combat binary/manifest hash discrepancy remains pinned by the source test; neither assets nor manifests are rewritten here.
