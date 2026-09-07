"""Start only the backend and dependencies copied into this Dev app."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from uselesspet.dev_service import main  # noqa: E402

main()
