# Frontend (Flutter) recipes.

# List the recipes of this module.
default:
    @just --list frontend

install:
    flutter pub get

analyze:
    flutter analyze

format-check:
    dart format --set-exit-if-changed lib test

# Screenshot tests are left out; run them with `just docs::screenshots`.
test:
    flutter test --exclude-tags screenshots

# TEFTERI_FLUTTER_VERSION (for example 1.4.0+3, from scripts/version.sh) sets the build
# name and number of the builds below, and the version that the app shows (a --dart-define:
# the web client must not read it from a file that can be newer than its code). Without it
# pubspec.yaml decides.
build-linux:
    flutter build linux ${TEFTERI_FLUTTER_VERSION:+--build-name=${TEFTERI_FLUTTER_VERSION%+*} --build-number=${TEFTERI_FLUTTER_VERSION#*+} --dart-define=TEFTERI_APP_VERSION=${TEFTERI_FLUTTER_VERSION}}

build-apk:
    flutter build apk ${TEFTERI_FLUTTER_VERSION:+--build-name=${TEFTERI_FLUTTER_VERSION%+*} --build-number=${TEFTERI_FLUTTER_VERSION#*+} --dart-define=TEFTERI_APP_VERSION=${TEFTERI_FLUTTER_VERSION}}

build-web:
    flutter build web ${TEFTERI_FLUTTER_VERSION:+--build-name=${TEFTERI_FLUTTER_VERSION%+*} --build-number=${TEFTERI_FLUTTER_VERSION#*+} --dart-define=TEFTERI_APP_VERSION=${TEFTERI_FLUTTER_VERSION}}
