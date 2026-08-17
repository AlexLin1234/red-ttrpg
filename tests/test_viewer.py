from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).parents[1]
VIEWER = ROOT / "viewer" / "new-game-project"


def test_godot_project_has_a_main_scene_and_phase_scenes():
    project = (VIEWER / "project.godot").read_text(encoding="utf-8")
    assert 'run/main_scene="res://scenes/main.tscn"' in project
    for relative in (
        "scenes/main.tscn",
        "scenes/token.tscn",
        "scenes/resolution_card.tscn",
        "scenes/inspector_panel.tscn",
        "scenes/damage_float.tscn",
        "scenes/gunshot_vfx.tscn",
    ):
        assert (VIEWER / relative).is_file(), relative


def test_viewer_exposes_exact_v1_action_bar():
    main = (VIEWER / "scripts" / "main.gd").read_text(encoding="utf-8")
    expected = '["Fire", "Aimed", "Autofire", "Reload", "Move", "Take Cover", "Dodge"]'
    assert expected in main
    assert 'api.resolve_attack(payload)' in main
    assert 'CoverDetector.classify' in main


def test_viewer_calls_stateful_combat_routes():
    client = (VIEWER / "scripts" / "api_client.gd").read_text(encoding="utf-8")
    for route in (
        "/encounter",
        "/resolve",
        "/encounter/reload",
        "/encounter/undo",
        "/encounter/redo",
    ):
        assert f'"{route}"' in client


def test_viewer_fetches_before_seeding_a_demo_encounter():
    main = (VIEWER / "scripts" / "main.gd").read_text(encoding="utf-8")
    assert "api.fetch_session()" in main
    assert 'kind == "fetch" and payload.get("actors", []).is_empty()' in main
    assert "_sync_tokens(actor_map)" in main
    assert '_sync_cover_state(payload.get("covers", {}))' in main


def test_stream_card_and_inspector_meet_minimum_information_contract():
    card_scene = (VIEWER / "scenes" / "resolution_card.tscn").read_text(encoding="utf-8")
    inspector = (VIEWER / "scripts" / "inspector_panel.gd").read_text(encoding="utf-8")
    assert "font_size = 24" in card_scene
    for label in (
        "Seriously Wounded",
        "ARMOR",
        "AMMO",
        "RELEVANT SKILLS",
        "LIFESTYLE",
        "COVER",
    ):
        assert label in inspector


def test_map_upload_zones_and_month_end_use_server_rules():
    main = (VIEWER / "scripts" / "main.gd").read_text(encoding="utf-8")
    client = (VIEWER / "scripts" / "api_client.gd").read_text(encoding="utf-8")
    zone_canvas = (VIEWER / "scripts" / "map_zone_canvas.gd").read_text(encoding="utf-8")
    assert "FileDialog.ACCESS_FILESYSTEM" in main
    assert "api.upload_map(path)" in main
    assert "ImageTexture.create_from_image" in main
    assert 'event.keycode == KEY_M' in main
    assert '"/map/image?filename="' in client
    assert '"/map/zones"' in client
    assert "normalized" in zone_canvas
    assert "_finish_zone" in zone_canvas
    assert '"/encounter/month-end"' in client
    assert "api.close_month()" in main


def test_vfx_are_created_after_resolver_events_return():
    main = (VIEWER / "scripts" / "main.gd").read_text(encoding="utf-8")
    success_handler = main.index("func _on_api_success")
    play_call = main.index("_play_pending_shot", success_handler)
    resolve_call = main.index('if kind == "resolve"', success_handler)
    assert play_call > resolve_call
    vfx = (VIEWER / "scripts" / "gunshot_vfx.gd").read_text(encoding="utf-8")
    for component in ("OmniLight3D", "CylinderMesh", "GPUParticles3D", "Sprite3D"):
        assert component in vfx
