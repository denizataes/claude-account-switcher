<p align="center">
  <img src="Icon-Preview.png" width="64" alt="Claude Account Switcher icon">
</p>

# Claude Code Account Switcher for Windows

**Your Claude accounts, one tray away.** Switch the default Claude Code account, see your five-hour and weekly usage limits, and get back to work.

A small Windows system tray app for developers who use multiple **claude.ai subscription accounts**. Save accounts once, pick a card, then run plain `claude` from any terminal or project. No separate project launcher, no runtime package manager, no copied tokens in your shell history.

![Windows build](https://github.com/denizataes/claude-account-switcher/actions/workflows/windows.yml/badge.svg)

[Download Setup.exe](https://github.com/denizataes/claude-account-switcher/releases/latest/download/Claude-Hesap-Setup.exe) · [Releases](https://github.com/denizataes/claude-account-switcher/releases) · [Türkçe](README.tr.md)

![Claude Code multi-account Windows tray with five-hour and weekly usage meters](docs/images/tray.png)

*Demo accounts and quota fixtures, not real account data. The current application UI is Turkish.*

![Per-user Windows setup with startup, desktop shortcut, and launch options](docs/images/setup.png)

![Setup completion after successful tray initialization](docs/images/setup-complete.png)

*Setup previews use demonstration states. The completion message distinguishes a successful launch from an installed app that could not confirm startup.*

## Why it exists

If you regularly switch between personal and work Claude Code accounts, repeated browser logins interrupt your flow. This multi-account switcher keeps encrypted account snapshots on your own Windows profile and changes the default account for future Claude Code launches.

- **One-click account switching** from the notification area, with any number of saved accounts.
- **Account-wide usage monitoring:** five-hour and weekly percentages **used**, reset times, and countdowns. These are provider quotas, not estimates from one session's token count.
- **A proper Windows setup wizard:** per-user installation, optional autostart, desktop shortcut and launch at completion, no administrator elevation. Upgrades retain existing shortcut preferences unless you change them.
- **Local OAuth storage:** sensitive snapshots use Windows DPAPI `CurrentUser`; credentials are never included in the repository or release package.
- **Clear session confirmation:** switching or adding an account asks before closing verified Claude Code processes. Cancel leaves them running. Importing the current account does not close sessions.
- **Active account first:** the active account appears at the top with a clear badge. Hover the tray icon for its name and cached five-hour usage when available.
- **A warm, compact interface:** rounded account cards, keyboard-accessible buttons, and a scrollable list.

Tooltip updates reuse local metadata and usage caches; hovering adds no network request or timer. If an external Claude login changes the default profile, the tooltip says **Son bilinen** (last known) until opening the panel resolves the current account. Cached usage older than five minutes, past its reset, or affected by a failed request is marked **eski** (old).

## Install and use

Requirements: Windows 10/11, Windows PowerShell 5.1, .NET Framework 4.x, and [Claude Code](https://code.claude.com/docs/en/setup) installed and available as `claude` on `PATH`. The account storage integration was tested against **Claude Code 2.1.286** on Windows.

1. Download **Claude-Hesap-Setup.exe** from [Releases](https://github.com/denizataes/claude-account-switcher/releases).
2. Run the setup wizard and choose startup, desktop-shortcut and immediate-launch options. The executable is **unsigned**, so Windows SmartScreen may show an unfamiliar-app warning; you can inspect and build the source yourself.
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

Other fields—including MCP OAuth credentials, project settings, and history—are preserved. Refreshed outgoing credentials are saved only when the account identity matches. Writes are atomic per file, with an encrypted rollback journal covering native auth fields and the owned settings/ledger route. A failed browser login restores the previous account or token route; the app does not call logout to revoke sessions.

The integration depends on Claude Code's **internal Windows storage format**, which can change. Browser-based Console authentication, cloud-provider overrides, custom authentication helpers, and custom `CLAUDE_CONFIG_DIR` routes are not supported. Conflicting settings are rejected rather than silently switching the wrong route. Later terminal or project overrides can still change which authentication Claude uses. Do not start a new Claude session while a switch or login is in progress.

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

### Setup and update behavior

Version 1.6 stages and validates the complete embedded payload before stopping the app's own tray host. It backs up known app files, owned shortcuts and app registration, then updates files with atomic replacements. Reported installation failures roll those changes back; if rollback itself fails, the backup location is retained and reported. Unknown files in the app folder and account data are not removed. A delayed uninstall helper checks its installation generation so it cannot remove a newer upgrade.

Only a verified tray host is asked to exit. The installer does not close Claude Code sessions. A current account operation blocks an update. The setup log at `%LOCALAPPDATA%\ClaudeAccountSwitcher\setup.log` contains fixed phase/status strings and timestamps, not credentials or HTTP responses.

The installed launcher and startup shortcut use **hidden Windows PowerShell directly**. Successful launch is confirmed by the tray's readiness signal; installation can succeed even if local policy prevents launching it. The completion page explains that case. PowerShell/app-control policies still apply. A forced termination or power loss during an update may require rerunning setup; do not infer a crash-proof transaction guarantee.

For unattended installation:

```powershell
.\Claude-Hesap-Setup.exe /install /quiet
.\Claude-Hesap-Setup.exe /install /quiet /no-launch /no-startup /desktop
```

On upgrades, omitted shortcut flags preserve existing preferences. `/startup` or `/no-startup` and `/desktop` or `/no-desktop` explicitly change them. Exit codes are **0** for installed/launch-confirmed (or launch not requested), **1** for rejected/failed setup, and **2** for installed but launch not confirmed. Quiet mode does not display dialogs. `Install.ps1` and `Kur.bat` delegate to this same setup executable instead of maintaining a separate installer.


### Paste your own token (1.7)

![Masked token dialog with explicit authentication type and local storage notice](docs/images/token-dialog.png)

Use **Token ekle** in the tray panel. Give the record a name, choose its type, and paste into the masked field. Saving does **not** activate it or close Claude; select it later to activate the route for new normal `claude` sessions. Browser login remains available. Nothing reads the clipboard automatically, passes tokens as command-line arguments, or sends model requests for validation.

| Type | Native Claude route | Optional read-only check | Limitations |
| --- | --- | --- | --- |
| `claude setup-token` | `CLAUDE_CODE_OAUTH_TOKEN` in user settings `env` | Format only; shown unverified | Inference-only token, no profile/usage quota; actual expiry unknown |
| OAuth access token | `CLAUDE_CODE_OAUTH_TOKEN` in user settings `env` | Official-host OAuth profile GET verifies account identity when authorized | No refresh token is invented and access tokens are not refreshed; profile validation does not prove model permission; expiry unknown; quota only for profile-validated records when the service supports it |
| Anthropic API key | `ANTHROPIC_API_KEY` in user settings `env` | `/v1/models?limit=1` GET checks key authorization, without inference | **API billing applies to the key owner**, not subscription five-hour/weekly limits; no subscription quota/identity claim |

Checks run asynchronously and can be cancelled; failed checks do not save the record. You can disable the optional check to save an explicitly unverified record. A token-looking prefix proves only its format, not validity. The [documented token routes](https://code.claude.com/docs/en/authentication) and [settings environment support](https://code.claude.com/docs/en/settings) are used; the OAuth profile/usage interfaces are version-sensitive internal endpoints. The public [Models API](https://platform.claude.com/docs/en/api/models/list) is used only for optional API-key validation.

**Storage:** saved token snapshots and the ownership ledger `accounts/route.bin` are protected with Windows DPAPI. The **active token is necessarily plaintext in your own `%USERPROFILE%\.claude\settings.json` `env` block**, because native Claude must read it. User-profile access controls apply; do not share this file, screenshots containing secrets, or account-state files. “DPAPI protected” refers to saved records, not the active native settings file. Each teammate uses their own credentials locally; no central credential collection exists.

The tool owns only the exact key/value recorded in its protected ledger. It refuses to overwrite unrelated or externally modified authentication routes, preserves unrelated settings/credentials, and removes its own token route when a browser account is selected. Protected recovery records cover native credentials, account metadata, the owned settings route and ledger; a conflicting external edit stops recovery safely. Token records have local record IDs, not fabricated account UUIDs. Expired tokens need replacement or normal browser login.
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

Installed shortcuts launch Windows PowerShell with `-STA` and a hidden window; the older VBS launcher remains only as a compatibility source asset. Creating `.lnk` shortcuts uses the Windows shell COM interface. Autostart and script execution must respect your organization's policy.

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

`Claude-Hesap-Setup.exe /test` checks clean install, upgrade, Unicode/space paths, injected failures after staging/files/shortcuts/registry, rollback, quiet rejection, concurrent setup exclusion, generation-safe cleanup, and preservation of unrelated files in isolated temporary directories and a temporary registry key. `UI-Preview.ps1`, `UI-Performance.ps1`, and `Standalone-Test.ps1` are local visual/fixture checks; real on-screen hover, focus, press, scrolling, and DPI checks still belong in release QA.

The tray reuses an unchanged panel, caches JSON by file metadata, and shares disposable fonts/icons. The active-account UI cache retains only the account identity, not the entire project/settings dictionary. Hidden panels do not continuously spawn usage collectors. `UI-Performance.ps1` uses a 12-account fixture with 100 reused open/close cycles and 20 rebuild/dispose cycles, recording first-open time, average cycle latency, GDI objects and handles. Timings vary with JIT, desktop load and hardware; these checks bound resource growth rather than promise universal speedups. Release validation also samples a collector-free installed tray for 60 seconds. No "zero defects" or device-independent performance guarantee is implied.

## Contributing

Bug reports and small focused improvements are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Never attach tokens, credential files, encrypted snapshots, or real account identifiers. Screenshots should use demo labels.

[MIT license](LICENSE) · Made for a calmer multi-account Claude Code workflow.

Metadata stamp implementation uses a fresh .NET FileInfo per call. Three matched 100-call samples had median 17.84ms versus 63.76ms with Get-Item, and about 1.29MB versus 9.60MB allocated. This is a component benchmark, not an overall application speedup claim. No new idle timer or network poll was added.
