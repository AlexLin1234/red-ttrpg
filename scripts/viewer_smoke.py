"""Drive a sample encounter against a running GM service.

Use this to confirm an OBS scene before a stream: it loads two combatants,
fires a few shots, broadcasts a reload, then walks undo and redo so every
region of the viewer draws at least once. It only calls the service's public
routes, so it changes nothing the GM could not do by hand.
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request


ACTORS = {
    "solo": {
        "name": "Rache Bartmoss",
        "max_hp": 40,
        "attack_base": 14,
        "weapons": {
            "Heavy Pistol": {"ammo": 8, "weapon_type": "pistol", "damage_dice": 3, "magazine": 8},
        },
    },
    "goon": {
        "name": "Maelstrom Booster",
        "max_hp": 35,
        "armor": {"body": 7, "head": 7},
        "cover_hp": 6,
        "evasion_base": 10,
        "weapons": {"Very Heavy Pistol": {"ammo": 8, "weapon_type": "pistol", "damage_dice": 4}},
    },
}

ATTACK = {"attacker_id": "solo", "target_id": "goon", "weapon": "Heavy Pistol", "distance_m": 12}


# The GM service is local by definition, so never let an ambient proxy setting
# reroute these calls off the machine.
DIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def post(base: str, path: str, payload: dict | None = None) -> dict:
    request = urllib.request.Request(
        f"{base}{path}",
        data=json.dumps(payload or {}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with DIRECT.open(request) as response:
        return json.loads(response.read().decode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--shots", type=int, default=4)
    parser.add_argument("--pause", type=float, default=2.0, help="seconds between actions")
    arguments = parser.parse_args()

    try:
        post(arguments.base_url, "/encounter", {"actors": ACTORS})
    except urllib.error.URLError as exc:
        raise SystemExit(f"could not reach the GM service at {arguments.base_url}: {exc}")
    print("loaded the sample encounter")
    time.sleep(arguments.pause)

    for shot in range(arguments.shots):
        snapshot = post(arguments.base_url, "/encounter/attack", ATTACK)
        card = snapshot["card"]
        print(f"shot {shot + 1}: {card['title']} ({card['hp_damage']} HP)")
        time.sleep(arguments.pause)

    for path in ("/encounter/reload", "/encounter/undo", "/encounter/redo"):
        payload = {"actor_id": "solo", "weapon": "Heavy Pistol"} if path.endswith("reload") else None
        try:
            post(arguments.base_url, path, payload)
            print(f"{path.rsplit('/', 1)[-1]}: ok")
        except urllib.error.HTTPError as exc:
            print(f"{path.rsplit('/', 1)[-1]}: skipped ({exc.read().decode('utf-8')})")
        time.sleep(arguments.pause)


if __name__ == "__main__":
    main()
