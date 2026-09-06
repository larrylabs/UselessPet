# Security

Security fixes are currently maintained on `main` for the 0.1 series.

Please use [GitHub's private vulnerability reporting](https://github.com/larrylabs/UselessPet/security/advisories/new) for security issues. Include affected versions, a minimal reproduction, and the expected impact. Do not put authentication tokens or private user data in public issues.

The local service binds only to loopback, authenticates every connection, rejects browser origins, limits incoming message size, and accepts two fixed companion commands. It is designed for a single user on a trusted desktop. It does not protect against malware or another process already running as that user.

Please keep uv, Xcode, macOS, and the locked dependencies up to date. Normal UI and installation problems belong in public issues.
