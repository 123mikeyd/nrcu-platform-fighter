extends RefCounted
class_name FxLabUiTokens
## FX Lab-only visual contract. Keep authoring-tool density and popup styling
## separate from the frontend/gameplay token system.

const BG := Color("11141a")
const SURFACE := Color("1a1f28")
const SURFACE_HOVER := Color("252d39")
const SURFACE_PRESSED := Color("303d4d")
const BORDER := Color("3b4654")
const BORDER_FOCUS := Color("e3aa62")
const TEXT := Color("f2eee7")
const TEXT_DIM := Color("aeb7c4")
const TEXT_MUTED := Color("7e8998")
const ACCENT := Color("e3aa62")
const DANGER := Color("e17878")
const BODY_SIZE := 14
const TITLE_SIZE := 16
const META_SIZE := 13
const HELP_SIZE := 12
const HIT_HEIGHT := 32
const HIT_WIDTH := 32
const POPUP_MAX_WIDTH := 360
const POPUP_MAX_HEIGHT := 520

static func _box(fill: Color, border: Color, radius := 4, border_width := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	return box

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = BODY_SIZE
	theme.set_font_size("font_size", "Button", META_SIZE)
	theme.set_font_size("font_size", "Label", BODY_SIZE)
	theme.set_font_size("font_size", "OptionButton", META_SIZE)
	theme.set_font_size("font_size", "MenuButton", META_SIZE)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", TEXT_MUTED)
	theme.set_stylebox("normal", "Button", _box(SURFACE, BORDER))
	theme.set_stylebox("hover", "Button", _box(SURFACE_HOVER, BORDER_FOCUS))
	theme.set_stylebox("pressed", "Button", _box(SURFACE_PRESSED, ACCENT))
	theme.set_stylebox("focus", "Button", _box(SURFACE_HOVER, BORDER_FOCUS))
	theme.set_stylebox("disabled", "Button", _box(BG, BORDER))
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_disabled_color", "Label", TEXT_MUTED)
	theme.set_stylebox("panel", "Panel", _box(BG, BORDER, 4))
	theme.set_stylebox("panel", "PanelContainer", _box(SURFACE, BORDER, 4))
	theme.set_stylebox("normal", "LineEdit", _box(SURFACE, BORDER, 3))
	theme.set_stylebox("focus", "LineEdit", _box(SURFACE_HOVER, BORDER_FOCUS, 3))
	theme.set_stylebox("read_only", "LineEdit", _box(BG, BORDER, 3))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	theme.set_stylebox("normal", "SpinBox", _box(SURFACE, BORDER, 3))
	theme.set_stylebox("focus", "SpinBox", _box(SURFACE_HOVER, BORDER_FOCUS, 3))
	theme.set_stylebox("panel", "TabContainer", _box(BG, BORDER, 3))
	theme.set_stylebox("panel", "TabBar", _box(SURFACE, BORDER, 3))
	theme.set_stylebox("normal", "OptionButton", _box(SURFACE, BORDER))
	theme.set_stylebox("hover", "OptionButton", _box(SURFACE_HOVER, BORDER_FOCUS))
	theme.set_stylebox("pressed", "OptionButton", _box(SURFACE_PRESSED, ACCENT))
	theme.set_stylebox("normal", "MenuButton", _box(SURFACE, BORDER))
	theme.set_stylebox("hover", "MenuButton", _box(SURFACE_HOVER, BORDER_FOCUS))
	theme.set_stylebox("pressed", "MenuButton", _box(SURFACE_PRESSED, ACCENT))
	theme.set_stylebox("panel", "PopupMenu", _box(SURFACE, BORDER, 5))
	theme.set_stylebox("hover", "PopupMenu", _box(SURFACE_HOVER, BORDER_FOCUS, 3))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_color("font_disabled_color", "PopupMenu", TEXT_MUTED)
	theme.set_font_size("font_size", "PopupMenu", META_SIZE)
	theme.set_font_size("font_size", "TooltipLabel", HELP_SIZE)
	theme.set_stylebox("panel", "TooltipPanel", _box(SURFACE, BORDER_FOCUS, 4))
	return theme

static func apply_hit_target(control: Control) -> void:
	if control == null:
		return
	control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, HIT_HEIGHT)
	if control is Button:
		(control as Button).add_theme_font_size_override("font_size", META_SIZE)

static func apply_tool_style(control: Control) -> void:
	if control == null:
		return
	if control is PanelContainer:
		control.add_theme_stylebox_override("panel", _box(SURFACE, BORDER, 4))
	elif control is Panel:
		control.add_theme_stylebox_override("panel", _box(BG, BORDER, 4))
	elif control is LineEdit:
		control.add_theme_stylebox_override("normal", _box(SURFACE, BORDER, 3))
		control.add_theme_stylebox_override("focus", _box(SURFACE_HOVER, BORDER_FOCUS, 3))
		control.add_theme_stylebox_override("read_only", _box(BG, BORDER, 3))
	elif control is SpinBox:
		control.add_theme_stylebox_override("normal", _box(SURFACE, BORDER, 3))
		control.add_theme_stylebox_override("focus", _box(SURFACE_HOVER, BORDER_FOCUS, 3))
	elif control is TabContainer:
		control.add_theme_stylebox_override("panel", _box(BG, BORDER, 3))

static func bound_popup(popup: PopupMenu, viewport_size: Vector2) -> void:
	if popup == null:
		return
	var content := popup.get_contents_minimum_size()
	var bounded := Vector2i(clampi(int(ceil(maxf(content.x, 120.0))), 120, POPUP_MAX_WIDTH), clampi(int(ceil(maxf(content.y, HIT_HEIGHT))), HIT_HEIGHT, POPUP_MAX_HEIGHT))
	popup.min_size = bounded
	popup.max_size = Vector2i(POPUP_MAX_WIDTH, POPUP_MAX_HEIGHT)
	if popup.visible:
		var size := popup.size
		var max_pos := Vector2i(maxi(0, int(viewport_size.x) - size.x), maxi(0, int(viewport_size.y) - size.y))
		popup.position = Vector2i(clampi(popup.position.x, 0, max_pos.x), clampi(popup.position.y, 0, max_pos.y))
