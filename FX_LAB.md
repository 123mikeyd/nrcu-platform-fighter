# FX Lab vNEXT and VS screen

The VS screen plays between match setup and gameplay for PLAY launches of
fighters that have VS art (doge_man, ggb, ice_mage, mephisto, teknium,
turbofit, witcheer); Story and other rosters keep the existing route.

The FX Lab vNEXT authoring surface lives in `scenes/nrcu_fx_lab_vnext.tscn`. Its
production output is consumed by the shared resolver/renderer in
`scripts/fx_vnext/` and by the VS presentation adapter; authoring state is
separate from the read-only game consumer. `CLASH_OVERDRIVE` uses semantic
scopes (`ECHO_ONLY` for the vacuum pass and `EXCLUDE_PRIMARY` for impact
speedlines/distortion). The local adapter smoke path is a technical parity
fixture; it is not a substitute for a manual artist review or for testing the
full frontend MatchFlow route.

The live game consumer reads an approved V2 production plan from
`NRCU_FX_DATA_DIR`, else from a locally authored `res://nrcu_fx_data`, else
from the tracked read-only default in `assets/vs/fx/default_production/`, so a
fresh checkout or an export shows the VS screen without any setup. If the
chosen store is present but invalid, the VS adapter fails closed with
`fx_production_unavailable` and gameplay starts on the normal route.

The FX Lab has a deliberate external-workspace launcher, not a
normal Home/MatchFlow menu route:

```text
python tools/fx_review.py --engine <path-to-godot> --workspace <external-review-dir> --scenario CLASH_OVERDRIVE
```

For a local technical review, provide the matching Godot executable explicitly
(or set `GODOT_ENGINE` for the suite runner / `GODOT_BIN` for the review
launcher) and keep captures outside the repository. The runner requires each
suite to emit an explicit `done ... checks=N failures=0` marker; it rejects
parser/runtime errors even when Godot exits with code 0. Review workspaces must
also be outside the checkout (the launcher rejects `./review`, `./evidence`,
and other project subdirectories).

```text
python tools/run_godot_suite.py --engine <path-to-godot-console> --script res://tests/fx_vnext_final_composite_test.gd

# Windows cmd.exe:
set "FX_FINAL_STATIC_ONLY=1" && python tools/run_godot_suite.py --engine <path-to-godot-console> --script res://tests/fx_vnext_final_composite_test.gd --headless

# PowerShell:
$env:FX_FINAL_STATIC_ONLY="1"; python tools/run_godot_suite.py --engine <path-to-godot-console> --script res://tests/fx_vnext_final_composite_test.gd --headless

# POSIX shells:
FX_FINAL_STATIC_ONLY=1 python tools/run_godot_suite.py --engine <path-to-godot-console> --script res://tests/fx_vnext_final_composite_test.gd --headless

python tools/run_godot_suite.py --engine <path-to-godot-console> --script res://tests/fx_vnext_matchflow_route_test.gd
python tools/fx_review.py --engine <path-to-godot> --workspace <external-review-dir> --scenario CLASH_OVERDRIVE
```

The default final-composite check performs mandatory GPU pixel readback and
therefore runs windowed on the Compatibility renderer. `FX_FINAL_STATIC_ONLY=1`
is an explicit static-contract mode for headless CI; it does not replace the
default readback gate.

Generated captures and logs belong in ignored `.verification/` or an external
review workspace; do not use `git add -A` for this project.
