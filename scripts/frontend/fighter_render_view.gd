class_name FighterRenderView
extends Control
# Menus use existing offline portraits only. No fighter, world, camera or
# SubViewport is ever constructed, even when callers request LIVE_IDLE.
const Factory = preload("res://scripts/frontend/fighter_presentation_factory.gd")
const Portraits = preload("res://scripts/frontend/portrait_data.gd")
const PROFILE_PORTRAIT = Factory.PROFILE_PORTRAIT
const PROFILE_PLAYER_BAY = Factory.PROFILE_PLAYER_BAY
const PROFILE_RESULTS_HERO = Factory.PROFILE_RESULTS_HERO
const PROFILE_RESULTS_TEAM = Factory.PROFILE_RESULTS_TEAM
const MODE_STATIC_POSE = Factory.MODE_STATIC_POSE
const MODE_LIVE_IDLE = Factory.MODE_LIVE_IDLE
var _ids: Array[String] = []
var _palette := 0
var _subject_palettes: Array = []
var _profile_name = PROFILE_PLAYER_BAY
var _row: HBoxContainer
func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = true
    _rebuild()
func _rebuild() -> void:
    if _row != null:
        remove_child(_row)
        _row.queue_free()
    _row = HBoxContainer.new()
    _row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_row)
    _row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for id in _ids:
        var column := VBoxContainer.new()
        column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        column.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _row.add_child(column)
        var picture := TextureRect.new()
        picture.texture = Portraits.body_texture(id, _palette_for(_ids.find(id)))
        picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
        picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
        column.add_child(picture)
        # No name label here: every host (CSS bay name plate, Story/How-to
        # FighterName, Results rows) already names the fighter.
func set_profile(profile) -> void: _profile_name = Factory.profile_name(profile)
func profile_name() -> String: return _profile_name
func profile_config() -> Dictionary: return Factory.profile_config(_profile_name)
func set_subjects(ids: Array) -> void:
    _ids.clear()
    for id in ids: _ids.append(str(id))
    if is_inside_tree(): _rebuild()
func clear_subjects() -> void: set_subjects([])
func subjects() -> Array[String]: return _ids.duplicate()
func subject_nodes() -> Array[Node3D]: return []
func subject_scripts() -> Array[String]: return []
func get_subject_count() -> int: return _ids.size()
func has_subjects() -> bool: return not _ids.is_empty()
func set_palette(index: int) -> void:
    if index == _palette and _subject_palettes.is_empty():
        return
    _palette = index
    _subject_palettes.clear()
    if is_inside_tree(): _rebuild()
func _palette_for(i: int) -> int:
    if i >= 0 and i < _subject_palettes.size(): return int(_subject_palettes[i])
    return _palette
func palette_index() -> int: return _palette
func set_subject_palettes(indices: Array) -> void:
    _subject_palettes = indices.duplicate()
    if not indices.is_empty(): _palette = int(indices[0])
    if is_inside_tree(): _rebuild()
func set_presentation_mode(_mode) -> void: pass
func presentation_mode() -> int: return MODE_STATIC_POSE
func presentation_mode_name() -> String: return "STATIC_PORTRAIT"
func is_animating() -> bool: return false
func is_live() -> bool: return false
func set_live(_enabled: bool) -> void: pass
func request_render() -> void: pass
func set_sway_enabled(_value: bool) -> void: pass
func set_render_size(_value: Vector2i) -> void: pass
func render_size() -> Vector2i: return Vector2i(size)
func render_target() -> Texture2D:
    return Portraits.body_texture(_ids[0], _palette_for(0)) if not _ids.is_empty() else null
func view() -> SubViewport: return null
func pose_ready() -> bool: return has_subjects()
func frame_model() -> void: pass
func update_mode() -> int: return -1
