"""Run the helper.

Godot launches this process, writes a freshly generated session token to its
standard input, and reads one line of JSON back naming the port the helper is
listening on. Both halves of that handshake stay off the command line, so
neither the token nor anything derived from it appears in a process list.

Closing the pipe shuts the helper down, which is what happens when Redline
exits — including when it crashes — so no orphan is left holding a socket.
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import threading

from assistant import __version__, paths

HOST = "127.0.0.1"
TOKEN_MIN_LENGTH = 16
BACKLOG = 8


def _read_token(stream: "object") -> str:
    line = stream.readline()  # type: ignore[attr-defined]
    token = str(line).strip()
    if len(token) < TOKEN_MIN_LENGTH:
        raise SystemExit("the session token must be at least 16 characters")
    return token


def _watch_for_parent_exit(stream: "object", stop: "object") -> None:
    """Stop the helper when Redline closes the pipe."""

    try:
        while stream.readline():  # type: ignore[attr-defined]
            continue
    except (OSError, ValueError):
        pass
    stop.should_exit = True  # type: ignore[attr-defined]


def serve(token: str, host: str = HOST, port: int = 0) -> None:
    import uvicorn

    from assistant.service import create_app

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((host, port))
    listener.listen(BACKLOG)
    bound_port = listener.getsockname()[1]

    server = uvicorn.Server(
        uvicorn.Config(
            create_app(token),
            log_level="warning",
            access_log=False,
            # Book text and questions must never reach a log file.
            log_config=None,
        )
    )
    # The socket is already listening, so a request sent the instant Godot reads
    # this line waits in the backlog rather than being refused.
    print(json.dumps({"port": bound_port, "version": __version__, "ready": True}), flush=True)
    threading.Thread(target=_watch_for_parent_exit, args=(sys.stdin, server), daemon=True).start()
    server.run(sockets=[listener])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="redline-assistant", description=__doc__)
    parser.add_argument("--version", action="version", version=__version__)
    parser.add_argument(
        "--print-home", action="store_true", help="print the private application-data directory and exit"
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="check that this packaged build can extract, index and search locally",
    )
    parser.add_argument("--host", default=HOST, help=argparse.SUPPRESS)
    parser.add_argument("--port", type=int, default=0, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    if args.print_home:
        print(paths.assistant_home())
        return 0
    if args.self_test:
        return self_test()
    if args.host != HOST:
        raise SystemExit("the assistant helper only ever binds to the loopback interface")

    serve(_read_token(sys.stdin), args.host, args.port)
    return 0


def self_test() -> int:
    """Prove a packaged build works before a Game Master depends on it."""

    import tempfile
    from pathlib import Path

    import pymupdf

    from assistant.extract import Chunk
    from assistant.index import ChunkIndex

    with tempfile.TemporaryDirectory() as directory:
        sample = Path(directory) / "sample.pdf"
        document = pymupdf.open()
        document.new_page().insert_text((72, 100), "Redline helper self test page.", fontsize=11)
        document.save(sample)
        document.close()

        index = ChunkIndex(Path(directory) / "index.sqlite3")
        index.replace_book("selftest", [Chunk("selftest", 1, 0, "Redline helper self test page.")])
        found = index.search_text('"redline"', ["selftest"], 1)
    print(json.dumps({"ok": bool(found), "version": __version__}))
    return 0 if found else 1


if __name__ == "__main__":
    raise SystemExit(main())
