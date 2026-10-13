extends RefCounted

const CHARACTERS := ["teknium", "doge_man", "ggb", "turbofit", "ice_mage", "witcheer", "mephisto", "bobo"]
const NAMES := ["Teknium", "Doge Man", "GGB", "TurboFit", "Ice Mage", "Witcheer", "Mephisto", "Bobo (Prototype)"]
const DIFFICULTIES := ["easy", "normal", "hard"]
const PLAYER_COLORS := [Color("ed6868"), Color("74b9e5"), Color("edc16d"), Color("8eccad")]
const COSTUMES := {
    "turbofit": ["01", "02", "03", "04"],
    "teknium": ["01", "02", "03", "04"],
    "ggb": ["01", "02", "03", "05", "06", "07"],
    "witcheer": ["01", "02", "03", "04"],
    "bobo": ["01", "02", "03", "04"],
    "doge_man": ["01", "02", "04", "07"],
}

const COSTUME_NAMES := {
    "turbofit": {"01":"Black Russet", "02":"Midnight Indigo", "03":"Tangerine Denim", "04":"Swamp Moss"},
    "teknium": {"01":"Burgundy Charcoal", "02":"Midnight Violet", "03":"Emerald Forest", "04":"Tangerine Eggshell"},
    "ggb": {"01":"Original", "02":"Candy Cyan", "03":"Orchid Pink", "05":"Amber Honey", "06":"Royal Blue", "07":"Warm Berry"},
    "witcheer": {"01":"Burgundy Burnt Oak", "02":"Midnight Violet", "03":"Emerald Forest", "04":"Mango Eggshell"},
    "bobo": {"01":"Dark Cherry", "02":"Mango Tangerine", "03":"Royal Electric", "04":"Icy Pearl Cobalt"},
    "doge_man": {"01":"Original", "02":"Midnight", "04":"Emerald", "07":"Obsidian"},
}

static func costume_name(character: String, costume: String) -> String:
    return COSTUME_NAMES.get(character, {}).get(costume, "Original")

static func costume_portrait(character: String, costume: String) -> String:
    return "res://assets/costume_previews/%s_%s.png" % [character, costume]

static func costume_ids(character: String) -> Array:
    return COSTUMES.get(character, ["01"]).duplicate()

static func default_costume(character: String) -> String:
    return costume_ids(character)[0]

static func valid_costume(character: String, costume: String) -> bool:
    return costume in costume_ids(character)

static func default_slots() -> Array:
    var slots: Array = []
    for i in range(4):
        slots.append({"kind": "human" if i == 0 else "bot", "character": CHARACTERS[i], "costume": default_costume(CHARACTERS[i]), "team": i % 2, "difficulty": "normal", "device": -1})
    return slots

static func validate(slots: Array, teams: bool) -> String:
    if slots.size() != 4:
        return "Configure exactly four slots; unused slots can be Empty."
    var active := 0
    var sides: Array = []
    var devices: Array = []
    for i in range(slots.size()):
        var slot: Dictionary = slots[i]
        if slot.get("kind", "") not in ["empty", "human", "bot"]:
            return "Choose Human, Bot, or Empty for every slot."
        if slot.kind == "empty":
            continue
        active += 1
        if slot.get("character", "") not in CHARACTERS:
            return "Choose a valid character."
        # Legacy callers construct slots without presentation data; they retain
        # the stable default rather than invalidating a match.
        if slot.has("costume") and not valid_costume(slot.character, str(slot.costume)):
            return "Choose a valid costume."
        if slot.get("difficulty", "") not in DIFFICULTIES:
            return "Choose Easy, Normal, or Hard bot difficulty."
        if slot.get("team", -1) not in [0, 1]:
            return "Choose team A or B."
        if slot.team not in sides:
            sides.append(slot.team)
        if slot.kind == "human":
            var device: int = slot.get("device", -1)
            if device < 0 and i > 1:
                return "P3/P4 humans need a connected gamepad; or choose Bot/Empty."
            if device >= 0:
                if device in devices:
                    return "Each human needs a different gamepad."
                if device not in Input.get_connected_joypads():
                    return "Selected gamepad is disconnected."
                devices.append(device)
    if active < 2:
        return "Choose at least two active fighters."
    if teams and (active < 3 or sides.size() < 2):
        return "Teams need at least three fighters and both teams represented."
    return ""
