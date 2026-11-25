# Building Layer Studio

## Requirements
- Flutter stable (Dart SDK bundled with Flutter)
- Android SDK for APK builds
- Visual Studio with Desktop development with C++ workload for Windows builds

## Local setup
```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## Android APK
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

## Windows
```bash
flutter build windows --release
```
Output: `build/windows/x64/runner/Release/`

The workflow packages the Windows runner directory as a ZIP artifact. An installer is not yet created; a signed installer requires a Windows packaging/signing step and publisher certificate.

## Offline behavior
The app has no network client, account system, analytics or backend integration. Flutter runtime and all user assets stay local. First-time installation of dependencies/build tools requires internet access on the build machine or CI runner.

## Fonts
The application uses system fallback fonts unless actual licensed font files are added to `assets/fonts/`. Only redistribute font files whose licenses permit bundling. See `assets/fonts/README.md`.
