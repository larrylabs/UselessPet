"""An installed Dev app's service exits when its native parent exits or crashes."""

import argparse
import asyncio
import os
import signal

from .config import Settings
from .daemon import running_service


async def run(settings: Settings, parent: int) -> None:
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for signum in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(signum, stop.set)
    try:
        # Refuse an orphaned launch before opening a socket or changing discovery data.
        if parent <= 1 or os.getppid() != parent:
            raise RuntimeError("The Dev app is no longer running")
        async with running_service(settings):
            while os.getppid() == parent and not stop.is_set():
                try:
                    await asyncio.wait_for(stop.wait(), timeout=0.5)
                except TimeoutError:
                    pass
    finally:
        for signum in (signal.SIGINT, signal.SIGTERM):
            loop.remove_signal_handler(signum)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parent", type=int, required=True)
    args = parser.parse_args()
    asyncio.run(run(Settings.from_environment(), args.parent))


if __name__ == "__main__":
    main()
