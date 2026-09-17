# Portable source and regeneration recipes

This local experimental PR is based on upstream v0.2. The current acceptance
record and merge gates are in [upstream-pr-preparation.md](upstream-pr-preparation.md).
Older private milestone counts are not acceptance evidence for this tree.

## Requirements and source snapshot

Use Git with materialized Git LFS assets, Python 3.11+, and Godot
`4.7.2.stable.official.ed1daf0bf`. Matching 4.7.2 export templates are needed only
for player exports. Start at the repository root with nonexistent destinations:

```sh
git lfs pull
python3 tools/portable_snapshot.py --repo . \
  --manifest docs/manifests/pr-curated-source.json \
  --target ../nrcu-review-source --engine godot --import-project
python3 ../nrcu-review-source/tools/run_all_tests.py \
  --engine "$(command -v godot)" --timeout 900 --output .verification/full
```

The curated manifest includes current upstream dependencies and all retained
regressions, including the pressure transaction and v0.2 public Ice dispatch
characterizations. [Optional Ice compatibility](OPTIONAL_ICE_COMPATIBILITY.md)
is explicitly incomplete; its authored-helper oracle is not a production parity
fix. The original home scene remains the default. Select the opt-in
frontend explicitly:

```sh
godot --path ../nrcu-review-source res://scenes/experimental_full_game.tscn
```

## Regeneration, not hash-only updates

Run recipes only in a disposable snapshot. Do not regenerate a user's working
copy or overwrite manual balance data:

```sh
godot --headless --path ../nrcu-review-source \
  --script res://tools/author_tek_swing.gd
godot --headless --path ../nrcu-review-source \
  --script res://scripts/tools/generate_character_collisions.gd -- \
  --generate --output=res://.verification/regenerated
```

The v0.2 integration reran the actual imported-mesh profile generator for all
seven profiles. Doge and Mephisto raw source identities changed; their generated
anatomy did not. Witcheer's original presenter changed. Teknium and Turbofit's
previous presenter-only drift was reconciled after proving byte equality of
all generated geometry and metadata except the presenter hash. Their two
anatomical overrides retain every authored dimension and transform, with only
the reviewed generated-profile and presenter identities advanced.

The unchanged Teknium raw GLB still produces the same derived library. Its
canonical imported graph changed only at the albedo and emission texture
`load_path` leaves: upstream now selects `.s3tc.ctex`. The exact new graph is
pinned, not normalized or permitted via a wildcard. Material, hierarchy, bone,
root transform, resource and clip tampering remain rejection cases. Engine or
importer changes remain fail-closed review gates.

## Optional local export

```sh
python3 tools/export_full_game.py --stage ../nrcu-review-source \
  --output ../nrcu-review-web --engine godot
```

This changes only a disposable stage and neither serves nor publishes it. The
Web preset retains all v0.2 original-game JSON filters. The raw manifest contains
28 explicit inputs, including fitted-reaction JSON, Bobo thrust, Witcheer bounds,
source GLBs, generated profiles, manual overrides and the derived library.
ResourceLoader remapping alone does not prove FileAccess/raw-byte availability.
Export and browser/physical-device acceptance are separate from source tests.

## Security and rights

Use a trusted manifest and quiescent user-owned filesystem, never an adversarial
shared directory or privileged account. Inputs are checked for path traversal,
symlinks, forbidden cache/evidence/credential names, case/normalization collisions
and LFS pointer stubs. Raw installer files must not have multiple links. The
snapshot inventory is an unsigned local integrity record, not an attestation.
Ancestor checks have TOCTOU windows; concurrent hostile rename/mount attacks
are outside the contract. Output publication is per-file atomic, not a global
transaction: discard a partially failed disposable stage instead of retrying it.

No private evidence, caches, build/player outputs or LAN host configuration belong
in the source manifest or patch series. Source UIDs and import hooks do.
LF is pinned narrowly for authenticated text resources. Linux checkout-filter
checks are not physical Windows acceptance.

Asset rights, named contributor attribution and the permitted sharing audience
remain unresolved. Existing README/notices are retained. Technical derivation,
local commits and reproducibility do not grant redistribution permission.
