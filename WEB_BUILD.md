# NRCU browser build

## Current tester prerelease: v0.3-web.4

[Current changes and limits](RELEASE_NOTES_v0.3-web.4.md). Both Windows and Web packages use the same source commit. Use each package's `build.json`, `manifest.json` and release SHA256SUMS for exact sizes and hashes. The pinned Pages archive retains member/type/path/hash validation. Physical phones are not certified.

## Historical combined prerelease: v0.3-web.3

See [combined release notes](RELEASE_NOTES_v0.3-web.3.md) for mobile controls, static menus, Doge counter, Tek kit, verification and exact legacy failures. Godot 4.7.2 Compatibility remains single-threaded; this update enables desktop **and mobile** compressed textures. The PCK is 649,474,048 bytes and WASM 39,514,754 bytes; the public payload is approximately 657.50 MiB. Physical phones are not certified.

The existing deployment workflow pins `v0.3-web.3`, its source commit and archive SHA-256, verifies all members/bytes/hashes and safe paths, then deploys the exact reviewed archive. `build.json` contains the real source commit and `manifest.json` lists the relative artifact hashes. The release archive excludes private evidence and the local handoff manifest. Prior releases remain available. Runtime source matches the tested candidate byte-for-byte; metadata is added outside its unchanged PCK.

## Historical v0.3-web.1 build report

The report below documents the original export only; its sizes, desktop-only input limits, hashes and local verification are not claims about v0.3-web.3. For the current reviewed archive pins, use `.github/workflows/deploy-web.yml` and the new prerelease assets.


This exports the **published v0.3 game**, not a JavaScript recreation or a reduced roster. All gameplay scripts, scenes, fighter assets and native settings remain unchanged. The existing Windows release remains available as the fallback.

## Build

Use **Godot 4.7.2 stable** and the matching official standard export templates. The preset uses Compatibility/WebGL 2, single-threaded WebAssembly, no GDExtensions, desktop texture compression and no service worker. It does not require cross-origin isolation headers.

Official templates:

- Release: https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable
- Archive: https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
- Archive SHA-256: `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`

Install through Godot's Export Template Manager, or extract `templates/web_*.zip` from the verified archive into Godot's `export_templates/4.7.2.stable` directory. Keep the ZIPs zipped. The selected release preset needs `web_nothreads_release.zip`.

From the repository root, with Python 3.11+:

```sh
python tools/export_web.py --godot /path/to/godot --output /path/outside/checkout/nrcu-web
python -m http.server 8873 --bind 127.0.0.1 --directory /path/outside/checkout/nrcu-web
```

Open **http://127.0.0.1:8873/** and click **Play Now**. Do not open `index.html` as a file URL. The build script runs the import and release export, rejects engine error logs, copies third-party notices, and writes `manifest.json` containing actual sizes and SHA-256 hashes. Import/export logs stay alongside (not inside) the publication directory.

The HTML shell is `web/shell.html`; do not edit exported HTML. The startup page defers the large WASM/PCK downloads until the player's click, reports actual byte progress and initialization separately, provides controls and the Windows link, and keeps cancel/reload available during loading. There is no artificial progress animation or claimed instant download.

## Size and hosting

The first measured full export contains:

- Game PCK: **452,818,440 bytes**.
- WASM: **39,514,754 bytes**.
- Startup engine + game payload: about **469.5 MiB**, before transport compression.

This is a large first download and requires substantially more RAM than the compressed assets alone. Localhost load time is not evidence of internet load time. No assets or roster members have been silently removed to make these numbers smaller.

For GitHub Pages, `.github/workflows/deploy-web.yml` downloads the fixed reviewed **v0.3-web.1** release archive, verifies its pinned SHA-256 and source tag, validates every manifest member and safe ZIP paths/types/size, uploads the exact export directory as a Pages artifact, and deploys it. It does not rebuild or silently replace the tested export. Dispatch only on `main`; the deployment environment is `github-pages`. No personal credentials, paid runners, or committed export binaries are required.

