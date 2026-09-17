extends "res://tests/test_core_collision_lab_ui.gd"

func run() -> void:
    for dimensions in [Vector2i(1280,720), Vector2i(960,540)]:
        root.content_scale_size = Vector2i.ZERO
        root.size = dimensions
        var lab = load("res://scenes/combat_lab.tscn").instantiate()
        root.add_child(lab)
        lab.set_paused(true)
        lab.select_fighter(1, "turbofit")
        for i in 4: await process_frame
        await click(lab.generated_collision_button)
        check(lab.generated_collision_enabled, "real toggle installs tuned draft")
        var notice: Label = lab.generated_collision_label
        check(notice.text.contains("anatomically tuned") and notice.text.contains("DRAFT"), "explicit tuned draft label")
        check(notice.text.contains("all accepted Teknium/Turbo recipient routes"), "no stale air-kicks-only disclosure")
        check(notice.text.contains("teknium_anatomical_v1") and notice.text.contains("turbofit_anatomical_v1") and notice.text.contains("anatomical-v1"), "exact active profile names and balance revision visible")
        check(notice.tooltip_text.contains("res://data/collision/overrides/teknium_anatomical_v1.tres") and notice.tooltip_text.contains("res://data/collision/overrides/turbofit_anatomical_v1.tres"), "exact active override paths inspectable")
        check(lab.find_child("CollisionEditor",true,false).tooltip_text.contains("generated base") and lab.find_child("CollisionEditor",true,false).tooltip_text.contains("not the active merged"), "editor distinction explicit")
        for i in 4: await process_frame
        check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(notice.get_global_rect()), "active identity fits viewport " + str(dimensions))
        check(notice.get_global_rect().end.y <= notice.get_parent().get_parent().get_global_rect().end.y, "identity inside panel")
        await click(lab.collision_snapshot_button)
        check(lab.collision_snapshot_phase == "contact_snapshot", "snapshot control remains mouse accessible with active identity")
        var metadata: Dictionary = lab.get_snapshot().get("active_collision_profiles", {})
        check(metadata.size() == 2, "snapshot publishes both active profile identities")
        if metadata.size() == 2:
            check(metadata[1].revision == "anatomical-v1" and metadata[2].revision == "anatomical-v1", "explicit balance revision separate from install generation")
            check(metadata[1].source_sha256 == load("res://data/collision/generated/teknium.tres").source_sha256, "published source identity")
        lab.set_collision_shapes_visible(true)
        await shortcut(KEY_F2)
        for i in 3: await physics_frame
        if DisplayServer.get_name() != "headless":
            await RenderingServer.frame_post_draw
            check(root.get_texture().get_image().save_png("res://.verification/core/two-fighter-fit-integration/native-%dx%d.png" % [dimensions.x,dimensions.y]) == OK, "native UI evidence")
        check(lab.set_generated_collision_enabled(false), "opt out")
        check(lab.get_snapshot().get("active_collision_profiles", {}).is_empty(), "no stale active tuned identity after optout")
        lab.free()
    if not failures: print("PASS: anatomical draft active identity UI real mouse both viewport sizes")
    quit(1 if failures else 0)
