# Layer Studio

Offline-first, non-destructive image composition editor for Android and Windows, built with Flutter.

## Features
- Add text, raster image and SVG logo layers over a photo.
- Move, scale, rotate, reorder, hide, lock, and delete layers.
- Edit text, select embedded Cairo/Open Sans fonts, set colour, weight, italic and alignment.
- Arabic and English interface with RTL/LTR support.
- Light, dark and system themes.
- Local projects; original images and overlays are copied to app-owned storage.
- Autosave, manual save, rename, reopen, delete, undo and redo.
- Export PNG, JPEG and WebP at the source image dimensions.
- Android saves to a dedicated Layer Studio gallery album; Windows uses a Save As dialog.
- No account, remote database, analytics or runtime internet dependency.

## Build
See [BUILDING.md](BUILDING.md) for local setup and GitHub Actions instructions.

## CI
The GitHub Actions workflow validates, runs tests, and builds:
- Android release APK
- Windows x64 application ZIP
- Windows x64 Setup installer

Run it from the **Actions** tab or push to `main`. Push a version tag such as `v1.0.0` to publish a GitHub Release.

## Important notes
- First-time developer builds need internet access for Flutter dependencies and for downloading licensed fonts. Font files are embedded in the final app, which then works offline.
- Android releases use a debug signing key until a private release keystore is configured in CI.
- Windows Setup is not code-signed, so SmartScreen may show an unknown-publisher warning.
- The app retains the original image and renders overlays at export time. JPEG/WebP output is compressed according to the chosen quality; PNG is lossless.
