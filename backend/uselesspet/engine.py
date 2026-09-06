"""Daemon-owned companion selection and voluntary interaction."""

import random
from datetime import datetime, timezone
from typing import Any

from . import persistence
from .config import Settings

COMPANIONS = {"nara": "Nara", "mochi": "Mochi", "pando": "Pando", "lumi": "Lumi"}
REACTIONS = ("joy", "delight", "surprise", "silly", "cuddle")


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


class CommandError(ValueError):
    """A client command is outside the public companion protocol."""


class Engine:
    def __init__(self, settings: Settings, *, rng: random.Random | None = None):
        self.settings = settings
        self.rng = rng or random.Random()
        self._bag: list[str] = []
        self._previous: str | None = None
        raw = persistence.read_state(settings.state_file)
        if raw is None:
            self.state = {"schema_version": 1, "species_id": "nara", "born_at": now()}
        else:
            if type(raw.get("schema_version")) is not int or raw["schema_version"] != 1:
                raise ValueError("Unsupported saved-state version; the file has been preserved.")
            if not isinstance(raw.get("species_id"), str) or raw["species_id"] not in COMPANIONS:
                raise ValueError("Unknown saved companion; the file has been preserved.")
            self.state = dict(raw)

    def snapshot(self) -> dict[str, Any]:
        return {**self.state, "species_name": COMPANIONS[self.state["species_id"]]}

    def save(self) -> None:
        persistence.save_state(self.settings.state_file, self.state)

    def apply(self, command: dict[str, Any]) -> dict[str, Any]:
        kind = command.get("type")
        args = command.get("args", {})
        if not isinstance(args, dict):
            raise CommandError("args must be an object")
        if kind == "cmd.pet":
            if args:
                raise CommandError("cmd.pet takes no arguments")
            if not self._bag:
                self._bag = list(REACTIONS)
                self.rng.shuffle(self._bag)
                if self._bag[-1] == self._previous:
                    self._bag[0], self._bag[-1] = self._bag[-1], self._bag[0]
            reaction = self._bag.pop()
            self._previous = reaction
            self.state["last_interaction_at"] = now()
            return {"type": "event.petted", "payload": {"reaction": reaction}}
        if kind == "cmd.switch_species":
            chosen = args.get("species_id")
            if (
                set(args) != {"species_id"}
                or not isinstance(chosen, str)
                or chosen not in COMPANIONS
            ):
                raise CommandError("Choose nara, mochi, pando, or lumi")
            changed = chosen != self.state["species_id"]
            if changed:
                self.state["species_id"] = chosen
                self.state["last_interaction_at"] = now()
            return {
                "type": "event.species_changed",
                "payload": {
                    "species_id": chosen,
                    "changed": changed,
                    **({} if changed else {"reason": "no_op"}),
                },
            }
        raise CommandError("Only cmd.pet and cmd.switch_species are supported")
