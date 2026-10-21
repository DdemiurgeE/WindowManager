# WindowManager release model

## v2.9 — restore diagnostics and retry (local candidate; live acceptance pending)

The last-restore card retains its dismissed state across view remounts; Show/Hide
still works, and optional per-window details remain bounded. Restore diagnostics
distinguish verified positions, application clamps, AX failures, skipped/missing
windows and unavailable display coordinates. An unavailable-only result is visible
in both compact and copied counts and remains eligible for retry; these counts
are selected outcomes, not an exhaustive partition of all statuses.

Copied diagnostics omit layout, application and window names by default. Explicit
opt-in includes those names; capture/offscreen-skip console messages no longer
interpolate window titles. This is a local candidate at `MARKETING_VERSION=2.9`
and `CURRENT_PROJECT_VERSION=7`: synthetic QA and an unsigned macOS build do not
constitute live visual, Accessibility, or real-window acceptance. Do not publish
until independent exact-commit QA and review pass and live acceptance is decided.

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