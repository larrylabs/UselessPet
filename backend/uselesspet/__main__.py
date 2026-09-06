"""Entry points for make targets and optional terminal interaction."""

import argparse
import asyncio
import json
import logging
from pathlib import Path

from websockets.exceptions import WebSocketException

from . import __version__, client, daemon, launcher
from .config import Settings
from .engine import COMPANIONS


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="uselesspet", description="Completely useless. Surprisingly good company."
    )
    parser.add_argument("--version", action="version", version=f"UselessPet {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("daemon", help="run the local companion service")
    sub.add_parser("status", help="show the current companion")
    sub.add_parser("pet", help="say hello to your companion")
    switch = sub.add_parser("switch", help="choose a companion")
    switch.add_argument("companion", choices=COMPANIONS)
    run = sub.add_parser("run", help="run the built native view and its local service")
    run.add_argument("--overlay", type=Path, required=True)
    args = parser.parse_args()
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s: %(message)s")
    try:
        settings = Settings.from_environment()
        if args.command == "daemon":
            asyncio.run(daemon.run(settings))
            return 0
        if args.command == "run":
            return launcher.run(settings, args.overlay)
        command = None
        if args.command == "pet":
            command = {"type": "cmd.pet", "args": {}}
        elif args.command == "switch":
            command = {"type": "cmd.switch_species", "args": {"species_id": args.companion}}
        result = asyncio.run(client.request(settings, command))
        print(json.dumps(result["state"], indent=2))
        return 0
    except KeyboardInterrupt:
        return 0
    except (OSError, ValueError, RuntimeError, TimeoutError, WebSocketException) as error:
        parser.exit(1, f"UselessPet: {error}\nStart the companion with make run.\n")


if __name__ == "__main__":
    raise SystemExit(main())
