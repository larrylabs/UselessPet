import asyncio
import os
import signal
import subprocess
import sys
import time

from uselesspet.client import ready, request
from uselesspet.launcher import environment, stop


def await_ready(settings, expected=True):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if asyncio.run(ready(settings)) == expected:
            return
        time.sleep(0.1)
    raise AssertionError(f"Service readiness did not become {expected}")


def test_dev_service_quits_cleanly_and_keeps_selection(settings):
    child = subprocess.Popen(
        [sys.executable, "-m", "uselesspet.dev_service", "--parent", str(os.getpid())],
        env=environment(settings),
    )
    try:
        await_ready(settings)
        asyncio.run(
            request(settings, {"type": "cmd.switch_species", "args": {"species_id": "lumi"}})
        )
    finally:
        stop(child)
    assert child.returncode == 0
    await_ready(settings, False)
    assert not settings.token_file.exists()
    assert '"lumi"' in settings.state_file.read_text()


def test_dev_service_exits_after_native_parent_crashes(settings, tmp_path):
    pid_file = tmp_path / "child.pid"
    parent_script = tmp_path / "parent.py"
    parent_script.write_text(
        "import os, subprocess, sys, time\n"
        "from pathlib import Path\n"
        "child = subprocess.Popen([sys.executable, '-m', 'uselesspet.dev_service', "
        "'--parent', str(os.getpid())], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n"
        f"Path({str(pid_file)!r}).write_text(str(child.pid))\n"
        "time.sleep(60)\n"
    )
    parent = subprocess.Popen([sys.executable, str(parent_script)], env=environment(settings))
    try:
        await_ready(settings)
        parent.kill()
        parent.wait(timeout=5)
        await_ready(settings, False)
        assert not settings.token_file.exists()
        assert settings.state_file.exists()
    finally:
        stop(parent)
        if asyncio.run(ready(settings)) and pid_file.exists():
            os.kill(int(pid_file.read_text()), signal.SIGTERM)
