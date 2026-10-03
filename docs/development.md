# Development guide

ShipNotes is a Swift 6 executable package with a functional test target. Xcode
provides the macOS SDK, SwiftPM, and `swift-format`; no third-party package or
formatter installation is required.

## Source organization

| Directory | Responsibility |
| --- | --- |
| `Sources/ShipNotes/App/` | App entry point, scenes, commands, and app delegate |
| `Sources/ShipNotes/Models/` | Domain values for App Store data, release notes, store copy, screenshots, AI configuration, and Apple Ads |
| `Sources/ShipNotes/State/` | Observable state, feature workflows, caches, selection, and persistence |
| `Sources/ShipNotes/Services/` | Parsing, validation, file access, retry policy, and platform integration |
| `Sources/ShipNotes/Services/AppStoreConnect/` | API requests, DTOs, authentication, and credential storage |
| `Sources/ShipNotes/Services/AI/` | Provider requests, response parsing, endpoint resolution, and AI credential storage |
| `Sources/ShipNotes/Services/AppleAds/` | Apple Ads requests, authentication, reports, and keyword preparation |
| `Sources/ShipNotes/Views/` | Feature workspaces, sheets, reusable components, and settings pages |
| `Sources/ShipNotes/Support/` | Appearance, localization, logging, and shared settings utilities |
| `Sources/ShipNotes/Resources/` | Runtime icon assets and localized strings |
| `Tests/ShipNotesTests/` | Functional tests, synthetic fixtures, and test doubles |
| `Examples/` | Importable release-note examples |
| `Design/AppIcon/` | Editable icon source; runtime exports live in the asset catalog |
| `scripts/` | Build, run, and quality-check entry points |

`AppState` owns observable values and injected dependencies. Feature extensions
implement workflows and derived state without changing that ownership. Views
compose native SwiftUI controls; settings forms keep drafts in their own feature
views. Small related models share a file when they belong to the same domain.

## Everyday commands

```sh
# Build the executable without launching it.
swift build

# Check Swift formatting, run functional tests, and check diff whitespace.
./scripts/check.sh

# Apply the repository's Swift formatting policy.
xcrun swift-format format --in-place --recursive Package.swift Sources Tests

# Build an ad-hoc-signed app bundle without launching it.
CONFIG=debug SIGN_IDENTITY=- ./scripts/build-app.sh

# Build and launch; stops an existing ShipNotes process first.
./scripts/run-app.sh
```

The run script also accepts `--verify` (check that the process stays running),
`--debug` (launch through LLDB), `--logs`, and `--telemetry`. Its default is a
debug build with ad-hoc signing. `CONFIG` and `SIGN_IDENTITY` can override those
settings. The Codex Run action calls the same script.

## Code conventions

- Use the checked-in `.swift-format` configuration: four spaces, a 120-column
  formatting target, ordered imports, and consistent declaration formatting.
  Strings and documentation may exceed the formatting target.
- Keep the app entry point focused on scenes and commands. Group views,
  models, state, and services by responsibility rather than implementation phase.
- Keep view state close to the form or feature that owns it. Pass explicit
  values, bindings, and actions to reusable components.
- Use `@MainActor` for UI state. Keep expensive file scans and request work off
  the main actor, forwarding cancellation and checking request identity before
  applying delayed results.
- Prefer `private` implementation details. The executable module's default
  internal visibility is sufficient for code shared across feature files.
- Inject network and credential protocols in tests. Do not make tests depend on
  the developer's real Keychain, preferences, account, or live endpoints.
- Localize interface text with `L(...)` and update all three `.strings` files.
  Localization tests check key coverage and format placeholders.
- Explain non-obvious constraints in comments; use names and file boundaries
  to describe routine behavior.

## Verification

Use a filtered `swift test --filter <suite-or-test>` during focused changes,
then run the functional suite before submitting. Optional performance probes are
skipped by default; see [performance measurement](performance.md) for commands
and limits. Formatting changes should not require duplicated behavior tests.

CI tests with Xcode 26.3 and Xcode 27, runs `swift-format` lint on Xcode 27, and
scans the fetched Git history with Gitleaks. Formatting is checked with one
compiler generation to avoid differences between formatter versions.

For packaging changes, validate the generated bundle:

```sh
CONFIG=debug SIGN_IDENTITY=- ./scripts/build-app.sh
codesign --verify --deep --strict dist/ShipNotes.app
plutil -lint dist/ShipNotes.app/Contents/Info.plist
```

Saved credentials can reconnect to live services when the app launches. Use an
isolated macOS profile for sample-mode UI testing. Functional tests and bundle
validation do not verify live APIs, UI behavior, notarization, or another Mac's
installation. Record the checks actually performed in the pull request.

See [CONTRIBUTING.md](../CONTRIBUTING.md), [security reporting](../SECURITY.md),
and [credentials and data flow](privacy-and-data.md) before sharing examples or
logs.
