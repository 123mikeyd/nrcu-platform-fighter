"""Game-adapter evidence gates, complementary to the unchanged independent oracle."""
import argparse
import json
from pathlib import Path
import numpy as np
from analyze_fx_pixels import Gates, pixels, contact_sheet


def run(folder):
    g = Gates()
    manifest = json.loads((folder / "game_manifest.json").read_text())
    g.check("game capture and lifecycle completed", manifest["failures"] == 0, checks=manifest["checks"])
    g.check("five readiness/cover/exit cycles", manifest["cover"] == 5 and manifest["finished"] == 5)
    samples = manifest["lifecycle"]
    g.check("no steady-state node/object/resource growth", len(samples) == 5 and samples[1] == samples[2] == samples[3], samples=samples)
    g.check("no orphan nodes after any exit", all(s["orphans"] == 0 for s in samples))
    doc = manifest["doc"]
    g.check("one artist recipe instance", len(doc["metadata"]["recipe_instances"]) == 1)
    for phase, time in manifest["phases"]:
        game, lab = [pixels(folder, phase + suffix)[..., :3] for suffix in ("_game", "_lab")]
        g.check(phase + " exact Lab/game parity", np.array_equal(game, lab), maximum=float(abs(game-lab).max()))
        for prefix in ("", "timeline_"):
            active, neutral, repeat = [pixels(folder, prefix+phase+suffix)[..., :3] for suffix in ("_game", "_neutral", "_repeat")]
            g.check(prefix+phase+" exact fresh-entry repeat", np.array_equal(active, repeat), maximum=float(abs(active-repeat).max()))
            mad = float(abs(active-neutral).mean())
            # Same .0005 floor as the original independent artist oracle. No relaxed gates.
            g.check(prefix+phase+" neutral/active contract", np.array_equal(active, neutral) if phase in ("pre", "recovery") else mad > .0005, mad=mad, threshold=.0005, time=time)
    phases = [p[0] for p in manifest["phases"]]
    contact_sheet(folder, [(p+"_neutral", p+"_game") for p in phases], "game_frozen_comparison.png")
    contact_sheet(folder, [("timeline_"+p+"_neutral", "timeline_"+p+"_game") for p in phases], "game_timeline_comparison.png")
    contact_sheet(folder, [(p+"_lab", p+"_game") for p in phases], "lab_game_parity.png")
    return g.save(folder / "game_pixel_gates.json")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    raise SystemExit(run(parser.parse_args().folder))
