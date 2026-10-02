# Share the project

Copy and adapt these announcements for channels where sharing your project is welcome. They describe the actual app; no stars, usage counts, endorsements or performance promises are assumed.

## English — short

Built a Windows tray app for switching my own Claude Code accounts: active account first, favorites, five-hour/weekly usage limits, and optional cached quota warnings. Browser login and masked OAuth token/API-key import are supported. Open source, MIT, unofficial, Turkish UI.

Repo: https://github.com/denizataes/claude-account-switcher
Setup: https://github.com/denizataes/claude-account-switcher/releases/latest

## English — with context

Using Claude Code with multiple accounts on Windows meant repeating browser logins, so I built a small system tray account switcher. Save your own accounts, pick a favorite, then start plain `claude` from any project.

It shows account-wide five-hour and weekly usage when the service provides it, keeps the active account first, and can warn at 80%/95% using the existing fresh usage cache. It adds no continuous background polling. There is also a masked dialog for your own setup-token, OAuth access token or API key; each route's validation and billing limits are explained in the UI.

It's independent and unofficial, Windows-only, with a Turkish interface and English/Turkish documentation. Saved authentication snapshots use Windows DPAPI; active token routes necessarily live in Claude's plaintext user settings. API keys use API billing, setup-token quotas are unavailable, and quota endpoints are version-sensitive. The installer is unsigned.

Source and screenshots: https://github.com/denizataes/claude-account-switcher
Download: https://github.com/denizataes/claude-account-switcher/releases/latest

## Türkçe — kısa

Kendi Claude Code hesaplarım arasında geçmek için Windows tray uygulaması yaptım: aktif hesap ilk sırada, favoriler, 5 saatlik/haftalık limitler ve önbellekten isteğe bağlı kota uyarıları. Tarayıcı girişi ve maskeli OAuth token/API key ekleme destekleniyor. Açık kaynak, MIT, bağımsız ve resmi olmayan araç.

Repo: https://github.com/denizataes/claude-account-switcher
Kurulum: https://github.com/denizataes/claude-account-switcher/releases/latest

## Türkçe — açıklamalı

Windows'ta birden fazla kendi Claude Code hesabım arasında geçerken tekrar giriş yapmak akışı bölüyordu. Hesapları kaydedip favorileri tray panelinden seçebileceğim bir araç yaptım; sonra herhangi bir projede normal `claude` komutunu kullanıyorum.

Aktif hesap ilk sırada. Servis desteklediğinde hesap genelindeki 5 saatlik/haftalık limitler okunuyor; güncel önbelleğe göre %80/%95 uyarıları açılabiliyor. Sürekli arka plan polling'i eklemiyor. Kendi setup-token, OAuth access token veya API key'inizi maskeli alandan ekleyebilirsiniz; türüne göre doğrulama ve faturalandırma sınırları açıkça belirtiliyor.

Bağımsız, resmi olmayan Windows uygulaması; arayüz Türkçe, belgeler EN/TR. Kayıtlı kimlik bilgileri DPAPI ile korunuyor; etkin token Claude'un kullanıcı ayarlarında açık metin olmak zorunda. API key kullanımı API faturası oluşturur, setup-token için kota bilgisi yoktur ve kullanım endpoint'leri sürüme bağlıdır. Kurulum dosyası imzasızdır.

Kaynak ve görüntüler: https://github.com/denizataes/claude-account-switcher
İndir: https://github.com/denizataes/claude-account-switcher/releases/latest

## Suggested preview

Use [the original project banner](docs/images/hero.svg) or [the neutral demo tray screenshot](docs/images/favorites-alerts.png). Never share real account names, tokens or credentials. The icon/banner are original project artwork, not official Anthropic branding.

The [1280 × 640 PNG social preview](docs/images/social-preview.png) is original repository artwork suitable for a GitHub repository social preview.

## Optional curated-list draft — not submitted

The [awesome-claude-code contribution rules](https://github.com/hesreallyhim/awesome-claude-code/blob/main/CONTRIBUTING.md) currently require active development plus at least 14 days since the first default-branch commit, or 100 stars. This repository's first commit was October 1, 2026 at 15:35:45 Türkiye time. The age condition is not met before **October 15, 2026 after 15:36 Türkiye time**. Recheck the current rules and development status then; no listing or acceptance is claimed.

The maintainers require a human to use their [resource recommendation web form](https://github.com/hesreallyhim/awesome-claude-code/issues/new?template=recommend-resource.yml). Do not submit this via an automated PR/CLI, precheck attestations or claim eligibility now.

Draft fields for later human review:

- Display name: **Claude Code Account Switcher for Windows**
- Category: **Configuration**
- Resource link: https://github.com/denizataes/claude-account-switcher
- Author: **denizataes** — https://github.com/denizataes
- Description (under 500 characters): **Unofficial Windows tray app for switching your own Claude Code accounts. Keeps the active account first, adds favorites, shows cached five-hour/weekly usage when supported, and offers optional quota warnings. Supports browser login and masked OAuth token/API-key import with explicit limitations. Turkish UI, EN/TR docs, MIT, unsigned setup.**

Review every form field and attestation yourself when eligible. This file is a draft, not an external announcement or a submission record.
