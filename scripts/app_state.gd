extends RefCounted
# Entry flag shared between the frontend scenes and the arena (main.tscn).
# "vs"    = player-facing VS flow (Character Select -> Stage Select -> match)
# "story" = the player-facing Story route (Story Fighter Select/Briefing ->
#           encounter). The Story ROUTE is frontend-owned since WP-0 step 4:
#           MatchFlow hosts it, gameplay never enters it directly.
# "debug" = the old setup screen as a developer launcher (default for direct
#           main.tscn loads, which keeps every existing test unchanged)
static var enter_mode := "debug"

# Story Fighter Select state that has to survive a frontend scene change: the
# briefing's selection is preserved when the route returns to Main and when
# gameplay returns to the flow for the Story Result (Doc 02 §1/§4).
static var story_fighter_id := "turbofit"
