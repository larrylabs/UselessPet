# Privacy

UselessPet runs locally. It has no account system, analytics, advertising, cloud model, or telemetry endpoint.

The app stores your selected companion and basic interaction timestamps in its own local directory. Native preferences store display settings and language. It reads the mouse pointer's position for optional gaze following; those coordinates are not saved or sent elsewhere. The app does not read documents, browser content, messages, email, calendar data, microphone audio, camera video, or screen contents.

The Python service and native view communicate over an authenticated WebSocket bound to `127.0.0.1`. This is traffic inside your computer. The authentication token is stored with user-only file permissions. Software running as your own operating-system user is outside this isolation boundary.

Installing or updating requires connections to GitHub and public package registries. GitHub may load badge images when you view the README. Those services have their own privacy policies; they are not contacted by the running companion.

To remove UselessPet, quit it, delete your clone, and optionally remove its `~/Library/Application Support/UselessPet/` directory and macOS preferences. Back up saved state first if you want to keep your selection. UselessPet does not register a startup service.
