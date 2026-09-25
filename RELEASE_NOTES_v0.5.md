# NRCU v0.5 — consolidated unfinished alpha

## Release target

The Windows and browser releases use `current_game/project.godot`. The earlier root public project is retained as a separate source target. No experimental combat-engine replacement or imported-scene trust bypass is included.

## Included

- Current eight-character freeplay roster, including Bobo, current authored move kits, short-input capture and state coordination.
- Six Story hero choices: Teknium, Doge Man, GGB, TurboFit, Witcheer and Mephisto.
- Seven encounters per run: the Bobo, Ice Mage, Witcheer, GGB, TurboFit, Doge Man, Teknium and historical paired Mephisto catalog skips the selected hero. Mephisto runs end at Teknium; other runs end at the namespaced historical Mephisto boss.
- Explicit route board, briefings, fresh-attempt stocks, current-node retries, pause, final victory and credits.
- Final-success-only saved Battle Lab access. Practice uses current fighters with idle opponents and ordinary combat; R resets damage/stocks. There is no native subprocess dependency.
- Industrial Fortress, playable music hall and meadow, and the retained single-platform Toy Room. Sky remains a legacy freeplay option, outside curated Story.
- Kainan terminal display, licensed industrial material maps and contributor credits.

The local-only background cameo sequence is not part of this public source or release. Quarker's separate experimental combat and collision-authoring applications are also not bundled.

## Verification boundaries

The bounded integration contract covers hero/opponent/world routing, retry/pause/result lifecycle, final-only clearance/reload, current fighter factories, practice mode, basic input/contact and source/resource contracts. Story results in automated coverage are forced production-outcome fixtures; they are not natural full campaign wins. Deeper world tests cover bounded bot approach, moving-platform carry/drop and double-jump crossings, not all-matchup navigation certification.

Source native tests and local exported browser input tests are separate from final package and hosted-site verification. CI keeps the earlier root release contracts and adds a fresh import/contract for the actual v0.5 target plus packaging-tool unit tests. Passing those gates is not a full legacy-suite pass. Historical failed legacy assertions have not been relabeled as successful.

Known limits: unfinished balance/presentation, no natural full-campaign certification, no exhaustive matchup or long-session soak, and no physical controller/phone acceptance. Browser and Windows clearance use separate storage. Browser progress persistence requires browser storage; private modes and cleared site data may not retain it. Mobile emulation does not establish hardware viability.

## Reproduction and notices

See the README for the correct nested project and runner commands. Use matching official Godot 4.7.2 templates. Packaging tooling requires an explicit clean committed source identity, engine/font/asset notices, safe ZIP members and exact hashes; arbitrary pre-existing export bytes do not prove their own source provenance.

Preserve `third_party/Godot-LICENSE.txt`, `Godot-COPYRIGHT.txt`, `OFL-ZillaSlab.txt` and `ASSET-NOTICES.txt` with distributed packages. No blanket reuse license for character artwork is granted.
