<p align="center">
  <img src="Icon-Preview.png" width="64" alt="Claude Account Switcher icon">
</p>

# Claude Code Account Switcher for Windows

**Your Claude accounts, one tray away.** Switch the default Claude Code account, see your five-hour and weekly usage limits, and get back to work.

A small Windows system tray app for developers who use multiple **claude.ai subscription accounts**. Save accounts once, pick a card, then run plain `claude` from any terminal or project. No separate project launcher, no runtime package manager, no copied tokens in your shell history.

[Download Setup.exe](https://github.com/denizataes/claude-account-switcher/releases/latest/download/Claude-Hesap-Setup.exe) · [Releases](https://github.com/denizataes/claude-account-switcher/releases) · [Türkçe](README.tr.md)

![Claude Code multi-account Windows tray with five-hour and weekly usage meters](docs/images/tray.png)

*Demo accounts and quota fixtures, not real account data. The current application UI is Turkish.*

## Why it exists

If you regularly switch between personal and work Claude Code accounts, repeated browser logins interrupt your flow. This multi-account switcher keeps encrypted account snapshots on your own Windows profile and changes the default account for future Claude Code launches.

- **One-click account switching** from the notification area, with any number of saved accounts.
- **Account-wide usage monitoring:** five-hour and weekly percentages **used**, reset times, and countdowns. These are provider quotas, not estimates from one session's token count.
- **A proper Windows setup wizard:** per-user installation, optional autostart and desktop shortcut, no administrator elevation.
- **Local OAuth storage:** sensitive snapshots use Windows DPAPI `CurrentUser`; credentials are never included in the repository or release package.
- **Clear session confirmation:** switching or adding an account asks before closing verified Claude Code processes. Cancel leaves them running. Importing the current account does not close sessions.
- **A warm, compact interface:** rounded account cards, active-account marker, keyboard-accessible buttons, and a scrollable list.

## Install and use

Requirements: Windows 10/11, Windows PowerShell 5.1, .NET Framework 4.x, and [Claude Code](https://code.claude.com/docs/en/setup) installed and available as `claude` on `PATH`. The account storage integration was tested against **Claude Code 2.1.286** on Windows.

1. Download **Claude-Hesap-Setup.exe** from [Releases](https://github.com/denizataes/claude-account-switcher/releases).
2. Run the setup wizard. The executable is **unsigned**, so Windows SmartScreen may show an unfamiliar-app warning; you can inspect and build the source yourself.
3. Open the tray icon. If Windows hides it, expand the notification-area overflow and pin it using Windows taskbar settings.
4. Choose **Mevcut hesabı kaydet** to save the account already logged into Claude Code, or **+ Yeni hesap** to add an account through Claude's normal browser login.
5. Click an account card. If Claude sessions are open, review the confirmation: continuing ends those sessions and can interrupt unsaved work. Terminal windows are not closed.
6. Start `claude` normally from your terminal. Use `/status` inside Claude Code to check the account and authentication method.

Adding an account saves the new login and restores the previously selected default; select the new card when you want to use it. Every teammate signs into their own accounts on their own machine. **Share the installer, not your account-storage folder.**

## How account switching works

This is an **unofficial, independent tool**, not an Anthropic product or an official brand logo. Claude and Claude Code are names of Anthropic products. The icon is an original design.

Claude's [documented multiple-account approach](https://code.claude.com/docs/en/authentication#log-in-with-multiple-accounts) uses separate `CLAUDE_CONFIG_DIR` folders. This app serves a different workflow: changing the global default used by subsequent plain `claude` launches. It merges only:

- `claudeAiOauth` in `%USERPROFILE%\.claude\.credentials.json`;
- `oauthAccount` in `%USERPROFILE%\.claude.json`.

Other fields—including MCP OAuth credentials, project settings, and history—are preserved. Refreshed outgoing credentials are saved only when the account identity matches. Writes are atomic per file, with an encrypted rollback journal covering the pair. A failed browser login restores the previous account; the app does not call logout to revoke sessions.

The integration depends on Claude Code's **internal Windows storage format**, which can change. API-key/Console authentication, cloud-provider overrides, custom authentication helpers, and custom `CLAUDE_CONFIG_DIR` routes are not supported. Conflicting settings are rejected rather than silently switching the wrong route. Later terminal or project overrides can still change which authentication Claude uses. Do not start a new Claude session while a switch or login is in progress.

## Usage limits: real data, honest freshness

The usage monitor makes read-only HTTPS requests to `api.anthropic.com/api/oauth/usage`, the internal endpoint used by the tested Claude Code version. **This is not a stable, publicly documented API contract** and may stop working after provider changes.

- Requests use only your own local OAuth credentials, go to the fixed official host, and do not follow redirects.
- No model messages, purchases, login automation, or token refresh/rotation are used to collect usage.
- Each account has a **minimum five-minute cache interval**; the refresh button respects it.
- HTTP 429 responses apply a shared `Retry-After` backoff. The collector runs for a bounded period, with no continuous polling while the panel is hidden.
- Unknown data is shown as `—`, never fabricated as zero. Errors and expired logins preserve the last known readings with a stale label.

Inactive accounts may need a fresh normal login if their saved access token has expired. The figures are **account-wide**, not per terminal session. Existing Claude [statusline](https://code.claude.com/docs/en/statusline) settings are left alone.

## Local files and uninstalling

| Location | Contents |
| --- | --- |
| `%LOCALAPPDATA%\ClaudeAccountSwitcher\app` | Installed app assets |
| `%LOCALAPPDATA%\ClaudeAccountSwitcher\accounts` | DPAPI-encrypted snapshots and an index containing account labels/identities |
| `%LOCALAPPDATA%\ClaudeAccountSwitcher\usage.json` | Percentages, reset times, status, and cache timestamps; no OAuth tokens |

DPAPI protects snapshots for the current Windows user; it is not a defense against another process already running as that user. The index is not encrypted. Do not upload the user-data folder to Git, cloud drives, or issue reports.

Uninstall from **Windows Settings → Apps**. Uninstall removes app files and shortcuts while preserving saved accounts and the currently selected Claude login. Delete the `accounts` folder separately if you want to remove saved switcher snapshots.

## Build from source

No Node, npm, Python, or downloaded compiler is required. The build uses the .NET Framework C# compiler bundled with Windows and Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Setup.ps1
```

The result is `Claude-Hesap-Setup.exe`. The installer embeds its app payload and visual controls; **the EXE works without companion files**. `VisualControls.dll` is generated for the tray app. Build outputs are ignored by Git.

For a source checkout, build first, then launch the tray without installing:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Claude-Tray.ps1
```

The installed hidden launcher uses Windows Script Host/VBS. If corporate policy disables it, launch the PowerShell script with `-STA` instead. Autostart must respect your organization's policy.

The CLI alternative supports the same saved accounts:

```powershell
.\Claude-Hesap.bat -SaveCurrent -Name "Personal"
.\Claude-Hesap.bat -Add -Name "Work"
.\Claude-Hesap.bat -Select 2
```

## Tests and performance

Core tests use temporary fake user profiles, fake OAuth values, and mocked or dedicated test processes. They do not log into, switch, or stop real Claude sessions.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Smoke-Test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tray-Test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Runtime-Test.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Usage-Test.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Rendering-Test.ps1
```

`Setup.exe /test` validates installation in an isolated temporary directory and temporary registry key. `UI-Preview.ps1`, `UI-Performance.ps1`, and `Standalone-Test.ps1` are local visual/fixture checks; real on-screen hover, focus, press, scrolling, and DPI checks still belong in release QA.

The tray reuses an unchanged panel, caches JSON by file metadata, and shares disposable fonts/icons. In one local **12-account fixture**, 50 reused open/close cycles averaged approximately **44 ms**, with +2 GDI objects and +1 handle; 20 rebuild/dispose cycles finished below the initial GDI count. This is a scoped test result, not a performance guarantee for every machine.

## Contributing

Bug reports and small focused improvements are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Never attach tokens, credential files, encrypted snapshots, or real account identifiers. Screenshots should use demo labels.

[MIT license](LICENSE) · Made for a calmer multi-account Claude Code workflow.
