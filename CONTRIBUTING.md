# Contributing

Thanks for helping a small, completely useless companion feel a little better.

Useful contributions include reproducible bug reports, localization fixes, accessibility improvements, and gentle interaction ideas. For a substantial feature or dependency, open an issue first so we can agree on scope.

1. Fork the repository and create a branch.
2. Follow the README source setup.
3. Make a focused change. Keep saved-state decisions in the daemon and rendering in the native view.
4. Run `make test`, `make lint`, `make verify-assets`, and, for native changes, `make test-overlay`.
5. For visual changes, attach before/after screenshots from the running app and check light/dark mode. Review all five languages if layout or copy changes.
6. Open a pull request with the problem, resulting behavior, and checks you ran. Say plainly which checks you could not run.

Do not commit local state, authentication tokens, private paths, build outputs, or unrelated assets. Tests must use isolated temporary directories and ports.

Code contributions are under the repository's MIT License. Existing character artwork remains under its separate asset license. For new or modified artwork, explain its source and license, identify modifications, and confirm you have permission to contribute it. Do not add third-party characters without authorization.
