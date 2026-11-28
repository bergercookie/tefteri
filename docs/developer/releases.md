# Releases

One GitHub workflow, `release.yml`, publishes tefteri. It calls only `just` recipes. You can run
the same recipes on your computer.

## Every push to the main branch is a release

When code reaches the main branch, the workflow takes the newest version tag and adds one to the
patch number. It builds the server image and the client packages with that version. It then makes
the GitHub release and the tag at the commit that it built.

| Newest tag | Version of the next release |
| --- | --- |
| `v1.2.3` | `1.2.4` |
| `v3.3` | `3.3.1` |
| none | `0.0.1` |

The newest tag is the highest version, not the tag that was made last. The `v` is optional, and a
tag needs at least a major and a minor number. Other tags, such as the old `nightly-...` tags, do
not count.

The workflow does these steps:

- `just release::next` finds the next version. It also says that no release is needed when the
  commit already has a version tag.
- `just release::image` builds the server image and pushes it to
  `ghcr.io/bergercookie/tefteri` with the tags `1.2.4` and `latest`.
- `just release::clients-linux` builds the `.deb` package and the AppImage into `dist/`.
  `just release::clients-android` builds the `.apk`. The two recipes run in separate jobs.
- `just release::publish` creates the GitHub release `v1.2.4` with the three packages. This also
  creates the tag. It is the last step, so a build that fails leaves no tag and no release.

A change that only touches `docs/`, `specs/` or `.md` files is not a release. Pushes are
released one at a time, in order, so each one gets its own number. You can also start the
workflow by hand from the Actions page.

The workflow checks nothing about the tests: the CI runs at the same time on the same push. Keep
the main branch green.

## Start a new major or minor version

Push a tag by hand. The workflow does not start from a tag.

```bash
git tag v1.3
git push origin v1.3
```

The next push to the main branch is `1.3.1`. A tag with a patch number, such as `v1.3.0`, works
in the same way: the next release is `1.3.1`. A tag that you push by hand is not a release
itself, and has no packages.

## Run the recipes on your computer

`just release::next-version` prints the version of the next release. The other recipes read the
version from the variable `TEFTERI_RELEASE_VERSION`, or from the tag `vX.Y.Z` at `HEAD`:

```bash
TEFTERI_RELEASE_VERSION=1.2.4 just release::clients-linux
```

## Version strings

`scripts/version.sh` computes the version. The release version is `X.Y.Z`. The packages use
these forms of it:

| Use | Form | Example |
| --- | --- | --- |
| Image tag, Python package and package file names | `image`, `pep440` | `1.2.4` |
| Flutter build name and number | `flutter` | `1.2.4+318` |

The number after the plus sign is the number of commits. Android needs a build number that is
more than 0.

The recipes `frontend::build-web`, `build-linux` and `build-apk` also pass this version to the app
with `--dart-define=TEFTERI_APP_VERSION`. The app shows that version in the menu and in Admin
settings. The web client does not read the version from a file on the server, because a browser
that holds old code could then show a newer number than the code that runs.

The update check in Settings compares the version of the app with the latest GitHub release.

## Old nightly builds

Earlier, a nightly workflow published the pre-releases `nightly` and `nightly-<version>` and the
image tag `nightly`. They are not made any more. The workflow does not delete the ones that exist.
You can delete them on the Releases page and the Packages page of the repository.

## Signing the Android package

The release workflow signs the `.apk` with a release keystore. Add these
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

The jobs for the server image and the Android package install devbox. The job that finds the version needs only `git` and `just`. The runner
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
