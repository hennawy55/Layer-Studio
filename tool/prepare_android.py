from pathlib import Path
import re

# Flutter plugins in the current stable channel require the host app to compile
# against Android API 36. Keep minSdk independent from compileSdk.
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

gradle_kts = Path("android/app/build.gradle.kts")
if gradle_kts.exists():
    source = gradle_kts.read_text(encoding="utf-8")
    source = re.sub(r"compileSdk\s*=\s*flutter\.compileSdkVersion", "compileSdk = 36", source)
    source = re.sub(r"compileSdk\s*=\s*\d+", "compileSdk = 36", source)
    source = source.replace("minSdk = flutter.minSdkVersion", "minSdk = 24")
    gradle_kts.write_text(source, encoding="utf-8")

gradle = Path("android/app/build.gradle")
if gradle.exists():
    source = gradle.read_text(encoding="utf-8")
    source = re.sub(r"compileSdkVersion\s+flutter\.compileSdkVersion", "compileSdkVersion 36", source)
    source = re.sub(r"compileSdkVersion\s+\d+", "compileSdkVersion 36", source)
    source = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", source)
    gradle.write_text(source, encoding="utf-8")
