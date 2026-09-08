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
The private key belongs in GitHub Actions secret `SPARKLE_PRIVATE_KEY` and must
never be committed. GitHub Pages is configured for the `main` branch `/docs`
source. The appcast job runs before release publication and fails if Sparkle
cannot validate the signed application archive.

The application starts `SPUStandardUpdaterController` at launch and exposes
**Check for Updates…** in the application menu. Sparkle is pinned through the
Swift Package Manager dependency in the Xcode project.

A release is not update-ready until the ZIP contains a Developer ID-signed,
notarized application. The local build intentionally uses `CODE_SIGNING_ALLOWED=NO`;
Sparkle rejects that archive, which is safer than publishing an unusable feed.
Developer ID certificate import and notarization credentials must be added to
Actions before creating the first public update tag.

Verify local artifacts with:

```bash
(cd dist && shasum -a 256 -c SHA256SUMS)
```