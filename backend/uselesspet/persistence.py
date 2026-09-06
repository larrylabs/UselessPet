"""Small atomic files and process locks; existing malformed state is preserved."""

import fcntl
import json
import os
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def read_state(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        if path.stat().st_size > 64 * 1024:
            raise ValueError("state file is too large")
        value = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            raise ValueError("state must be an object")
        return value
    except (OSError, ValueError) as error:
        raise ValueError(
            "Cannot read saved state. The original file has been preserved; "
            "see docs/TROUBLESHOOTING.md before starting fresh."
        ) from error


def save_state(path: Path, state: dict) -> None:
    atomic_write(path, json.dumps(state, indent=2) + "\n")


@contextmanager
def instance_lock(directory: Path, name: str) -> Iterator[None]:
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory / name
    descriptor = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("This UselessPet instance is already running.") from error
        os.ftruncate(descriptor, 0)
        os.write(descriptor, str(os.getpid()).encode())
        yield
    finally:
        # Keep the lock inode: deleting it would permit two concurrent owners.
        os.close(descriptor)
