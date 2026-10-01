extends PanelContainer
# NRCU FX Lab vNext — plane section drop target (specs/02 §12, matrix Q).
# Dropping a layer row onto a section moves the layer to that composition plane.

var shell
var plane := ""

func _can_drop_data(_pos: Vector2, data) -> bool:
	return data is Dictionary and str((data as Dictionary).get("kind", "")) == "layer"

func _drop_data(_pos: Vector2, data) -> void:
	if shell != null and data is Dictionary:
		shell._drop_layer_on_plane(str((data as Dictionary)["layer_id"]), plane)
