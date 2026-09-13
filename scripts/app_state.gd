extends RefCounted
# Entry flag shared between the home scene and the arena (main.tscn).
# "vs"    = player-facing VS flow (Character Select -> Stage Select -> match)
# "story" = jump straight into the story selection
# "debug" = the old setup screen as a developer launcher (default for direct
#           main.tscn loads, which keeps every existing test unchanged)
static var enter_mode := "debug"
