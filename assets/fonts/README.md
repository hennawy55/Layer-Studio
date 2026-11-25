# Bundled fonts

The build scripts retrieve two font families from the official Google Fonts repository:
- **Cairo** — Arabic and Latin glyph coverage, variable weight and slant.
- **Open Sans** — Latin typography, variable width and weight.

Both are distributed under the SIL Open Font License (OFL). The exact OFL notices are downloaded with the font files as part of the build.

Run locally before `flutter pub get`:
- Linux/macOS: `bash tool/fetch_fonts.sh`
- Windows PowerShell: `./tool/fetch_fonts.ps1`

The build embeds font files in the APK and Windows app. The installed application never downloads fonts and works without internet access.
