"""Authenticated loopback WebSocket service for the native companion view."""

import asyncio
import json
import logging
import secrets
import signal
from contextlib import asynccontextmanager
from http import HTTPStatus

from websockets.asyncio.server import ServerConnection, serve
from websockets.exceptions import ConnectionClosed

from .config import Settings
from .engine import CommandError, Engine
from .persistence import atomic_write, instance_lock

logger = logging.getLogger("uselesspet")


class Bridge:
    def __init__(self, engine: Engine, token: str):
        self.engine = engine
        self.token = token
        self.clients: set[ServerConnection] = set()
        self.command_lock = asyncio.Lock()

    def authorize(self, connection, request):
        # Browser connections are rejected, even if they somehow know a token.
        if request.headers.get_all("Origin"):
            return connection.respond(HTTPStatus.FORBIDDEN, "Browser origins are not supported.\n")
        values = request.headers.get_all("Authorization")
        if len(values) != 1 or not secrets.compare_digest(values[0], f"Bearer {self.token}"):
            return connection.respond(HTTPStatus.UNAUTHORIZED, "Local authentication required.\n")
        if request.path != "/":
            return connection.respond(HTTPStatus.NOT_FOUND, "Not found.\n")
        if len(self.clients) >= 8:
            return connection.respond(HTTPStatus.SERVICE_UNAVAILABLE, "Too many local clients.\n")
        return None

    def snapshot(self) -> dict:
        return {"type": "state.snapshot", "service": "UselessPet", "state": self.engine.snapshot()}

    async def send(self, client, value: dict) -> None:
        try:
            await asyncio.wait_for(client.send(json.dumps(value)), timeout=2)
        except (ConnectionClosed, TimeoutError):
            self.clients.discard(client)
            await client.close()

    async def broadcast(self, value: dict) -> None:
        await asyncio.gather(*(self.send(client, value) for client in tuple(self.clients)))

    async def handler(self, client: ServerConnection) -> None:
        self.clients.add(client)
        try:
            async with self.command_lock:
                await self.send(client, self.snapshot())
            async for message in client:
                try:
                    value = json.loads(message)
                    if not isinstance(value, dict):
                        raise CommandError("Messages must be JSON objects")
                    if value.get("type") == "hello":
                        continue
                    async with self.command_lock:
                        event = self.engine.apply(value)
                        self.engine.save()
                        await self.broadcast(event)
                        await self.broadcast(self.snapshot())
                except (ValueError, UnicodeDecodeError):
                    # Do not echo arbitrary input or filesystem details back to clients.
                    await self.send(
                        client,
                        {
                            "type": "command.error",
                            "payload": {
                                "code": "invalid_command",
                                "message": "Unsupported or malformed companion command",
                            },
                        },
                    )
        except ConnectionClosed:
            pass
        finally:
            self.clients.discard(client)


@asynccontextmanager
async def running_service(settings: Settings):
    with instance_lock(settings.state_dir, ".daemon.lock"):
        engine = Engine(settings)
        token = secrets.token_urlsafe(32)
        bridge = Bridge(engine, token)
        async with serve(
            bridge.handler,
            settings.host,
            settings.port,
            process_request=bridge.authorize,
            origins=[None],
            max_size=4096,
            max_queue=16,
            open_timeout=5,
            ping_interval=20,
            ping_timeout=10,
            close_timeout=2,
        ) as server:
            # Only replace discovery data after successfully binding the port.
            engine.save()
            atomic_write(settings.token_file, token + "\n")
            logger.info("UselessPet is ready on its local companion port.")
            try:
                yield server
            finally:
                try:
                    if settings.token_file.read_text().strip() == token:
                        settings.token_file.unlink()
                except FileNotFoundError:
                    pass


async def run(settings: Settings) -> None:
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for signum in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(signum, stop.set)
    try:
        async with running_service(settings):
            await stop.wait()
    finally:
        for signum in (signal.SIGINT, signal.SIGTERM):
            loop.remove_signal_handler(signum)
