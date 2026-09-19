extends "res://tests/test_collision_authoring_layout.gd"
func run() -> void:
    var lab = load("res://scenes/collision_authoring_lab.tscn").instantiate(); root.add_child(lab)
    check(lab.has_method("serialize_download"), "download serialization independently verifiable")
    if not lab.has_method("serialize_download"): lab.free(); quit(1); return
    lab.open_profile("res://data/collision/generated/teknium.tres")
    var original := FileAccess.get_file_as_bytes(lab.generated_path)
    check(lab.edit_body("0.4","2.1","0","1.1","0"), "body edit before download")
    var h = lab.working.hurtboxes[0]
    check(lab.edit_hurtbox(0,h.bone_name,str(h.radius * 0.9),str(h.height),"1","2","3"), "hurtbox edit before download")
    check(lab.scrub(lab.animation_selector.get_item_text(0),0.2), "scrub before serialization")
    var bytes: PackedByteArray = lab.serialize_download()
    check(not bytes.is_empty(), "download produces actual resource bytes")
    var file := FileAccess.open("user://download_roundtrip.tres",FileAccess.WRITE); file.store_buffer(bytes); file.close()
    var saved = ResourceLoader.load("user://download_roundtrip.tres","",ResourceLoader.CACHE_MODE_IGNORE)
    check(saved.manual_override and saved.hurtboxes[0].manual_override and not saved.override_fields.has("hurtboxes"), "download keeps shared stable-ID manual hurtbox contract")
    check(is_equal_approx(saved.body_radius,0.4) and saved.hurtboxes[0].local_transform.origin == Vector3(1,2,3), "serialized edits survive real resource reload")
    check(saved.provenance.authoring_generated_path == lab.generated_path, "download provenance identifies baseline")
    check(FileAccess.get_file_as_bytes(lab.generated_path) == original, "download never changes baseline")
    check(not lab.download_override(), "native cannot falsely claim browser download")
    lab.free()
    if not failures: print("PASS collision authoring web serialization (native; browser emission pending)")
    quit(1 if failures else 0)
