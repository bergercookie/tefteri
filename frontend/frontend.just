# Frontend (Flutter) recipes.

install:
    flutter pub get

analyze:
    flutter analyze

format-check:
    dart format --set-exit-if-changed lib test

test:
    flutter test

build-linux:
    flutter build linux

build-apk:
    flutter build apk

build-web:
    flutter build web
