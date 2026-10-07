# ShipNotes

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

[![CI](https://github.com/HuangCodes233/ShipNotes/actions/workflows/ci.yml/badge.svg)](https://github.com/HuangCodes233/ShipNotes/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A native macOS app for preparing and syncing localized App Store release notes, store copy, and screenshots from local files.

**Status: early developer preview.** Build from source and start with the demo account. Signed binary distribution and live service workflows still need verification.

## Features

- **Release notes:** import Markdown, YAML, JSON, and changelogs; map locales, compare changes, and validate drafts before syncing.
- **Store copy:** edit descriptions, keywords, subtitles, promotional text, and store URLs across locales.
- **Screenshots:** scan folders, check device sizes and locale coverage, and preview uploads or replacements.
- **Local drafts and history:** restore edits for each account, app, and version; protect changes during synchronization; search and export history as JSON or CSV. [Behavior and storage](docs/reliability.md).
- **Optional AI:** use your own OpenAI-compatible or Anthropic credentials for parsing, translation, copy optimization, and screenshot language matching.
- **Apple Ads:** view reports and manage campaigns and keywords with separate credentials.
- **Native interface:** English, Simplified Chinese, and Japanese; Liquid Glass on macOS 26 and later, with material fallbacks on older systems.

## Requirements

| Item | Requirement |
| --- | --- |
| Deployment target | macOS 14 or later; runtime behavior on macOS 14/15 still needs verification |
| Build tools | Xcode 26 or later, the macOS 26 or newer SDK, and Swift 6 support |
| Demo account | No Apple or AI credentials required on a fresh installation |
| Live App Store access | Your own App Store Connect API credentials with the necessary app permissions |
| Optional services | Separate AI API keys and Apple Ads credentials |

Use the full Xcode installation. The package has no third-party package dependencies.

## Quick start

Build a local app with ad-hoc signing:

```sh
git clone https://github.com/HuangCodes233/ShipNotes.git
cd ShipNotes
CONFIG=debug SIGN_IDENTITY=- ./scripts/build-app.sh
open dist/ShipNotes.app
```

On the first launch, choose **Explore the demo first**:

1. Select a sample app and an editable version.
2. Open **Release Notes** and import `Examples/release-notes/1.4.0/` as a folder, or `Examples/release-notes/1.5.0.yaml` as a file.
3. Select a locale, edit the draft, inspect the diff, and run **Dry Run**.
4. Explore the store-copy, screenshot, and Apple Ads workspaces.

A configured installation can restore saved credentials and reconnect to live services on launch. Check the connection indicator and selected app/version before syncing.

## Release-note files

Use one Markdown file per locale, such as `1.4.0/en-US.md`, or a YAML/JSON document containing a version and locale map. A YAML example:

```yaml
version: 1.5.0
locales:
  en-US: |
    • Added folder watching.
  zh-Hans: |
    • 新增文件夹监听。
  ja: |
    • フォルダ監視を追加しました。
```

The [example files](Examples/release-notes/) include multilingual Markdown and YAML fixtures. Changelogs and combined metadata documents are also supported; ambiguous imports offer a preview for review.

## Connecting services and privacy

In **Settings → Account**, enter your App Store Connect issuer ID, key ID, and `.p8` private key. Configure AI and Apple Ads separately when needed. Review the destination app, version, locales, and proposed changes before any live write.

Credentials are stored in the macOS Keychain. Preferences, paths, and sync history use local storage. AI operations send input text or screenshot thumbnails to the configured provider; custom endpoints receive that profile's requests and credentials. See [credentials and data flow](docs/privacy-and-data.md) before using private material.

## Development

Open `Package.swift` in Xcode or use SwiftPM. Run formatting checks, functional tests, and whitespace checks together:

```sh
./scripts/check.sh
```

Build and launch the app during development:

```sh
./scripts/run-app.sh
```

The run script defaults to debug/ad-hoc signing and stops an existing ShipNotes process before launching. It also supports `--verify`, `--debug`, `--logs`, and `--telemetry`. The Codex Run action uses the same entry point.

CI tests Xcode 26.3 and Xcode 27, checks Swift formatting on Xcode 27, and scans Git history with Gitleaks. See the [development guide](docs/development.md) for source organization and checks, and [performance probes](docs/performance.md) for optional benchmarks.

## Packaging and limitations

Build a release-configured local bundle:

```sh
CONFIG=release VERSION=0.1.0 BUILD=1 SIGN_IDENTITY=- ./scripts/build-app.sh
```

The output is `dist/ShipNotes.app`. The packaging script supports Developer ID signing and optional notarization; ad-hoc signing is for local development.

Current verification gaps:

- Live App Store Connect, Apple Ads, and AI operations are covered by doubles rather than end-to-end service verification.
- Developer ID distribution, notarization, and installation on another Mac remain unverified.
- Mac App Store sandbox entitlements and security-scoped bookmarks are not implemented.
- Older macOS runtime behavior and automated UI coverage remain follow-up work.

See [development status](docs/development-status.md) for the maintained follow-up list.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. For bugs, include a minimal reproduction, commit, macOS/Xcode versions, and sanitized sample data. Discuss substantial changes in an issue first.

Report vulnerabilities privately using [SECURITY.md](SECURITY.md). Keep credentials, customer data, and personal paths out of public issues, screenshots, and logs.

## License

Code, scripts, and documentation are licensed under [MIT](LICENSE). The AI-generated icon is also made available under MIT to the extent of the maintainer's rights; see [asset licensing](docs/asset-licensing.md). The ShipNotes name and icon do not grant permission to present a derivative as an official release.
