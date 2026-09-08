# WindowManager release model

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