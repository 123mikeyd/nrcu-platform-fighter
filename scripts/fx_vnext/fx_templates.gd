extends RefCounted
# NRCU FX Lab vNext — Add Layer templates (specs/02 §8).
#
# UI sugar only: every template produces a real SOURCE_COPY or FX layer with
# sensible neutral-ish defaults and the correct underlying type. No new schema
# types, no hidden fields.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

const TEMPLATES := ["Source Copy", "Outer Halo", "Edge Treatment", "RGB Tear", "Dither Treatment", "Custom FX Layer"]

static func template_layer(template: String) -> Dictionary:
	match template:
		"Source Copy":
			var copy := FxLookScript.new_layer("SOURCE_COPY", "Source Copy")
			copy["plane"] = "TARGET_UNDERLAY"
			return copy
		"Outer Halo":
			var halo := FxLookScript.new_layer("FX", "Outer Halo")
			halo["input"] = "ORIGINAL_SOURCE"
			halo["mask"] = _mask(true, "ORIGINAL_SOURCE_ALPHA", "OUTER_BAND", 6.0, 3.0)
			halo["fx"] = {
				"fringe": 1.0, "intensity": 1.2, "edge_width": 8.0,
				"wind_reach": 40.0, "wind_trail": 1.0, "fringe_bleed": 1.0,
			}
			return halo
		"Edge Treatment":
			var edge := FxLookScript.new_layer("FX", "Edge Treatment")
			edge["input"] = "ORIGINAL_SOURCE"
			edge["mask"] = _mask(true, "ORIGINAL_SOURCE_ALPHA", "EDGE_BAND", 2.0, 2.0)
			edge["fx"] = {
				"fringe": 1.0, "intensity": 1.0, "edge_width": 12.0,
				"wind_reach": 24.0, "wind_trail": 0.35, "color_blur": 1.0,
			}
			return edge
		"RGB Tear":
			var rgb := FxLookScript.new_layer("FX", "RGB Tear")
			rgb["input"] = "ORIGINAL_SOURCE"
			rgb["fx"] = {"rgb": 1.0, "intensity": 1.0, "rgb_shift_amount": 12.0}
			return rgb
		"Dither Treatment":
			var dither := FxLookScript.new_layer("FX", "Dither Treatment")
			dither["input"] = "ORIGINAL_SOURCE"
			dither["fx"] = {"dither": 1.0, "intensity": 1.0, "dither_levels": 6.0, "dither_pixel": 2.0, "dither_space": 2.0}
			return dither
		"Custom FX Layer":
			var custom := FxLookScript.new_layer("FX", "Custom FX Layer")
			custom["input"] = "ORIGINAL_SOURCE"
			return custom
	return FxLookScript.new_layer("FX", "Custom FX Layer")

static func _mask(enabled: bool, source: String, region: String, width_px: float, feather_px: float) -> Dictionary:
	var mask := FxLookScript.neutral_mask()
	mask["enabled"] = enabled
	mask["source"] = source
	mask["region"] = region
	mask["width_px"] = width_px
	mask["feather_px"] = feather_px
	return mask
