extends RefCounted
# AppState — the cross-scene channel between the frontend routes and the arena.
#
# It keeps ONLY what the MatchFlow router genuinely cannot own, because the
# router scene does not survive a gameplay launch:
#   * enter_mode — the player-facing entry flag the Main Menu row sets and the
#     router consumes ("vs" | "story" | "debug"). PLAIN modes only: since WP-0
#     step 5 the post-match route no longer rides origin strings such as
#     "vs:results" / "vs:stage" / "story:result:won" (Doc 02 §5 owns route
#     origins as the router's typed origin stack);
#   * story_fighter_id — the Story roster choice, which has to survive the
#     route returning to Main and re-entering the flow;
#   * post_match — the typed post-match hand-off (Doc 02 §4, §5 RETURN):
#     gameplay produces the immutable MatchResult / the story outcome at match
#     resolution and hands it over, the router presents the PostMatch surface.
#
# "vs"    = player-facing VS flow (Character Select -> Stage Select -> match)
# "story" = the player-facing Story route (the Story surface lives in MatchFlow
#           since WP-0 step 4; gameplay never enters it directly)
# "debug" = the old setup screen as a developer launcher (default for direct
#           main.tscn loads, which keeps every existing test unchanged)
static var enter_mode := "debug"

# The MEANINGFUL entry device the Main Menu recorded when the player left for
# the flow (Doc 01 §2 "input seeded from entry device"): "mouse_keyboard" or
# "controller:<pad id>". MatchFlowState.fresh_vs() consumes it to seed P1.
static var enter_device := "mouse_keyboard"

# Story roster choice that survives a frontend scene change (Doc 02 §1/§4).
static var story_fighter_id := "turbofit"

# --- typed post-match hand-off (WP-0 step 5) --------------------------------
# The payload kinds of the RETURN verb. "vs" carries the immutable MatchResult
# (plus the preserved launch snapshot and the resolution context); "story"
# carries the StoryOutcome.
const POST_MATCH_VS := "vs"
const POST_MATCH_STORY := "story"

static var post_match: Dictionary = {}

static func vs_return_payload(result, config, teams: bool, stage: String, slots: Array) -> Dictionary:
    # Built by gameplay at match resolution (Doc 06 §5: MatchResult created ->
    # Frontend/PostMatch takes ownership -> gameplay world torn down).
    #   result  immutable MatchResult snapshot (never a live fighter read)
    #   config  the preserved MatchLaunchConfig the match was launched with
    #           (null for a direct/debug arena start), so REMATCH LAUNCHes the
    #           exact frozen snapshot instead of re-seeded defaults
    #   mode/stage/slots  the resolution context the router restores the setup
    #           state from when no launch snapshot exists
    return {
        "kind": POST_MATCH_VS,
        "result": result,
        "config": config,
        "teams": bool(teams),
        "mode": 1 if teams else 0,
        "stage": str(stage),
        "slots": slots.duplicate(true) if slots is Array else [],
    }

static func story_return_payload(won: bool, encounter_id: String, fighter_id: String, stage: String, config) -> Dictionary:
    # The StoryOutcome (Doc 02 §4): encounter id, the played fighter, won/lost
    # and the preserved story launch snapshot for REPLAY/RETRY.
    return {
        "kind": POST_MATCH_STORY,
        "won": bool(won),
        "encounter_id": str(encounter_id),
        "fighter_id": str(fighter_id),
        "stage": str(stage),
        "config": config,
    }

static func return_to_post_match(payload: Dictionary) -> void:
    post_match = payload

static func has_post_match() -> bool:
    return not post_match.is_empty()

static func take_post_match() -> Dictionary:
    # Consumed by the router on entry; a stale payload can never re-open a
    # finished match.
    var payload := post_match
    post_match = {}
    return payload

static func peek_post_match() -> Dictionary:
    return post_match
