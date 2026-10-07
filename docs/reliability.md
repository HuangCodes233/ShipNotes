# Drafts, synchronization, and history

ShipNotes keeps local editing separate from writes to App Store Connect. Saving
a draft does not publish it, and a successful upload does not discard edits made
while the request was running.

## Local drafts

Release notes, store-copy fields, imported source locations, and screenshot
workspace choices are saved locally for each account, app, and version. Changes
are saved after a short delay, on workspace switches, and when the app leaves
the foreground or terminates normally. On launch, the last available workspace
is selected and its drafts are restored over freshly loaded remote content.

Draft files are stored in the app's Application Support directory and replaced
atomically. They can contain unpublished text and local file paths; account
scoping uses a hash of non-secret account identifiers. API keys and private keys
remain in the Keychain and are not included in draft files. Public and private
builds have separate application identifiers and therefore separate draft stores.

When a source file or remote field changes after a local edit, ShipNotes keeps
the edited draft and reports the conflict. Re-importing should not silently
replace an edited draft. Changes made only in ShipNotes are not written back to
the original files.

The current application is not sandboxed. Restoring a file URL does not establish
security-scoped bookmark support; Mac App Store sandbox distribution still needs
that separate implementation.

## Synchronization and review

A release-note response updates the remote snapshot. Text typed after the request
started remains a draft, with its differences recalculated. Re-selecting the same
app or version does not reload the workspace, and opening another window does
not restart initialization of the shared state.

Before review submission, ShipNotes checks for unsent local changes, including
rows left in a failed state by a previous attempt. Failed syncs and invalid
fields stop submission. Edits made during automatic synchronization also require
another review attempt so they are not silently omitted.

New App Store Connect credentials are validated using a candidate client before
they replace the stored connection. A failed candidate leaves the previous
connection intact, and failures to load apps remain visible.
App-list responses from a previous connection are ignored after an account
change, including their errors and loading-state cleanup.

## Screenshots

Thumbnail loading includes the scanned content hash, so refreshing a file
replaced at the same path loads the new image. Refresh retains language mapping,
sharing, and order for unchanged files; changed files are reconsidered.

Apple's asset processing is separate from uploading bytes. A processing timeout
is recorded as processing, not as confirmed success. The pending reservations
are saved locally and can be checked again without deleting or uploading the
files a second time. Cancellation stops scheduling remaining screenshot reads.

## History

New sync runs include the app name and version at the time of the operation.
Earlier records remain readable and fall back to available app/version data or
their identifiers. History can be searched and filtered by app, operation, and
result. JSON and CSV exports contain the currently filtered records and are
saved to a location selected by the user.

The existing retention limit remains 100 runs. Exports can retain an independent
copy; this change does not claim unlimited archival storage.

## Verification

Regression tests use injected services, memory credential stores, and temporary
draft storage. They cover editing during sync, consecutive review attempts after
a failed sync, repeated selection/initialization, candidate credential failures,
draft restoration and account isolation, screenshot processing recovery, and
history compatibility/export. Tests do not establish that a particular live
Apple account or provider will accept a write.