- Reviewed export source: `52a6ccdd1553d3681137888ae13144c78fd6ec9a`.
- Release archive: `NRCU-v0.3-web.1.zip` (348,113,612 bytes).
- Archive SHA-256: `f1e93c6cbd40424ce5491c728da352ad564ff94ff13dd6ea94f2af37765aa2ff`.
- Extracted site: 13 files, 492,776,142 bytes, including the relative-path-only manifest and third-party notices. `index.html` is at the archive root.

Do **not** commit `.pck`, `.wasm`, `.godot`, template archives, caches, or export outputs to Git. Keep exported filenames and relative paths unchanged. WASM/PCK are served from Pages itself, not fetched from Releases at runtime. Serve WASM as `application/wasm` over HTTPS. The site is below Pages' 1 GB site limit, but the roughly 469.5 MiB startup download can consume the 100 GB/month soft bandwidth allowance quickly. Hosting success does not establish hosted gameplay compatibility.

To repeat this deployment, run `gh workflow run deploy-web.yml --ref main`, then check the actual run and live site. Never overwrite the reviewed tag/archive: a changed export requires a new versioned release, new checksums, review, and a workflow update. Keep [Windows v0.3](https://github.com/123mikeyd/nrcu-platform-fighter/releases/tag/v0.3) available. The README Play Now destination is a separate hosted-browser acceptance gate and is not changed by this workflow.

## Browser QA performed

A real hardware-accelerated Chrome 152 headless browser on Windows loaded the release export over HTTP with cross-origin isolation **off**. GPU diagnostics reported NVIDIA GeForce RTX 5060 Ti and enabled WebGL. Actual canvas screenshots, browser network responses and engine logs were inspected, not just the export exit code.

Verified:

- User-gesture loading, title, Enter to home, Story character selection and briefing.
- Teknium movement and attacks; Bobo HP decreased from 400 to 80, then naturally to victory through keyboard input (no forced health/result calls).
- Escape pause/resume, natural result screen, Replay resetting Bobo to 400 HP.
- Return to menus; Smash selection with Doge Man and TurboFit; Sky Temple match.
- The existing `.ogv` cloud video rendered and advanced in the Web export.
- Normal-run console had no engine errors, page exceptions or failed observed requests; engine/WASM/PCK returned HTTP 200.
- Final shell defers data download until Play Now; notice links return 200; injected PCK download failure shows an error and its retry reloads the launch page.

Short Sky Temple sampling gave a median animation-frame interval of 17.2 ms and a 95th percentile of 18 ms on that machine. This is a browser-frame sample, **not** a low-end hardware performance guarantee or a complete gameplay benchmark.

## Limits and remaining release checks

- Verified browser is Chrome on Windows. Edge, Firefox, Safari, macOS, physical controllers and low-memory devices are not yet verified. Desktop keyboard is the supported input target; no touch controls were added.
- Not every fighter/move/stage was exhaustively retested. Published alpha gameplay behavior and existing legacy test failures are unchanged.
- The published source contains **no AudioStreamGenerator, AudioStreamPlayer or AudioStreamWAV usage**. Its frontend event layer explicitly reserves audio for future work; there is no music/combat sound to verify or replace. The sky video is intentionally muted. No procedural-audio workaround was applied unnecessarily. If procedural sound is added later, Godot's default Web Sample mode cannot play it: use `Audio > General > Default Playback Type.web = Stream` or an explicit player Stream mode and test latency.
- Browser storage persistence, blocked cookies/private mode and gamepad mappings vary. Background tabs pause processing.
- An injected WASM fetch abort did not reject Godot's startup promise within 60 seconds. Cancel/reload remains available while waiting, and the Windows fallback remains accessible. A clean normal load and injected PCK failure recovery both pass.
- Final HTTPS-hosted load and network/compression behavior must be checked after publication. Do not describe this local verification as a deployed release.

References: [Godot Web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html), [Web export options](https://docs.godotengine.org/en/stable/classes/class_editorexportplatformweb.html), [custom HTML shell](https://docs.godotengine.org/en/stable/tutorials/platform/web/customizing_html5_shell.html).
