# ShipNotes

Preview and sync localized App Store release notes, store copy, and screenshots from local files, in a native macOS app.

**Early developer preview.** ShipNotes is intended for indie developers and small teams that already keep their release material in Markdown, YAML, or project folders. Start with the built-in sample account; live publishing and distribution still need further verification.

## What it does

- Import localized release notes from Markdown folders, YAML, JSON, and changelogs.
- Map local language codes to App Store Connect locales, inspect diffs, and validate drafts before syncing.
- Edit and sync store copy, including description, keywords, promotional text, subtitle, and privacy policy URL.
- Scan screenshot folders, check locale/device coverage, and preview uploads or replacements.
- Optionally use your own OpenAI or Anthropic credentials for parsing, translation, and screenshot language matching.
- Explore Apple Ads reports and campaign tools in a separate workspace with separate credentials.

The interface supports English, Simplified Chinese, and Japanese. Liquid Glass is used on macOS 26 and later, with material fallbacks on older systems.

## Requirements

- **Runtime:** macOS 14 or later is the deployment target. Older supported macOS releases still need runtime verification.
- **Build:** Xcode 26 or later with the macOS 26 or newer SDK, and Swift 6 support. Select the full Xcode installation with `xcode-select` if your command-line tools point elsewhere.
- **Sample mode:** no Apple or AI credentials required on a fresh installation.
- **Live mode:** your own App Store Connect API credentials with access to the app and the operations you intend to perform. AI and Apple Ads are optional and configured separately.

## Quick start

Clone the repository and build a local, ad-hoc-signed app:

```sh
git clone https://github.com/HuangCodes233/ShipNotes.git
cd ShipNotes
CONFIG=debug SIGN_IDENTITY=- scripts/build-app.sh
open dist/ShipNotes.app
```

The first launch offers **Explore the demo first**. Before entering any credentials:

1. Choose a sample app and an editable version in the sidebar.
2. In **Release Notes**, use **Import Folder** with `Examples/release-notes/1.4.0/`, or import `Examples/release-notes/1.5.0.yaml` as a file.
3. Select a locale, edit its draft, inspect the diff, and run **Dry Run**.
4. Explore **Store Copy**, **Screenshots**, and the sample **Ads** workspace.

Existing saved credentials are restored on launch and may reconnect to live services. Check the connection indicator before syncing. Sample mode is a first-run experience, not an offline override for an already configured installation.

To connect a real account, open Settings and enter your App Store Connect issuer ID, key ID, and `.p8` private key. Confirm the selected app, version, locales, and proposed changes before using sync, screenshot replacement, or review submission. See [credentials and data flow](docs/privacy-and-data.md) for what is stored locally and sent to each service.

## Development

Open `Package.swift` in Xcode, or use the bundled build/run entrypoint:

```sh
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

The script builds a proper `.app` bundle, replaces the existing ShipNotes process, and launches the new app. It defaults to a debug build with ad-hoc signing; `CONFIG` and `SIGN_IDENTITY` can override those defaults. `--logs`, `--telemetry`, and `--debug` provide optional diagnostics. The Codex Run action uses this same script.

Run the functional tests:

```sh
swift test
```

The test suite uses test doubles and isolated settings. Optional performance probes are skipped by default; reproduction commands and measurement limits are in the [performance audit](docs/performance-audit.md).

CI runs tests with Xcode 26.3 on `macos-15` and the bundled Xcode on the `xcode-27` preview image, logging the actual OS, compiler, and SDK. A separate job scans Git history for secrets with Gitleaks. Workflow configuration alone is not evidence of a successful run; check the [Actions results](https://github.com/HuangCodes233/ShipNotes/actions) for the relevant commit.

## Packaging and current limits

`scripts/build-app.sh` creates `dist/ShipNotes.app` with an `Info.plist`, compiled icon, SwiftPM resources, and code signature. Build overrides include:

```sh
CONFIG=release VERSION=0.1.0 BUILD=1 SIGN_IDENTITY=- scripts/build-app.sh
```

The packaging script also supports Developer ID signing and optional notarization. That support does not establish that a release has been notarized or tested on another Mac. This preview does not promise a ready-to-install signed release.

Other verification gaps:

- Recent App Store Connect, Apple Ads, and AI fixes were tested with doubles, not live accounts.
- Mac App Store sandbox entitlements and persistent security-scoped folder access are not implemented.
- macOS 14/15 runtime behavior and a second-Mac installation still need verification.
- The SwiftPM test target is a functional suite, not an automated UI suite.

See [development status](docs/development-status.md) for follow-ups and [the product plan](ShipNotes_PLAN.md) for proposed directions; planned capabilities are not a list of delivered features.

## Feedback and contributions

Report reproducible problems using the [bug report template](https://github.com/HuangCodes233/ShipNotes/issues/new?template=bug_report.yml). Include the commit, macOS/Xcode version, and a sanitized sample. Discuss substantial features before opening a large pull request. This is a personally maintained project, with no guaranteed response time.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before contributing and [SECURITY.md](SECURITY.md) for private security reporting. Never post API keys, private keys, tokens, or customer data in an issue.

## License

Source code, scripts, and documentation are available under the [MIT License](LICENSE), which permits commercial reuse and redistribution subject to its notice requirements. The AI-generated app icon and its exports are also made available under MIT to the extent of the maintainer's rights; see [asset licensing](docs/asset-licensing.md) for provenance.

The ShipNotes name and icon are not a grant of permission to present a derivative as an official ShipNotes release.
