"""Local paths and connection settings. No remote services are used."""

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    state_dir: Path
    port: int = 17574
    host: str = "127.0.0.1"

    @property
    def state_file(self) -> Path:
        return self.state_dir / "state.json"

    @property
    def token_file(self) -> Path:
        return self.state_dir / "bridge.token"

    @property
    def url(self) -> str:
        return f"ws://{self.host}:{self.port}/"

    @classmethod
    def from_environment(cls) -> "Settings":
        raw_port = os.environ.get("USELESSPET_PORT", "17574")
        try:
            port = int(raw_port)
        except ValueError as error:
            raise ValueError("USELESSPET_PORT must be an integer") from error
        if not 1 <= port <= 65535:
            raise ValueError("USELESSPET_PORT must be between 1 and 65535")
        directory = (
            Path(
                os.environ.get(
                    "USELESSPET_STATE_DIR",
                    Path.home() / "Library" / "Application Support" / "UselessPet",
                )
            )
            .expanduser()
            .resolve()
        )
        return cls(directory, port)
