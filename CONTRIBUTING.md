# Contributing to ShipNotes

ShipNotes is an early, personally maintained macOS developer tool. Bug reports, documentation corrections, and focused fixes are welcome. Response times and feature delivery are not guaranteed.

## Before you open an issue

- Check existing issues and the [development status](docs/development-status.md).
- Include the Git commit, macOS version, Xcode version, and whether you used sample or live mode.
- Give the shortest reproduction you can, with expected and actual behavior.
- Attach sanitized examples using fictitious app names and account identifiers. Remove credentials, private endpoints, customer information, and personal file paths from screenshots and logs.
- Report security problems privately using [SECURITY.md](SECURITY.md).

## Local development

Use Xcode 26 or later with the macOS 26 or newer SDK. The runtime deployment target is macOS 14.

```sh
swift test
./script/build_and_run.sh --verify
```

The run script stops the existing ShipNotes process and opens a local app bundle. Saved credentials may reconnect to live services; use a clean macOS user profile when you need an isolated sample-mode session. Do not use a production account for a reproduction that modifies remote data.

## Pull requests

1. For substantial features or design changes, discuss scope in an issue first.
2. Keep the change focused. Explain the user-visible problem and resulting behavior.
3. Add meaningful regression coverage when changing parsing, credential handling, API behavior, or sync safety. Documentation-only changes do not need new tests.
4. Run `swift test` and `git diff --check`. If changing packaging, run `CONFIG=debug SIGN_IDENTITY=- scripts/build-app.sh`.
5. Record exactly what you verified. Distinguish mock tests, local UI checks, and live API checks.

Do not add real `.p8` keys, API tokens, account exports, generated `.app` bundles, or build output. Secret patterns in test fixtures should be obviously nonfunctional; avoid broad scan allowlists.

For a local secret scan, install [Gitleaks](https://github.com/gitleaks/gitleaks), then run:

```sh
gitleaks git . --log-opts="--all" --redact
gitleaks git . --staged --redact
```

The history scan covers commits; stage intended changes before using the staged scan. Check untracked files before committing them.

Only contribute code or materials that you have the right to submit under the repository's [MIT License](LICENSE). Declare third-party sources and licenses in the pull request. The app icon has separate [asset licensing](docs/asset-licensing.md) considerations.
