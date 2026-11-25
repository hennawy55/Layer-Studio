import os
from pathlib import Path
import re

# Flutter plugins in the current stable channel require Android API 36.
# The app module and file_picker's Android library module must both compile
# against API 36; changing only the app module is not sufficient.
manifest = Path("android/app/src/main/AndroidManifest.xml")
if manifest.exists():
    source = manifest.read_text(encoding="utf-8")
    permission = '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />'
    if permission not in source:
        source = source.replace("<application", f"{permission}\n    <application", 1)
    if "android:requestLegacyExternalStorage" not in source:
        source = source.replace(
            "<application",
            '<application android:requestLegacyExternalStorage="true"',
            1,
        )
    manifest.write_text(source, encoding="utf-8")

def force_api_36(gradle_file: Path) -> None:
    if not gradle_file.exists():
        return
    source = gradle_file.read_text(encoding="utf-8")
    source = re.sub(
        r"compileSdkVersion\s+flutter\.compileSdkVersion",
        "compileSdkVersion 36",
        source,
    )
    source = re.sub(
        r"compileSdkVersion\s+\d+",
        "compileSdkVersion 36",
        source,
    )
    source = re.sub(
        r"compileSdk\s*=\s*flutter\.compileSdkVersion",
        "compileSdk = 36",
        source,
    )
    source = re.sub(r"compileSdk\s*=\s*\d+", "compileSdk = 36", source)
    source = re.sub(r"compileSdk\s+\d+", "compileSdk 36", source)
    gradle_file.write_text(source, encoding="utf-8")

# Host application
force_api_36(Path("android/app/build.gradle.kts"))
force_api_36(Path("android/app/build.gradle"))

app_gradle = Path("android/app/build.gradle.kts")
if app_gradle.exists():
    source = app_gradle.read_text(encoding="utf-8")
    source = source.replace("minSdk = flutter.minSdkVersion", "minSdk = 24")
    app_gradle.write_text(source, encoding="utf-8")

app_gradle_groovy = Path("android/app/build.gradle")
if app_gradle_groovy.exists():
    source = app_gradle_groovy.read_text(encoding="utf-8")
    source = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", source)
    app_gradle_groovy.write_text(source, encoding="utf-8")

# file_picker 8.x pins its Android library module to API 34. Its dependency
# flutter_plugin_android_lifecycle has a minCompileSdk of 36. Patch the
# downloaded package in the ephemeral CI pub cache before Gradle configures it.
pub_cache = Path(os.environ.get("PUB_CACHE", str(Path.home() / ".pub-cache")))
hosted = pub_cache / "hosted"
patched = []
if hosted.exists():
    for registry in hosted.iterdir():
        package_dir = registry / "file_picker-8.1.7"
        for relative in ("android/build.gradle", "android/build.gradle.kts"):
            gradle_file = package_dir / relative
            if gradle_file.exists():
                force_api_36(gradle_file)
                patched.append(str(gradle_file))

if not patched:
    raise FileNotFoundError(
        f"Could not locate file_picker 8.1.7 Android Gradle file under {hosted}"
    )

print("Prepared Android compileSdk 36 for app and file_picker:")
for file_path in patched:
    print(f" - {file_path}")
