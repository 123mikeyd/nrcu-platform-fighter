extends HBoxContainer
# NRCU FX Lab vNext — layer row with drag support (specs/02 §7/§12, matrix B/Q).
# Rows report drags into the shell; the shell owns the mutation + persistence.

var shell
var layer_id := ""

func _get_drag_data(_pos: Vector2):
	if shell == null:
		return null
	var name: String = str(shell.layer_display_name(layer_id))
	var preview := Label.new()
	preview.text = "  ↗ " + name
	preview.add_theme_color_override("font_color", Color(0.9, 0.68, 0.41))
	var wrap := Control.new()
	wrap.add_child(preview)
	set_drag_preview(wrap)
	return {"kind": "layer", "layer_id": layer_id}

func _can_drop_data(_pos: Vector2, data) -> bool:
	return data is Dictionary and str((data as Dictionary).get("kind", "")) == "layer" and str((data as Dictionary).get("layer_id", "")) != layer_id

func _drop_data(_pos: Vector2, data) -> void:
	if shell != null and data is Dictionary:
		shell._drop_layer_on_layer(str((data as Dictionary)["layer_id"]), layer_id)
