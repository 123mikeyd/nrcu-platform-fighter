extends RefCounted

const CHARACTERS := ["teknium", "doge_man", "ggb", "turbofit", "ice_mage", "witcheer", "mephisto", "bobo"]
const NAMES := ["Teknium", "Doge Man", "GGB", "TurboFit", "Ice Mage", "Witcheer", "Mephisto", "Bobo (Prototype)"]
const DIFFICULTIES := ["easy", "normal", "hard"]

static func default_slots() -> Array:
    var slots: Array = []
    for i in range(4):
        slots.append({"kind": "human" if i == 0 else "bot", "character": CHARACTERS[i], "team": i % 2, "difficulty": "normal", "device": -1})
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
