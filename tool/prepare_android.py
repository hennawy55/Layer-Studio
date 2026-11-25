from pathlib import Path
import re

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

gradle = Path("android/app/build.gradle.kts")
if gradle.exists():
    source = gradle.read_text(encoding="utf-8")
    source = source.replace("minSdk = flutter.minSdkVersion", "minSdk = 24")
    gradle.write_text(source, encoding="utf-8")

groovy = Path("android/app/build.gradle")
if groovy.exists():
    source = groovy.read_text(encoding="utf-8")
    source = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", source)
    groovy.write_text(source, encoding="utf-8")
