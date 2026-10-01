# Contributing

Keep changes small and readable. Build on Windows with `Build-Setup.ps1`, then run the isolated tests listed in the README. Do not introduce authentication changes without tests for rollback, preserved unrelated fields, case-distinct project keys, and process consent.

UI changes need actual on-screen checks at common Windows scaling levels; `DrawToBitmap` alone can miss native painting defects. Check normal, hover, pressed, keyboard focus, and scrolling with demo accounts. Do not switch real accounts or terminate real Claude sessions during automated tests.

Use fake OAuth strings in fixtures. Do not upload credentials, account snapshots, cache files, personal process metrics, real user data, or access tokens in logs. Report only sanitized error/status information.

The usage endpoint and Claude Code storage format are internal and version-sensitive. Document assumptions and preserve existing user settings/history.
