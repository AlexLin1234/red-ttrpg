from __future__ import annotations

import json

import pymupdf
from fastapi.testclient import TestClient

from cprtool.gm.encounter import Encounter
from cprtool.gm.service import create_app
from test_encounter import FakeTables


def png_bytes(width: int = 96, height: int = 64) -> bytes:
    pixmap = pymupdf.Pixmap(pymupdf.csRGB, pymupdf.IRect(0, 0, width, height), False)
    pixmap.clear_with(0x16304AFF)
    return pixmap.tobytes("png")


def test_gm_can_upload_a_map_and_replace_its_normalized_zones(tmp_path):
    app = create_app(encounter=Encounter(FakeTables()), map_directory=tmp_path)
    with TestClient(app) as http:
        assert http.get("/map").json()["available"] is False

        uploaded = http.put(
            "/map/image",
            params={"filename": "warehouse floor.webp"},
            content=png_bytes(),
            headers={"content-type": "application/octet-stream"},
        )
        assert uploaded.status_code == 200
        manifest = uploaded.json()
        assert manifest["available"] is True
        assert manifest["original_name"] == "warehouse floor.webp"
        assert (manifest["width"], manifest["height"]) == (96, 64)
        assert manifest["zones"] == []

        image = http.get("/map/image")
        assert image.status_code == 200
        assert image.headers["content-type"] == "image/png"
        assert image.content.startswith(b"\x89PNG")

        zones = [
            {
                "id": "danger_1",
                "label": "Kill Zone",
                "color": "#ff3f67",
                "opacity": 0.3,
                "points": [[0.1, 0.2], [0.8, 0.2], [0.6, 0.9]],
            }
        ]
        saved = http.put("/map/zones", json={"zones": zones})
        assert saved.status_code == 200
        assert saved.json()["zones"][0]["color"] == "#FF3F67"

    persisted = json.loads((tmp_path / "active_map.json").read_text(encoding="utf-8"))
    assert persisted["zones"][0]["label"] == "Kill Zone"
    with TestClient(create_app(encounter=Encounter(FakeTables()), map_directory=tmp_path)) as http:
        assert http.get("/map").json()["zones"][0]["id"] == "danger_1"


def test_map_routes_reject_bad_images_and_invalid_zone_geometry(tmp_path):
    app = create_app(encounter=Encounter(FakeTables()), map_directory=tmp_path)
    with TestClient(app) as http:
        bad_image = http.put("/map/image", params={"filename": "map.txt"}, content=b"not an image")
        assert bad_image.status_code == 400
        assert "supported raster image" in bad_image.json()["detail"]

        bad_zone = http.put(
            "/map/zones",
            json={
                "zones": [
                    {
                        "id": "outside",
                        "points": [[0, 0], [1.2, 0], [0, 1]],
                    }
                ]
            },
        )
        assert bad_zone.status_code == 400
        assert "normalized coordinates" in bad_zone.json()["detail"]
