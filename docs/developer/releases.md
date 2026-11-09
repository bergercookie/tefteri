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
- `just release::clients-linux` builds the `.deb` package and the AppImage into `dist/`.
  `just release::clients-android` builds the `.apk`. The two recipes run in separate jobs.
- `just release::publish` creates the GitHub release `v1.4.0` with the three packages.

## Nightly builds

The workflow `nightly.yml` runs every night. It does nothing when the newest nightly image
already has the current commit. Otherwise it does these steps:

- `just release::nightly-versions` computes the version.
- `just release::nightly-image` pushes the image with the tags `nightly` and the version.
- `just release::nightly-clients-linux` and `just release::nightly-clients-android` build the
  packages, in separate jobs.
- `just release::nightly-publish` publishes them as two pre-releases on GitHub: one named
  `nightly-<version>` that stays, and `nightly`, which it replaces. The update check of the app
  reads `nightly`, so it always holds the newest build.
- `just release::nightly-prune` then deletes the pre-releases `nightly-<version>` except the newest
  five. To keep another number, pass it: `just release::nightly-publish <version> 10`. It never
  touches `nightly` or the releases `vX.Y.Z`.

The container images are not pruned. Their tags give the post number of the next nightly.

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

The jobs for the server image, the version and the Android package install devbox. The runner
gives Docker and the Android SDK.

The job for the Linux packages does not use devbox. It runs on the oldest Ubuntu image that
GitHub offers, so that the packages also run on older systems. It installs the compiler, the
GTK development files and `just` with `apt-get` and actions, and it installs a plain Flutter SDK.
The version of this SDK is in the variable `FLUTTER_SDK` of the workflow. Keep it equal to the
version in `devbox.json`.

```{note}
Devbox sets up the dependencies for development. The CI bypasses it for the Linux packages,
because a bundle that links the libraries of devbox does not start on other computers.
`packaging/check-bundle.sh` checks the bundle before it goes into a package.
```

## Upgrade notes for the planner (spec 002)

Put this note in the release notes of the release that adds the planner:

- The planner schedules tasks by the due date only. It does not write the start date or the end
  date of a Vikunja task any more.
- A task that an older version scheduled only through the start date and the end date, and that
  has no due date, shows as not scheduled. Tefteri does not change it in Vikunja. The user drags
  the task to a time to set the due date.
- A task with a due time of exactly 00:00 in the time zone of the user shows as a task for a date
  only. Check this convention against your Vikunja server before the release.
