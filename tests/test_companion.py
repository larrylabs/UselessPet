import asyncio
import json
import random
import stat
import subprocess
import sys
import time

import pytest
from uselesspet.client import ready, request
from uselesspet.config import Settings
from uselesspet.daemon import running_service
from uselesspet.engine import COMPANIONS, REACTIONS, CommandError, Engine
from uselesspet.launcher import environment, stop
from uselesspet.persistence import instance_lock
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed, InvalidStatus


def test_reactions_are_varied_and_selection_survives_restart(settings):
    engine = Engine(settings, rng=random.Random(12))
    reactions = [engine.apply({"type": "cmd.pet"})["payload"]["reaction"] for _ in range(25)]
    assert all(a != b for a, b in zip(reactions, reactions[1:]))
    assert all(set(reactions[n : n + 5]) == set(REACTIONS) for n in range(0, 25, 5))
    for chosen in COMPANIONS:
        engine.apply({"type": "cmd.switch_species", "args": {"species_id": chosen}})
        engine.save()
        assert Engine(settings).snapshot()["species_id"] == chosen
    before = dict(engine.state)
    event = engine.apply({"type": "cmd.switch_species", "args": {"species_id": chosen}})
    assert event["payload"]["reason"] == "no_op"
    assert engine.state == before
    assert stat.S_IMODE(settings.state_file.stat().st_mode) == 0o600


@pytest.mark.parametrize(
    "command",
    [
        {"type": "cmd.feed"},
        {"type": "cmd.pet", "args": {"amount": 5}},
        {"type": "cmd.pet", "args": []},
        {"type": "cmd.switch_species", "args": {"species_id": []}},
        {"type": "cmd.switch_species", "args": {"species_id": "unknown"}},
    ],
)
def test_bad_commands_preserve_state(settings, command):
    engine = Engine(settings)
    before = dict(engine.state)
    with pytest.raises(CommandError):
        engine.apply(command)
    assert engine.state == before


@pytest.mark.parametrize(
    "raw", ["not json", "[]", '{"schema_version":2}', '{"schema_version":1,"species_id":[]}']
)
def test_corrupt_state_is_preserved(settings, raw):
    settings.state_dir.mkdir()
    settings.state_file.write_text(raw)
    with pytest.raises(ValueError):
        Engine(settings)
    assert settings.state_file.read_text() == raw


def test_instance_lock_releases_without_deleting_inode(settings):
    with instance_lock(settings.state_dir, ".test.lock"):
        with pytest.raises(RuntimeError):
            with instance_lock(settings.state_dir, ".test.lock"):
                pytest.fail("second owner acquired lock")
    with instance_lock(settings.state_dir, ".test.lock"):
        pass


async def test_bridge_authentication_broadcast_and_restart(settings):
    async with running_service(settings):
        token = settings.token_file.read_text().strip()
        assert stat.S_IMODE(settings.token_file.stat().st_mode) == 0o600
        for headers, origin, code in [
            ({}, None, 401),
            ({"Authorization": "Bearer wrong"}, None, 401),
            ({"Authorization": f"Bearer {token}"}, "https://example.com", 403),
        ]:
            with pytest.raises(InvalidStatus) as caught:
                async with connect(
                    settings.url, additional_headers=headers, origin=origin, proxy=None
                ):
                    pass
            assert caught.value.response.status_code == code
        headers = {"Authorization": f"Bearer {token}"}
        async with (
            connect(settings.url, additional_headers=headers, proxy=None) as first,
            connect(settings.url, additional_headers=headers, proxy=None) as second,
        ):
            for client in (first, second):
                assert json.loads(await client.recv())["service"] == "UselessPet"
            await first.send(
                json.dumps({"type": "cmd.switch_species", "args": {"species_id": "mochi"}})
            )
            for client in (first, second):
                assert json.loads(await client.recv())["type"] == "event.species_changed"
                assert json.loads(await client.recv())["state"]["species_id"] == "mochi"
            for malformed in ["[1,2]", "{", '{"type":"cmd.pet","args":null}']:
                await first.send(malformed)
                assert json.loads(await first.recv())["type"] == "command.error"
            await first.send("x" * 5000)
            with pytest.raises(ConnectionClosed):
                await first.recv()
        assert await ready(settings)
    assert not settings.token_file.exists()
    async with running_service(settings):
        assert settings.token_file.read_text().strip() != token
        assert (await request(settings))["state"]["species_id"] == "mochi"


async def test_port_conflict_does_not_replace_token(settings, tmp_path):
    async with running_service(settings):
        token = settings.token_file.read_text()
        other = Settings(tmp_path / "other-state", port=settings.port)
        with pytest.raises(OSError):
            async with running_service(other):
                pytest.fail("port conflict accepted")
        assert settings.token_file.read_text() == token
        assert not other.token_file.exists()


def test_source_launcher_owns_and_cleans_up_daemon(settings, tmp_path):
    # A short-lived stand-in exercises real process startup and graceful shutdown.
    overlay = tmp_path / "test-overlay"
    overlay.write_text("#!/bin/sh\nsleep 1\n")
    overlay.chmod(0o700)
    completed = subprocess.run(
        [sys.executable, "-m", "uselesspet", "run", "--overlay", str(overlay)],
        env=environment(settings),
        capture_output=True,
        text=True,
        timeout=25,
    )
    assert completed.returncode == 0, completed.stderr
    assert settings.state_file.exists()
    assert not settings.token_file.exists()
    assert not asyncio.run(ready(settings))


def test_launcher_preserves_manually_started_service(settings, tmp_path):
    daemon = subprocess.Popen(
        [sys.executable, "-m", "uselesspet", "daemon"], env=environment(settings)
    )
    try:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and not asyncio.run(ready(settings)):
            time.sleep(0.1)
        assert asyncio.run(ready(settings))
        overlay = tmp_path / "test-overlay"
        overlay.write_text("#!/bin/sh\nexit 0\n")
        overlay.chmod(0o700)
        result = subprocess.run(
            [sys.executable, "-m", "uselesspet", "run", "--overlay", str(overlay)],
            env=environment(settings),
            timeout=15,
        )
        assert result.returncode == 0
        assert daemon.poll() is None
        assert asyncio.run(ready(settings))
    finally:
        stop(daemon)
