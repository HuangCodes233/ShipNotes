# Credentials and data flow

This document describes the current implementation, not a guarantee about third-party services. Review your selected provider's terms and data handling before sending private material.

## Local storage

- App Store Connect credentials, including the `.p8` private-key content, are stored in the macOS Keychain by `KeychainCredentialStore`.
- AI API keys are stored in the Keychain by `AIKeychainStore`. Text and screenshot-vision profiles have separate key entries.
- Apple Ads credentials use a separate Keychain service in `AppleAdsKeychainStore`.
- Non-secret preferences, AI model/base-URL settings, screenshot overrides, and sync history are stored locally using `UserDefaults`. Up to 100 sync runs are retained. These preferences are not encrypted by ShipNotes as secret storage.
- Imported release material stays in its source files and in the app's working state. Local file paths can appear in settings, errors, and diagnostic output; sanitize them before sharing logs or screenshots.
- Workspace drafts are saved in Application Support under the application's bundle identifier. They include unpublished text, imported source paths, and screenshot workspace choices, scoped by account/app/version; they do not contain API keys or private keys. Draft files use atomic replacement and are not encrypted by ShipNotes.
- Pending screenshot-processing reservations are saved locally so they can be checked again without repeating a destructive replacement. History exports include the filtered operation records and their error messages. Review exported files before sharing them.

See [draft and synchronization behavior](reliability.md) for restoration, conflict handling, processing states, and export limits.

Keychain credentials are configured with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Credentials may be cached in process memory during a session. Uninstalling the app bundle should not be treated as revoking keys or clearing all local state; remove credentials in Settings and revoke them with their issuing services when needed.

## Public-preview storage identifiers

The public snapshot uses `org.shipnotes.app` as its bundle identifier and
product-only Keychain service identifiers. Earlier private-preview settings and
credentials are not automatically migrated. Configure the public preview again
in Settings; changing namespaces does not revoke keys or delete old local data.

## Network requests

| Feature | Destination | Material sent |
| --- | --- | --- |
| App Store Connect loading and sync | Apple's App Store Connect API; screenshot upload URLs supplied by that API | Signed JWT authentication, app/version/locale identifiers, selected metadata, screenshot files, and review/build operations as requested |
| Apple Ads | Apple's OAuth and Apple Ads APIs | OAuth authentication and account/campaign/report/keyword requests; campaign changes when requested |
| AI text parsing and translation | The selected OpenAI-compatible or Anthropic endpoint | Input text and operation context, such as target locales, app name, version, and glossary entries where applicable; the configured API key authenticates the request |
| AI screenshot language matching | The selected vision endpoint | JPEG thumbnails, relative image paths, device-size labels, known locales, and optional app name; the configured API key authenticates the request |

Apple authentication uses signatures generated locally from private keys. The App Store Connect and Apple Ads authentication implementations do not put the private-key PEM itself in API request bodies.

AI folder parsing can assemble text from supported files under the chosen folder, with relative-path headers. A parse failure can offer or invoke AI fallback when AI is configured, and **Ask AI to re-parse** also sends the assembled input. Choose a release-material folder deliberately; do not assume a whole project folder has been scrubbed of confidential text.

Screenshot matching downsamples images to at most 512 pixels on the longest side and sends them in batches. Anonymous request IDs replace absolute-path asset IDs, but **relative paths and visible image content are still sent**. They can contain private information.

AI requests use an ephemeral `URLSession` to avoid normal on-disk session caching. That does not control what a provider or proxy stores. A custom base URL receives the credentials and payload for that profile; configure only endpoints you trust.

## First launch and reconnecting

A fresh installation offers mock App Store data and sample Apple Ads data without credentials. Launch also checks for stored credentials and can reconnect to live Apple services. A previously configured installation is therefore not guaranteed to stay offline or in sample mode.

AI credentials are optional. Local parsing, draft editing, diffs, and validation do not require them. AI-assisted operations send content to the selected endpoint.

## Verification limits

The repository has automated tests using doubles and generated fixtures. Recent fixes have not been exercised against live App Store Connect, Apple Ads, or AI accounts as part of the public-release preparation. Secret scans do not establish the absence of every sensitive value or an independent security review.
