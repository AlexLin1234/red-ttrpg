"""The helper as Godot actually runs it: a process, a pipe, and a port."""

from __future__ import annotations

import json
import socket
import subprocess
import sys
import time
from pathlib import Path

import httpx
import pytest

from assistant.service import TOKEN_HEADER

TOKEN = "process-test-token-0123456789abcdef"
REPO_ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def helper(private_home):
    """Start the helper the way Godot does and hand back its port."""

    process = subprocess.Popen(
        [sys.executable, "-m", "assistant"],
        cwd=REPO_ROOT,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env={
            "PATH": "/usr/bin:/bin",
            "PYTHONPATH": str(REPO_ROOT),
            "REDLINE_ASSISTANT_HOME": str(private_home),
            "HOME": str(private_home),
        },
    )
    try:
        process.stdin.write(TOKEN + "\n")
        process.stdin.flush()
        handshake = json.loads(process.stdout.readline())
        yield process, handshake
    finally:
        if process.poll() is None:
            process.kill()
        process.wait(timeout=10)


def test_the_handshake_names_a_port_and_the_helper_answers_on_it(helper):
    process, handshake = helper

    assert handshake["ready"] is True
    assert 1024 < handshake["port"] <= 65535

    response = httpx.get(f"http://127.0.0.1:{handshake['port']}/health", timeout=10)
    assert response.json()["name"] == "redline-assistant"
    assert process.poll() is None


def test_the_token_never_appears_on_the_command_line(helper):
    process, _handshake = helper

    command_line = Path(f"/proc/{process.pid}/cmdline")
    if not command_line.exists():  # pragma: no cover - not Linux
        pytest.skip("process arguments are only readable this way on Linux")

    assert TOKEN not in command_line.read_bytes().decode("utf-8", "ignore")


def test_a_request_without_the_token_is_refused_over_the_socket(helper):
    _process, handshake = helper
    base = f"http://127.0.0.1:{handshake['port']}"

    assert httpx.get(f"{base}/library", timeout=10).status_code == 401
    assert (
        httpx.get(f"{base}/library", headers={TOKEN_HEADER: TOKEN}, timeout=10).status_code == 200
    )


def test_the_helper_is_not_reachable_from_the_network_interface(helper):
    _process, handshake = helper
    try:
        address = socket.gethostbyname(socket.gethostname())
    except OSError:  # pragma: no cover - depends on the host
        pytest.skip("this machine has no resolvable hostname")
    if address.startswith("127."):  # pragma: no cover - depends on the host
        pytest.skip("this machine has no non-loopback address to try")

    with pytest.raises(OSError):
        with socket.create_connection((address, handshake["port"]), timeout=2):
            pass


def test_closing_the_pipe_shuts_the_helper_down(helper):
    process, _handshake = helper

    process.stdin.close()

    deadline = time.monotonic() + 15
    while process.poll() is None and time.monotonic() < deadline:
        time.sleep(0.1)
    assert process.poll() is not None, "the helper outlived Redline"


def test_the_helper_refuses_to_bind_anywhere_but_loopback():
    result = subprocess.run(
        [sys.executable, "-m", "assistant", "--host", "0.0.0.0"],
        cwd=REPO_ROOT,
        input=TOKEN + "\n",
        capture_output=True,
        text=True,
        timeout=60,
        env={"PATH": "/usr/bin:/bin", "PYTHONPATH": str(REPO_ROOT)},
    )

    assert result.returncode != 0
    assert "loopback" in result.stderr
