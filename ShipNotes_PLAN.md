# ShipNotes Product Plan

Date: 2026-05-19

## Product Name

**ShipNotes**

A native macOS app for syncing App Store Connect release notes from local files, with diff preview, locale mapping, AI-assisted translation, and a macOS 26 Liquid Glass interface.

## One-Line Pitch

ShipNotes lets developers update App Store Connect "What's New" text from local release-note files without opening the App Store Connect website.

## Core Problem

Updating App Store release notes is repetitive:

- Developers often already write release notes locally.
- App Store Connect requires entering localized text per app version.
- The web UI is slow for repeated updates.
- Multi-language updates are error-prone.
- There is no quick local diff before pushing metadata.

ShipNotes should make release-note publishing feel like a local developer workflow.

## Target Users

- Indie iOS and macOS developers.
- Small teams shipping apps through App Store Connect.
- Developers maintaining localized App Store metadata.
- Teams that already keep release notes in `CHANGELOG.md`, markdown files, or versioned folders.

## Core Workflow

1. Connect App Store Connect API credentials.
2. Choose an app from the local macOS sidebar.
3. Choose the editable App Store version.
4. Import release notes from a local file or watched folder.
5. Match local files to App Store locales.
6. Preview local vs remote diff.
7. Fix warnings such as missing locale, over-limit text, or unavailable version state.
8. Optionally generate translations.
9. Dry run.
10. Sync selected locales to App Store Connect.

## MVP Scope

### App Store Connect Integration

- Store App Store Connect API credentials locally.
- Generate JWT tokens for API requests.
- Fetch apps connected to the account.
- Fetch App Store versions for a selected app.
- Detect editable versions.
- Fetch version localizations.
- Update `whatsNew` for selected localizations.
- Show clear errors for auth failure, permission issues, non-editable version state, validation failure, and rate limits.

### Local Release Notes

Support these input formats first:

```text
release-notes/
  1.4.0/
    en-US.md
    zh-Hans.md
    ja.md
    ko.md
```

Also support a single YAML file:

```yaml
version: 1.4.0
locales:
  en-US: |
    Fixed import issues and improved stability.
  zh-Hans: |
    修复导入问题，并提升稳定性。
```

### Locale Mapping

- Detect locale from filename.
- Match local locale codes to App Store Connect locale codes.
- Show missing local files.
- Show locales that exist locally but not remotely.
- Allow manual mapping overrides.

### Diff And Validation

- Show side-by-side diff between local notes and current App Store Connect notes.
- Validate character length against App Store limits.
- Preserve bullet formatting as plain text.
- Warn if markdown syntax will be synced as plain text.
- Show summary: ready, needs review, missing, over limit, failed.

### Sync Actions

- Sync selected locales.
- Dry run without writing.
- Retry transient network failures.
- Save sync result history locally.

## Differentiating Features

### Watched Folder

- Let users choose a release-notes folder.
- Auto-refresh parsed notes when files change.
- Show a "Watching" indicator in the source path capsule.
- Recalculate diff automatically after file edits.

### AI Translation

- Generate missing locales from a source language.
- Preserve app names, feature names, and glossary terms.
- Let users review every generated translation before sync.
- Store translation preferences per app.

### AI Rewrite

- Convert engineering-style commit notes into user-facing App Store copy.
- Generate concise, friendly release notes from:
  - Git commits.
  - Git tags.
  - `CHANGELOG.md`.
  - Pull request titles.

### Git And Changelog Support

- Read current version from local project config where possible.
- Suggest release notes from commits since the last tag.
- Parse `CHANGELOG.md` sections by version.
- Let users choose between local files, changelog, or generated notes.

### Safe Publishing

- Always show diff before writing.
- Default to dry-run friendly behavior.
- Block sync if the target version is not editable.
- Show exact locale and field that failed.
- Allow rollback by keeping previous remote notes in local history.

## macOS 26 Liquid Glass UI Direction

Use Liquid Glass selectively. The app must feel modern, but release-note text and diffs must stay readable.

### Glass Surfaces

- Left sidebar.
- Floating toolbar.
- Source path capsule.
- Right inspector shell.
- Bottom sync command bar.
- Status chips when appropriate.

### High-Readability Surfaces

- Locale table.
- Diff body.
- Text editor.
- Error messages.
- Character counters.

### Main Layout

- `NavigationSplitView` with three areas:
  - Sidebar: accounts and apps.
  - Content: selected app, version, local source, locale table.
  - Detail inspector: language selector, diff, editor.

### Key Screens

- Onboarding and API key setup.
- App picker.
- Version picker.
- Release notes sync workspace.
- Translation review.
- Settings.
- Sync history.

## Suggested UI Details

### Sidebar

- App Store Connect account status.
- List of apps with app icons.
- Selected app with glass selection treatment.
- Settings entry at the bottom.

### Toolbar

- Refresh.
- Import file.
- Watch folder.
- Generate translations.
- Preview diff.
- Search.

### Center Workspace

