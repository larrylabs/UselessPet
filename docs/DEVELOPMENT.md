# Development

UselessPet is a source-run macOS companion. Requirements and the first launch are in the [README](../README.md).

## Layout

- `backend/uselesspet/`: Python daemon, state storage, command client, and process supervisor.
- `overlay/Sources/UselessPet/`: SwiftUI menu panel and RealityKit desktop view.
- `overlay/Sources/UselessPet/Resources/`: four character sets, portraits, and five localizations.
- `tests/` and `overlay/Tests/`: isolated backend and native tests.

The daemon owns selection and reaction choice. The native view renders snapshots and short-lived events; it does not change saved state itself. Idle motion and face animation are presentation behavior.

## Commands

```sh
make setup            # uv sync --locked
make run              # build, start the daemon, launch the native view
make test             # backend, protocol, process lifecycle
make test-overlay     # native unit tests
make lint             # Python static and format checks
make verify-assets    # resource inventory and SHA-256 verification
make qa-console       # light/dark panels in all five languages
make qa-render        # all four characters and reaction samples
```

Keep `DEVELOPER_DIR` set to full Xcode as shown in the README. Native QA requires a logged-in graphical macOS session and writes only to `build/qa/`. Unit tests can run in CI. QA pictures are not a substitute for checking the running desktop app.

Use `make format` for Python formatting. Dependencies are managed with uv; after intentionally changing them, run `uv lock` and `make setup`, then commit both the project file and lockfile. Do not use pip.

For separate processes, run `make daemon` in one terminal and `make overlay` in another. `make status`, `make pet`, and `make switch PET=mochi` talk to that service. A standalone daemon remains yours to stop with Control-C.

## Storage and local connection

The default storage directory is `~/Library/Application Support/UselessPet/`:

- `state.json`: schema version, companion selection, creation time, and last interaction time.
- `bridge.token`: a random authentication token, created on startup with user-only permissions and removed on a clean shutdown.
- `.daemon.lock` and `.desktop.lock`: single-instance locks; the small files can remain after shutdown.

macOS preferences hold language, pet size, cursor following, and desktop position under `io.github.LarryZYN.UselessPet`. There are no imported or migrated settings from other applications.

The WebSocket listens only on `127.0.0.1:17574`. Every connection requires the local token in an Authorization header. Browser origins are rejected. No commands evaluate code or access arbitrary paths.

For a second isolated development instance, set both variables before running any command:

```sh
export USELESSPET_STATE_DIR="$PWD/build/dev-state"
export USELESSPET_PORT=17575
make run
```

Use a dedicated temporary state directory in tests. Do not reset or modify a developer's real pet state. Corrupt or unsupported saved state produces an error and is preserved for recovery.

## Protocol

On an authenticated connection, the daemon sends `state.snapshot` with `service: "UselessPet"` and the current `state`. It accepts only:

```json
{"type":"cmd.pet"}
{"type":"cmd.switch_species","args":{"species_id":"nara"}}
```

The four IDs are `nara`, `mochi`, `pando`, and `lumi`. Successful commands send `event.petted` or `event.species_changed`, followed by a snapshot to connected clients. Invalid commands receive `command.error`. Reaction names are `joy`, `delight`, `surprise`, `silly`, and `cuddle`; a shuffled bag avoids adjacent repeats. Reconnecting restores selection without replaying a previous reaction.

## Release scope

The repository is a standalone source distribution. There is no bundled Python runtime, automatic updater, launch-at-login helper, installer, signing setup, or notarized app. Build outputs and local data are ignored by Git. Automated checks cover Python on Linux and native compilation/tests on macOS; real rendering is checked locally.
