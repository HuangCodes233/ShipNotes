# Development status

ShipNotes is an early developer preview. The [product plan](../ShipNotes_PLAN.md)
describes intended direction; it does not establish that every planned feature
is implemented or verified.

## Implemented

- Local release-note and store-copy parsing, locale mapping, diffs, validation,
  editing, and App Store Connect synchronization.
- Screenshot scanning, locale/device coverage checks, upload previews, and
  replacement workflows bound to the selected app and version.
- Optional AI parsing, translation, and screenshot language matching, plus a
  separate Apple Ads workspace with its own credentials.
- Sync cancellation and stale-response guards, structured errors, progress
  reporting, persistent sync history, and recursive file watching.
- Shared screenshot caches, efficient diff summaries, and reusable date
  formatters. [Performance probes](performance-audit.md) describe how to measure
  these paths without making whole-app performance claims.
- App packaging with icon resources, ad-hoc or Developer ID signing, and optional
  notarization/stapling support.

## Verification

Functional tests use doubles and synthetic fixtures. CI tests Xcode 26.3 on
`macos-15` and the bundled Xcode on the `xcode-27` preview image, logging the
actual OS, compiler, and SDK. Gitleaks scans the fetched Git history separately.
Check [Actions](https://github.com/HuangCodes233/ShipNotes/actions) for results
on the current commit.

Local packaging can validate the generated app bundle and ad-hoc signature.
That does not establish live API behavior, successful notarization, or runtime
compatibility on every supported macOS version.

## Remaining work

- **Sandbox support:** implement security-scoped bookmarks and entitlements,
  then verify restored folder access and file watching before enabling the
  Mac App Store sandbox.
- **Distribution:** produce a release with the intended Developer ID, complete
  notarization/stapling, and verify installation and launch on another Mac.
- **Compatibility:** verify runtime behavior on macOS 14 and 15. The deployment
  target remains macOS 14 and older-system material fallbacks are implemented.
- **Live services:** exercise App Store Connect, Apple Ads, and AI operations
  with appropriately isolated test accounts.
- **UI automation:** consider an Xcode app/test host for XCUITest. The current
  SwiftPM test target provides functional coverage rather than automated UI tests.

The public snapshot uses the product-only bundle identifier `org.shipnotes.app`
and matching credential namespaces. Settings and credentials from earlier
private previews must be configured again; automatic migration is not included.
