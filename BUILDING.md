# Building Layer Studio

## Requirements
- Flutter stable with Dart 3.11 or newer
- Android SDK for APK builds
- Visual Studio 2022 with Desktop development with C++ workload for Windows builds
- Internet access during first-time dependency and font setup

## Prepare the project

Generate Android and Windows runner projects and fetch the 24 licensed Arabic/Latin font families:

Linux/macOS:
```bash
flutter create --platforms=android,windows --project-name=layer_studio --org=com.layerstudio --no-pub .
bash tool/fetch_fonts.sh
python3 tool/prepare_android.py
flutter pub get
dart format lib test
flutter analyze
flutter test
```

Windows PowerShell:
```powershell
flutter create --platforms=android,windows --project-name=layer_studio --org=com.layerstudio --no-pub .
./tool/fetch_fonts.ps1
python tool/prepare_android.py
flutter pub get
dart format lib test
flutter analyze
flutter test
```

## Android APK
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

The APK produced by the default workflow uses Flutter's debug signing key unless a release keystore is configured. Configure a private upload keystore before distributing updates to users; never commit the keystore or passwords.

## Windows application and installer
```powershell
flutter config --enable-windows-desktop
flutter build windows --release
choco install innosetup --yes --no-progress
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" installer\LayerStudio.iss
```
Outputs:
- `build/windows/x64/runner/Release/layer_studio.exe` and its runtime files
- `dist/Layer-Studio-Setup-x64.exe`

The installer is not code-signed. Windows SmartScreen may show an unknown-publisher warning until a publisher certificate is used.

## GitHub Actions
The `Build Layer Studio` workflow runs validation and builds APK + Windows x64. Use **Actions → Build Layer Studio → Run workflow** to start a build manually. Push a tag such as `v1.0.0` to publish the APK and Windows installer as a GitHub Release.

## Runtime privacy and offline mode
The app contains no login, remote database, analytics or runtime network client. User images, overlays, projects, and bundled fonts stay on the device. Internet is used only by developers/CI to retrieve package dependencies and font assets before producing the installable build.
