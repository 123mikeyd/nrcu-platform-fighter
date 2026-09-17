extends "res://tests/test_collision_authoring_layout.gd"
func run() -> void:
    var lab = load("res://scenes/collision_authoring_lab.tscn").instantiate(); root.add_child(lab)
    lab.open_profile("res://data/collision/generated/teknium.tres")
    var h = lab.working.hurtboxes[0]
    var radius: float = h.radius * 0.9
    check(lab.edit_hurtbox(0,h.bone_name,str(radius),str(h.height),"1","2","3"), "edit existing hurtbox by stable ID")
    check(lab.save_override("user://review_fixed_override.tres"), "persist editor override")
    var saved = ResourceLoader.load("user://review_fixed_override.tres","",ResourceLoader.CACHE_MODE_IGNORE)
    var merged: Dictionary = lab.generated.merged_with(saved)
    check(merged.errors.is_empty(), "persisted editor override accepted by shared merged_with: " + str(merged.errors))
    if merged.errors.is_empty():
        check(is_equal_approx(merged.profile.hurtboxes[0].radius,radius), "shared merge retains edited radius")
        var builder = load("res://scripts/core/collision/collision_snapshot.gd").new()
        check(builder.configure(merged.profile,merged.profile.source_asset,merged.profile.source_sha256,"editor-review").is_empty(), "shared snapshot config consumes merged override")
        var pose := {}
        for box in merged.profile.hurtboxes: pose[box.bone_name] = Transform3D.IDENTITY
        var revision := {"source_asset":merged.profile.source_asset,"source_sha256":merged.profile.source_sha256,"clip":"Idle","seconds":0.0,"policy":0,"episode_id":"editor-review"}
        var snapshot: Dictionary = builder.build("preview",pose,Transform3D.IDENTITY,revision)
        check(snapshot.get("ok",false), "shared snapshot builds all saved volumes")
        var found := false
        for primitive in snapshot.get("primitives",[]):
            if primitive.id == h.hurtbox_id:
                found = true
                check(is_equal_approx(primitive.radius,radius), "saved radius reaches snapshot primitive")
        check(found, "saved stable hurtbox ID consumed")
    check(lab.reload_override("user://review_fixed_override.tres"), "editor reload uses same standard override")
    var other_bone := ""
    for i in range(lab.skeleton.get_bone_count()):
        if lab.skeleton.get_bone_name(i) != h.bone_name: other_bone = lab.skeleton.get_bone_name(i); break
    check(not lab.edit_hurtbox(0,other_bone,str(radius),str(h.height),"1","2","3"), "reject bone rebind unsupported by shared override contract")
    var outside := ProjectSettings.globalize_path("res://.verification/core/collision-authoring-nav/outside-allowed-roots")
    DirAccess.make_dir_recursive_absolute(outside)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://review_fixed_nested"))
    var directory := DirAccess.open("user://")
    for alias in ["user://review_fixed_alias", "user://review_fixed_nested/alias"]:
        var absolute := ProjectSettings.globalize_path(alias)
        check(directory.create_link(outside,absolute) == OK, "create isolated symlink ancestor fixture")
        var escaped := outside.path_join("escaped.tres")
        if FileAccess.file_exists(escaped): DirAccess.remove_absolute(escaped)
        check(not lab.safe_save_path(alias + "/escaped.tres"), "symlink ancestor not an allowed path: " + alias)
        check(not lab.save_override(alias + "/escaped.tres"), "symlink save fails before ResourceSaver")
        check(not FileAccess.file_exists(escaped), "no writes outside allowed roots")
        DirAccess.remove_absolute(absolute)
        if FileAccess.file_exists(escaped): DirAccess.remove_absolute(escaped)
    var target := outside.path_join("target.tres")
    ResourceSaver.save(lab.working,target)
    var before := FileAccess.get_file_as_bytes(target)
    var leaf := ProjectSettings.globalize_path("user://review_fixed_leaf.tres")
    check(directory.create_link(target,leaf) == OK, "create target file symlink fixture")
    check(not lab.save_override("user://review_fixed_leaf.tres"), "target-file symlink rejected")
    check(FileAccess.get_file_as_bytes(target) == before, "aliased target unchanged")
    DirAccess.remove_absolute(leaf)
    var temporary := ProjectSettings.globalize_path("user://collision_authoring_download.tres")
    if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
    check(directory.create_link(target,temporary) == OK, "create download temporary-file alias")
    check(lab.serialize_download().is_empty(), "download also refuses aliased temporary path")
    check(FileAccess.get_file_as_bytes(target) == before, "download leaves aliased target unchanged")
    DirAccess.remove_absolute(temporary)
    check(not lab.safe_save_path("user://review_fixed_nested/../escape.tres"), "traversal remains refused")
    check(not lab.safe_save_path(lab.generated_path), "generated path remains refused")
    lab.free()
    if not failures: print("PASS collision authoring review fixes")
    quit(1 if failures else 0)
