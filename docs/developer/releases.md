# Releases and nightly builds

Two GitHub workflows publish tefteri. Both call only `just` recipes. You can run the same
recipes on your computer.

## Make a release

1. Make sure that the CI passes on `master`.
2. Create a tag with the version: `git tag v1.4.0`.
3. Push the tag: `git push origin v1.4.0`.

The workflow `release.yml` starts. It does these steps:

- `just release::image` builds the server image and pushes it to
  `ghcr.io/bergercookie/tefteri` with the tags `1.4.0` and `latest`.
- `just release::clients` builds the `.deb` package, the AppImage and the `.apk` into `dist/`.
- `just release::publish` creates the GitHub release `v1.4.0` with the three packages.

## Nightly builds

The workflow `nightly.yml` runs every night. It does nothing when the newest nightly image
already has the current commit. Otherwise it does these steps:

- `just release::nightly-versions` computes the version.
- `just release::nightly-image` pushes the image with the tags `nightly` and the version.
- `just release::nightly-clients` and `just release::nightly-publish` replace the `nightly` pre-release on
  GitHub with new packages.

## Version strings

`scripts/version.sh` computes all versions. `just release::version-nightly` prints the nightly version.

A nightly version has the form `<previous release>.<commit>.post<N>`, for example
`1.4.0.a1b2c3d.post3`. The previous release is the newest tag `vX.Y.Z` before the commit. The
number N is one more than the highest N that is already published for that release. The script
reads the published tags from the container registry.

This form is not a valid Python version, so the packages use other forms of the same version:

| Use | Form | Example |
| --- | --- | --- |
| Image tag and package file names | `image` | `1.4.0.a1b2c3d.post3` |
| Python package | `pep440` | `1.4.0.post3+a1b2c3d` |
| Flutter build name and number | `flutter` | `1.4.0+3` |

For a release, the image and Python forms are `X.Y.Z`. The Flutter form is `X.Y.Z+<number of
commits>`, because Android needs a build number that is more than 0.

## Signing the Android package

The release and nightly workflows sign the `.apk` with a release keystore. Add these
repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The keystore file, encoded with `base64 -w0`. |
| `ANDROID_KEYSTORE_PASSWORD` | The password of the keystore. |
| `ANDROID_KEY_ALIAS` | The alias of the key. |
| `ANDROID_KEY_PASSWORD` | The password of the key. |

Without these secrets, the `.apk` has the debug signature. Android cannot update a debug-signed
app with a release-signed app. Keep the keystore safe: you need the same key for every update.

## Tools on the CI runner

The workflows install devbox. They also install the Linux desktop build tools with `apt-get`,
because devbox does not give them. The runner gives Docker and the Android SDK.
