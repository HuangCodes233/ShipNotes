# Public-preview preparation

ShipNotes is published as an early developer preview with source code, scripts,
documentation, and the AI-generated app icon under the [MIT License](../LICENSE).
See [asset licensing](asset-licensing.md) for the recorded icon provenance.

## Publication snapshot

Public development starts from a sanitized source snapshot. The public repository
has independent Git history: previous development commits, pull requests, and
Actions logs were not imported.

Preparation removes personal author contact details, personal and company
namespaces, workstation paths, internal review notes, and product copy from
unrelated projects. Test fixtures use fictional products and temporary folders.
The public commit identity is `ShipNotes contributors` with a reserved,
non-deliverable email domain. GitHub still displays the repository's owner and
public account activity.

The icon PNGs contain image chunks only; no text or EXIF metadata was found.
Build products, credentials, local preferences, and diagnostic logs are excluded
from the published source snapshot.

## Verification

Before changing visibility, the publication commit must pass:

- A scan of the complete new Git history using Gitleaks, plus inspection of
  author metadata, tracked files, fixtures, URLs, and asset metadata.
- The functional `swift test` suite locally and in both CI toolchains.
- Debug app packaging with ad-hoc signing, strict code-signature validation,
  and generated `Info.plist` validation.
- Inspection of the new repository's branches and Actions results, with no
  development history or old logs imported.

Check the [Actions results](https://github.com/HuangCodes233/ShipNotes/actions)
for the commit being evaluated. Four optional performance probes are skipped
by default; they can be run using [the benchmark commands](performance-audit.md).
Automated scans do not prove the absence of every possible sensitive value.

The app is not launched during preparation because startup may reconnect to
stored services. Live API operations, notarization, UI automation, older macOS
runtime behavior, and installation on another Mac remain unverified. See
[development status](development-status.md) for follow-ups.
