# Client packaging recipes. Call as `just packaging::<recipe>`; build the client first.

deb:
    just frontend::build-linux
    bash deb/build.sh

appimage:
    just frontend::build-linux
    bash appimage/build.sh

apk:
    just frontend::build-apk
    @echo "APK at frontend/build/app/outputs/flutter-apk/app-release.apk"
