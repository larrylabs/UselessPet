"""Local authenticated command client, also used for startup readiness."""

import asyncio
import json

from websockets.asyncio.client import connect

from .config import Settings


async def request(settings: Settings, command: dict | None = None) -> dict:
    token = settings.token_file.read_text().strip()
    async with connect(
        settings.url,
        additional_headers={"Authorization": f"Bearer {token}"},
        proxy=None,
        open_timeout=2,
        close_timeout=1,
        max_size=65536,
    ) as socket:
        snapshot = json.loads(await asyncio.wait_for(socket.recv(), 2))
        if snapshot.get("service") != "UselessPet" or snapshot.get("type") != "state.snapshot":
            raise RuntimeError("This port is not serving UselessPet")
        if command is None:
            return snapshot
        await socket.send(json.dumps(command))
        while True:
            event = json.loads(await asyncio.wait_for(socket.recv(), 3))
            if event.get("type") == "command.error":
                raise ValueError("The daemon rejected this companion command")
            if event.get("type") == "state.snapshot":
                return event


async def ready(settings: Settings) -> bool:
    try:
        await request(settings)
        return True
    except (OSError, TimeoutError, ValueError, RuntimeError):
        return False
    except Exception:
        # Handshake rejection means another service or a daemon still starting.
        return False
