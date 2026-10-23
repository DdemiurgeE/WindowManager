# WindowManager release model

## v3.2 — per-display snapping (candidate; live acceptance required)

The main window now offers **Snap Windows**: refresh available windows, select an
individual window and a currently attached display, then choose a half, quarter,
third, two-thirds or fill-visible-area tile. The calculation uses each display's
visible frame (excluding Dock and menu bar), and the target is revalidated
before the Accessibility write. Saved layouts are not overwritten by snapping;
**Save Current Layout** captures a chosen arrangement for later restoration.

An explicit **Snap while dragging** switch (off by default) monitors mouse
movement outside the app. It snaps the focused standard window on release at a
display edge only if its Accessibility position changed during a title-bar drag.
Corners produce quarters, sides produce halves, top fills the usable area, and
bottom produces thirds. It does not install a keyboard event tap or intercept
input. Accessibility is required; macOS may also require Input Monitoring for
global mouse observation. A denied monitor fails inactive, not as an implied
permission grant. Test geometry, gesture gating and missing/duplicate displays
synthetically; do not mistake those tests for a real drag-and-drop UX check.

No automatic test may rearrange actual windows or displays, change saved layouts,
start the installed application, or alter the user's settings. Before publishing
this feature, verify the live drag interaction with explicit user permission or
record an informed risk decision. Proposed version: 3.2, build 10.

## v3.1 — stable physical display matching (released; live acceptance pending)

A unique, nonzero vendor/model/serial fingerprint (stored only as a SHA-256 digest)
now follows each physical monitor when macOS reassigns its temporary screen number.
Capture, restore, and the display monitor use the same identity source. If a
captured physical monitor is missing or ambiguous, its windows are skipped rather
than moved to a different display. Legacy `screen_` identifiers are not trusted
for exact manual selection; saved geometry provides a best-effort fallback.
Auto-apply requires a complete unique physical display set, so existing layouts
must be captured again. The Saved Layouts view explains this limitation; manual
preview and restore remain available. Monitors without a unique hardware serial
cannot safely enable Auto-apply.

Version `MARKETING_VERSION=3.1`, build `CURRENT_PROJECT_VERSION=9`.
PR #16 passed Debug/Release hosted CI, was merged at `6f8919263e8dd49b689baba32e882180e2f4f509`,
and was published from tag `v3.1` after the post-merge CI passed. All 12
standalone synthetic harnesses and the legacy JSON fixture passed locally;
the downloaded release ZIP, DMG, checksum manifest, and bundled code signature
were verified. The Sparkle entry signs the exact downloaded ZIP, with public
feed propagation verified separately. No live GUI/Accessibility operation,
display reconnection, real-window mutation, layout capture, clipboard
operation, or user-setting change was part of automated acceptance. Synthetic
tests do not prove live monitor behavior.

## v3.0 — per-copy diagnostics consent and console privacy (released; live acceptance pending)

**Copy with names…** now requires confirmation on every action; old persisted
consent is ignored. Confirmation is bound to the specific restore-result revision,
so stale alerts cannot copy newly updated names. A stale confirmation is reported
separately from a clipboard-write failure. Capture and restore console messages
avoid window/layout identifiers, including aliased and multiline output sinks.
Version `MARKETING_VERSION=3.0`, build `CURRENT_PROJECT_VERSION=8`.

The privacy source passed independent synthetic/static QA and review in PR #13;
version/build 3.0 (8) passed its own gates in PR #14 and was published from
`v3.0`. The downloaded release ZIP, DMG and checksums were verified; the
Sparkle entry signs the exact downloaded ZIP. Public feed propagation is a
separate gate. No live SwiftUI alert/AX, real clipboard, real windows/displays
or user settings were exercised: the ordering of alert dismissal and delayed
error presentation remains unverified, not a proven fix. Do not describe the
synthetic checks as live acceptance.

## v2.9 — restore diagnostics and retry (released; live acceptance pending)

The last-restore card retains its dismissed state across view remounts; Show/Hide
still works, and optional per-window details remain bounded. Restore diagnostics
distinguish verified positions, application clamps, AX failures, skipped/missing
windows and unavailable display coordinates. An unavailable-only result is visible
in both compact and copied counts and remains eligible for retry; these counts
are selected outcomes, not an exhaustive partition of all statuses.