- App icon and app name.
- Version string.
- App Store version state badge.
- Local source path capsule.
- Locale sync table.

### Right Inspector

- Language dropdown.
- Summary: changed lines, over-limit status.
- Side-by-side diff.
- Editable release-note text area.
- Character counter.

### Bottom Command Bar

- Sync readiness summary, for example `5 ready · 1 needs review`.
- Dry Run button.
- Sync Selected primary button.

## Data Model Draft

### Account

- id
- name
- issuerId
- keyId
- privateKeyReference
- createdAt
- lastUsedAt

### AppRecord

- id
- name
- bundleId
- platform
- iconUrl

### ReleaseVersion

- id
- appId
- versionString
- platform
- appStoreState
- canEditMetadata

### LocaleNote

- locale
- localPath
- localText
- remoteText
- length
- status
- diffSummary

### SyncRun

- id
- appId
- versionId
- startedAt
- completedAt
- dryRun
- result
- localeResults

## Technical Architecture

### Platform

- Native macOS app.
- SwiftUI.
- macOS 26 Liquid Glass APIs where available.
- Compatibility fallback for older macOS versions.

### Core Modules

- `AppStoreConnectClient`
- `JWTTokenProvider`
- `CredentialStore`
- `ReleaseNotesParser`
- `LocaleMapper`
- `DiffEngine`
- `ValidationEngine`
- `SyncCoordinator`
- `TranslationProvider`
- `GitReleaseNotesProvider`
- `FileWatcher`

### Storage

- Keychain for App Store Connect private key and sensitive account data.
- App support directory for preferences, locale mappings, and sync history.
- Optional project-local config file for team-shared defaults.

### Security

- Never store `.p8` private keys as plain text.
- Use Keychain references.
- Avoid logging tokens, private keys, or full API responses containing credentials.
- Let users remove credentials completely.

## Project-Local Config Idea

```yaml
app:
  bundleId: com.example.examplegallery
  defaultVersionSource: project

releaseNotes:
  folder: release-notes
  format: per-locale-markdown
  sourceLocale: zh-Hans

locales:
  zh-Hans: zh-Hans.md
  en-US: en-US.md
  ja: ja.md

translation:
  glossary:
    Example Gallery: Example Gallery
    App Store Connect: App Store Connect
```

## Error States To Handle

- Missing API key.
- Invalid API key.
- Expired JWT.
- Missing App Store Connect permissions.
- No editable version found.
- Version currently in review.
- Locale missing in App Store Connect.
- Local file missing.
- Local text exceeds character limit.
- Network failure.
- Rate limit.
- Partial sync failure.
- Translation provider failure.

## Testing Plan

### Unit Tests

- Release-note file parsing.
- YAML parsing.
- Locale matching.
- Character-limit validation.
- Diff summary generation.
- JWT creation.
- App Store Connect error mapping.

### Integration Tests

- Mock App Store Connect API.
- Dry-run sync.
- Partial sync failure.
- Retry behavior.
- File watcher refresh.

### UI Tests

- Connect account flow.
- Import local notes.
- Select locales.
- Preview diff.
- Dry run.
- Sync selected.
- Translation review.

### Visual QA

- Light mode.
- Dark mode if supported later.
- Reduced transparency.
- Long app names.
- Long locale text.
- Small window sizes.
- Large locale lists.

## Roadmap

### Phase 1: Local Sync MVP

- API key setup.
- App and version selection.
- Folder import.
- Locale table.
- Diff preview.
- Dry run.
- Sync selected `whatsNew`.

### Phase 2: Safer Publishing

- Watched folders.
- Sync history.
- Rollback from previous remote notes.
- Manual locale mapping.
- Better error recovery.

### Phase 3: AI Assistance

- Generate missing translations.
- Rewrite release notes from rough notes.
- Glossary support.
- Translation review workflow.

### Phase 4: Developer Workflow

- Git commit summary.
- `CHANGELOG.md` parsing.
- Project config file.
- Menu bar quick action.
- App Store version status notifications.

### Phase 5: Team Features

- Shared config.
- Export sync reports.
- Multiple App Store Connect accounts.
- Metadata fields beyond `whatsNew`, such as promotional text and description.

## Open Questions

- Should the app start as a normal window app or a menu bar utility?
- Should AI translation be built in, plugin-based, or user-provider-key based?
- Should project config live inside the repo by default?
- Should ShipNotes support only App Store Connect first, or also Google Play later?
- Should sync history include full previous release-note text for rollback?

## Initial Implementation Order

1. Build a SwiftUI shell with the three-column layout.
2. Implement local release-note folder parsing.
3. Implement locale table, validation, and diff preview with mocked remote data.
4. Add Keychain-based credential setup.
5. Add App Store Connect API client.
6. Wire real fetch for apps, versions, and localizations.
7. Implement dry run and sync selected.
8. Add watched folder refresh.
9. Add translation provider abstraction.
10. Polish Liquid Glass UI and reduced-transparency fallback.
