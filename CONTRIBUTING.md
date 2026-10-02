# Contributing

## Start here

For usage questions, [open a discussion](https://github.com/denizataes/claude-account-switcher/discussions). For a reproducible problem or a concrete improvement, use the [issue templates](https://github.com/denizataes/claude-account-switcher/issues/new/choose). Check existing issues first. Small documentation fixes, translations, accessibility improvements and isolated regression tests are welcome; for larger authentication or architecture changes, discuss the approach before implementing it.

Fork the repository, create a focused branch, and describe the problem, resulting behavior and validation in your pull request. Build and test on Windows PowerShell 5.1; the repository needs no npm dependencies. Follow the commands in the README, including the hotkey tests when changing shortcuts. UI screenshots must use demo accounts and contain no real tokens or account details. State the Windows display scaling used when reporting a visual defect.

Bug reports do not require code or a full diagnostic archive. A short reproduction, expected/actual result, app and Claude Code versions, Windows version and sanitized screenshot are usually enough. Never attach native credential/settings files, DPAPI account snapshots or complete HTTP responses. If an error contains sensitive data, redact it before posting.

Questions in English or Turkish are welcome. / Sorularını İngilizce veya Türkçe yazabilirsin.

Keep changes small and readable. Build on Windows with `Build-Setup.ps1`, then run the isolated tests listed in the README. Do not introduce authentication changes without tests for rollback, preserved unrelated fields, case-distinct project keys, and process consent.

UI changes need actual on-screen checks at common Windows scaling levels; `DrawToBitmap` alone can miss native painting defects. Check normal, hover, pressed, keyboard focus, and scrolling with demo accounts. Do not switch real accounts or terminate real Claude sessions during automated tests.

Use fake OAuth strings in fixtures. Do not upload credentials, account snapshots, cache files, personal process metrics, real user data, or access tokens in logs. Report only sanitized error/status information.

The usage endpoint and Claude Code storage format are internal and version-sensitive. Document assumptions and preserve existing user settings/history.
