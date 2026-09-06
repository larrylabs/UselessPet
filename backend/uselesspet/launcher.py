"""Own the source-run processes and clean them up when the user quits."""

import asyncio
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

from .client import ready
from .config import Settings
from .persistence import instance_lock


def stop(process: subprocess.Popen | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def environment(settings: Settings) -> dict[str, str]:
    return {
        **os.environ,
        "USELESSPET_STATE_DIR": str(settings.state_dir),
        "USELESSPET_PORT": str(settings.port),
    }


def start_daemon(settings: Settings) -> subprocess.Popen:
    process = subprocess.Popen(
        [sys.executable, "-m", "uselesspet", "daemon"],
        env=environment(settings),
        start_new_session=True,
    )
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError(
                    "The daemon could not start. Check for another instance or a port conflict."
                )
            if asyncio.run(ready(settings)):
                return process
            time.sleep(0.15)
        raise RuntimeError("Timed out waiting for the local companion service.")
    except BaseException:
        stop(process)
        raise


def run(settings: Settings, executable: Path) -> int:
    if not executable.is_file():
        raise RuntimeError("The native executable is missing. Run make build first.")
    daemon = None
    overlay = None
    previous_sigterm = signal.getsignal(signal.SIGTERM)

    def interrupted(_signum, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    try:
        with instance_lock(settings.state_dir, ".desktop.lock"):
            if not asyncio.run(ready(settings)):
                daemon = start_daemon(settings)
            overlay = subprocess.Popen(
                [str(executable.resolve())], env=environment(settings), start_new_session=True
            )
            restarts = 0
            while overlay.poll() is None:
                if daemon is not None and daemon.poll() is not None:
                    if restarts >= 3:
                        raise RuntimeError(
                            "The companion service exited repeatedly; please restart make run."
                        )
                    restarts += 1
                    print("Reconnecting to your companion…", flush=True)
                    daemon = start_daemon(settings)
                time.sleep(0.2)
            return overlay.returncode or 0
    except KeyboardInterrupt:
        return 0
    finally:
        stop(overlay)
        stop(daemon)
        signal.signal(signal.SIGTERM, previous_sigterm)
