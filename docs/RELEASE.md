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
The private key belongs in GitHub Actions secrets and must never be committed.
Until Developer ID signing, notarization, and Sparkle EdDSA signing are
configured, the GitHub Release remains the install/update source but is not a
trusted unattended update channel.

Verify local artifacts with:

```bash
(cd dist && shasum -a 256 -c SHA256SUMS)
```