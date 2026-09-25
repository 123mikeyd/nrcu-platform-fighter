extends RefCounted
class_name FxEvidence

static func _ensure_parent(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())

static func write_text(path: String, text: String) -> bool:
	_ensure_parent(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == text

static func write_json(path: String, value) -> bool:
	return write_text(path, JSON.stringify(value, "  "))

static func save_png(image: Image, path: String) -> bool:
	_ensure_parent(path)
	if image == null or image.save_png(path) != OK:
		return false
	return FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() > 0

static func save_jpg(image: Image, path: String, quality: float = 0.92) -> bool:
	_ensure_parent(path)
	if image == null or image.save_jpg(path, quality) != OK:
		return false
	return FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() > 0
