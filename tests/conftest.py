import socket

import pytest
from uselesspet.config import Settings


@pytest.fixture
def settings(tmp_path):
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    return Settings(tmp_path / "state", port=port)