Copied diagnostics omit layout, application and window names by default. The
published v2.9 build used a persistent opt-in for named copies; the v3.0
change (not part of v2.9) requires confirmation for every
"Copy with names…" action and ignores the old stored consent. Names remain on the
clipboard until replaced. Capture/offscreen-skip console messages no longer
interpolate window titles. Version `MARKETING_VERSION=2.9` and
`CURRENT_PROJECT_VERSION=7` was published from tag `v2.9` after independent
synthetic QA, review, and hosted CI. The release ZIP, DMG, checksums, and signed
Sparkle feed were verified. Live visual, Accessibility, and real-window
acceptance was not performed; those behaviors remain unverified in a live session.

## v2.8 — local import (synthetic QA/review passed; live acceptance pending)

Manual **Import Backup…** accepts v2.7 unversioned `[Layout]` and v2.8 versioned
envelopes, validates before a non-writing preview, rejects whole-file collisions,
and requires explicit confirmation. A first confirmed import installs a private
transactional Application Support store while retaining the original SavedLayouts
blob untouched. Imported layouts keep their timestamps but cannot Auto-apply.
New exports are versioned with UTC millisecond dates; v2.7 seconds-only dates
cannot regain lost precision. The new authoritative file contains sensitive
window metadata; older releases see only the preserved pre-import defaults
snapshot after downgrade. No live import or window mutation is part of automated
QA. Release metadata is `MARKETING_VERSION=2.8` and `CURRENT_PROJECT_VERSION=6`.
Do not publish until independent synthetic QA and review of the exact commit pass.

## v2.7 — export-only backup

Saved Layouts gains a manual **Export Backup…** action. After a privacy warning,
the user chooses a local JSON destination. It snapshots all saved layouts in the
existing ISO-8601 `[Layout]` format without modifying SavedLayouts or applying
windows. Window titles, app names, frames and display details are sensitive;
the app does not upload backups. There is no import or migration in this release.
Release metadata is `MARKETING_VERSION=2.7` and
`CURRENT_PROJECT_VERSION=5`; verify both in the published app before tagging.

## Versioning

The marketing version is stored in `MARKETING_VERSION`; the build number is
stored in `CURRENT_PROJECT_VERSION`. A release tag must be `v<marketing version>`
(for example, `v2.4`).

## Local build

```bash
./scripts/build-release.sh
```

The script builds a Release archive without a developer certificate, strips
macOS extended attributes, and produces a ZIP, DMG, and `SHA256SUMS` in `dist/`.
For public distribution, configure Developer ID signing and notarization in CI;
the unsigned local build is intended for smoke testing only.

## GitHub release

```bash
git tag v2.4
git push origin main --follow-tags
```

The `release.yml` workflow builds the artifacts and attaches them to the GitHub
Release for the tag. It must be run from a clean, reviewed commit.

## Automatic updates

The app advertises the GitHub Pages appcast URL through `SUFeedURL` and enables
automatic checks. The appcast must be generated and signed with Sparkle's
`generate_appcast` using the release ZIP and the repository's EdDSA private key.
The private key remains in the local macOS Keychain under the Sparkle `ed25519`
account and must never be committed or uploaded to GitHub. GitHub Pages is
configured for the `main` branch `/docs` source.

The application starts `SPUStandardUpdaterController` at launch and exposes
**Check for Updates…** in the application menu. Sparkle is pinned through the
Swift Package Manager dependency in the Xcode project.

A release uses an ad-hoc Apple signature, matching Canary Transcriber. It is
not notarized, so macOS may require the user to approve the first launch in
Privacy & Security. Sparkle still verifies the app's Apple signature and the
EdDSA signature of the update archive.

After uploading the ZIP to a GitHub Release, generate and publish the feed
locally from the Keychain:

```bash
./scripts/generate-appcast.sh 2.3 v2.3
git add docs/appcast.xml
git commit -m "chore: update Sparkle appcast"
git push origin main
```

Verify local artifacts with:

```bash
(cd dist && shasum -a 256 -c SHA256SUMS)
```