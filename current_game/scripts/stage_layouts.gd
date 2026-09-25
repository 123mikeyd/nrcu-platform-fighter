extends RefCounted
# Single authority for collision bodies and every playable-surface art layer.
# Stable body identities preserve fighter pass-through collision exceptions.
const NAMES = ["MainPlatform", "LeftPlatform", "RightPlatform", "TopPlatform"]
static func surfaces(id: String) -> Array:
    match id:
        "toy_room":
            # One longer combat shelf; background collection shelf is scenery.
            return [[Vector3(0,-0.55,0),Vector3(24,1,5)]]
        "sky":
            # Broad flight deck, two raised side lookouts, ten-unit open center.
            # Equal top heights leave headroom and remain double-jump reachable.
            # The unused TopPlatform body keeps its RID but is hidden/disabled.
            return [[Vector3(0,-0.55,0),Vector3(24,1,5)],
                [Vector3(-7,3.6,0),Vector3(6,0.4,3.8)],
                [Vector3(8,3.6,0),Vector3(4,0.4,3.4)]]
        _:
            return [[Vector3(0,-0.55,0),Vector3(18,1,5)],
                [Vector3(-5.2,3,0),Vector3(5,0.45,3.8)],
                [Vector3(5.2,3,0),Vector3(5,0.45,3.8)],
                [Vector3(0,6,0),Vector3(4.5,0.4,3.4)]]
